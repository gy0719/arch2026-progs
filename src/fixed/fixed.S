# RV32I leaf functions. Arguments and results use a0-a2; t registers
# are caller-saved. q_mul uses pairs t1:t0 and t3:t2 for 64-bit values.
    .text
    .globl op1_asm
    .type op1_asm, @function
    .align 2
op1_asm:
    li t0, 0
    beqz a1, .Ladd_done
.Ladd_loop:
    and t1, a0, a1
    xor a0, a0, a1
    slli a1, t1, 1
    addi t0, t0, 1
    bnez a1, .Ladd_loop
.Ladd_done:
    sw t0, 0(a2)
    ret
    .size op1_asm, .-op1_asm

    .globl op2_asm
    .type op2_asm, @function
    .align 2
op2_asm:
    sub a0, a0, a1
    ret
    .size op2_asm, .-op2_asm

    .globl op3_asm
    .type op3_asm, @function
    .align 2
op3_asm:
    and t0, a0, a1
    xor a0, a0, a1
    srli a0, a0, 1
    add a0, a0, t0
    ret
    .size op3_asm, .-op3_asm

    .globl q_mul_asm
    .type q_mul_asm, @function
    .align 2
q_mul_asm:
    # Take unsigned magnitudes without overflowing on INT32_MIN.
    srai t4, a0, 31
    srai t5, a1, 31
    xor t6, t4, t5
    xor t2, a0, t4
    sub t2, t2, t4
    xor a1, a1, t5
    sub a1, a1, t5
    li t0, 0
    li t1, 0
    li t3, 0
    beqz a1, .Lmul_signed
.Lmul_loop:
    andi t4, a1, 1
    beqz t4, .Lmul_shift
    add t0, t0, t2
    sltu t5, t0, t2
    add t1, t1, t3
    add t1, t1, t5
.Lmul_shift:
    srli t4, t2, 31
    slli t3, t3, 1
    or t3, t3, t4
    slli t2, t2, 1
    srli a1, a1, 1
    bnez a1, .Lmul_loop
.Lmul_signed:
    beqz t6, .Lmul_round
    # Two's-complement the full 64-bit product.
    seqz t4, t0
    neg t0, t0
    not t1, t1
    add t1, t1, t4
.Lmul_round:
    # Rounding adds bit 19 to bits 20 through 51 modulo 2^32.
    srli t2, t0, 20
    slli t1, t1, 12
    or t2, t2, t1
    srli t0, t0, 19
    andi t0, t0, 1
    add a0, t2, t0
    ret
    .size q_mul_asm, .-q_mul_asm
