/* c_system.c
 * Test systeme en C, compile comme un programme normal (start.S + link.ld) :
 * recopie de .data, mise a zero de .bss, pile en PSRAM, recursion, pointeurs
 * de fonction (jalr ra, B6), acces octet/demi-mot (Q5), libgcc (mul/div),
 * libc (memcpy/memset/strlen). Resultat ecrit a TOHOST (voir env/riscv_test.h).
 */
#include <stdint.h>
#include <string.h>

#define TOHOST (*(volatile uint32_t *)0x00000040)

static int err = 0;                       /* .bss : doit valoir 0 */
static volatile int init_val = 0x1234;    /* .data : copie depuis la flash */
static uint8_t bytes[8];
static char msg[] = "RV32I";

#define CHECK(n, cond) do { if (!(cond) && err == 0) err = (n); } while (0)

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

static int add3(int x) { return x + 3; }
static int mul5(int x) { return x * 5; }

typedef int (*op_t)(int);
static op_t volatile ops[2] = { add3, mul5 };   /* volatile : pas de devirtualisation */

int main(void)
{
    volatile int a = 1234567, b = -89, n = 10;

    CHECK(2, err == 0);
    CHECK(3, init_val == 0x1234);

    CHECK(4, fib(n) == 55);                       /* recursion : pile */

    CHECK(5, ops[0](10) == 13);                   /* jalr ra via pointeur */
    CHECK(6, ops[1](10) == 50);

    CHECK(7, a * b == -109876463);                /* __mulsi3 */
    CHECK(8, a / b == -13871);                    /* __divsi3 */
    CHECK(9, a % b == 48);                        /* __modsi3 */
    CHECK(10, (unsigned)a / 7u == 176366u);       /* __udivsi3 */

    for (int i = 0; i < 8; i++)                   /* SB a tous les offsets */
        bytes[i] = (uint8_t)(0xA0 + i);
    CHECK(11, *(volatile uint32_t *)&bytes[0] == 0xA3A2A1A0u);
    CHECK(12, *(volatile uint16_t *)&bytes[6] == 0xA7A6u);
    CHECK(13, *(volatile int8_t *)&bytes[5] == (int8_t)0xA5);

    memset(bytes, 0x5A, 3);
    CHECK(14, bytes[2] == 0x5A && bytes[3] == 0xA3);
    char buf[8];
    memcpy(buf, msg, sizeof msg);
    CHECK(15, strlen(buf) == 5 && buf[4] == 'I');

    TOHOST = err == 0 ? 1u : ((uint32_t)err << 1) | 1u;
    for (;;) {}
}
