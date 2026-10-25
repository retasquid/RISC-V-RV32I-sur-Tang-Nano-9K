/* demo.c
 * Demo graphique pour le RISC-V RV32I de la Tang Nano 9K, ecran 320x200 en
 * 16 niveaux de gris (affiche en 640x400). Cinq parties enchainees avec des
 * cartons de titre et des fondus au noir :
 *   1. intro
 *   2. champ d'etoiles 3D (eclat selon la distance) + texte defilant en vague
 *   3. jeu de la vie plein ecran avec trainees (64 000 cellules)
 *   4. plasma anime (16 gris + tramage 2x2)
 *   5. tore 3D en fil de fer, assombri avec la profondeur
 * Tout en entiers : pas de FPU, et pas de multiplication dans les boucles
 * chaudes (RV32I : la multiplication est une routine logicielle). Les 8
 * pixels d'un mot sont souvent traites ensemble (fondu, jeu de la vie).
 * Les tampons rapides sont dans la VRAM hors ecran (mots 8000 a 8191, acces
 * en 2 cycles) plutot qu'en PSRAM (25 a 30 cycles).
 *
 * Compilation : comp.bat demo.c flash
 * Simulation  : -DSIM (attentes raccourcies), -DDEMO_PART=n (une partie,
 *               sans fondu, pour relever l'image)
 */
#include <stdint.h>
#include "periph.h"
#include "font.c"

#define VRAM    ((volatile uint32_t *)0xC0000000)
#define WPL     40                                    /* mots par ligne */
#define SPARE   ((volatile uint32_t *)0xC0007D00)     /* mots 8000..8191, hors ecran */
#define SPARE8  ((volatile uint8_t  *)0xC0007D00)
#define NIB     0x11111111u                           /* bit 0 de chaque pixel */

/* sin(2*pi*i/256) en virgule fixe Q14 */
static const int16_t SIN[256] = {
         0,    402,    804,   1205,   1606,   2006,   2404,   2801,   3196,   3590,   3981,   4370,   4756,   5139,   5520,   5897,
      6270,   6639,   7005,   7366,   7723,   8076,   8423,   8765,   9102,   9434,   9760,  10080,  10394,  10702,  11003,  11297,
     11585,  11866,  12140,  12406,  12665,  12916,  13160,  13395,  13623,  13842,  14053,  14256,  14449,  14635,  14811,  14978,
     15137,  15286,  15426,  15557,  15679,  15791,  15893,  15986,  16069,  16143,  16207,  16261,  16305,  16340,  16364,  16379,
     16383,  16379,  16364,  16340,  16305,  16261,  16207,  16143,  16069,  15986,  15893,  15791,  15679,  15557,  15426,  15286,
     15137,  14978,  14811,  14635,  14449,  14256,  14053,  13842,  13623,  13395,  13160,  12916,  12665,  12406,  12140,  11866,
     11585,  11297,  11003,  10702,  10394,  10080,   9760,   9434,   9102,   8765,   8423,   8076,   7723,   7366,   7005,   6639,
      6270,   5897,   5520,   5139,   4756,   4370,   3981,   3590,   3196,   2801,   2404,   2006,   1606,   1205,    804,    402,
         0,   -402,   -804,  -1205,  -1606,  -2006,  -2404,  -2801,  -3196,  -3590,  -3981,  -4370,  -4756,  -5139,  -5520,  -5897,
     -6270,  -6639,  -7005,  -7366,  -7723,  -8076,  -8423,  -8765,  -9102,  -9434,  -9760, -10080, -10394, -10702, -11003, -11297,
    -11585, -11866, -12140, -12406, -12665, -12916, -13160, -13395, -13623, -13842, -14053, -14256, -14449, -14635, -14811, -14978,
    -15137, -15286, -15426, -15557, -15679, -15791, -15893, -15986, -16069, -16143, -16207, -16261, -16305, -16340, -16364, -16379,
    -16384, -16379, -16364, -16340, -16305, -16261, -16207, -16143, -16069, -15986, -15893, -15791, -15679, -15557, -15426, -15286,
    -15137, -14978, -14811, -14635, -14449, -14256, -14053, -13842, -13623, -13395, -13160, -12916, -12665, -12406, -12140, -11866,
    -11585, -11297, -11003, -10702, -10394, -10080,  -9760,  -9434,  -9102,  -8765,  -8423,  -8076,  -7723,  -7366,  -7005,  -6639,
     -6270,  -5897,  -5520,  -5139,  -4756,  -4370,  -3981,  -3590,  -3196,  -2801,  -2404,  -2006,  -1606,  -1205,   -804,   -402,
};

