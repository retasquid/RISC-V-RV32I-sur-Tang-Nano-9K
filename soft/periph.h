#ifndef PERIPH_H
#define PERIPH_H

#include <stdint.h>
#include <stdbool.h>

#define GPIO0       (*(volatile int*)0x00000010)
#define DIRGPIO0    (*(volatile int*)0x00000014)
#define TX_UART     (*(volatile int*)0x00000018)
#define RX_UART     (*(volatile int*)0x0000001C)
#define BAUD_UART   (*(volatile int*)0x00000020)

/* Timer 64 bits (peripherals.vhd) : cycles de clk_sys et microsecondes depuis
 * le reset, en lecture seule. Lire LO fige HI : toujours lire LO puis HI
 * (time_cycles / time_us le font), la valeur 64 bits est alors coherente. */
#define TIME_LO     (*(volatile uint32_t*)0x00000030)
#define TIME_HI     (*(volatile uint32_t*)0x00000034)
#define USEC_LO     (*(volatile uint32_t*)0x00000038)
#define USEC_HI     (*(volatile uint32_t*)0x0000003C)

/* Ecran 320x200 en 16 niveaux de gris (0 = noir, 15 = blanc), affiche en
 * 640x400 (chaque pixel double) : 4 bits par pixel, 40 mots de 32 bits par
 * ligne, 8 pixels par mot, pixel de gauche dans les bits 31..28.
 * Mots 0..7999 a l'ecran, 8000..8191 libres (hors ecran). */
#define SCREEN_P_BEGIN   (int*)0xc0000000
#define SCREEN_P_END     (int*)0xc0007fff
#define SCREEN_WIDTH 320
#define SCREEN_HEIGHT 200
#define SCREEN_WPL   40                 /* mots par ligne */
#define GRAY_BLACK   0
#define GRAY_WHITE   15

#define CLK_27_FREQ     27000000UL
/* Horloge systeme = rPLL 27 * 7 / 6 = 31.5 MHz (CLK_HZ dans top.vhd) : coeur,
 * QSPI et UART. Le coeur est multicycle et attend la flash/PSRAM : une
 * instruction prend de ~14 a ~50 cycles selon le type et la memoire. Ne pas
 * faire de delai logiciel en comptant des instructions avec cette valeur. */
#define CLK_CORE_FREQ   31500000UL

/* L'UART est cadencee par l'horloge systeme : phase_inc = baud * 2^32 / f */
#define serialInit(baud)  BAUD_UART = (int)(((uint64_t)(baud)<<32) / CLK_CORE_FREQ)

static inline uint64_t time_cycles(void)
{
    uint32_t lo = TIME_LO;
    return ((uint64_t)TIME_HI << 32) | lo;
}

static inline uint64_t time_us(void)
{
    uint32_t lo = USEC_LO;
    return ((uint64_t)USEC_HI << 32) | lo;
}

/* Microsecondes sur 32 bits (reboucle apres 71 min) : les differences
 * (micros() - t0) restent justes a travers le rebouclage */
static inline uint32_t micros(void)
{
    return USEC_LO;
}

static inline void delay_us(uint32_t us)
{
    uint32_t t0 = USEC_LO;
    while (USEC_LO - t0 < us) {}
}

static inline void delay_ms(uint32_t ms)
{
    while (ms--)
        delay_us(1000);
}

int serialRead(char *ptr, int len_max);
int serialWrite(char *ptr);
void clearScreen(uint32_t color);        /* gris 0..15 */
void set_pixel(uint16_t x, uint16_t y);     /* blanc */
void clear_pixel(uint16_t x, uint16_t y);   /* noir */
void plotPixel(uint16_t x, uint16_t y, uint32_t color);   /* gris 0..15, hors ecran ignore */

#endif