#ifndef SCREENAPI_H
#define SCREENAPI_H

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 400

extern uint32_t framebuffer[SCREEN_WIDTH * SCREEN_HEIGHT];

void plotPixel(uint16_t x, uint16_t y, uint32_t color);
void clearScreen(uint32_t color);

#endif