/* 30 + 30*sin(2*pi*i/256), 0..60 : quatre ondes du plasma <= 240, et
 * 240 + 12 (seuil de tramage) tient dans 0..15 apres >> 4 */
static const uint8_t SIN60[256] = {
     30,  31,  31,  32,  33,  34,  34,  35,  36,  37,  37,  38,  39,  39,  40,  41,
     41,  42,  43,  43,  44,  45,  45,  46,  47,  47,  48,  48,  49,  50,  50,  51,
     51,  52,  52,  53,  53,  54,  54,  55,  55,  55,  56,  56,  56,  57,  57,  57,
     58,  58,  58,  58,  59,  59,  59,  59,  59,  60,  60,  60,  60,  60,  60,  60,
     60,  60,  60,  60,  60,  60,  60,  60,  59,  59,  59,  59,  59,  58,  58,  58,
     58,  57,  57,  57,  56,  56,  56,  55,  55,  55,  54,  54,  53,  53,  52,  52,
     51,  51,  50,  50,  49,  48,  48,  47,  47,  46,  45,  45,  44,  43,  43,  42,
     41,  41,  40,  39,  39,  38,  37,  37,  36,  35,  34,  34,  33,  32,  31,  31,
     30,  29,  29,  28,  27,  26,  26,  25,  24,  23,  23,  22,  21,  21,  20,  19,
     19,  18,  17,  17,  16,  15,  15,  14,  13,  13,  12,  12,  11,  10,  10,   9,
      9,   8,   8,   7,   7,   6,   6,   5,   5,   5,   4,   4,   4,   3,   3,   3,
      2,   2,   2,   2,   1,   1,   1,   1,   1,   0,   0,   0,   0,   0,   0,   0,
      0,   0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,   1,   2,   2,   2,
      2,   3,   3,   3,   4,   4,   4,   5,   5,   5,   6,   6,   7,   7,   8,   8,
      9,   9,  10,  10,  11,  12,  12,  13,  13,  14,  15,  15,  16,  17,  17,  18,
     19,  19,  20,  21,  21,  22,  23,  23,  24,  25,  26,  26,  27,  28,  29,  29,
};

/* ------------------------------------------------------------------------ */
/* Outils                                                                   */
/* ------------------------------------------------------------------------ */

static uint32_t seed = 0x2545F491;
static int fade_on = 1;

static uint32_t rnd(void)
{
    uint32_t x = seed;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return seed = x;
}

/* Attente exacte avec le timer materiel ; raccourcie en simulation */
static void wait_ms(int ms)
{
#ifdef SIM
    ms >>= 5;
#endif
    delay_ms(ms);
}

static void cls(void)
{
    volatile uint32_t *p = VRAM;
    for (int i = 0; i < 8000; i += 4, p += 4) {
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0;
    }
}

/* Pixel (x, y) de gris c ; pixel de gauche d'un mot = bits 31..28 */
static inline void pix(int x, int y, uint32_t c)
{
    volatile uint32_t *p = VRAM + y * WPL + (x >> 3);
    int sh = 28 - ((x & 7) << 2);
    *p = (*p & ~(15u << sh)) | (c << sh);
}

/* Pixel qui ne fait qu'eclaircir (texte lisse sur un fond) */
static inline void pix_max(int x, int y, uint32_t c)
{
    volatile uint32_t *p = VRAM + y * WPL + (x >> 3);
    int sh = 28 - ((x & 7) << 2);
    if (((*p >> sh) & 15) < c)
        *p = (*p & ~(15u << sh)) | (c << sh);
}

/* Segment de Bresenham de gris c (0 = efface). Un segment qui sort de
 * l'ecran est ignore (les objets de la demo restent dedans). */
