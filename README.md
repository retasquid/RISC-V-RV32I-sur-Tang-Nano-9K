# RISC-V RV32I sur Tang Nano 9K

Processeur **RV32I multicycle écrit en VHDL** pour la carte Sipeed **Tang Nano 9K** (FPGA Gowin GW1NR-9). Il démarre depuis une flash QSPI externe, utilise une PSRAM QSPI externe comme RAM et se programme en C avec `riscv-none-elf-gcc`.

## Caractéristiques

- Jeu d'instructions **RV32I** complet, sans CSR, interruptions ni `fence.i`. Il passe les 40 tests `rv32ui` des [riscv-tests](https://github.com/riscv-software-src/riscv-tests) applicables.
- Cœur multicycle à **27 MHz**, une seule horloge, sans clock-enable : 2 cycles par instruction hors attente mémoire, 4 pour un load/store.
- Code exécuté directement depuis la **flash QSPI GigaDevice GD25Q32C** (4 Mio) : lecture Quad I/O `EBh` en mode continu, et CS# maintenu bas pendant les fetchs séquentiels.
- **8 Mio de RAM** : PSRAM QSPI Lyontek **LY68L6400**, en mode QPI.
- Périphériques : 32 GPIO, UART (débit programmable).
- Contrôleur VGA 640×400 monochrome présent dans les sources, mais désactivé pour l'instant.

## Carte mémoire

| Adresse | Zone | Contenu |
|---|---|---|
| `0x0000_0000` | IO | `0x10` GPIO, `0x14` direction GPIO, `0x18` UART TX, `0x1C` UART RX, `0x20` débit UART |
| `0x4000_0000` | Flash QSPI (4 Mio) | code et constantes ; adresse de reset |
| `0x8000_0000` | PSRAM QSPI (8 Mio) | `.data`, `.bss`, pile |
| `0xC000_0000` | VRAM | (VGA désactivé) |

Registre RX : le bit 8 vaut 1 quand un octet est disponible (bits 7:0). La lecture consomme l'octet ; sans octet disponible, la lecture rend 0.

## Arborescence

```
RISC-V/                 projet Gowin EDA (RISC-V.gprj)
  src/                  RTL VHDL (top.vhd = sommet), contraintes .cst/.sdc, IP Gowin
  tb/                   testbenches auto-vérifiants + modèles de la flash et de la PSRAM
  sim/                  scripts ModelSim (*.do)
soft/                   logiciel : start.s, link.ld, periph.c/h, comp.bat, elf2rom.py
  Flasher3.1/           programmation de la flash via un Arduino (MCU) + script Python (PC)
  tests/                programmes de test système (riscv-tests rv32ui + tests maison)
logisim_evo/, RISCV.ods schéma Logisim et notes de conception
CLAUDE.md               notes techniques détaillées : architecture, historique des bugs, état des tests
```

## Matériel

- Tang Nano 9K.
- Flash GD25Q32C et PSRAM LY68L6400 câblées sur les broches définies dans [RISC-V/src/RISC-V.cst](RISC-V/src/RISC-V.cst).
- Un Arduino avec `soft/Flasher3.1/MCU_QSPIflasher` pour écrire dans la flash. Le bit QE de la flash (Quad Enable) est activé par le flasher.
- Un adaptateur série sur `uart_tx` / `uart_rx` (115200 bauds dans les exemples). Ses niveaux doivent être compatibles avec les bancs d'IO déclarés dans le `.cst`.

## Compiler et programmer

**Bitstream** : ouvrir `RISC-V/RISC-V.gprj` dans Gowin EDA (testé avec V1.9.11.01 Education), lancer la synthèse et le placement-routage, puis charger le bitstream sur la carte.

**Logiciel** : il faut `riscv-none-elf-gcc` (par exemple xPack) dans le PATH, puis Python 3 avec `pyserial` pour le flasher.

```bat
cd soft
comp.bat main.c flash     :: compile puis programme la flash externe (port COM dans flasher.py)
comp.bat main.c rom       :: variante : génère RISC-V/src/ROM.vhd (ROM interne, voir top.vhd)
```

Au démarrage, le processeur attend environ 2 ms (initialisation de la flash et de la PSRAM), puis exécute le code à partir de `0x4000_0000`.

## Simulation

Les testbenches tournent sous **ModelSim** (testé avec ModelSim ASE en VHDL-2008). Chacun affiche une ligne `TB_RESULT: SUCCES` ou `TB_RESULT: ECHEC`.

```sh
cd RISC-V/sim
vsim -c -do "do qspi_sram.do; quit -f"      # contrôleur PSRAM + modèle LY68L6400
vsim -c -do "do qspi_flash.do; quit -f"     # contrôleur flash + modèle GD25Q32C
vsim -c -do "do peripherals.do; quit -f"    # GPIO + UART
vsim -c -do "do psram_model.do; quit -f"    # autotests des modèles
vsim -c -do "do flash_model.do; quit -f"

# Tests système : processeur complet + modèles mémoire, un programme par test
python ../../soft/tests/build_tests.py
vsim -c -do "do top_tests.do; quit -f"                            # 43 programmes
vsim -c -do "set TEST rv32ui-add; do top_tests.do; quit -f"       # un seul
```

Les modèles de la flash et de la PSRAM vérifient le protocole et les timings des datasheets : séquence de mise sous tension, temps de CS#, lignes non pilotées, conflits de bus, etc.

## État

- Jeu d'instructions : validé en simulation (43/43 tests système).
- PSRAM, flash et UART (émission et réception) : validés sur carte.
- La dernière optimisation (cœur sans clock-enable, flux flash) est validée en simulation. Il reste à vérifier sur carte et dans le rapport de timing Gowin.
- Le VGA reste à réintégrer.

Le détail figure dans [CLAUDE.md](CLAUDE.md).

## Licences

Le sous-ensemble des riscv-tests dans `soft/tests/riscv-tests/` est distribué sous sa licence BSD d'origine ([LICENSE](soft/tests/riscv-tests/LICENSE)).
