# Optimal HTM IDA* port of gy0719/minirubik solver.S (7f76bff6aff1).
# Public ABI: a0 = state, a1 = out, a2 = cap; result in a0.
# No C calls, heap, writable globals, recursive calls, or environment access.
#
# The 496-byte frame remains 16-byte aligned throughout all private helpers:
#   0..383    twelve suspended search nodes, each eight 32-bit fields
#   384..395  solution path (at most eleven moves)
#   396       solution length
#   400/404   original permutation/orientation ranks for replay
#   408/412   output pointer/capacity
#   416       original input pointer
#   432..479  saved s0..s11; 480 saved ra; other bytes are padding
# Validation uses a0..a2 and t0..t6 before allocating the frame. Helpers use
# a/t registers and s0..s11 under the private convention described below;
# only rubik_solve_asm is a public ABI entry. gp and tp are never modified.

    .option norvc
    .option norelax
    .text
    .balign 4
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
rubik_solve_asm:
    # Validate each byte before reading the next: short strings are safe.
    li      t0, 0
    li      t1, 0
.Lrubik_validate_perm:
    add     t2, a0, t0
    lbu     t3, 0(t2)
    addi    t3, t3, -49
    li      t4, 7
    bgeu    t3, t4, .Lrubik_invalid
    li      t4, 1
    sll     t4, t4, t3
    and     t5, t1, t4
    bnez    t5, .Lrubik_invalid
    or      t1, t1, t4
    addi    t0, t0, 1
    li      t4, 7
    bltu    t0, t4, .Lrubik_validate_perm
    addi    t0, a0, 7
    li      t1, 0
    li      t2, 7
.Lrubik_validate_ori:
    lbu     t3, 0(t0)
    addi    t3, t3, -49
    li      t4, 3
    bgeu    t3, t4, .Lrubik_invalid
    add     t1, t1, t3
    bltu    t1, t4, .Lrubik_ori_reduced
    addi    t1, t1, -3
.Lrubik_ori_reduced:
    addi    t0, t0, 1
    addi    t2, t2, -1
    bnez    t2, .Lrubik_validate_ori
    bnez    t1, .Lrubik_invalid
    lbu     t3, 0(t0)
    bnez    t3, .Lrubik_invalid
    # Error priority: invalid input is -1 even when capacity is zero.
    beqz    a2, .Lrubik_zero_capacity

    addi    sp, sp, -496
    sw      s0, 432(sp)
    sw      s1, 436(sp)
    sw      s2, 440(sp)
    sw      s3, 444(sp)
    sw      s4, 448(sp)
    sw      s5, 452(sp)
    sw      s6, 456(sp)
    sw      s7, 460(sp)
    sw      s8, 464(sp)
    sw      s9, 468(sp)
    sw      s10, 472(sp)
    sw      s11, 476(sp)
    sw      ra, 480(sp)
    sw      a0, 416(sp)
    sw      a1, 408(sp)
    sw      a2, 412(sp)

    jal     ra, rubik_asm_rank_permutation
    sw      a0, 400(sp)
    lw      a0, 416(sp)
    addi    a0, a0, 7
    jal     ra, rubik_asm_rank_orientation
    sw      a0, 404(sp)
    mv      a1, a0
    lw      a0, 400(sp)
    jal     ra, rubik_asm_solve
    beqz    a0, .Lrubik_internal_failure
    lw      a0, 400(sp)
    lw      a1, 404(sp)
    jal     ra, rubik_asm_replay_solution
    beqz    a0, .Lrubik_internal_failure

    # Determine the complete text length before writing any move bytes.
    lw      t0, 396(sp)
    addi    t1, sp, 384
    li      t2, 0
    li      t3, 0
    la      t6, .Lrubik_move_names