static void line(int x0, int y0, int x1, int y1, uint32_t c)
{
    if ((unsigned)x0 >= 320 || (unsigned)x1 >= 320 ||
        (unsigned)y0 >= 200 || (unsigned)y1 >= 200)
        return;
    int dx = x1 - x0, dy = y1 - y0, sy = WPL, right = 1;
    if (dx < 0) { dx = -dx; right = 0; }
    if (dy < 0) { dy = -dy; sy = -WPL; }
    volatile uint32_t *p = VRAM + y0 * WPL + (x0 >> 3);
    int sh = 28 - ((x0 & 7) << 2);
    int n = dx > dy ? dx : dy;
    int err = dx - dy;
    for (;;) {
        *p = (*p & ~(15u << sh)) | (c << sh);
        if (n-- == 0)
            break;
        int e2 = err << 1;
        if (e2 > -dy) {
            err -= dy;
            if (right) {
                sh -= 4;
                if (sh < 0) { sh = 28; p++; }
            } else {
                sh += 4;
                if (sh > 28) { sh = 0; p--; }
            }
        }
        if (e2 < dx) {
            err += dx;
            p += sy;
        }
    }
}

/* Fondu au noir : chaque pixel non nul perd un niveau, 8 pixels par mot a
 * la fois (aucune retenue ne passe d'un pixel au suivant) */
static void fade_out(void)
{
    if (!fade_on)
        return;
    for (int s = 0; s < 15; s++) {
        volatile uint32_t *p = VRAM;
        for (int i = 0; i < 8000; i++) {
            uint32_t v = p[i];
            p[i] = v - ((v | (v >> 1) | (v >> 2) | (v >> 3)) & NIB);
        }
        wait_ms(12);
    }
}

/* Police 16x21 (font.c) : les caracteres n'occupent que les colonnes 6 a
 * 15 de leur case (10 pixels, cales a droite) : on les dessine a partir de
 * la colonne 6, avec un pas de 11 pixels */
#define F16_COL0 6
#define F16_STEP 11
#define F8_STEP  6

/* Grande police en gris g */
static void char16(int x, int y, char ch, uint32_t g)
{
    if (ch < 32 || ch > 126)
        return;
    const short *f = &font[(ch - 32) * 21];
    for (int r = 0; r < 21; r++) {
        int bits = f[r];
        for (int col = F16_COL0; col < 16; col++)
            if (bits & (1 << (15 - col)))
                pix_max(x + col - F16_COL0, y + r, g);
    }
}

/* Petite police 8x11 lissee : la police 16x21 reduite de moitie, chaque
 * pixel prend un gris proportionnel au nombre de points du bloc 2x2 */
static void char8(int x, int y, char ch, uint32_t g)
{
    if (ch < 32 || ch > 126)
        return;
    const short *f = &font[(ch - 32) * 21];
    for (int r = 0; r < 11; r++) {
        int b0 = f[2 * r], b1 = (2 * r + 1 < 21) ? f[2 * r + 1] : 0;
        for (int col = F16_COL0 / 2; col < 8; col++) {
            int s = 14 - 2 * col;
            int n = ((b0 >> s) & 1) + ((b0 >> (s + 1)) & 1) +
                    ((b1 >> s) & 1) + ((b1 >> (s + 1)) & 1);
            /* g * n / 4 sans multiplication (n = 0..4) */
            uint32_t lvl = ((n & 1) ? g : 0) + ((n & 2) ? g << 1 : 0) + ((n & 4) ? g << 2 : 0);
            lvl >>= 2;
            if (lvl)
                pix_max(x + col - F16_COL0 / 2, y + r, lvl);
        }
    }
}

static int slen(const char *t)
{
    int n = 0;
    while (t[n])
        n++;
    return n;
}

static void text16(int y, const char *t, uint32_t g)
{
    int n = slen(t);
    int x = (320 - (n * F16_STEP - 1)) >> 1;
    for (int i = 0; t[i]; i++, x += F16_STEP)
        char16(x, y, t[i], g);
}

static void text8(int y, const char *t, uint32_t g)
{
    int n = slen(t);
    int x = (320 - (n * F8_STEP - 1)) >> 1;
    for (int i = 0; t[i]; i++, x += F8_STEP)
        char8(x, y, t[i], g);
}

