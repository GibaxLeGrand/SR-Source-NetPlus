"""Échantillonneur rapide du runner (Windows, ctypes, aucune dépendance) : SuspendThread +
GetThreadContext + ResumeThread sur les fils les plus chargés de moderngekko-run.exe, ~1 kHz.
Relève RIP, et 8 mots en haut de la pile (indice d'appelant), pour chaque fil choisi.

usage: python -I echantillonneur.py <dossier auto> <commande début> <commande fin> <sortie>
  Commence quand <auto>/processed/<début>.txt existe, s'arrête quand <fin> est traitée (ou échoue)
  ou quand le runner sort. Écrit <sortie>.bin (enregistrements) et <sortie>.json (modules, fils,
  temps CPU de chaque fil pendant la fenêtre). Analyse : analyse_echantillons.py.

Format d'un enregistrement (little endian, 88 o) : tid u32, t_us u32 (depuis le début), rip u64,
rsp u64, 8 × u64 lus à partir de rsp (0 si illisibles).
"""
import ctypes
import ctypes.wintypes as wt
import json
import os
import struct
import sys
import time

PERIODE = float(os.environ.get("ECH_PERIODE_S", "0.001"))
SEUIL_CPU = float(os.environ.get("ECH_SEUIL_CPU", "0.10"))   # part d'un cœur pour qu'un fil soit relevé
MAX_FILS = int(os.environ.get("ECH_MAX_FILS", "6"))
NOM_EXE = "moderngekko-run.exe"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
HANDLE = ctypes.c_void_p


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wt.DWORD),
                ("cntThreads", wt.DWORD), ("th32ParentProcessID", wt.DWORD),
                ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]


class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", ctypes.c_long),
                ("tpDeltaPri", ctypes.c_long), ("dwFlags", wt.DWORD)]


class MODULEINFO(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p), ("SizeOfImage", wt.DWORD), ("EntryPoint", ctypes.c_void_p)]


def proto(fn, res, *args):
    fn.restype = res
    fn.argtypes = list(args)
    return fn


CreateToolhelp32Snapshot = proto(k32.CreateToolhelp32Snapshot, HANDLE, wt.DWORD, wt.DWORD)
Process32FirstW = proto(k32.Process32FirstW, wt.BOOL, HANDLE, ctypes.POINTER(PROCESSENTRY32W))
Process32NextW = proto(k32.Process32NextW, wt.BOOL, HANDLE, ctypes.POINTER(PROCESSENTRY32W))
Thread32First = proto(k32.Thread32First, wt.BOOL, HANDLE, ctypes.POINTER(THREADENTRY32))
Thread32Next = proto(k32.Thread32Next, wt.BOOL, HANDLE, ctypes.POINTER(THREADENTRY32))
CloseHandle = proto(k32.CloseHandle, wt.BOOL, HANDLE)
OpenProcess = proto(k32.OpenProcess, HANDLE, wt.DWORD, wt.BOOL, wt.DWORD)
OpenThread = proto(k32.OpenThread, HANDLE, wt.DWORD, wt.BOOL, wt.DWORD)
SuspendThread = proto(k32.SuspendThread, wt.DWORD, HANDLE)
ResumeThread = proto(k32.ResumeThread, wt.DWORD, HANDLE)
GetThreadContext = proto(k32.GetThreadContext, wt.BOOL, HANDLE, ctypes.c_void_p)
GetThreadTimes = proto(k32.GetThreadTimes, wt.BOOL, HANDLE, *[ctypes.POINTER(ctypes.c_ulonglong)] * 4)
GetExitCodeProcess = proto(k32.GetExitCodeProcess, wt.BOOL, HANDLE, ctypes.POINTER(wt.DWORD))
ReadProcessMemory = proto(k32.ReadProcessMemory, wt.BOOL, HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                          ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t))
EnumProcessModulesEx = proto(k32.K32EnumProcessModulesEx, wt.BOOL, HANDLE, ctypes.POINTER(ctypes.c_void_p),
                             wt.DWORD, ctypes.POINTER(wt.DWORD), wt.DWORD)
GetModuleInformation = proto(k32.K32GetModuleInformation, wt.BOOL, HANDLE, ctypes.c_void_p,
                             ctypes.POINTER(MODULEINFO), wt.DWORD)