.Lrubik_length_loop:
    beq     t2, t0, .Lrubik_length_done
    lbu     t4, 0(t1)
    slli    t5, t4, 1
    add     t4, t4, t5
    add     t4, t6, t4
    lbu     t4, 1(t4)
    snez    t4, t4
    addi    t3, t3, 1
    add     t3, t3, t4
    beqz    t2, .Lrubik_length_no_space
    addi    t3, t3, 1
.Lrubik_length_no_space:
    addi    t1, t1, 1
    addi    t2, t2, 1
    j       .Lrubik_length_loop
.Lrubik_length_done:
    lw      a1, 408(sp)
    lw      a2, 412(sp)
    bgeu    t3, a2, .Lrubik_small_buffer
    addi    t1, sp, 384
    li      t2, 0
.Lrubik_output_loop:
    beq     t2, t0, .Lrubik_output_done
    beqz    t2, .Lrubik_output_move
    li      t4, 32
    sb      t4, 0(a1)
    addi    a1, a1, 1
.Lrubik_output_move:
    lbu     t4, 0(t1)
    slli    t5, t4, 1
    add     t4, t4, t5
    add     t4, t6, t4
    lbu     t5, 0(t4)
    sb      t5, 0(a1)
    addi    a1, a1, 1
    lbu     t5, 1(t4)
    beqz    t5, .Lrubik_output_next
    sb      t5, 0(a1)
    addi    a1, a1, 1
.Lrubik_output_next:
    addi    t1, t1, 1
    addi    t2, t2, 1
    j       .Lrubik_output_loop
.Lrubik_output_done:
    sb      zero, 0(a1)
    mv      a0, t0
    j       .Lrubik_return
.Lrubik_small_buffer:
    sb      zero, 0(a1)
    li      a0, -2
    j       .Lrubik_return
.Lrubik_internal_failure:
    # Unreachable for valid coordinates and the verified complete tables.
    li      a0, -1
.Lrubik_return:
    lw      s0, 432(sp)
    lw      s1, 436(sp)
    lw      s2, 440(sp)
    lw      s3, 444(sp)
    lw      s4, 448(sp)
    lw      s5, 452(sp)
    lw      s6, 456(sp)
    lw      s7, 460(sp)
    lw      s8, 464(sp)
    lw      s9, 468(sp)
    lw      s10, 472(sp)
    lw      s11, 476(sp)
    lw      ra, 480(sp)
    addi    sp, sp, 496
    ret
.Lrubik_invalid:
    li      a0, -1
    ret
.Lrubik_zero_capacity:
    li      a0, -2
    ret
    .size rubik_solve_asm, . - rubik_solve_asm

# Ranking helpers: a0 input pointer, a0 result; clobber a0..a4 and t0..t6.
# The permutation uses the original shift/add factoradic recurrence; the
# orientation uses only the first six independent base-3 digits.
.type rubik_asm_rank_permutation, @function
rubik_asm_rank_permutation:
    mv      t0, a0          /* base pointer */
    li      t1, 0           /* rank */
    li      t2, 0           /* i */

.Lperm_outer:
    li      t3, 6
    bgeu    t2, t3, .Lperm_done

    /* current = input[i] */
    add     t4, t0, t2
    lbu     t5, 0(t4)

    /* Count elements to the right smaller than current. */
    addi    t6, t2, 1       /* j = i + 1 */
    li      a1, 0           /* smaller = 0 */

.Lperm_inner:
    li      a2, 7
    bgeu    t6, a2, .Lperm_digit_done

    add     a3, t0, t6
    lbu     a4, 0(a3)

    bltu    a4, t5, .Lperm_smaller

.Lperm_next_j:
    addi    t6, t6, 1
    j       .Lperm_inner

.Lperm_smaller:
    addi    a1, a1, 1
    j       .Lperm_next_j


.Lperm_digit_done:
    /*
     * Lexicographic rank recurrence:
     *
     * rank = rank * (7 - i) + smaller
     *
     * Use shift/add multiplication because RV32I has no MUL.
     */

    li      a2, 7
    sub     a2, a2, t2      /* multiplier = 7 - i */

    li      a3, 0           /* product */
    mv      a4, t1          /* shifted multiplicand */

