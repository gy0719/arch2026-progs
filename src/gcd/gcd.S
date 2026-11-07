# Leaf function: a0/a1 are the operands, t0 holds the common power of two.
# All temporaries are caller-saved; no stack or memory access is needed.
    .text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function
    .align 2
gcd_u32_asm:
    beqz a0, .Lret_b
    beqz a1, .Lret
    li t0, 0
.Lcommon:
    or t1, a0, a1
    andi t1, t1, 1
    bnez t1, .La_odd
    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    j .Lcommon
# Strip trailing zeroes from a in chunks. The zero input was handled above,
# so after these tests a single final shift is sufficient.
.La_odd:
    andi t1, a0, 1
    bnez t1, .Lb_odd
    slli t1, a0, 16
    bnez t1, .La_8
    srli a0, a0, 16
.La_8:
    andi t1, a0, 255
    bnez t1, .La_4
    srli a0, a0, 8
.La_4:
    andi t1, a0, 15
    bnez t1, .La_2
    srli a0, a0, 4
.La_2:
    andi t1, a0, 3
    bnez t1, .La_1
    srli a0, a0, 2
.La_1:
    andi t1, a0, 1
    bnez t1, .Lb_odd
    srli a0, a0, 1
.Lb_odd:
    andi t1, a1, 1
    bnez t1, .Lcompare
.Lshift_b:
    srli a1, a1, 1
    andi t1, a1, 1
    beqz t1, .Lshift_b
# Both operands are odd. Their nonzero difference is necessarily even.
.Lcompare:
    bltu a1, a0, .Lswap
    sub a1, a1, a0
    bnez a1, .Lshift_b
    j .Ldone
.Lswap:
    sub t1, a0, a1
    mv a0, a1
    mv a1, t1
    j .Lshift_b
.Ldone:
    sll a0, a0, t0
.Lret:
    ret
.Lret_b:
    mv a0, a1
    ret
    .size gcd_u32_asm, .-gcd_u32_asm