/* Titre qui apparait progressivement */
static void text16_fade_in(int y, const char *t)
{
    for (uint32_t g = 3; g <= 15; g += 3) {
        text16(y, t, g);
        wait_ms(60);
    }
}

static void card(const char *title, const char *l1, const char *l2)
{
    cls();
    text16_fade_in(72, title);
    text8(108, l1, 11);
    text8(122, l2, 11);
    wait_ms(2200);
    fade_out();
}

/* ------------------------------------------------------------------------ */
/* 1. Intro                                                                 */
/* ------------------------------------------------------------------------ */

static void intro(void)
{
    cls();
    text16_fade_in(30, "RISC-V RV32I");
    wait_ms(300);
    text8(62, "un processeur fait maison", 12);
    wait_ms(400);
    /* Rampe des 16 gris : 16 blocs de 16 pixels */
    for (int y = 82; y < 100; y++)
        for (int x = 32; x < 288; x++)
            pix(x, y, (uint32_t)((x - 32) >> 4));
    wait_ms(400);
    text8(112, "Tang Nano 9K - 31,5 MHz - cache 8 Ko", 10);
    text8(126, "VGA 320x200 en 16 niveaux de gris", 10);
    wait_ms(400);
    text8(150, "pas de FPU, pas de multiplieur", 8);
    text8(164, "tout en entiers et en decalages", 8);
    wait_ms(3500);
    fade_out();
}

/* ------------------------------------------------------------------------ */
/* 2. Champ d'etoiles 3D + texte defilant en vague                          */
/* ------------------------------------------------------------------------ */

#define NSTAR   120
#define BAND    130                   /* lignes 130..199 : texte defilant */
#define STAR_CY 64

static int16_t  stx[NSTAR], sty[NSTAR], stz[NSTAR];
static int16_t  stw[NSTAR];           /* mot VRAM du dernier dessin, -1 = aucun */
static uint32_t stm[NSTAR];           /* masque du dernier dessin */
static uint8_t  stb[NSTAR];           /* 1 = etoile proche (2x2) */

/* Degrade "chrome" des 21 lignes de la police */
static const uint8_t CHROME[21] = {
    6, 8, 10, 12, 14, 15, 15, 14, 12, 10, 8, 6, 5, 6, 8, 10, 12, 13, 12, 10, 8
};

static const char SCROLL[] =
    "          BIENVENUE DANS LA DEMO DU RISC-V RV32I FAIT MAISON  ***  "
    "31,5 MHz, CACHE FLASH 8 Ko, ECRAN 320 x 200 EN 16 GRIS  ***  "
    "PAS DE FPU NI DE MULTIPLIEUR : TOUT EN ENTIERS ET EN DECALAGES  ***  ";

static void star_spawn(int i, int z)
{
    stx[i] = (int16_t)((rnd() & 1023) - 512);
    sty[i] = (int16_t)((rnd() & 511) - 256);
    stz[i] = (int16_t)z;
}

static void scroller(int pos, int phase)
{
    volatile uint32_t *p = VRAM + BAND * WPL;
    for (int i = 0; i < (200 - BAND) * WPL; i += 4, p += 4) {
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0;
    }
    const int len = sizeof(SCROLL) - 1;
    int ci = 0, sub = pos;                       /* pos < len * F16_STEP */
    while (sub >= F16_STEP) {
        sub -= F16_STEP;
        ci++;
    }
    const short *g = &font[(SCROLL[ci] - 32) * 21];
    for (int x = 0; x < 320; x++) {
        int bit = 15 - F16_COL0 - sub;
        int y0 = 155 + ((SIN[(x * 3 + phase) & 255] * 16) >> 14);
        volatile uint32_t *q = VRAM + y0 * WPL + (x >> 3);
        int sh = 28 - ((x & 7) << 2);
        for (int r = 0; r < 21; r++, q += WPL)
            if ((g[r] >> bit) & 1)
                *q |= (uint32_t)CHROME[r] << sh;      /* bande effacee : OU suffit */
        if (++sub == F16_STEP) {
            sub = 0;
            if (++ci == len)
                ci = 0;
            g = &font[(SCROLL[ci] - 32) * 21];
        }
    }
}

