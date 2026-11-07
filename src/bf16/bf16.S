# RV32I leaf routines. Arguments and return values use a0/a1; a2-a7 and
# t0-t6 are caller-saved temporaries. No stack or external helpers are used.
    .text
    .globl bf16_from_f32_asm
    .type bf16_from_f32_asm, @function
    .align 2
bf16_from_f32_asm:
    srli t0, a0, 23
    andi t0, t0, 255
    li t1, 255
    beq t0, t1, .Lf32_return
    srli t0, a0, 16
    andi t0, t0, 1
    li t1, 0x7fff
    add a0, a0, t1
    add a0, a0, t0
.Lf32_return:
    srli a0, a0, 16
    ret
    .size bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl bf16_mul_asm
    .type bf16_mul_asm, @function
    .align 2
bf16_mul_asm:
    xor a2, a0, a1
    li t0, 0x8000
    and a2, a2, t0
    srli a3, a0, 7
    andi a3, a3, 255
    srli a4, a1, 7
    andi a4, a4, 255
    andi a5, a0, 127
    andi a6, a1, 127
    li t0, 255
    beq a3, t0, .Lmul_a_special
    beq a4, t0, .Lmul_b_special
    li t0, 0x7fff
    and t1, a0, t0
    and t2, a1, t0
    beqz t1, .Lmul_zero
    beqz t2, .Lmul_zero
    # Normalize denormal significands and track their adjusted exponents.
    bnez a3, .Lmul_a_normal
    li a3, 1
.Lmul_a_norm_loop:
    andi t0, a5, 128
    bnez t0, .Lmul_a_ready
    slli a5, a5, 1
    addi a3, a3, -1
    j .Lmul_a_norm_loop
.Lmul_a_normal:
    ori a5, a5, 128
.Lmul_a_ready:
    bnez a4, .Lmul_b_normal
    li a4, 1
.Lmul_b_norm_loop:
    andi t0, a6, 128
    bnez t0, .Lmul_b_ready
    slli a6, a6, 1
    addi a4, a4, -1
    j .Lmul_b_norm_loop
.Lmul_b_normal:
    ori a6, a6, 128
.Lmul_b_ready:
    # Exact 8-by-8 unsigned product, without the M extension.
    li t0, 0
.Lmul_product:
    andi t1, a6, 1
    beqz t1, .Lmul_no_add
    add t0, t0, a5
.Lmul_no_add:
    slli a5, a5, 1
    srli a6, a6, 1
    bnez a6, .Lmul_product
    add a3, a3, a4
    addi a3, a3, -127
    li t1, 0x8000
    and t1, t1, t0
    beqz t1, .Lmul_low_product
    srli t0, t0, 8
    addi a3, a3, 1
    j .Lmul_pack
.Lmul_low_product:
    srli t0, t0, 7
.Lmul_pack:
    li t1, 255
    bge a3, t1, .Lmul_inf
    andi t0, t0, 127
    blez a3, .Lmul_denormal
    slli a3, a3, 7
    or a0, a2, a3
    or a0, a0, t0
    ret
.Lmul_denormal:
    li t1, -6
    blt a3, t1, .Lmul_zero
    li t1, 1
    sub t1, t1, a3
    srl t0, t0, t1
    or a0, a2, t0
    ret
.Lmul_a_special:
    bnez a5, .Lmul_return_a
    li t0, 0x7fff
    and t0, a1, t0
    beqz t0, .Lmul_nan
    j .Lmul_inf
.Lmul_b_special:
    bnez a6, .Lmul_return_b
    li t0, 0x7fff
    and t0, a0, t0
    beqz t0, .Lmul_nan
.Lmul_inf:
    li a0, 0x7f80
    or a0, a0, a2
    ret
.Lmul_zero:
    mv a0, a2
.Lmul_return_a:
    ret
.Lmul_return_b:
    mv a0, a1
    ret
.Lmul_nan:
    li a0, 0x7fc0
    ret
    .size bf16_mul_asm, .-bf16_mul_asm

    .globl bf16_sqrt_asm
    .type bf16_sqrt_asm, @function
    .align 2
bf16_sqrt_asm:
    srli t0, a0, 7
    andi t0, t0, 255
    andi t1, a0, 127
    li t2, 255
    beq t0, t2, .Lsqrt_special
    li t2, 0x7fff
    and t2, a0, t2
    beqz t2, .Lsqrt_zero
    li t2, 0x8000
    and t2, a0, t2
    bnez t2, .Lsqrt_nan
    beqz t0, .Lsqrt_zero
    ori t1, t1, 128
    andi t2, t0, 1
    bnez t2, .Lsqrt_even_exponent
    slli t1, t1, 1
.Lsqrt_even_exponent:
    # Integer square root of 128*(m+1)-1, eight base-four steps.
    addi t1, t1, 1
    slli t1, t1, 7
    addi t1, t1, -1
    # Every normal input has x >= 128^2, so the first step succeeds.
    li t2, 0x4000
    sub t1, t1, t2
    li t3, 0x1000
    # The first remaining weight is 4096; later weights fit immediates.
    add t4, t2, t3
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    add t2, t2, t3
1:
    addi t4, t2, 1024
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    addi t2, t2, 1024
1:
    addi t4, t2, 256
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    addi t2, t2, 256
1:
    addi t4, t2, 64
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    addi t2, t2, 64
1:
    addi t4, t2, 16
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    addi t2, t2, 16
1:
    addi t4, t2, 4
    srli t2, t2, 1
    bltu t1, t4, 1f
    sub t1, t1, t4
    addi t2, t2, 4
1:
    addi t4, t2, 1
    srli t2, t2, 1
    bltu t1, t4, 1f
    addi t2, t2, 1
1:
    addi t0, t0, 127
    srli t0, t0, 1
    slli t0, t0, 7
    andi t2, t2, 127
    or a0, t0, t2
    ret
.Lsqrt_special:
    bnez t1, .Lsqrt_return
    li t2, 0x8000
    and t2, a0, t2
    beqz t2, .Lsqrt_return
.Lsqrt_nan:
    li a0, 0x7fc0
    ret
.Lsqrt_zero:
    li a0, 0
.Lsqrt_return:
    ret
    .size bf16_sqrt_asm, .-bf16_sqrt_asm
