#!/usr/bin/env python3
"""Merge a recompiled REL module into a game's recompiled DOL output.

Sonic Riders (GXEE8P) keeps most of its code in files/_Main.rel, which the
game links at a fixed address (0x803FBD00, measured twice). DolRecomp can
recompile a REL at that base (--rel-base); this script puts its output into
the DOL's output so that the RecompCore module template builds ONE module
covering both, without any change to the template:

  generated.h        the DOL's, plus the REL's func_ declarations and its
                     range in dolrecomp_find_original() (and <GAME_ID>.h, the
                     same header under the name the chunks include)
  chunks/*.c         the REL's chunks are added (chunk_*_rel1_*.c)
  generated_smc.txt  the REL's candidate SMC sites are added
  main.dol           gets one more text section holding the REL's code as the
                     game has it in RAM once linked (relocated here, the way
                     OSLink does it), so gen_module_tables.py hashes the REL's
                     chunks like the DOL's. Only the template reads this copy
                     (preflight.sh compares recomp.stamp's dol_sha256).

usage:
  merge_rel.py --dol-out DIR --rel-out DIR --rel FILE --base 0xADDR
               [--check-ram MEM1_DUMP_DIR]

--rel-out is DolRecomp's output for the REL (the folder with generated.h and
chunks/). --check-ram compares the relocated code with a dump of MEM1 taken
while the game runs (mem1_lo.bin at 0x80000000, mem1_hi.bin at 0x81000000).
"""
import argparse
import re
import shutil
import struct
import sys
from pathlib import Path

MARK = "// SR-Source Net Plus: REL merged by tools/dolrecomp/merge_rel.py"


def be32(buf, off):
    return struct.unpack_from(">I", buf, off)[0]


def parse_rel(data):
    h = {}
    (h["id"], _, _, h["num_sections"], h["section_info"], _, _, h["version"],
     h["bss_size"], h["rel_offset"], h["imp_offset"], h["imp_size"]) = struct.unpack_from(">12I", data, 0)
    if h["version"] >= 2:
        h["align"], h["bss_align"] = struct.unpack_from(">II", data, 0x40)
    if h["version"] >= 3:
        h["fix_size"] = be32(data, 0x48)
    h["sections"] = [struct.unpack_from(">II", data, h["section_info"] + 8 * i)
                     for i in range(h["num_sections"])]
    return h


