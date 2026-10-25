#!/usr/bin/env python3
"""Compile les programmes de test pour top_tb.

  riscv-tests/isa/rv32ui/*.S  -> rv32ui-<nom>   (env/riscv_test.h, env/link_test.ld)
  riscv-tests/isa/rv32um/*.S  -> rv32um-<nom>   (idem ; tout est compile en -march=rv32im)
  custom/*.S                  -> custom-<nom>   (idem)
  custom/*.c                  -> custom-<nom>   (start.S + link.ld du projet, comme comp.bat)

Sorties dans RISC-V/sim/tests/ : <test>.elf, <test>.hex (pour flash_model,
via elf2rom.py) et <test>.dump (desassemblage, pour le debug).

Usage : python build_tests.py [filtre]     (ex. : python build_tests.py jalr)
"""
import contextlib
import io
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFT = HERE.parent
OUT = SOFT.parent / "RISC-V" / "sim" / "tests"

sys.path.insert(0, str(SOFT))
import elf2rom  # noqa: E402

GCC = "riscv-none-elf-gcc"
OBJDUMP = "riscv-none-elf-objdump"
ARCH = ["-march=rv32im", "-mabi=ilp32"]   # extension M depuis l'etape 12

ASM_FLAGS = ARCH + [
    "-static", "-nostdlib", "-nostartfiles",
    "-I", str(HERE / "env"),
    "-I", str(HERE / "riscv-tests" / "isa" / "macros" / "scalar"),
    "-T", str(HERE / "env" / "link_test.ld"),
]

C_FLAGS = ARCH + [
    "-O2", "-ffreestanding", "-nostartfiles",
    "-I", str(SOFT),
    "-T", str(SOFT / "link.ld"),
    str(SOFT / "start.S"),
]
C_LIBS = ["-Wl,--start-group", "-lc", "-lm", "-lgcc", "-Wl,--end-group", "-specs=nosys.specs"]


def build(name, cmd, elf):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ECHEC compilation {name}\n{r.stderr}")
        return False
    with contextlib.redirect_stdout(io.StringIO()):
        start, words = elf2rom.make_words(elf2rom.parse_elf(str(elf)))
    if start != 0x40000000:
        print(f"  ECHEC {name} : l'image commence a 0x{start:08x} au lieu de 0x40000000")
        return False
    elf2rom.write_hex(str(elf.with_suffix(".hex")), words)
    dump = subprocess.run([OBJDUMP, "-d", str(elf)], capture_output=True, text=True).stdout
    elf.with_suffix(".dump").write_text(dump)
    print(f"  {name:24s} {len(words) * 4:6d} octets")
    return True


def main():
    filt = sys.argv[1] if len(sys.argv) > 1 else ""
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = []
    for src in sorted((HERE / "riscv-tests" / "isa" / "rv32ui").glob("*.S")):
        jobs.append((f"rv32ui-{src.stem}", src, "asm"))
    for src in sorted((HERE / "riscv-tests" / "isa" / "rv32um").glob("*.S")):
        jobs.append((f"rv32um-{src.stem}", src, "asm"))
    for src in sorted((HERE / "custom").glob("*.S")):
        jobs.append((f"custom-{src.stem}", src, "asm"))
    for src in sorted((HERE / "custom").glob("*.c")):
        jobs.append((f"custom-{src.stem}", src, "c"))

    ok = 0
    jobs = [j for j in jobs if filt in j[0]]
    for name, src, kind in jobs:
        elf = OUT / f"{name}.elf"
        if kind == "asm":
            cmd = [GCC] + ASM_FLAGS + [str(src), "-o", str(elf)]
        else:
            cmd = [GCC] + C_FLAGS + [str(src)] + C_LIBS + ["-o", str(elf)]
        ok += build(name, cmd, elf)
    print(f"{ok}/{len(jobs)} test(s) compile(s) dans {OUT}")
    return 0 if ok == len(jobs) else 1


if __name__ == "__main__":
    sys.exit(main())