GetModuleFileNameExW = proto(k32.K32GetModuleFileNameExW, wt.DWORD, HANDLE, ctypes.c_void_p, wt.LPWSTR, wt.DWORD)
try:
    GetThreadDescription = proto(k32.GetThreadDescription, ctypes.c_long, HANDLE, ctypes.POINTER(wt.LPWSTR))
    LocalFree = proto(k32.LocalFree, ctypes.c_void_p, ctypes.c_void_p)
except AttributeError:
    GetThreadDescription = None

INVALID = ctypes.c_void_p(-1).value
THREAD_ACCESS = 0x0002 | 0x0008 | 0x0040 | 0x0800   # SUSPEND_RESUME, GET_CONTEXT, QUERY_INFORMATION, QUERY_LIMITED
PROCESS_ACCESS = 0x0400 | 0x0010                     # QUERY_INFORMATION, VM_READ
CONTEXT_SIZE = 1232
CONTEXT_FLAGS_OFF, RSP_OFF, RIP_OFF = 0x30, 0x98, 0xF8
CONTEXT_CONTROL = 0x00100001
REC = struct.Struct("<IIQQ8Q")


def find_pid():
    snap = CreateToolhelp32Snapshot(2, 0)
    if snap in (None, INVALID):
        return None
    try:
        e = PROCESSENTRY32W()
        e.dwSize = ctypes.sizeof(e)
        ok = Process32FirstW(snap, ctypes.byref(e))
        while ok:
            if e.szExeFile.lower() == NOM_EXE:
                return e.th32ProcessID
            ok = Process32NextW(snap, ctypes.byref(e))
    finally:
        CloseHandle(snap)
    return None


def thread_ids(pid):
    snap = CreateToolhelp32Snapshot(4, 0)
    out = []
    if snap in (None, INVALID):
        return out
    try:
        e = THREADENTRY32()
        e.dwSize = ctypes.sizeof(e)
        ok = Thread32First(snap, ctypes.byref(e))
        while ok:
            if e.th32OwnerProcessID == pid:
                out.append(e.th32ThreadID)
            ok = Thread32Next(snap, ctypes.byref(e))
    finally:
        CloseHandle(snap)
    return out


