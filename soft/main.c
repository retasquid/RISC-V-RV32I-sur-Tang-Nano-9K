//#include"lib2d.h"
#include"periph.h"

char buf[16];

int main(void)
{
    DIRGPIO0 = 0xffff;
    serialInit(115200UL);
    serialRead(buf, 16);
    serialWrite(buf);
    GPIO0 = 0x1f;
    /*serialWrite("color : \n\r");
    clearScreen(0x00000000);
    for(int i = 0; i<640; i++) drawLine(320, 200, i, 400, 1);
    for(int i = 400; i>0; i--) drawLine(320, 200, 640, i, 1);
    for(int i = 640; i>0; i--) drawLine(320, 200, i, 0, 1);
    for(int i = 0; i<400; i++) drawLine(320, 200, 0, i, 1);
    clearScreen(0x00000000);
    for(int i = 15; i<640; i++) drawLine(10, 10, i, 400, 1);
    for(int i = 400; i>15; i--) drawLine(10, 10, 640, i, 1);
    while (1) {}*/
    return 0;
}