.Lperm_mul:
    andi    a5, a2, 1
    beqz    a5, .Lperm_mul_skip

    add     a3, a3, a4

.Lperm_mul_skip:
    slli    a4, a4, 1
    srli    a2, a2, 1
    bnez    a2, .Lperm_mul

    add     t1, a3, a1      /* rank = product + smaller */

    addi    t2, t2, 1
    j       .Lperm_outer


.Lperm_done:
    mv      a0, t1
    ret

.size rubik_asm_rank_permutation, . - rubik_asm_rank_permutation


/* ------------------------------------------------------------
 * rubik_asm_rank_orientation
 *
 * Input:
 *   a0 = address of first orientation character
 *
 * Output:
 *   a0 = orientation coordinate [0, 728]
 *
 * Only the first six orientations are independent.
 *
 * rank = rank * 3 + digit
 *
 * ASCII:
 *   '1' -> 0
 *   '2' -> 1
 *   '3' -> 2
 * ------------------------------------------------------------ */
.type rubik_asm_rank_orientation, @function
rubik_asm_rank_orientation:
    mv      t0, a0          /* base pointer */
    li      t1, 0           /* rank */
    li      t2, 0           /* i */

.Lori_loop:
    li      t3, 6
    bgeu    t2, t3, .Lori_done

    add     t4, t0, t2
    lbu     t5, 0(t4)

    /* Convert ASCII '1'/'2'/'3' to 0/1/2. */
    addi    t5, t5, -49

    /* rank *= 3 -> rank = (rank << 1) + rank */
    slli    t6, t1, 1
    add     t1, t6, t1

    /* rank += digit */
    add     t1, t1, t5

    addi    t2, t2, 1
    j       .Lori_loop


.Lori_done:
    mv      a0, t1
    ret

.size rubik_asm_rank_orientation, . - rubik_asm_rank_orientation


# Private core convention (only the public wrapper obeys the external ABI):
# a4/a5 root ranks, a6 solve return PC, t6 search/replay return PC.
# heuristic uses a3 for its return PC and preserves a4..a6/t6/s registers.
# search keeps the active node in s0..s11, row-pair base in a2,
# heuristic bases in t3/t4,
# a1 = 11, ra = 3, t5 = suspended-frame cursor, a7 = path cursor.
# All helpers keep sp unchanged. The inner loop makes no function calls.

/* a0 = packed table, a1 = coordinate; return a0 = four-bit distance.
 * Clobbers t0/t1. Even coordinates select the low nibble.
 */
.type rubik_asm_packed_get, @function
rubik_asm_packed_get:
    srli    t0, a1, 1
    add     t0, a0, t0
    lbu     a0, 0(t0)
    andi    t1, a1, 1
    slli    t1, t1, 2
    srl     a0, a0, t1
    andi    a0, a0, 15
    ret
.size rubik_asm_packed_get, . - rubik_asm_packed_get

/* a0 = p, a1 = o; return a0 = max(hp[p], ho[o]). */
.type rubik_asm_heuristic, @function
rubik_asm_heuristic:
    mv      a3, ra
    mv      a2, a1
    mv      a1, a0
    la      a0, rubik_asm_hp_packed
    jal     ra, rubik_asm_packed_get
    mv      t2, a0
    mv      a1, a2
    la      a0, rubik_asm_ho_packed
    jal     ra, rubik_asm_packed_get
    bgeu    a0, t2, .Lheuristic_return
    mv      a0, t2
.Lheuristic_return:
    jalr    zero, 0(a3)
.size rubik_asm_heuristic, . - rubik_asm_heuristic

