# vram.S
# VRAM (0xC0000000, 32 Kio en BRAM double port, vue par le coeur sur clk27) :
# lecture/ecriture de mots, octets et demi-mots a tous les offsets, bords de
# l'ecran (mot 0 et mot 7999), et une lecture ne doit rien ecrire.

#include "riscv_test.h"
#include "test_macros.h"

#define VRAM 0xC0000000

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # Test 2 : SW / LW au debut de l'ecran
test_2:
  li    TESTNUM, 2
  li    t0, VRAM
  li    t1, 0x12345678
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t2, t1, fail

  # Test 3 : dernier mot de l'ecran (7999 -> 0xC0007CFC)
test_3:
  li    TESTNUM, 3
  li    t0, VRAM + 7999*4
  li    t1, 0xCAFEBABE
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t2, t1, fail

  # Test 4 : une lecture ne modifie pas le mot (relu deux fois, voisin intact)
test_4:
  li    TESTNUM, 4
  li    t0, VRAM
  lw    t2, 4(t0)
  lw    t2, 0(t0)
  lw    t2, 0(t0)
  li    t1, 0x12345678
  bne   t2, t1, fail

  # Test 5 : SB aux offsets 0..3
test_5:
  li    TESTNUM, 5
  li    t0, VRAM + 0x100
  sw    zero, 0(t0)
  li    t1, 0x11
  sb    t1, 0(t0)
  li    t1, 0x22
  sb    t1, 1(t0)
  li    t1, 0x33
  sb    t1, 2(t0)
  li    t1, 0x44
  sb    t1, 3(t0)
  lw    t2, 0(t0)
  li    t1, 0x44332211
  bne   t2, t1, fail

  # Test 6 : SH aux offsets 0 et 2, relus en LHU / LB
test_6:
  li    TESTNUM, 6
  li    t0, VRAM + 0x104
  li    t1, 0xBEEF
  sh    t1, 0(t0)
  li    t1, 0x8001
  sh    t1, 2(t0)
  lw    t2, 0(t0)
  li    t1, 0x8001BEEF
  bne   t2, t1, fail
  lhu   t2, 2(t0)
  li    t1, 0x8001
  bne   t2, t1, fail
  lb    t2, 3(t0)
  li    t1, -128
  bne   t2, t1, fail

  # Test 7 : les mots 0x100 et 0x104 sont independants
test_7:
  li    TESTNUM, 7
  li    t0, VRAM + 0x100
  lw    t2, 0(t0)
  li    t1, 0x44332211
  bne   t2, t1, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .word 0
RVTEST_DATA_END
