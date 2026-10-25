#include"screenApi.h"

uint32_t framebuffer[SCREEN_WIDTH * SCREEN_HEIGHT] = {0};

void plotPixel(uint16_t x, uint16_t y, uint32_t color){
    if(color) color = 0xFFFFFFFF;
    framebuffer[y * SCREEN_WIDTH + x] = color;
}

void clearScreen(uint32_t color){
    memset(framebuffer, color, sizeof(framebuffer));
}