/* a0 = face (R=0, B=1, D=2); return a0/a1 = p/o row pointers.
 * Face-major row strides: 5040 halfwords = 10080 bytes and
 * 729 halfwords = 1458 bytes. No multiplication is required.
 */
.type rubik_asm_transition_rows, @function
rubik_asm_transition_rows:
    la      t0, rubik_asm_perm_move_table
    la      a1, rubik_asm_ori_move_table
    beqz    a0, .Lrows_return
    li      t1, 10080
    add     t0, t0, t1
    addi    a1, a1, 1458
    li      t2, 1
    beq     a0, t2, .Lrows_return
    add     t0, t0, t1
    addi    a1, a1, 1458
.Lrows_return:
    mv      a0, t0
    ret
.size rubik_asm_transition_rows, . - rubik_asm_transition_rows

/* a0/a1 = quarter-turn coordinates, s10/s11 = selected p/o rows.
 * Return the next quarter-turn coordinates in a0/a1.
 */
.type rubik_asm_quarter_transition, @function
rubik_asm_quarter_transition:
    slli    t0, a0, 1
    add     t0, s10, t0
    lhu     a0, 0(t0)
    slli    t0, a1, 1
    add     t0, s11, t0
    lhu     a1, 0(t0)
    ret
.size rubik_asm_quarter_transition, . - rubik_asm_quarter_transition

/* A face indexes one aligned pair of precomputed transition row pointers.
 * a2 holds the pair table's base; t1 is scratch. The saved frame still holds
 * face numbers 0..2, so restoring a parent selects exactly the same rows.
 */
.macro search_transition_rows
    slli    t1, s5, 3
    add     t1, a2, t1
    lw      s10, 0(t1)
    lw      s11, 4(t1)
.endm

/* a0 = root p, a1 = root o, a2 = bound.
 * Return a0 = -1 (FOUND), or the minimum exceeded f / INT_MAX.
 * Active node:
 *   s0 depth; s1 p; s2 o; s3 quarter_p; s4 quarter_o;
 *   s5 face; s6 turn; s7 previous; s8 minimum; s9 bound;
 *   s10 permutation row; s11 orientation row; t3 hp base; t4 ho base.
 *   a2 transition row-pair table base.
 *   t5 points to the current depth's frame slot, updated only on push/pop.
 *   a7 points to the current depth's solution_path byte.
 *   ra is the constant 3; the inner search loop makes no calls.
 *   a1 is the constant maximum depth 11.
 */
.type rubik_asm_search, @function
rubik_asm_search:
    mv      t6, ra
    mv      s1, a0
    mv      s2, a1
    mv      s9, a2
    jal     ra, rubik_asm_heuristic
    bltu    s9, a0, .Lsearch_return
    or      t0, s1, s2
    beqz    t0, .Lsearch_root_goal

    /* Cache packed table bases once per expanded rubik_asm_search root. */
    la      t3, rubik_asm_hp_packed
    la      t4, rubik_asm_ho_packed
    la      a2, .Lrubik_transition_rows
    addi    t5, sp, 0
    addi    a7, sp, 384
    li      ra, 3
    li      a1, 11

    li      s0, 0
    mv      s3, s1
    mv      s4, s2
    li      s5, 0
    li      s6, 0
    li      s7, 3
    li      s8, 0x7fffffff
    li      s10, 0
    li      s11, 0

.Lsearch_loop:
    bne     s6, ra, .Lsearch_face
.Lsearch_advance_face:
    addi    s5, s5, 1
    li      s6, 0
.Lsearch_face:
    bne     s5, ra, .Lsearch_next_face
    beqz    s0, .Lsearch_exhausted

    /* Return an exhausted child's minimum to its suspended parent. */
    mv      t0, s8
    addi    s0, s0, -1
    addi    t5, t5, -32
    addi    a7, a7, -1
    lw      s1, 0(t5)
    lw      s2, 4(t5)
    lw      s3, 8(t5)
    lw      s4, 12(t5)
    lw      s5, 16(t5)
    lw      s6, 20(t5)
    lw      s7, 24(t5)
    lw      s8, 28(t5)
    bgeu    t0, s8, .Lsearch_restored
    mv      s8, t0
