#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        ++passes;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* Magnitudes and unsigned arithmetic also handle INT32_MIN safely. */
    uint32_t ma = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t mb = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint32_t lo = 0, hi = 0, term_lo = ma, term_hi = 0;
    while (mb) {
        if (mb & 1u) {
            uint32_t next = lo + term_lo;
            hi += term_hi + (next < lo);
            lo = next;
        }
        term_hi = (term_hi << 1) | (term_lo >> 31);
        term_lo <<= 1;
        mb >>= 1;
    }
    if ((a < 0) != (b < 0)) {
        hi = ~hi + (lo == 0);
        lo = 0u - lo;
    }
    uint32_t rounded = lo + (1u << (Q - 1));
    hi += lo > UINT32_MAX - (1u << (Q - 1));
    uint32_t bits = (rounded >> Q) | (hi << (32 - Q));
    /* Convert the low 32 bits without an out-of-range signed conversion. */
    if (bits <= INT32_MAX)
        return (int32_t) bits;
    return -1 - (int32_t) ~bits;
}
