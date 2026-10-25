/* vga_demo.c
 * Demonstration du VGA 640x400 monochrome : cadre, mire de lignes, damier et
 * triangle plein. Compilation : comp.bat vga_demo.c flash
 * La progression est envoyee sur l'UART (115200 bauds).
 */
#include "periph.h"
#include "lib2d.h"

int main(void)
{
    DIRGPIO0 = 0xffff;
    serialInit(115200UL);
    serialWrite("VGA : effacement\r\n");
    clearScreen(0x00000000);

    serialWrite("VGA : cadre et lignes\r\n");
    drawRectangle(0, 0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1, 1);
    for (int x = 0; x < SCREEN_WIDTH; x += 40)
        drawLine(320, 200, x, 0, 1);
    for (int x = 0; x < SCREEN_WIDTH; x += 40)
        drawLine(320, 200, x, SCREEN_HEIGHT - 1, 1);

    serialWrite("VGA : damier\r\n");
    /* Damier 32x32 pixels dans le coin haut gauche : un mot = 32 pixels */
    volatile uint32_t *vram = (volatile uint32_t *)SCREEN_P_BEGIN;
    for (int y = 8; y < 136; y++)
        for (int w = 0; w < 4; w++)
            vram[y * 20 + w] = (((y - 8) / 32 + w) & 1) ? 0xFFFFFFFF : 0x00000000;

    serialWrite("VGA : triangle\r\n");
    drawFilledTriangle(480, 300, 600, 380, 420, 380, 1);

    serialWrite("VGA : termine\r\n");
    GPIO0 = 0x1f;
    for (;;) {}
}