def modules(hproc):
    arr = (ctypes.c_void_p * 4096)()
    need = wt.DWORD()
    if not EnumProcessModulesEx(hproc, arr, ctypes.sizeof(arr), ctypes.byref(need), 3):
        return []
    out = []
    buf = ctypes.create_unicode_buffer(1024)
    for i in range(min(need.value // ctypes.sizeof(ctypes.c_void_p), 4096)):
        mi = MODULEINFO()
        if not GetModuleInformation(hproc, arr[i], ctypes.byref(mi), ctypes.sizeof(mi)):
            continue
        GetModuleFileNameExW(hproc, arr[i], buf, 1024)
        out.append({"base": mi.lpBaseOfDll, "size": mi.SizeOfImage, "path": buf.value})
    return out


def thread_name(h):
    if GetThreadDescription is None:
        return ""
    p = wt.LPWSTR()
    if GetThreadDescription(h, ctypes.byref(p)) < 0 or not p:
        return ""
    s = p.value or ""
    LocalFree(p)
    return s


def cpu_time(h):
    c, e, k, u = (ctypes.c_ulonglong() for _ in range(4))
    if not GetThreadTimes(h, ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u)):
        return None
    return k.value, u.value   # unités de 100 ns


def alive(hproc):
    code = wt.DWORD()
    return GetExitCodeProcess(hproc, ctypes.byref(code)) and code.value == 259


def main():
    auto, debut, fin, sortie = sys.argv[1:5]
    proc_dir = os.path.join(auto, "processed")
    fail_dir = os.path.join(auto, "failed")
    fait = lambda c: os.path.exists(os.path.join(proc_dir, c + ".txt")) or os.path.exists(os.path.join(fail_dir, c + ".txt"))

    pid = None
    for _ in range(600):
        pid = find_pid()
        if pid:
            break
        time.sleep(0.1)
    if not pid:
        print("échantillonneur : pas de runner")
        return 1
    hproc = OpenProcess(PROCESS_ACCESS, False, pid)
    if not hproc:
        print(f"échantillonneur : OpenProcess a échoué ({ctypes.get_last_error()})")
        return 1
    while not fait(debut):
        if not alive(hproc):
            print("échantillonneur : runner sorti avant le début")
            return 1
        time.sleep(0.01)

    raw = ctypes.create_string_buffer(CONTEXT_SIZE + 16)
    base = ctypes.addressof(raw)
    ctx = (base + 15) & ~15
    stack = (ctypes.c_ulonglong * 8)()
    nread = ctypes.c_size_t()

    handles = {}     # tid -> handle
    names = {}
    t_debut_cpu = {}
    last_cpu = {}
    choisis = []
    t0 = time.perf_counter()
    t_choix = -1.0
    mods = modules(hproc)
    t_mods = t0
    n = 0
    suspend_fail = 0
    out = open(sortie + ".bin", "wb")
    buf = bytearray()
    raison = "fin"
    while True:
        now = time.perf_counter()
        if fait(fin):
            break
        if not alive(hproc):
            raison = "runner sorti"
            break
        if now - t_choix >= 0.5:
            # Rafraîchir les fils et garder ceux qui ont pris le plus de CPU depuis le dernier choix.
            for tid in thread_ids(pid):
                if tid not in handles:
                    h = OpenThread(THREAD_ACCESS, False, tid)
                    if h:
                        handles[tid] = h
                        names[tid] = thread_name(h)
                        ct = cpu_time(h)
                        if ct:
                            t_debut_cpu[tid] = ct
                            last_cpu[tid] = sum(ct)
            dt = (now - t_choix) if t_choix >= 0 else None
            charges = []
            for tid, h in handles.items():
                ct = cpu_time(h)
                if not ct:
                    continue
                tot = sum(ct)
                if dt:
                    charges.append(((tot - last_cpu.get(tid, tot)) / 1e7 / dt, tid))
                last_cpu[tid] = tot
            if dt:
                charges.sort(reverse=True)
                choisis = [tid for c, tid in charges[:MAX_FILS] if c >= SEUIL_CPU]
            t_choix = now
            if now - t_mods > 5:
                mods = modules(hproc)
                t_mods = now
            if not choisis:
                time.sleep(PERIODE)
                continue
        t_us = int((now - t0) * 1e6) & 0xFFFFFFFF
        for tid in choisis:
            h = handles[tid]
            if SuspendThread(h) == 0xFFFFFFFF:
                suspend_fail += 1
                continue
            ctypes.memset(ctx, 0, CONTEXT_SIZE)
            ctypes.c_uint32.from_address(ctx + CONTEXT_FLAGS_OFF).value = CONTEXT_CONTROL
            ok = GetThreadContext(h, ctx)
            ResumeThread(h)
            if not ok:
                continue
            rip = ctypes.c_uint64.from_address(ctx + RIP_OFF).value
            rsp = ctypes.c_uint64.from_address(ctx + RSP_OFF).value
            if not ReadProcessMemory(hproc, rsp, stack, 64, ctypes.byref(nread)):
                for i in range(8):
                    stack[i] = 0
            buf += REC.pack(tid, t_us, rip, rsp, *stack)
            n += 1
        if len(buf) > 1 << 20:
            out.write(buf)
            buf.clear()
        # cadence : une passe par période
        reste = PERIODE - (time.perf_counter() - now)
        if reste > 0:
            time.sleep(reste)
    duree = time.perf_counter() - t0
    out.write(buf)
    out.close()
    fils = []
    for tid, h in handles.items():
        ct = cpu_time(h)
        d = t_debut_cpu.get(tid)
        if ct and d:
            fils.append({"tid": tid, "nom": names.get(tid, ""), "cpu_s": (sum(ct) - sum(d)) / 1e7,
                         "noyau_s": (ct[0] - d[0]) / 1e7})
        CloseHandle(h)
    fils.sort(key=lambda f: -f["cpu_s"])
    mods = modules(hproc) or mods
    CloseHandle(hproc)
    json.dump({"pid": pid, "duree_s": duree, "echantillons": n, "echec_suspend": suspend_fail,
               "raison": raison, "periode_s": PERIODE, "modules": mods, "fils": fils},
              open(sortie + ".json", "w", encoding="utf-8"), indent=1)
    print(f"échantillonneur : {n} relevés en {duree:.1f} s ({n / max(duree, 1e-9):.0f}/s), {raison}, "
          f"échecs de suspension {suspend_fail}")
    for f in fils[:8]:
        print(f"  fil {f['tid']:6d} {f['nom'][:30]:30s} {f['cpu_s']:7.2f} s CPU ({100 * f['cpu_s'] / max(duree, 1e-9):5.1f} %)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
