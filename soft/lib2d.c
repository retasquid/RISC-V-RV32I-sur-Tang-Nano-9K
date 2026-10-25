#include "lib2d.h"

static void drawLineH(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    int32_t dy;
    if (x1 > x2) {
        dy = x1;
        x1 = x2;
        x2 = dy;
        dy = y1;
        y1 = y2;
        y2 = dy;
    }
    
    int32_t dx = x2 - x1;
    int32_t dir;

    if (y2 > y1) {
        dir = 1;
        dy = y2 - y1;
    }else{
        dir = -1;
        dy = y1 - y2;
    }
    
    int32_t y0 = y1;
    int32_t p = (dy << 1) - dx;
    int32_t i = 0;
    while(i <= dx) {
        plotPixel(x1 + i, y0, color);

        if (p >= 0) {
            y0 +=dir;
            p -= (dx << 1);
        }
        p += (dy << 1);
        i++;
    }
}

static void drawLineV(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    int32_t dx;
    if (y1 > y2) {
        dx = x1;
        x1 = x2;
        x2 = dx;
        dx = y1;
        y1 = y2;
        y2 = dx;
    }
    int32_t dy = y2 - y1;
    int32_t dir;

    if (x2 > x1) {
        dir = 1;
        dx = x2 - x1;
    } else {
        dir = -1;
        dx = x1 - x2;
    }

    int32_t p = (dx << 1) - dy;
    int32_t x0 = x1;
    int32_t i = 0;
    while(i <= dy){
        plotPixel(x0, y1 + i, color);

        if (p >= 0) {
            x0 += dir;
            p -= (dy << 1);
        }
        p += (dx << 1);
        i++;
    }
}

void drawLine(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color) {
    int32_t dx;
    if (x0>x1) {
        dx = x0 - x1;
    }else{
        dx = x1 - x0;
    }
    
    int32_t dy;
     if (y0>y1) {
        dy = y0 - y1;
    }else{
        dy = y1 - y0;
    }

    if (dx >= dy) {
        drawLineH(x0, y0, x1, y1, color);
    } else {
        drawLineV(x0, y0, x1, y1, color);
    }
}

void drawRectangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color){
    uint16_t i;
    if(x1<x0){
        i = x0;
        x0 = x1;
        x1 = i;
    }
    if(y1<y0){
        i = y0;
        y0 = y1;
        y1 = i;
    }
    i = x0;
    while(i <= x1){
        plotPixel(i, y0, color);
        plotPixel(i, y1, color);
        i++;
    }
    i = y0;
    while(i < y1){
        plotPixel(x0, i, color);
        plotPixel(x1, i, color);
        i++;
    }
}

void drawFilledRectangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint32_t color){
    uint16_t i;
    if(x1<x0){
        i = x0;
        x0 = x1;
        x1 = i;
    }
    if(y1<y0){
        i = y0;
        y0 = y1;
        y1 = i;
    }
    i = x0;
    while(i <= x1){
        for(int j = y0; j<y1; j++){
           plotPixel(i, j, color); 
        }
        i++;
    }
    i = y0;
    while(i < y1){
        for(int j = x0; j<x1; j++) {
            plotPixel(j, i, color);
        }
        i++;
    }
}

/*void drawChar(uint16_t x, uint16_t y, uint32_t color, char c) {
    if (c < 32)  return; 
    if (c > 126) return; 

    c-=32;
    for(short row = 0; row < FONT_HEIGHT; row++) {
        for(short col = 0; col < FONT_LENGHT; col++) {
            plotPixel(x+(FONT_LENGHT-col), y+row, (font[c*FONT_HEIGHT+row]>>col)&0x1);
        }
    }
}

void drawText(uint16_t x, uint16_t y, uint32_t color, char* text) {
    for(int i = 0; text[i]; i++){
        drawChar(x, y, color, text[i]);
        x += FONT_LENGHT;
    }
}*/


void drawBitmap(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint32_t* bitmap){
    for(short row = 0; row < w; row++) {
        for(short col = 0; col < h; col++) {
            plotPixel(x+(w-col), y+row, bitmap[row*w + col]);
        }
    }
}
void drawTriangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color){
    drawLine(x0, y0, x1, y1, color);
    drawLine(x2, y2, x1, y1, color);
    drawLine(x2, y2, x0, y0, color);
}

#define SWAP_INT(a, b) { int16_t t = a; a = b; b = t; }

static void drawFastHLine(int16_t x0, int16_t x1, int16_t y, uint32_t color) {
    if (x0 > x1) SWAP_INT(x0, x1);
    for (int16_t x = x0; x <= x1; x++) {
        plotPixel(x, y, color);
    }
}

void drawFilledTriangle(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    // 1. Trier les sommets par Y croissant (y0 <= y1 <= y2) pour balayer de haut en bas
    if (y0 > y1) { SWAP_INT(y0, y1); SWAP_INT(x0, x1); }
    if (y1 > y2) { SWAP_INT(y1, y2); SWAP_INT(x1, x2); }
    if (y0 > y1) { SWAP_INT(y0, y1); SWAP_INT(x0, x1); }

    // Cas trivial : le triangle est une simple ligne horizontale (hauteur nulle)
    if (y0 == y2) { 
        // Tri sur X pour s'assurer du sens
        if (x0 > x1) SWAP_INT(x0, x1);
        if (x1 > x2) SWAP_INT(x1, x2);
        if (x0 > x1) SWAP_INT(x0, x1);
        drawFastHLine(x0, x2, y0, color);
        return;
    }

    // 2. Calcul des pentes inverses (dx/dy) en virgule fixe (format 16.16)
    // Cela indique de combien de sous-pixels on avance en X pour chaque ligne Y
    int32_t dx01 = (y1 > y0) ? ((x1 - x0) << 16) / (y1 - y0) : 0;
    int32_t dx02 = ((x2 - x0) << 16) / (y2 - y0); // Pas de division par 0 car y2 > y0 garanti
    int32_t dx12 = (y2 > y1) ? ((x2 - x1) << 16) / (y2 - y1) : 0;

    // Accumulateurs X pour le bord court (curX1) et le bord long (curX2)
    int32_t curX1 = (int32_t)x0 << 16;
    int32_t curX2 = (int32_t)x0 << 16;

    // 3. Boucle principale de balayage de la ligne du haut (y0) jusqu'en bas (y2)
    for (int16_t y = y0; y <= y2; y++) {
        
        // Dès qu'on atteint le sommet du milieu (y1), le bord court change de trajectoire
        if (y == y1) {
            curX1 = (int32_t)x1 << 16; // Correction de précision pour s'ancrer au pixel exact
            if (y0 == y1) {
                // Cas spécifique du triangle plat en haut
                curX2 = (int32_t)x0 << 16;
            }
        }

        // Dessin de la ligne entre le bord court et le bord long
        drawFastHLine(curX1 >> 16, curX2 >> 16, y, color);

        // Mise à jour des coordonnées X pour la ligne Y suivante
        if (y < y1) {
            curX1 += dx01; // On suit le segment [Point0 -> Point1]
        } else {
            curX1 += dx12; // On suit le segment [Point1 -> Point2]
        }
        
        curX2 += dx02; // Le bord long suit toujours le segment [Point0 -> Point2]
    }
}