.Lsearch_restored:
    /* A saved turn is 1..3: resume directly without root-loop checks. */
    bgeu    s6, ra, .Lsearch_advance_face
    /* A completed face does not need its row pointers restored. */
    search_transition_rows
    j       .Lsearch_generate

.Lsearch_next_face:
    bnez    s6, .Lsearch_generate
    bne     s5, s7, .Lsearch_select_rows
    /* Same-face pruning skips all three turns at once. */
    addi    s5, s5, 1
    j       .Lsearch_loop
.Lsearch_select_rows:
    search_transition_rows
    mv      s3, s1
    mv      s4, s2

.Lsearch_generate:
    /* Reuse the preceding quarter turn for half/inverse children. */
    slli    t0, s3, 1
    add     t0, s10, t0
    lhu     s3, 0(t0)
    slli    t0, s4, 1
    add     t0, s11, t0
    lhu     s4, 0(t0)
    /* Inline the child heuristic; cold root/solve calls keep the helper.
     * Preserve its nibble convention and max comparison exactly.
     */
    srli    t0, s3, 1
    add     t0, t3, t0
    lbu     t2, 0(t0)
    andi    t1, s3, 1
    slli    t1, t1, 2
    srl     t2, t2, t1
    andi    t2, t2, 15
    srli    t0, s4, 1
    add     t0, t4, t0
    lbu     a0, 0(t0)
    andi    t1, s4, 1
    slli    t1, t1, 2
    srl     a0, a0, t1
    andi    a0, a0, 15
    bgeu    a0, t2, .Lsearch_child_heuristic_done
    mv      a0, t2
.Lsearch_child_heuristic_done:
    /* Keep child depth in t0; a0 holds f until cutoff handling finishes. */
    addi    t0, s0, 1
    add     a0, t0, a0
    bltu    s9, a0, .Lsearch_cutoff
    /* Only a child within the bound can extend the solution path. */
    slli    t1, s5, 1
    add     t1, t1, s5
    add     t1, t1, s6
    sb      t1, 0(a7)
    addi    s6, s6, 1
    or      t1, s3, s4
    beqz    t1, .Lsearch_child_goal
    beq     t0, a1, .Lsearch_loop

    /* Only an expanded child suspends its parent. Frame layout:
     * +0 p, +4 o, +8 quarter_p, +12 quarter_o, +16 face,
     * +20 turn, +24 previous, +28 minimum; stride = 32 bytes.
     */
    sw      s1, 0(t5)
    sw      s2, 4(t5)
    sw      s3, 8(t5)
    sw      s4, 12(t5)
    sw      s5, 16(t5)
    sw      s6, 20(t5)
    sw      s7, 24(t5)
    sw      s8, 28(t5)
    addi    t5, t5, 32
    addi    s0, s0, 1
    addi    a7, a7, 1
    mv      s1, s3
    mv      s2, s4
    mv      s7, s5
    li      s5, 0
    li      s6, 0
    li      s8, 0x7fffffff
    j       .Lsearch_loop

.Lsearch_cutoff:
    addi    s6, s6, 1
    bgeu    a0, s8, .Lsearch_loop
    mv      s8, a0
    j       .Lsearch_loop
.Lsearch_child_goal:
    addi    t0, sp, 396
    addi    t1, s0, 1
    sw      t1, 0(t0)
    li      a0, -1
    j       .Lsearch_return
.Lsearch_root_goal:
    addi    t0, sp, 396
    sw      zero, 0(t0)
    li      a0, -1
    j       .Lsearch_return
.Lsearch_exhausted:
    mv      a0, s8
.Lsearch_return:
    jalr    zero, 0(t6)
.size rubik_asm_search, . - rubik_asm_search

