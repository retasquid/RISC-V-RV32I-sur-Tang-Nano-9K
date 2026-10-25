#ifndef PERIPH_H
#define PERIPH_H

#include <stdint.h>
#include <stdbool.h>

#define GPIO0       (*(volatile int*)0x00000010)
#define DIRGPIO0    (*(volatile int*)0x00000014)
#define TX_UART     (*(volatile int*)0x00000018)
#define RX_UART     (*(volatile int*)0x0000001C)
#define BAUD_UART   (*(volatile int*)0x00000020)

#define SCREEN_P_BEGIN   (int*)0xc0000000
#define SCREEN_P_END     (int*)0xc0007fff
#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 400

#define CLK_27_FREQ     27000000UL
/* Horloge systeme = rPLL 27 * 7 / 6 = 31.5 MHz (CLK_HZ dans top.vhd) : coeur,
 * QSPI et UART. Le coeur est multicycle et attend la flash/PSRAM : une
 * instruction prend de ~14 a ~50 cycles selon le type et la memoire. Ne pas
 * faire de delai logiciel en comptant des instructions avec cette valeur. */
#define CLK_CORE_FREQ   31500000UL

/* L'UART est cadencee par l'horloge systeme : phase_inc = baud * 2^32 / f */
#define serialInit(baud)  BAUD_UART = (int)(((uint64_t)(baud)<<32) / CLK_CORE_FREQ)

int serialRead(char *ptr, int len_max);
int serialWrite(char *ptr);
void clearScreen(uint32_t color);
void set_pixel(uint16_t x, uint16_t y);
void clear_pixel(uint16_t x, uint16_t y);
void plotPixel(uint16_t x, uint16_t y, uint32_t color);

#endif