static void stars(int frames)
{
    cls();
    for (int i = 0; i < NSTAR; i++) {
        star_spawn(i, 64 + (rnd() & 1023) % 960);
        stw[i] = -1;
    }
    const int scroll_len = (sizeof(SCROLL) - 1) * F16_STEP;
    int pos = 0;
    for (int f = 0; f < frames; f++) {
        for (int i = 0; i < NSTAR; i++) {
            /* Effacement du dessin precedent */
            if (stw[i] >= 0) {
                VRAM[stw[i]] &= ~stm[i];
                if (stb[i])
                    VRAM[stw[i] + WPL] &= ~stm[i];
            }
            stw[i] = -1;
            int z = stz[i] - 8;
            if (z < 24) {
                star_spawn(i, 1023);
                continue;
            }
            stz[i] = (int16_t)z;
            int x = 160 + (stx[i] * 128) / z;
            int y = STAR_CY + (sty[i] * 128) / z;
            if ((unsigned)x >= 319 || (unsigned)y >= BAND - 4) {
                star_spawn(i, 1023);
                continue;
            }
            /* Eclat : 15 tout pres, 2 au loin */
            uint32_t c = z < 128 ? 15 : 15 - (uint32_t)((z - 128) >> 6);
            int w = y * WPL + (x >> 3);
            int sh = 28 - ((x & 7) << 2);
            uint32_t m = 15u << sh, v = c << sh;
            int big = z < 220 && (x & 7) != 7;
            if (big) {
                m |= m >> 4;
                v |= v >> 4;
            }
            VRAM[w] = (VRAM[w] & ~m) | v;
            if (big)
                VRAM[w + WPL] = (VRAM[w + WPL] & ~m) | v;
            stw[i] = (int16_t)w;
            stm[i] = m;
            stb[i] = (uint8_t)big;
        }
        scroller(pos, f * 4);
        pos += 2;
        if (pos >= scroll_len)
            pos -= scroll_len;
    }
    fade_out();
}

/* ------------------------------------------------------------------------ */
/* 3. Jeu de la vie 320 x 200 avec trainees, bords morts                    */
/* ------------------------------------------------------------------------ */

/* Masque des cellules vivantes (pixel = 15) : bit 0 de chaque quartet */
static inline uint32_t alive(uint32_t v)
{
    return v & (v >> 1) & (v >> 2) & (v >> 3) & NIB;
}

/* Une generation, en place dans la VRAM, 8 cellules par mot. Une cellule
 * vivante vaut 15 ; une morte s'eteint de 2 niveaux par generation (trainee).
 * Les 8 voisins sont alignes par decalages de 4 bits et additionnes : la
 * somme (0..8) tient dans chaque quartet, sans retenue vers le voisin.
 * Les masques "vivant" de l'ancienne ligne du dessus et de la ligne
 * courante sont gardes en VRAM hors ecran. */
static void life_step(void)
{
    volatile uint32_t *up = SPARE, *cur = SPARE + 64, *t;
    for (int w = 0; w < WPL; w++)
        up[w] = 0;
    for (int y = 0; y < 200; y++) {
        volatile uint32_t *row = VRAM + y * WPL;
        volatile uint32_t *dn = row + WPL;
        int last = (y == 199);
        uint32_t aP = 0, aC = up[0];
        uint32_t vC = row[0], cP = 0, cC = alive(vC);
        uint32_t bP = 0, bC = last ? 0 : alive(dn[0]);
        for (int w = 0; w < WPL; w++) {
            uint32_t aN = 0, vN = 0, cN = 0, bN = 0;
            if (w < WPL - 1) {
                aN = up[w + 1];
                vN = row[w + 1];
                cN = alive(vN);
                if (!last)
                    bN = alive(dn[w + 1]);
            }
            cur[w] = cC;
            /* voisins ouest (quartet de gauche) et est, sur chaque ligne */
            uint32_t s = ((aC >> 4) | (aP << 28)) + aC + ((aC << 4) | (aN >> 28))
                       + ((cC >> 4) | (cP << 28)) +      ((cC << 4) | (cN >> 28))
                       + ((bC >> 4) | (bP << 28)) + bC + ((bC << 4) | (bN >> 28));
            /* vivante si 3 voisins, ou 2 et deja vivante */
            uint32_t na = (s >> 1) & ~(s >> 2) & ~(s >> 3) & (s | cC) & NIB;
            uint32_t full = (na << 4) - na;                       /* 15 par vivante */
            /* extinction : -1 si >= 1, et encore -1 si >= 2 */
            uint32_t d = vC - ((vC | (vC >> 1) | (vC >> 2) | (vC >> 3)) & NIB)
                            - (((vC >> 1) | (vC >> 2) | (vC >> 3)) & NIB);
            row[w] = (d & ~full) | full;
            aP = aC; aC = aN;
            cP = cC; cC = cN; vC = vN;
            bP = bC; bC = bN;
        }
        t = up; up = cur; cur = t;
    }
}