def relocate(data, h, base, bss_address):
    """Return {section: (address, bytearray)} linked at `base`, as OSLink does."""
    image = {}
    addresses = {}
    for index, (offset, size) in enumerate(h["sections"]):
        if size == 0:
            continue
        if offset & ~1:
            start = offset & ~1
            addresses[index] = base + start
            image[index] = bytearray(data[start:start + size])
        else:
            addresses[index] = bss_address  # the BSS section
    own_id = h["id"]
    for imp in range(h["imp_size"] // 8):
        module_id, cursor = struct.unpack_from(">II", data, h["imp_offset"] + 8 * imp)
        section = None
        position = 0
        while True:
            delta, kind, target_section, addend = struct.unpack_from(">HBBI", data, cursor)
            cursor += 8
            position += delta
            if kind == 203:  # R_DOLPHIN_END
                break
            if kind == 202:  # R_DOLPHIN_SECTION
                section, position = target_section, 0
                continue
            if kind in (0, 201):  # R_PPC_NONE, R_DOLPHIN_NOP
                continue
            if section not in image:
                raise SystemExit(f"error: relocation into section {section}, which has no bytes")
            buf = image[section]
            where = addresses[section] + position
            if module_id == 0:
                value = addend
            elif module_id == own_id:
                value = addresses[target_section] + addend
            else:
                raise SystemExit(f"error: import from module {module_id}: only the DOL and itself are supported")
            if kind == 1:  # R_PPC_ADDR32
                struct.pack_into(">I", buf, position, value & 0xFFFFFFFF)
            elif kind in (3, 4):  # R_PPC_ADDR16, R_PPC_ADDR16_LO
                struct.pack_into(">H", buf, position, value & 0xFFFF)
            elif kind == 5:  # R_PPC_ADDR16_HI
                struct.pack_into(">H", buf, position, (value >> 16) & 0xFFFF)
            elif kind == 6:  # R_PPC_ADDR16_HA
                struct.pack_into(">H", buf, position, ((value >> 16) + ((value >> 15) & 1)) & 0xFFFF)
            elif kind == 2:  # R_PPC_ADDR24
                word = be32(buf, position)
                struct.pack_into(">I", buf, position, (word & ~0x03FFFFFC) | (value & 0x03FFFFFC))
            elif kind in (7, 8, 9):  # R_PPC_ADDR14*
                word = be32(buf, position)
                struct.pack_into(">I", buf, position, (word & ~0xFFFC) | (value & 0xFFFC))
            elif kind == 10:  # R_PPC_REL24
                word = be32(buf, position)
                struct.pack_into(">I", buf, position,
                                 (word & ~0x03FFFFFC) | ((value - where) & 0x03FFFFFC))
            elif kind in (11, 12, 13):  # R_PPC_REL14*
                word = be32(buf, position)
                struct.pack_into(">I", buf, position, (word & ~0xFFFC) | ((value - where) & 0xFFFC))
            else:
                raise SystemExit(f"error: unsupported REL relocation type {kind}")
    return {i: (addresses[i], image[i]) for i in image}, addresses


def check_ram(dump_dir, sections, code_index):
    mem = (dump_dir / "mem1_lo.bin").read_bytes() + (dump_dir / "mem1_hi.bin").read_bytes()
    for index, (address, buf) in sorted(sections.items()):
        ram = mem[address - 0x80000000:address - 0x80000000 + len(buf)]
        diff = sum(1 for o in range(0, len(buf), 4) if buf[o:o + 4] != ram[o:o + 4])
        kind = "code" if index == code_index else "data"
        print(f"[merge_rel] RAM check, section {index} ({kind}) at 0x{address:08X}: "
              f"{diff} of {len(buf) // 4} words differ")
        if index == code_index and diff:
            first = next(o for o in range(0, len(buf), 4) if buf[o:o + 4] != ram[o:o + 4])
            print(f"[merge_rel]   first difference at 0x{address + first:08X}: "
                  f"relocated {buf[first:first + 4].hex()} RAM {ram[first:first + 4].hex()}")
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dol-out", type=Path, required=True)
    ap.add_argument("--rel-out", type=Path, required=True)
    ap.add_argument("--rel", type=Path, required=True)
    ap.add_argument("--base", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--check-ram", type=Path)
    args = ap.parse_args()

    data = args.rel.read_bytes()
    h = parse_rel(data)
    code = [i for i, (o, s) in enumerate(h["sections"]) if o & 1 and s]
    if len(code) != 1:
        raise SystemExit(f"error: expected one code section in {args.rel}, found {code}")
    code_index = code[0]
    # OSLinkFixed puts the BSS after the part of the file it keeps (fixSize).
    bss_align = h.get("bss_align", 32) or 32
    bss_address = (args.base + h["fix_size"] + bss_align - 1) & ~(bss_align - 1)
    sections, addresses = relocate(data, h, args.base, bss_address)
    code_address, code_bytes = sections[code_index]
    print(f"[merge_rel] {args.rel.name}: id {h['id']}, code 0x{code_address:08X} "
          f"(0x{len(code_bytes):X} bytes), BSS 0x{bss_address:08X}")
    if args.check_ram and not check_ram(args.check_ram, sections, code_index):
        raise SystemExit("error: the relocated code differs from the game's RAM")

    # --- generated.h ----------------------------------------------------------
    dol_h_path = args.dol_out / "generated.h"
    dol_h = dol_h_path.read_text()
    if MARK in dol_h:
        raise SystemExit(f"error: {dol_h_path} already has a REL merged (run recompile.sh again)")
    rel_h = (args.rel_out / "generated.h").read_text()
    rel_funcs = re.findall(r"^void func_[0-9A-Fa-f]{8}\(CPUState\* ctx\);\n", rel_h, re.M)
    block = re.search(r"static inline DolRecompFunction dolrecomp_find_original\(u32 address\) \{\n"
                      r"(.*?)\n    return NULL;\n\}", rel_h, re.S)
    if not rel_funcs or not block:
        raise SystemExit(f"error: {args.rel_out / 'generated.h'} doesn't look like DolRecomp output")
    rel_block = block.group(1)
    m = re.search(r"u32 offset = address - (0x[0-9A-Fa-f]+)u;", rel_block)
    if not m or int(m.group(1), 16) != code_address:
        raise SystemExit(f"error: the REL was recompiled at another base "
                         f"({m.group(1) if m else '?'}, expected 0x{code_address:08X}): use --rel-base")
    last_decl = list(re.finditer(r"^void func_[0-9A-Fa-f]{8}\(CPUState\* ctx\);\n", dol_h, re.M))[-1]
    dol_h = dol_h[:last_decl.end()] + MARK + "\n" + "".join(rel_funcs) + dol_h[last_decl.end():]
    find = re.search(r"(static inline DolRecompFunction dolrecomp_find_original\(u32 address\) \{\n.*?)"
                     r"(\n    return NULL;\n\})", dol_h, re.S)
    dol_h = dol_h[:find.end(1)] + "\n" + rel_block + dol_h[find.end(1):]
    # DolRecomp names its header <GAME_ID>.h or generated.h, and the chunks
    # include that name ("../GXEE8P.h"); recompile.sh copies it to generated.h,
    # which module_export.c includes. Every copy gets the merged text, so the
    # DOL's chunks call the REL's functions directly too.
    original = dol_h_path.read_text()
    copies = [p for p in sorted(args.dol_out.glob("*.h")) if p.read_text() == original]
    for header in copies:
        header.write_text(dol_h)
    print(f"[merge_rel] headers merged: {', '.join(p.name for p in copies)}")

    # --- chunks ---------------------------------------------------------------
    chunks = sorted((args.rel_out / "chunks").glob("*.c"))
    for chunk in chunks:
        target = args.dol_out / "chunks" / chunk.name
        if target.exists():
            raise SystemExit(f"error: {target} already exists")
        shutil.copyfile(chunk, target)

    # --- SMC candidates -------------------------------------------------------
    rel_smc = [line for line in (args.rel_out / "generated_smc.txt").read_text().splitlines()
               if re.match(r"0x[0-9A-Fa-f]+-0x[0-9A-Fa-f]+", line.strip())]
    with (args.dol_out / "generated_smc.txt").open("a") as f:
        f.write("\n".join(rel_smc) + "\n")

    # --- main.dol: one more text section with the linked REL code -------------
    dol_path = args.dol_out / "main.dol"
    dol = bytearray(dol_path.read_bytes())
    slot = next((i for i in range(7) if be32(dol, 0x90 + 4 * i) == 0), None)
    if slot is None:
        raise SystemExit("error: main.dol has no free text section for the REL's code")
    file_offset = (len(dol) + 31) & ~31
    dol += bytes(file_offset - len(dol)) + code_bytes
    struct.pack_into(">I", dol, 0x00 + 4 * slot, file_offset)
    struct.pack_into(">I", dol, 0x48 + 4 * slot, code_address)
    struct.pack_into(">I", dol, 0x90 + 4 * slot, len(code_bytes))
    dol_path.write_bytes(dol)

    print(f"[merge_rel] merged: {len(rel_funcs)} functions, {len(chunks)} chunks, "
          f"{len(rel_smc)} SMC ranges; REL code is text section {slot} of the hashing main.dol")
    return 0


if __name__ == "__main__":
    sys.exit(main())
