/* vga_demo.c
 * Mire de l'ecran 320x200 en 16 niveaux de gris : cadre, eventail de lignes,
 * damier, triangle plein et rampe des 16 gris en bas de l'ecran.
 * Compilation : comp.bat vga_demo.c flash
 * La progression est envoyee sur l'UART (115200 bauds).
 */
#include "periph.h"
#include "lib2d.h"

int main(void)
{
    DIRGPIO0 = 0xffff;
    serialInit(115200UL);
    serialWrite("VGA : effacement\r\n");
    clearScreen(0);

    serialWrite("VGA : cadre et lignes\r\n");
    drawRectangle(0, 0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1, 15);
    for (int x = 0; x < SCREEN_WIDTH; x += 20)
        drawLine(160, 90, x, 0, 15);
    for (int x = 0; x < SCREEN_WIDTH; x += 20)
        drawLine(160, 90, x, 169, 8);

    serialWrite("VGA : damier\r\n");
    /* Damier 16x16 pixels dans le coin haut gauche : 2 mots = 16 pixels */
    volatile uint32_t *vram = (volatile uint32_t *)SCREEN_P_BEGIN;
    for (int y = 4; y < 68; y++)
        for (int w = 0; w < 8; w++)
            vram[y * SCREEN_WPL + w] = ((((y - 4) >> 4) + (w >> 1)) & 1) ? 0xFFFFFFFF : 0x00000000;

    serialWrite("VGA : triangle\r\n");
    drawFilledTriangle(240, 150, 300, 165, 210, 165, 12);

    serialWrite("VGA : rampe de gris\r\n");
    /* 16 bandes de 20 pixels, gris 0 a 15, lignes 172 a 198 */
    for (int y = 172; y < 199; y++)
        for (int x = 1; x < SCREEN_WIDTH - 1; x++)
            plotPixel(x, y, x / 20);

    serialWrite("VGA : termine\r\n");
    GPIO0 = 0x1f;
    for (;;) {}
}
