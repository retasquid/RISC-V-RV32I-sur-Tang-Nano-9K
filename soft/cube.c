/* cube.c
 * Cube 3D en fil de fer qui tourne, calcule en flottants (libm logicielle,
 * pas de FPU en RV32I), avec sprintf du numero d'image sur l'UART (115200
 * bauds) et le numero d'image sur les GPIO. Gros programme (~96 Kio de code
 * avec newlib) : sert a mesurer le cache flash.
 * Compilation : comp.bat cube.c flash */
#include <stdio.h>
#include <math.h>
#include "periph.h"
#include "lib2d.h"

static const float V[8][3] = {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
                              {-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}};
static const int E[12][2] = {{0,1},{1,2},{2,3},{3,0},{4,5},{5,6},{6,7},{7,4},
                             {0,4},{1,5},{2,6},{3,7}};
static char txt[32];

int main(void)
{
    serialInit(115200UL);
    clearScreen(0);
    for (int f = 0; ; f++) {
        float a = f * 0.1f, ca = cosf(a), sa = sinf(a), cb = cosf(a * 0.7f), sb = sinf(a * 0.7f);
        int px[8], py[8];
        for (int i = 0; i < 8; i++) {
            float x = V[i][0] * ca - V[i][2] * sa;
            float z = V[i][0] * sa + V[i][2] * ca;
            float y = V[i][1] * cb - z * sb;
            z = V[i][1] * sb + z * cb + 4.0f;
            px[i] = 320 + (int)(160.0f * x / z);
            py[i] = 200 + (int)(160.0f * y / z);
        }
        clearScreen(0);
        for (int e = 0; e < 12; e++)
            drawLine(px[E[e][0]], py[E[e][0]], px[E[e][1]], py[E[e][1]], 1);
        sprintf(txt, "frame %d a=%d.%02d\r\n", f, (int)a, (int)(a * 100) % 100);
        serialWrite(txt);
        GPIO0 = f;
    }
}
