/* timer.c
 * Test systeme du timer 64 bits (peripherals.vhd, API de periph.h) :
 * lecture coherente LO puis HI, valeur au demarrage, 1 ms mesuree par le
 * compteur de microsecondes = 31 500 cycles a 31,5 MHz, delay_us.
 * Resultat ecrit a TOHOST (voir env/riscv_test.h).
 */
#include <stdint.h>
#include "periph.h"

#define TOHOST (*(volatile uint32_t *)0x00000040)

static int err = 0;

#define CHECK(n, cond) do { if (!(cond) && err == 0) err = (n); } while (0)

int main(void)
{
    uint64_t c0 = time_cycles();
    uint64_t c1 = time_cycles();
    CHECK(2, c1 > c0 && c1 - c0 < 200);           /* deux lectures proches */
    CHECK(3, (c1 >> 32) == 0);                    /* HI fige avec LO */

    /* main demarre apres l'init de la flash (~2,06 ms apres le reset) */
    uint64_t u0 = time_us();
    CHECK(4, u0 >= 1900 && u0 < 5000);
    CHECK(5, c1 > 1900 * 31 && c1 < 5000 * 32); /* meme instant en cycles */

    /* 1 ms comptee en microsecondes = 31 500 cycles */
    uint32_t t0 = USEC_LO;
    uint32_t a = TIME_LO;
    while (USEC_LO - t0 < 1000) {}
    uint32_t b = TIME_LO;
    CHECK(6, b - a > 31500 - 200 && b - a < 31500 + 200);

    /* delay_us(500) : entre 500 et ~510 us */
    uint32_t t1 = micros();
    delay_us(500);
    uint32_t d = micros() - t1;
    CHECK(7, d >= 500 && d < 510);

    TOHOST = err == 0 ? 1u : ((uint32_t)err << 1) | 1u;
    for (;;) {}
}