static void life_seed(void)
{
    for (int i = 0; i < 8000; i++) {
        uint32_t m = rnd() & (rnd() | rnd()) & NIB;          /* 37,5 % de vivantes */
        VRAM[i] = (m << 4) - m;
    }
}

static void life(int gens, int reseed)
{
    for (int g = 0; g < gens; g++) {
        if (g % reseed == 0)
            life_seed();
        life_step();
    }
    fade_out();
}

/* ------------------------------------------------------------------------ */
/* 4. Plasma : 160 x 100 cases de 2x2 pixels, 16 gris + tramage 2x2         */
/* ------------------------------------------------------------------------ */

static void plasma_frame(int t)
{
    /* Quatre ondes : horizontale (A), verticale (calculee par ligne), et
     * deux diagonales (C : x + y, D : x - y), tables d'octets en VRAM */
    volatile uint8_t *A = SPARE8, *C = SPARE8 + 160, *D = SPARE8 + 420;
    int u = t;
    for (int i = 0; i < 160; i++, u += 3)
        A[i] = SIN60[u & 255];
    u = t * 2;
    for (int i = 0; i < 260; i++, u += 2)
        C[i] = SIN60[u & 255];
    u = -t;
    for (int i = 0; i < 260; i++, u += 3)
        D[i] = SIN60[u & 255];

    int v0 = t * 3;
    for (int cy = 0; cy < 100; cy++, v0 += 5) {
        volatile uint32_t *p = VRAM + cy * (2 * WPL);
        int b = SIN60[v0 & 255];
        volatile uint8_t *a = A, *c = C + cy, *d = D + 99 - cy;
        for (int w = 0; w < WPL; w++) {
            uint32_t r0 = 0, r1 = 0;
            for (int k = 0; k < 4; k++) {
                uint32_t v = *a++ + b + *c++ + *d++;          /* 0..240 */
                /* tramage 2x2 : seuils 0, 8 (ligne 0) et 12, 4 (ligne 1) */
                r0 = (r0 << 8) | ((v >> 4) << 4) | ((v + 8) >> 4);
                r1 = (r1 << 8) | (((v + 12) >> 4) << 4) | ((v + 4) >> 4);
            }
            p[w] = r0;
            p[w + WPL] = r1;
        }
    }
}

static void plasma(int frames)
{
    for (int f = 0; f < frames; f++)
        plasma_frame(f * 2);
    fade_out();
}

/* ------------------------------------------------------------------------ */
/* 5. Tore 3D en fil de fer, assombri avec la profondeur                    */
/* ------------------------------------------------------------------------ */

#define TU 16                         /* sections autour de l'axe */
#define TV 8                          /* points par section */
#define NVTX (TU * TV)

static int16_t tvx[NVTX], tvy[NVTX], tvz[NVTX];
static int16_t tpx[2][NVTX], tpy[2][NVTX], tpz[NVTX];

static void torus_init(void)
{
    for (int u = 0; u < TU; u++)
        for (int v = 0; v < TV; v++) {
            int cu = SIN[(u * 16 + 64) & 255], su = SIN[u * 16];
            int cv = SIN[(v * 32 + 64) & 255], sv = SIN[v * 32];
            int rr = 55 + ((22 * cv) >> 14);
            int i = u * TV + v;
            tvx[i] = (int16_t)((rr * cu) >> 14);
            tvy[i] = (int16_t)((rr * su) >> 14);
            tvz[i] = (int16_t)((22 * sv) >> 14);
        }
}

