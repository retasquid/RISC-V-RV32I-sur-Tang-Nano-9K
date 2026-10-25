#!/usr/bin/env python3

import argparse
import struct
import sys
import math
from pathlib import Path


# ============================================================
# ELF constants
# ============================================================

ELF_MAGIC = b"\x7fELF"

ELFCLASS32 = 1
ELFDATA2LSB = 1

SHT_PROGBITS = 1

SHF_WRITE = 0x1
SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4

PT_LOAD = 1


# ============================================================
# ELF32 little endian parser
# ============================================================

def parse_elf(filename):

    data = Path(filename).read_bytes()

    if data[:4] != ELF_MAGIC:
        raise ValueError("Le fichier n'est pas un ELF.")

    elf_class = data[4]
    endian = data[5]

    if elf_class != ELFCLASS32:
        raise ValueError(
            "Ce programme supporte uniquement les ELF 32 bits."
        )

    if endian != ELFDATA2LSB:
        raise ValueError(
            "Seuls les ELF little-endian sont supportés."
        )

    # --------------------------------------------------------
    # ELF header
    # --------------------------------------------------------

    header = struct.unpack_from(
        "<16sHHIIIIIHHHHHH",
        data,
        0
    )

    (
        ident,
        e_type,
        e_machine,
        e_version,
        e_entry,
        e_phoff,
        e_shoff,
        e_flags,
        e_ehsize,
        e_phentsize,
        e_phnum,
        e_shentsize,
        e_shnum,
        e_shstrndx
    ) = header

    print(f"Entrée ELF : 0x{e_entry:08x}")

    # --------------------------------------------------------
    # Program headers (segments PT_LOAD) : donnent la LMA
    # (adresse de chargement physique) de chaque section, qui
    # peut différer de sa VMA (sh_addr) pour .data (AT > FLASH).
    # --------------------------------------------------------

    load_segments = parse_program_headers(
        data,
        e_phoff,
        e_phentsize,
        e_phnum
    )

    # --------------------------------------------------------
    # Section name string table
    # --------------------------------------------------------

    shstr_offset, shstr_size = get_section_info(
        data,
        e_shoff,
        e_shentsize,
        e_shstrndx
    )

    shstr = data[
        shstr_offset:
        shstr_offset + shstr_size
    ]

    # --------------------------------------------------------
    # Find loadable sections with actual file content
    # --------------------------------------------------------

    sections = []

    for i in range(e_shnum):

        offset = e_shoff + i * e_shentsize

        sh = struct.unpack_from(
            "<IIIIIIIIII",
            data,
            offset
        )

        (
            sh_name,
            sh_type,
            sh_flags,
            sh_addr,
            sh_offset,
            sh_size,
            sh_link,
            sh_info,
            sh_addralign,
            sh_entsize
        ) = sh

        name = get_string(shstr, sh_name)

        is_code = bool(sh_flags & SHF_EXECINSTR)

        # Section à programmer en ROM : toute section PROGBITS
        # chargeable (SHF_ALLOC) avec du contenu réel dans le
        # fichier (sh_size > 0). On NE filtre PLUS sur SHF_WRITE :
        # .data a un contenu initial qui doit être présent en ROM,
        # même si elle est modifiable une fois copiée en RAM.
        # .bss est de type SHT_NOBITS (pas PROGBITS) et est donc
        # déjà naturellement exclue, ce qui est correct : elle n'a
        # pas de contenu à programmer.
        if (
            sh_type == SHT_PROGBITS
            and (sh_flags & SHF_ALLOC)
            and sh_size > 0
        ):

            section_data = data[
                sh_offset:
                sh_offset + sh_size
            ]

            # Adresse à utiliser dans la ROM : la LMA (adresse de
            # chargement physique), pas la VMA. Pour .text/.rodata
            # les deux coïncident généralement ; pour .data elles
            # diffèrent (VMA en RAM, LMA en Flash).
            load_addr = to_load_address(sh_addr, load_segments)

            sections.append({
                "name": name,
                "addr": load_addr,
                "vaddr": sh_addr,
                "size": sh_size,
                "data": section_data,
                "code": is_code,
                "writable": bool(sh_flags & SHF_WRITE),
            })

            kind = "code  " if is_code else "rodata"
            if sh_flags & SHF_WRITE:
                kind = "data  "

            addr_note = ""
            if load_addr != sh_addr:
                addr_note = f" (VMA=0x{sh_addr:08x})"

            print(
                f"Section {name:12s} "
                f"[{kind}] "
                f"addr=0x{load_addr:08x}{addr_note} "
                f"size={sh_size}"
            )

    if not sections:
        raise ValueError(
            "Aucune section executable/rodata/data trouvée."
        )

    return sections


def parse_program_headers(data, e_phoff, e_phentsize, e_phnum):
    """Extrait les segments PT_LOAD (Elf32_Phdr), qui donnent la
    correspondance VMA (p_vaddr) <-> LMA (p_paddr) nécessaire pour
    placer correctement le contenu de .data dans la ROM."""

    segments = []

    for i in range(e_phnum):

        offset = e_phoff + i * e_phentsize

        ph = struct.unpack_from(
            "<IIIIIIII",
            data,
            offset
        )

        (
            p_type,
            p_offset,
            p_vaddr,
            p_paddr,
            p_filesz,
            p_memsz,
            p_flags,
            p_align
        ) = ph

        if p_type == PT_LOAD:
            segments.append({
                "vaddr": p_vaddr,
                "paddr": p_paddr,
                "filesz": p_filesz,
                "memsz": p_memsz,
            })

    return segments


