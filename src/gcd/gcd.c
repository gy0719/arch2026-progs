#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (!a)
        return b;
    if (!b)
        return a;
    /* Save the common power of two before making both operands odd. */
    unsigned shift = 0;
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        ++shift;
    }
    while ((a & 1u) == 0)
        a >>= 1;
    while ((b & 1u) == 0)
        b >>= 1;
    for (;;) {
        if (a > b) {
            uint32_t t = a;
            a = b;
            b = t;
        }
        b -= a;
        if (!b)
            break;
        /* The nonzero difference of two odd numbers is even. */
        do {
            b >>= 1;
        } while ((b & 1u) == 0);
    }
    return a << shift;
}
