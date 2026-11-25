"""SR-Source Net Plus, phase 1 prototype: a relay that closes frames for runners in lockstep.

usage: python -I relais.py --sieges N [--port 7845] [--delai-ms 100] [--cadence 60] [--journal relais.log]

Each runner (moderngekko-run with SRNP_RELAY=<host>:<port> SRNP_SEAT=<k>[,<k2>] SRNP_SEATS=<N>)
sends HELLO <seat> <seats> for each of its seats (one or two on one connection), then for every frame IN <frame> <seat> <pad> and now and then
  CK <frame> <seat> <hash>.
The relay closes frame f (sends OF <frame> <pad seat 0> ... <pad seat N-1> to every seat) when every
seat has sent its input for f, or --delai-ms after the first input for f arrived: a seat that is late
gets its last official input repeated, so a slow machine does not hold the others back, and its own
input for that frame, arriving later, is dropped. Frames are closed in order. Checksums of the same
frame are compared as soon as every seat has sent one: the journal says "identique" or "DIVERGENCE".

Start together: the relay answers each HELLO with WAIT <present> <seats> <states> to every connection,
and again every 2 s while a seat is missing (the runners wait at their first frame, and the line keeps
their connection alive). <states> has one letter per seat: O expected, V there, X left before the start.
Once no seat is expected (and one is there) it sends GO, followed by seat:character/gear for each seat
that left: the AI takes it over, with a character drawn at random here (the same on every machine), and
the relay gives it the AI flag as its input for the whole race. Until every seat has sent its first input, no
frame is closed without it (a runner that has just loaded is slow for a while): no input of the start
is replaced.

Tags: a runner may send TAG <seat> <tag> (its player's tag, up to 8 characters); the relay keeps them and
sends TAGS <tag 0>,<tag 1>,... ("-": none) to every connection at each new one and when a seat connects.
They are only shown (labels, results, waiting screen): nothing of the race depends on them.

Lobby (experimental): HELLO <seat> <seats> <delay> LOBBY says the seat will choose: it stays O until
READY <seat> (UNREADY <seat>: back to choosing). PICK <seat> <character> <gear> at each change; the relay
sends PICKS <c0>/<g0>,<c1>/<g1>,... ("-": none yet) to everyone; the runners set up the race with them.
The host (seat 0) sends RULES 0 <course> <laps> [<racers>] (course 1-16, laps 1-9, racers from the seats
to 8: the AI drives the others); the relay sends RULES <course> <laps> [<racers>] to everyone (and to
each new connection); the runners write them into the game at GO.
"""
import argparse
import asyncio
import random
import time

NEUTRE = "0000000000000000"
IA = "8000000000000000"            # le drapeau kSeatAI : le siège rend son racer à l'IA
# Persos tirés au hasard pour un siège parti (0-10, 12-16 : pas Super Sonic), planche 0 (le runner la
# remplace si le perso ne peut pas la prendre).
PERSOS = [c for c in range(17) if c != 11]