/* a0 = p, a1 = o; return a0 = success (1) or failure (0).
 * The next bound is the preceding rubik_asm_search's minimum exceeded f.
 */
.type rubik_asm_solve, @function
rubik_asm_solve:
    mv      a4, a0
    mv      a5, a1
    mv      a6, ra
    addi    t0, sp, 396
    sw      zero, 0(t0)
    addi    t0, sp, 384
    sw      zero, 0(t0)
    sw      zero, 4(t0)
    sw      zero, 8(t0)
    jal     ra, rubik_asm_heuristic
    mv      s9, a0
.Lsolve_iteration:
    li      t0, 11
    bltu    t0, s9, .Lsolve_failed
    mv      a0, a4
    mv      a1, a5
    mv      a2, s9
    jal     ra, rubik_asm_search
    li      t0, -1
    beq     a0, t0, .Lsolve_found
    li      t0, 0x7fffffff
    beq     a0, t0, .Lsolve_failed
    mv      s9, a0
    j       .Lsolve_iteration
.Lsolve_found:
    li      a0, 1
    jalr    zero, 0(a6)
.Lsolve_failed:
    li      a0, 0
    jalr    zero, 0(a6)
.size rubik_asm_solve, . - rubik_asm_solve


/* a0/a1 = preserved root coordinates; return a0 = replay success (1/0).
 * Replay preserves the path. Like search, it uses s registers for the active
 * state and t6 for its return PC.
 */
.type rubik_asm_replay_solution, @function
rubik_asm_replay_solution:
    mv      t6, ra
    mv      s0, a0
    mv      s1, a1
    addi    s2, sp, 384
    addi    t0, sp, 396
    lw      s3, 0(t0)
    li      t0, 11
    bltu    t0, s3, .Lreplay_failed

.Lreplay_move:
    beqz    s3, .Lreplay_finished
    lbu     s4, 0(s2)
    li      t0, 9
    bgeu    s4, t0, .Lreplay_failed

    /* Subtract each preceding face's three encodings. The remainder is
     * 0/1/2, so adding one gives the base quarter-turn count 1/2/3.
     */
    li      a0, 0
    li      t0, 3
    bltu    s4, t0, .Lreplay_decoded
    addi    s4, s4, -3
    li      a0, 1
    bltu    s4, t0, .Lreplay_decoded
    addi    s4, s4, -3
    li      a0, 2
.Lreplay_decoded:
    addi    s4, s4, 1
    jal     ra, rubik_asm_transition_rows
    mv      s10, a0
    mv      s11, a1

.Lreplay_quarter:
    mv      a0, s0
    mv      a1, s1
    jal     ra, rubik_asm_quarter_transition
    mv      s0, a0
    mv      s1, a1
    addi    s4, s4, -1
    bnez    s4, .Lreplay_quarter
    addi    s2, s2, 1
    addi    s3, s3, -1
    j       .Lreplay_move

.Lreplay_finished:
    /* An empty solution succeeds exactly when the root is solved. */
    or      t0, s0, s1
    sltiu   a0, t0, 1
    j       .Lreplay_store
.Lreplay_failed:
    li      a0, 0
.Lreplay_store:
    jalr    zero, 0(t6)
.size rubik_asm_replay_solution, . - rubik_asm_replay_solution


    .section .rodata,"a",@progbits
.Lrubik_move_names:
    .asciz "R", "", "R2", "R'", "B", "", "B2", "B'", "D", "", "D2", "D'"

    /* Three face-major row pairs. Strides are in bytes, not halfwords. */
    .balign 4
.Lrubik_transition_rows:
    .word rubik_asm_perm_move_table, rubik_asm_ori_move_table
    .word rubik_asm_perm_move_table + 10080, rubik_asm_ori_move_table + 1458
    .word rubik_asm_perm_move_table + 20160, rubik_asm_ori_move_table + 2916
