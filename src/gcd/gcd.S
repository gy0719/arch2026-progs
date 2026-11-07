# Binary GCD leaf function: a0/a1 hold operands, t0 the common shift,
# and t1 is a temporary. All registers used are caller-saved.
    .text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function
    .align 2
gcd_u32_asm:
    beqz a0, .Lret_b
    beqz a1, .Lret
    li t0, 0
# Remove the common power of two and restore it at the end.
.Lcommon:
    or t1, a0, a1
    andi t1, t1, 1
    bnez t1, .La_odd
    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    j .Lcommon
# Remove remaining factors of two from each nonzero operand.
.La_odd:
    andi t1, a0, 1
    bnez t1, .Lb_odd
    srli a0, a0, 1
    j .La_odd
.Lb_odd:
    andi t1, a1, 1
    bnez t1, .Lcompare
    srli a1, a1, 1
    j .Lb_odd
# Subtract the smaller odd operand from the larger one.
.Lcompare:
    bleu a0, a1, .Lsubtract
    mv t1, a0
    mv a0, a1
    mv a1, t1
.Lsubtract:
    sub a1, a1, a0
    bnez a1, .Lb_odd
    sll a0, a0, t0
.Lret:
    ret
.Lret_b:
    mv a0, a1
    ret
    .size gcd_u32_asm, .-gcd_u32_asm
