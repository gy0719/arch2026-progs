#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 255u) == 255u)
        return (uint16_t) (f32bits >> 16);
    return (uint16_t) ((f32bits + 0x7fffu + ((f32bits >> 16) & 1u)) >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;
    unsigned ea = (a >> 7) & 255u, eb = (b >> 7) & 255u;
    uint32_t fa = a & 127u, fb = b & 127u;
    if (ea == 255u) {
        if (fa)
            return a;
        if (!(b & 0x7fffu))
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }
    if (eb == 255u) {
        if (fb)
            return b;
        if (!(a & 0x7fffu))
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }
    if (!(a & 0x7fffu) || !(b & 0x7fffu))
        return (uint16_t) sign;
    int xa = (int) ea, xb = (int) eb;
    if (ea)
        fa |= 128u;
    else {
        xa = 1;
        while (fa < 128u) {
            fa <<= 1;
            --xa;
        }
    }
    if (eb)
        fb |= 128u;
    else {
        xb = 1;
        while (fb < 128u) {
            fb <<= 1;
            --xb;
        }
    }
    uint32_t product = 0;
    while (fb) {
        if (fb & 1u)
            product += fa;
        fa <<= 1;
        fb >>= 1;
    }
    int exponent = xa + xb - 127;
    if (product & 0x8000u) {
        product >>= 8;
        ++exponent;
    } else {
        product >>= 7;
    }
    if (exponent >= 255)
        return (uint16_t) (sign | 0x7f80u);
    if (exponent <= 0) {
        if (exponent < -6)
            return (uint16_t) sign;
        return (uint16_t) (sign | ((product & 127u) >> (1 - exponent)));
    }
    return (uint16_t) (sign | ((uint32_t) exponent << 7) | (product & 127u));
}

uint16_t bf16_sqrt(uint16_t a)
{
    unsigned exponent = (a >> 7) & 255u;
    uint32_t fraction = a & 127u;
    if (exponent == 255u) {
        if (fraction || !(a & 0x8000u))
            return a;
        return 0x7fc0u;
    }
    if (!(a & 0x7fffu))
        return 0;
    if (a & 0x8000u)
        return 0x7fc0u;
    if (!exponent)
        return 0;
    uint32_t m = 128u | fraction;
    if (!(exponent & 1u))
        m <<= 1;
    /* floor(mid*mid/128) <= m iff mid*mid <= 128*(m+1)-1. */
    uint32_t x = ((m + 1u) << 7) - 1u;
    uint32_t root = 0, bit = 1u << 14;
    while (bit) {
        uint32_t trial = root + bit;
        root >>= 1;
        if (x >= trial) {
            x -= trial;
            root += bit;
        }
        bit >>= 2;
    }
    unsigned out_exp = (exponent + 127u) >> 1;
    return (uint16_t) ((out_exp << 7) | (root & 127u));
}
