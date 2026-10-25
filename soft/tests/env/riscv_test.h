// riscv_test.h
// Environnement minimal pour faire tourner les riscv-tests (et les tests
// maison de tests/custom) sur le coeur RV32I du projet : pas de CSR, pas
// d'interruptions, pas d'ecall.
//
// Code en flash (0x40000000), donnees (.data, tdat...) en PSRAM (0x80000000),
// recopiees depuis la flash au demarrage (voir link_test.ld).
// Resultat : un mot ecrit a TOHOST (0x00000040, zone IO non decodee par
// peripherals, ecriture acquittee et ignoree) et releve par top_tb :
//   1            = succes
//   (n << 1) | 1 = echec du test n (TESTNUM)
#ifndef _ENV_RISCV_RV32I_TB_H
#define _ENV_RISCV_RV32I_TB_H

#define TOHOST 0x40
#define TESTNUM gp

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        la      t0, _data_load;                                         \
        la      t1, _data_start;                                        \
        la      t2, _data_end;                                          \
1:      bgeu    t1, t2, 2f;                                             \
        lw      t3, 0(t0);                                              \
        sw      t3, 0(t1);                                              \
        addi    t0, t0, 4;                                              \
        addi    t1, t1, 4;                                              \
        j       1b;                                                     \
2:      li      TESTNUM, 0;

#define RVTEST_CODE_END                                                 \
1:      j       1b;

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li      TESTNUM, 1;                                             \
        sw      TESTNUM, TOHOST(zero);                                  \
1:      j       1b;

#define RVTEST_FAIL                                                     \
        fence;                                                          \
        slli    TESTNUM, TESTNUM, 1;                                    \
        ori     TESTNUM, TESTNUM, 1;                                    \
        sw      TESTNUM, TOHOST(zero);                                  \
1:      j       1b;

#define RVTEST_DATA_BEGIN                                               \
        .data;                                                          \
        .align 4;                                                       \
        .global begin_signature;                                        \
begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4;                                                       \
        .global end_signature;                                          \
end_signature:

#endif
