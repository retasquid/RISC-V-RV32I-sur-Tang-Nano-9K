#ifndef LIB2D_H
#define LIB2D_H

/* include dependant du materiel devant contenir

    #define SCREEN_WIDTH {width}
    #define SCREEN_HEIGHT {height}

    void plotPixel(uint16_t x, uint16_t y, uint32_t color);
    void clearScreen(uint32_t color);
*/
#include"periph.h"
//#include"font.h"

void drawLine(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color);
void drawRectangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color);
void drawFilledRectangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color);
//void drawChar(uint16_t x, uint16_t y, uint32_t color, char c);
//void drawText(uint16_t x, uint16_t y, uint32_t color, char* text);
void drawBitmap(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint32_t* bitmap);
void drawTriangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);
void drawFilledTriangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);

#endif