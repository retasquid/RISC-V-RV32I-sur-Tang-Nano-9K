#include <stddef.h>
#include <stdint.h>

void *memset(void *ptr, int value, size_t size)
{
    unsigned char *p = (unsigned char *)ptr;
    unsigned char v = (unsigned char)value;

    /* Aligner dest sur 4 octets avant de passer en écriture par mot */
    while (size && ((uintptr_t)p & (sizeof(uint32_t) - 1))) {
        *p++ = v;
        size--;
    }

    if (size >= sizeof(uint32_t)) {
        /* Réplication par décalages/OR : pas de multiplication,
         * donc pas d'appel à __mulsi3 sur un cœur sans extension M */
        uint32_t vw = (uint32_t)v;
        vw |= vw << 8;
        vw |= vw << 16;

        uint32_t *pw = (uint32_t *)p;
        while (size >= sizeof(uint32_t)) {
            *pw++ = vw;
            size -= sizeof(uint32_t);
        }
        p = (unsigned char *)pw;
    }

    while (size--) *p++ = v;
    return ptr;
}

void *memcpy(void *restrict dest_str, const void *restrict src_str, size_t n)
{
    unsigned char *d = (unsigned char *)dest_str;
    const unsigned char *s = (const unsigned char *)src_str;

    /* Copie par mot de 32 bits uniquement si dest ET src sont alignés sur 4.
     * (d | s) & 3 == 0  <=>  d & 3 == 0 ET s & 3 == 0 */
    if (n >= sizeof(uint32_t) && (((uintptr_t)d | (uintptr_t)s) & (sizeof(uint32_t) - 1)) == 0) {

        uint32_t *dw = (uint32_t *)d;
        const uint32_t *sw = (const uint32_t *)s;

        while (n >= sizeof(uint32_t)) {
            *dw++ = *sw++;
            n -= sizeof(uint32_t);
        }
        d = (unsigned char *)dw;
        s = (const unsigned char *)sw;
    }

    /* Reste (0 à 3 octets), ou totalité si non aligné */
    while (n--) *d++ = *s++;
    return dest_str;
}

int memcmp(const void *restrict str1, const void *restrict str2, size_t n)
{
    const unsigned char *p1 = (const unsigned char *)str1;
    const unsigned char *p2 = (const unsigned char *)str2;

    if (n >= sizeof(uint32_t) && (((uintptr_t)p1 | (uintptr_t)p2) & (sizeof(uint32_t) - 1)) == 0) {

        const uint32_t *w1 = (const uint32_t *)p1;
        const uint32_t *w2 = (const uint32_t *)p2;

        while (n >= sizeof(uint32_t) && *w1 == *w2) {
            w1++;
            w2++;
            n -= sizeof(uint32_t);
        }
        p1 = (const unsigned char *)w1;
        p2 = (const unsigned char *)w2;
    }

    /* Comparaison finale octet par octet : nécessaire pour respecter la
     * norme (comparaison en unsigned char, indépendante de l'endianness),
     * et pour localiser précisément l'octet différent après le fast-path. */
    while (n--) {
        int diff = (int)*p1++ - (int)*p2++;
        if (diff) return diff;
    }
    return 0;
}