class Relais:
    def __init__(self, sieges, delai, journal, cadence=0.0):
        self.sieges = sieges
        self.delai = delai
        self.cadence = cadence        # frames par seconde de l'horloge du relais (0 : pas d'horloge)
        self.t0 = None
        self.f0 = None
        self.journal = journal
        self.clients = {}             # siège -> writer
        self.entrees = {}             # frame -> {siège: pad}
        self.premiere = {}            # frame -> instant de la première entrée
        self.dernier = [NEUTRE] * sieges
        self.prochaine = None         # prochaine frame à fermer
        self.demarre = False          # tous les sièges ont dit HELLO
        self.go = False               # GO envoyé
        self.etat = ["O"] * sieges    # O attendu, V là, X parti avant le départ
        self.vus = set()              # sièges qui ont envoyé au moins une entrée
        self.dernier_wait = 0.0
        self.delai_entree = 0         # délai d'entrée annoncé par les sièges (HELLO)
        self.f_saisie = 0             # première frame qui a des entrées
        self.retard_siege = [0] * sieges
        self.derniere_recue = [None] * sieges
        self.nb_recues = {}
        self.fermees = 0
        self.en_retard = 0
        self.ck = {}                  # frame -> {siège: hash}
        self.ck_ok = 0
        self.ck_ko = 0
        self.tags = [""] * sieges     # le tag de chaque siège (TAG), seulement affiché
        self.choix = [""] * sieges    # lobby : « perso/planche » de chaque siège (PICK)
        self.regles = None            # lobby : (course, tours) de l'hôte (RULES)
        self.debut = time.monotonic()

    def log(self, texte):
        ligne = f"{time.monotonic() - self.debut:9.3f} {texte}"
        print(ligne, flush=True)
        if self.journal:
            self.journal.write(ligne + "\n")
            self.journal.flush()

    async def diffuser(self, ligne):
        donnees = (ligne + "\n").encode()
        # Une connexion peut porter deux sièges : un seul envoi par connexion.
        for writer in {id(w): w for w in self.clients.values()}.values():
            try:
                writer.write(donnees)
                await writer.drain()
            except (ConnectionError, OSError):
                for siege in [s for s, w in self.clients.items() if w is writer]:
                    self.log(f"siège {siege} : perdu à l'envoi")
                    self.clients.pop(siege, None)

    async def fermer_pretes(self):
        """Ferme, dans l'ordre, les frames complètes ou dont le délai est passé. Rien avant que tous
        les sièges soient là (un siège qui arrive ensuite n'est pas pris en charge par ce prototype)."""
        if not self.demarre:
            if not self.go:
                return
            self.demarre = True
            for f in self.premiere:
                self.premiere[f] = time.monotonic()
            self.log("tous les sièges sont là : départ")
        while self.prochaine is not None and (self.prochaine in self.entrees or self.prochaine < self.f_saisie):
            f = self.prochaine
            recues = dict(self.entrees.get(f, {}))
            # Les premières frames (le délai d'entrée des sièges) n'ont d'entrée de personne : neutres.
            for s in range(self.sieges):
                if self.etat[s] == "X":
                    recues[s] = IA
            complete = f < self.f_saisie or all(s in recues for s in range(self.sieges))
            if self.cadence > 0:
                # Horloge du relais : la frame f est due à départ + (f - première) / cadence ; elle est
                # fermée dès qu'elle est complète, sinon à son échéance plus le délai.
                if self.t0 is None:
                    self.t0, self.f0 = time.monotonic(), f
                echeance = self.t0 + (f - self.f0) / self.cadence + self.delai
                if not complete and time.monotonic() < echeance:
                    return
            elif not complete and (len(self.vus) < len(self.actifs()) or time.monotonic() - self.premiere[f] < self.delai):
                # Au départ, pas de délai tant qu'un siège n'a rien envoyé : il vient de charger.
                return
            pads = []
            for s in range(self.sieges):
                if s in recues:
                    self.dernier[s] = recues[s]
                elif f >= self.f_saisie:
                    self.en_retard += 1
                    self.retard_siege[s] += 1
                    if self.retard_siege[s] <= 3:
                        self.log(f"frame {f} fermée sans le siège {s} (dernière entrée reçue de lui : "
                                 f"frame {self.derniere_recue[s]})")
                pads.append(self.dernier[s])
            await self.diffuser(f"OF {f} " + " ".join(pads))
            self.entrees.pop(f, None)
            self.premiere.pop(f, None)
            self.prochaine = f + 1
            self.fermees += 1
            if self.fermees % 600 == 0:
                self.log(f"frame {f} fermée ; {self.fermees} frames, {self.en_retard} entrées en retard "
                         f"remplacées ; sommes de contrôle : {self.ck_ok} identiques, {self.ck_ko} divergences")

    def ligne_choix(self):
        return "PICKS " + ",".join(c or "-" for c in self.choix)

    def ligne_tags(self):
        return "TAGS " + ",".join(t or "-" for t in self.tags)

    def actifs(self):
        return [s for s in range(self.sieges) if self.etat[s] != "X"]

    async def annoncer(self):
        """WAIT <présents> <sièges> <états> à tous, ou GO quand plus personne n'est attendu."""
        if self.go:
            return
        presents = self.etat.count("V")
        if "O" not in self.etat and presents > 0:
            self.go = True
            remplaces = []
            for s in range(self.sieges):
                if self.etat[s] == "X":
                    remplaces.append(f"{s}:{random.choice(PERSOS)}/0")
            self.log("plus personne n'est attendu : GO" + (" ; à l'IA : " + " ".join(remplaces) if remplaces else ""))
            await self.diffuser(" ".join(["GO"] + remplaces))
            await self.fermer_pretes()
        else:
            self.dernier_wait = time.monotonic()
            await self.diffuser(f"WAIT {presents} {self.sieges} {''.join(self.etat)}")

    async def minuteur(self):
        while True:
            await asyncio.sleep(0.005)
            if not self.go and self.clients and time.monotonic() - self.dernier_wait > 2.0:
                await self.annoncer()
            await self.fermer_pretes()

    def controle(self, frame, siege, valeur):
        recues = self.ck.setdefault(frame, {})
        recues[siege] = valeur
        if len(recues) == len(self.actifs()):
            if len(set(recues.values())) == 1:
                self.ck_ok += 1
            else:
                self.ck_ko += 1
                self.log(f"DIVERGENCE frame {frame} : " + " ".join(f"{s}={h}" for s, h in sorted(recues.items())))
            del self.ck[frame]

    async def client(self, reader, writer):
        siege = None
        sieges = []                   # les sièges de cette connexion (un ou deux)
        try:
            while True:
                ligne = await reader.readline()
                if not ligne:
                    break
                mots = ligne.decode(errors="replace").split()
                if not mots:
                    continue
                if mots[0] == "HELLO":
                    siege = int(mots[1])
                    sieges.append(siege)
                    if len(mots) > 3:
                        self.delai_entree = max(self.delai_entree, int(mots[3]))
                    self.clients[siege] = writer
                    lobby = len(mots) > 4 and mots[4] == "LOBBY"
                    if not self.go:
                        self.etat[siege] = "O" if lobby else "V"
                    self.log(f"siège {siege} connecté ({len(self.clients)}/{self.sieges})")
                    await self.annoncer()
                    if any(self.tags):
                        await self.diffuser(self.ligne_tags())
                    if any(self.choix):
                        await self.diffuser(self.ligne_choix())
                    if self.regles:
                        await self.diffuser("RULES " + " ".join(map(str, self.regles)))
                elif mots[0] == "PICK":
                    s_, c, g = int(mots[1]), int(mots[2]), int(mots[3])
                    if 0 <= s_ < self.sieges and 0 <= c <= 16 and 0 <= g < 64 and not self.go:
                        self.choix[s_] = f"{c}/{g}"
                        await self.diffuser(self.ligne_choix())
                elif mots[0] == "RULES" and len(mots) in (4, 5):
                    s_, c, t = int(mots[1]), int(mots[2]), int(mots[3])
                    r = int(mots[4]) if len(mots) == 5 else None
                    regles = (c, t) if r is None else (c, t, r)
                    if (s_ == 0 and 1 <= c <= 16 and 1 <= t <= 9 and (r is None or self.sieges <= r <= 8)
                            and not self.go and regles != self.regles):
                        self.regles = regles
                        self.log(f"règles de l'hôte : course {c}, {t} tour(s)" + (f", {r} racers" if r else ""))
                        await self.diffuser("RULES " + " ".join(map(str, regles)))
                elif mots[0] in ("READY", "UNREADY"):
                    s_ = int(mots[1])
                    if 0 <= s_ < self.sieges and not self.go and self.etat[s_] != "X":
                        self.etat[s_] = "V" if mots[0] == "READY" else "O"
                        self.log(f"siège {s_} : {'prêt' if mots[0] == 'READY' else 'choisit encore'} "
                                 f"({self.choix[s_] or 'sans choix'})")
                        await self.annoncer()
                elif mots[0] == "TAG":
                    s = int(mots[1])
                    tag = "".join(c for c in (mots[2] if len(mots) > 2 else "") if c != ",")[:8].upper()
                    if 0 <= s < self.sieges and tag and tag != self.tags[s]:
                        self.tags[s] = tag
                        self.log(f"tag du siège {s} : {tag}")
                        await self.diffuser(self.ligne_tags())
                elif mots[0] == "IN":
                    f, s, pad = int(mots[1]), int(mots[2]), mots[3]
                    self.derniere_recue[s] = f
                    if s not in self.vus:
                        self.vus.add(s)
                        if len(self.vus) == len(self.actifs()):
                            self.log(f"tous les sièges ont envoyé une entrée : délai de {self.delai * 1000:.0f} ms")
                    self.nb_recues[s] = self.nb_recues.get(s, 0) + 1
                    if self.nb_recues[s] <= 5:
                        self.log(f"entrée du siège {s} pour la frame {f} (prochaine à fermer : {self.prochaine})")
                    if self.prochaine is None:
                        self.prochaine = f - self.delai_entree
                        self.f_saisie = f
                        self.log(f"première frame : {self.prochaine} (entrées à partir de {f})")
                    if f < self.prochaine:
                        continue  # frame déjà fermée sans elle
                    self.entrees.setdefault(f, {})[s] = pad
                    self.premiere.setdefault(f, time.monotonic())
                    await self.fermer_pretes()
                elif mots[0] == "CK":
                    self.controle(int(mots[1]), int(mots[2]), mots[3])
        except (ConnectionError, OSError, ValueError, IndexError) as e:
            self.log(f"siège {siege} : erreur {e!r}")
        finally:
            for s in sieges:
                self.clients.pop(s, None)
                if not self.go:
                    self.etat[s] = "X"   # parti avant le départ : l'IA le remplacera
            if not self.go and sieges:
                await self.annoncer()
            self.log(f"siège(s) {sieges} parti(s) ; {self.fermees} frames fermées, {self.en_retard} entrées en retard "
                     f"(par siège : {self.retard_siege}), "
                     f"sommes de contrôle : {self.ck_ok} identiques, {self.ck_ko} divergences")


async def principal():
    p = argparse.ArgumentParser()
    p.add_argument("--sieges", type=int, required=True)
    p.add_argument("--port", type=int, default=7845)
    p.add_argument("--hote", default="127.0.0.1")
    p.add_argument("--delai-ms", type=float, default=100.0)
    p.add_argument("--journal")
    p.add_argument("--cadence", type=float, default=0.0,
                   help="frames par seconde : une frame est fermée au plus tard à son échéance (0 : sans horloge)")
    a = p.parse_args()
    journal = open(a.journal, "a", encoding="utf-8") if a.journal else None
    relais = Relais(a.sieges, a.delai_ms / 1000.0, journal, a.cadence)
    serveur = await asyncio.start_server(relais.client, a.hote, a.port)
    relais.log(f"relais : {a.sieges} sièges, {a.hote}:{a.port}, délai {a.delai_ms} ms, cadence {a.cadence}")
    asyncio.get_running_loop().create_task(relais.minuteur())
    async with serveur:
        await serveur.serve_forever()


if __name__ == "__main__":
    asyncio.run(principal())