/* Gris d'une arete selon la profondeur moyenne de ses extremites
 * (z > 0 = loin : plus sombre) */
static inline uint32_t depth_gray(int za, int zb)
{
    int g = 9 - ((za + zb) >> 5);
    return (uint32_t)(g < 3 ? 3 : g > 15 ? 15 : g);
}

static void torus_draw(int16_t *px, int16_t *py, int shade)
{
    for (int u = 0; u < TU; u++) {
        int un = (u + 1 == TU) ? 0 : u + 1;
        for (int v = 0; v < TV; v++) {
            int vn = (v + 1 == TV) ? 0 : v + 1;
            int i = u * TV + v, j = un * TV + v, k = u * TV + vn;
            line(px[i], py[i], px[j], py[j], shade ? depth_gray(tpz[i], tpz[j]) : 0);
            line(px[i], py[i], px[k], py[k], shade ? depth_gray(tpz[i], tpz[k]) : 0);
        }
    }
}

static void torus(int frames)
{
    cls();
    int cur = 0, have_old = 0;
    for (int f = 0; f < frames; f++) {
        int a = f * 2, b = f * 3;
        int ca = SIN[(a + 64) & 255], sa = SIN[a & 255];
        int cb = SIN[(b + 64) & 255], sb = SIN[b & 255];
        int16_t *px = tpx[cur], *py = tpy[cur];
        if (have_old)
            torus_draw(tpx[cur ^ 1], tpy[cur ^ 1], 0);
        for (int i = 0; i < NVTX; i++) {
            int x = tvx[i], y = tvy[i], z = tvz[i];
            int y1 = (y * ca - z * sa) >> 14;          /* rotation autour de X */
            int z1 = (y * sa + z * ca) >> 14;
            int x2 = (x * cb + z1 * sb) >> 14;         /* puis autour de Y */
            int z2 = (z1 * cb - x * sb) >> 14;
            int d = z2 + 200;
            px[i] = (int16_t)(160 + (x2 * 150) / d);
            py[i] = (int16_t)(100 + (y1 * 150) / d);
            tpz[i] = (int16_t)z2;
        }
        torus_draw(px, py, 1);
        have_old = 1;
        cur ^= 1;
    }
    fade_out();
}

/* ------------------------------------------------------------------------ */

int main(void)
{
    serialInit(115200UL);
    DIRGPIO0 = 0xffff;
    serialWrite("demo RISC-V RV32I\r\n");
    torus_init();
#ifdef DEMO_PART
    fade_on = 0;
    for (;;) {
        GPIO0 = DEMO_PART;
        if (DEMO_PART == 1) intro();
        if (DEMO_PART == 2) stars(40);
        if (DEMO_PART == 3) { life_seed(); for (int g = 0; g < 6; g++) life_step(); }
        if (DEMO_PART == 4) plasma(2);
        if (DEMO_PART == 5) torus(5);
        GPIO0 = 0x1F;                       /* fin de partie (relevee par le TB) */
    }
#endif
    for (;;) {
        GPIO0 = 1;
        serialWrite("intro\r\n");
        intro();

        GPIO0 = 2;
        serialWrite("etoiles\r\n");
        card("ETOILES", "120 etoiles en 3D, eclat selon la", "distance, et un texte en vague");
        stars(1500);

        GPIO0 = 3;
        serialWrite("jeu de la vie\r\n");
        card("LA VIE", "320 x 200 = 64 000 cellules, 8 par", "operation, avec des trainees");
        life(1200, 400);

        
        GPIO0 = 4;
        serialWrite("plasma\r\n");
        card("PLASMA", "quatre ondes, 16 gris", "et un tramage 2 x 2");
        plasma(700);

        GPIO0 = 5;
        serialWrite("tore\r\n");
        card("TORE 3D", "128 sommets, 256 aretes,", "assombri avec la profondeur");
        torus(900);
    }
}
