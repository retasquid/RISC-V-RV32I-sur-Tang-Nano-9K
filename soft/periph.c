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
    volatile unsigned int* p = SCREEN_P_BEGIN;
    for(int i = 0; i<(SCREEN_P_END-SCREEN_P_BEGIN); i++) {
        p[i] = color;
    }
}

void set_pixel(uint16_t x, uint16_t y){
    volatile int* ptr = SCREEN_P_BEGIN + (x/32) + (y*20);
    *ptr = (1<<(31-(x%32)))|(*ptr);
}

void clear_pixel(uint16_t x, uint16_t y){
    int* ptr = SCREEN_P_BEGIN + (x/32) + (y*20);
    *ptr = (~(1<<(31-(x%32))))&(*ptr);
}

void plotPixel(uint16_t x, uint16_t y, uint32_t color){
    if(color)set_pixel(x, y);
    else clear_pixel(x, y);
}