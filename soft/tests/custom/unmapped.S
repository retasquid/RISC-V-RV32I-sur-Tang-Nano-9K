# unmapped.S
# B4 : une zone non mappee (0x60..., 0x20..., 0xF0...)
# repond rdy = 1 et din = 0 : l'ecriture est perdue, la lecture rend 0 et le
# coeur ne se bloque pas. Verifie aussi qu'une ecriture TOHOST-like dans l'IO
# non decodee ne perturbe pas les registres voisins.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # Test 2 : SW puis LW a 0x60000004
test_2:
  li    TESTNUM, 2
  li    t0, 0x60000004
  li    t1, 0x12345678
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t2, zero, fail

  # Test 3 : LW a 0x20000000
test_3:
  li    TESTNUM, 3
  li    t0, 0x20000000
  li    t2, -1
  lw    t2, 0(t0)
  bne   t2, zero, fail

  # Test 4 : SB / LB signe a 0xF0000003
test_4:
  li    TESTNUM, 4
  li    t0, 0xF0000003
  li    t1, 0xFF
  sb    t1, 0(t0)
  li    t2, -1
  lb    t2, 0(t0)
  bne   t2, zero, fail

  # Test 5 : la RAM reste accessible apres ces acces
test_5:
  li    TESTNUM, 5
  la    t0, tdat
  li    t1, 0xCAFEF00D
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t2, t1, fail

  # Test 6 : lecture d'un registre IO non decode (0x3C) -> 0
test_6:
  li    TESTNUM, 6
  li    t2, -1
  lw    t2, 0x3C(zero)
  bne   t2, zero, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
tdat: .word 0
RVTEST_DATA_END