def to_load_address(vaddr, load_segments):
    """Convertit une adresse virtuelle (VMA, ex: adresse RAM de
    .data) en adresse de chargement physique (LMA, ex: adresse
    Flash où le contenu doit être programmé), via les segments
    PT_LOAD. Si aucun segment ne correspond (VMA == LMA, cas
    normal de .text/.rodata), renvoie l'adresse inchangée."""

    for seg in load_segments:
        if seg["vaddr"] <= vaddr < seg["vaddr"] + seg["memsz"]:
            return seg["paddr"] + (vaddr - seg["vaddr"])

    return vaddr


def get_section_info(data, shoff, shentsize, index):

    offset = shoff + index * shentsize

    sh = struct.unpack_from(
        "<IIIIIIIIII",
        data,
        offset
    )

    return sh[4], sh[5]


def get_string(table, offset):

    if offset >= len(table):
        return ""

    end = table.find(b"\0", offset)

    if end == -1:
        end = len(table)

    return table[offset:end].decode(
        "ascii",
        errors="replace"
    )


# ============================================================
# Convert executable sections into 32-bit words
# ============================================================

def make_words(sections, word_size=4):

    # Determine address range (basé sur les LMA maintenant)
    start = min(s["addr"] for s in sections)
    end = max(
        s["addr"] + s["size"]
        for s in sections
    )

    # Align start/end to words
    start &= ~(word_size - 1)
    end = (end + word_size - 1) & ~(word_size - 1)

    size = end - start

    words = [
        0
        for _ in range(size // word_size)
    ]

    for section in sections:

        addr = section["addr"]
        section_data = section["data"]

        for i, byte in enumerate(section_data):

            absolute_addr = addr + i
            index = (absolute_addr - start) // word_size
            byte_offset = (absolute_addr - start) % word_size

            words[index] |= byte << (8 * byte_offset)

    return start, words


# ============================================================
# HEX output
# ============================================================

def write_hex(filename, words):

    with open(filename, "w") as f:

        for word in words:

            f.write(
                f"{word & 0xffffffff:08x}\n"
            )


# ============================================================
# VHDL output
# ============================================================

def write_vhdl(
    filename,
    words,
    depth,
    entity_name="ROM"
):

    with open(filename, "w") as f:

        f.write(
f"""LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY ROM IS
    PORT(
        dout    : out std_logic_vector(31 downto 0);
        adr     : in  std_logic_vector({int(math.log2(depth)-1)} downto 0);
        rdy     : out std_logic;
        cs, rd  : in std_logic;
        clk     : in std_logic
    );
END ENTITY;

ARCHITECTURE ROMV1 OF ROM IS

    TYPE rom_type IS ARRAY (0 to {depth-1})
        OF std_logic_vector(31 downto 0);

    SIGNAL rom_d : rom_type := (
"""
        )

        for i in range(depth):

            if i < len(words):
                value = words[i]
            else:
                value = 0

            f.write(
                f'        {i} => x"{value:08x}"'
            )

            if i != depth - 1:
                f.write(",")

            f.write("\n")

        f.write(
f"""    );

    SIGNAL doutR : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL rdyR  : std_logic := '0';

BEGIN

    -- Pas de trois etats : top multiplexe les esclaves selon l'adresse
    dout <= doutR;
    rdy  <= rdyR;

    -- Lecture sans effet de bord : relue a chaque cycle (BRAM). rdy n'est
    -- leve que pour une requete qui vise la ROM (cs) et retombe avec rd.
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            doutR <= rom_d(to_integer(unsigned(adr)));
            IF cs = '1' AND rd = '1' THEN
                rdyR <= '1';
            ELSE
                rdyR <= '0';
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
""")


# ============================================================
# Main
# ============================================================

def main():

    parser = argparse.ArgumentParser(
        description="Convertit un ELF/O en ROM HEX ou VHDL."
    )

    parser.add_argument(
        "input",
        help="Fichier ELF ou objet .o"
    )

    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Fichier de sortie"
    )

    parser.add_argument(
        "--format",
        choices=["hex", "vhd"],
        default="hex",
        help="Format de sortie"
    )

    parser.add_argument(
        "--depth",
        type=int,
        default=None,
        help="Taille de la ROM en mots 32 bits"
    )

    parser.add_argument(
        "--entity",
        default="ROM",
        help="Nom de l'entity VHDL"
    )

    args = parser.parse_args()

    try:

        sections = parse_elf(args.input)

        start, words = make_words(sections)

        print()
        print(
            f"Adresse de début : 0x{start:08x}"
        )

        print(
            f"Nombre de mots : {len(words)}"
        )

        # ----------------------------------------------------
        # HEX
        # ----------------------------------------------------

        if args.format == "hex":

            write_hex(
                args.output,
                words
            )

        # ----------------------------------------------------
        # VHDL
        # ----------------------------------------------------

        elif args.format == "vhd":

            depth = args.depth

            if depth is None:
                depth = len(words)

            if len(words) > depth:

                raise ValueError(
                    f"Le programme nécessite {len(words)} mots, "
                    f"mais la ROM ne contient que {depth}."
                )

            write_vhdl(
                args.output,
                words,
                depth,
                args.entity
            )

        print()
        print(
            f"OK : {args.output}"
        )

    except Exception as e:

        print(
            f"ERREUR : {e}",
            file=sys.stderr
        )

        sys.exit(1)


if __name__ == "__main__":
    main()