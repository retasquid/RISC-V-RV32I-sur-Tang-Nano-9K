#include "periph.h"

int serialRead(char *ptr, int len_max)
{
    int i = 0;
    int tmp_rx = 0;
    while(tmp_rx != '\r') {
        tmp_rx = RX_UART;
        if(tmp_rx & 0x100){
            tmp_rx &= 0xff; 
            if(tmp_rx==0x7F){ // backspace
                if(i){
                    ptr[i]=0;
                    TX_UART = tmp_rx;
                    while(TX_UART);
                    i--;
                }
            }else if(i<(len_max-1)){
                ptr[i] = tmp_rx;
                TX_UART = tmp_rx;
                while(TX_UART);
                i++;
            }
        }
    }

    return i;
}

int serialWrite(char *ptr)
{
    int i = 0;
    for (; ptr[i]; i++) {
        TX_UART = ptr[i];
        while (TX_UART);
    }

    return i;
}

void clearScreen(uint32_t color){
    /* gris replique dans les 8 quartets du mot (sans multiplication) */
    uint32_t w = color & 15;
    w |= w << 4;
    w |= w << 8;
    w |= w << 16;
    volatile uint32_t* p = (volatile uint32_t*)SCREEN_P_BEGIN;
    for(int i = 0; i < SCREEN_HEIGHT * SCREEN_WPL; i++) {
        p[i] = w;
    }
}

void plotPixel(uint16_t x, uint16_t y, uint32_t color){
    if(x >= SCREEN_WIDTH || y >= SCREEN_HEIGHT) return;
    volatile uint32_t* ptr = (volatile uint32_t*)SCREEN_P_BEGIN + (x >> 3) + y * SCREEN_WPL;
    int sh = 28 - ((x & 7) << 2);      /* pixel de gauche = bits 31..28 */
    *ptr = (*ptr & ~(15u << sh)) | ((color & 15) << sh);
}

void set_pixel(uint16_t x, uint16_t y){
    plotPixel(x, y, GRAY_WHITE);
}

void clear_pixel(uint16_t x, uint16_t y){
    plotPixel(x, y, GRAY_BLACK);
}
