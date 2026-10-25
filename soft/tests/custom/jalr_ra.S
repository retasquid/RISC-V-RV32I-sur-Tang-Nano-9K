# jalr_ra.S
# B6 : JALR doit ecrire rd (appel par pointeur de fonction : jalr ra, ...)
# et forcer le bit 0 de la cible a 0. Le fetch flash aligne l'adresse : une
# cible impaire "marche" en apparence, mais le PC reste impair. On le voit
# avec AUIPC, qui doit rendre l'adresse paire de la fonction.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # Test 2 : appel par pointeur de fonction, ra ecrit par jalr
test_2:
  li    TESTNUM, 2
  la    t0, func_ra
  li    ra, 0
  li    a0, 0
  jalr  ra, t0, 0
ret_2:
  la    t1, ret_2
  bne   ra, t1, fail
  bne   a0, t1, fail          # func_ra a vu le bon ra

  # Test 3 : rd = rs1
test_3:
  li    TESTNUM, 3
  la    a2, func_a2
  jalr  a2, a2, 0
ret_3:
  la    t1, ret_3
  bne   a2, t1, fail

  # Test 4 : cible impaire (rs1 impair) -> bit 0 force a 0
test_4:
  li    TESTNUM, 4
  la    t0, func_pc
  addi  t0, t0, 1
  jalr  ra, t0, 0
ret_4:
  la    t1, ret_4
  bne   ra, t1, fail
  la    t1, func_pc
  bne   a1, t1, fail          # PC pair dans la fonction

  # Test 5 : cible impaire (immediat impair)
test_5:
  li    TESTNUM, 5
  la    t0, func_pc
  jalr  ra, t0, 1
ret_5:
  la    t1, ret_5
  bne   ra, t1, fail
  la    t1, func_pc
  bne   a1, t1, fail

  # Test 6 : jalr x0 (ret) n'ecrit pas x0
test_6:
  li    TESTNUM, 6
  la    t0, after_6
  jalr  x0, t0, 0
  j     fail
after_6:
  bne   x0, zero, fail

  TEST_PASSFAIL

func_ra:
  mv    a0, ra
  ret

func_a2:                      # retour par a2 (lien du test 3)
  jr    a2

func_pc:
  auipc a1, 0
  ret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .word 0
RVTEST_DATA_END
