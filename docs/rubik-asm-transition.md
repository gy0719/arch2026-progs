# Rubik state transition experiments

This stage starts from `df99611690e9097e8ff3ed08788ba761d4511190` and
changes the Assembly search's transition-related work. It keeps the same
IDA* search order, heuristic values, shortest solutions, and search frame.
The changes reduce the measured maximum, but the 7,500,000-instruction budget
still fails.

## Baseline and experiments

The baseline ranks permutation and orientation once per input. In the hot
loop, each child uses two halfword table loads, each preceded by a shift and
an address addition: six instructions in total. The following path update
also encoded and stored a move before knowing whether the child would be
cut off. Face selection rebuilt two row pointers with branches and additions
when starting a face or restoring a parent.

Three candidates were tested in order; each adds or refines one part:

1. **Defer path encoding.** Write the move only after the child's existing
   heuristic and bound check accepts it. This avoids the path write for
   cutoffs, but converting the already-incremented turn back costs one extra
   instruction for accepted children.
2. **Defer turn increment.** Keep the original zero-based turn until the
   bound check, then increment it in either the accepted or cutoff path. This
   removes the extra conversion while preserving the turn saved in the frame.
3. **Use row-pointer pairs.** Replace the branch-based search row selection
   with an index into three pairs of precomputed read-only pointers. This
   replaces variable-length face selection with four instructions. The three
   pairs cost 24 bytes of read-only storage; fewer code instructions make
   the overall implementation smaller.

Each candidate was independently built and validated before the next change.
The following counts use the same fixed -O2 caller and the same hardest input,
`54721631111111`, on rv32emu. Allocated bytes include code and all other
allocated implementation sections; the harness and debug data are excluded.

| Version | Instructions | Change from baseline | Expanded nodes | Code bytes | Read-only bytes | Allocated bytes |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | 29,409,443 | — | 106,635 | 1,748 | 37,527 | 39,275 |
| Candidate 1 | 27,383,425 | -2,026,018 | 106,635 | 1,752 | 37,527 | 39,279 |
| Candidate 2 | 27,276,795 | -2,132,648 | 106,635 | 1,752 | 37,527 | 39,279 |
| Candidate 3 | 26,236,374 | -3,173,069 | 106,635 | 1,688 | 37,551 | 39,239 |

Candidate 3 is the retained implementation. It reduces the observed worst
case by 10.79%, with 60 fewer code bytes and 36 fewer total allocated bytes.
The 496-byte stack frame is unchanged, and .data and .bss remain zero. The
allocated implementation plus that frame uses 39,735 bytes, below 128 KiB.

The maximum is still **18,736,374 instructions over budget**. Reaching the
budget for this input would require a further 71.41% reduction from the
retained result. Of the 2,987 measured calls, the number over budget changed
from 2,312 to 1,850, 1,822, and 1,611 for candidates 1, 2, and 3. The
official six-input -O2 benchmark improved from 143,512.00 to 128,165.17
instructions per call. On the 59 official vectors the mean fell from
1,491,435.63 to 1,330,491.25; on all 2,987 measured calls it fell from
8,466,846.48 to 7,552,145.87. These are averages over different specified
input sets, not estimates for a uniform random cube.

For candidate 1, 2,984 calls improved, two were unchanged, and one one-move
case increased by one instruction. Candidate 2 had 2,984 improvements and
three unchanged calls. Candidate 3 had 2,985 improvements and two unchanged
calls. These comparisons include repeated inputs in the 2,987-call set.

## Search work and memory access

For every measured call, separately instrumented search event counts match
the baseline: iterations, expanded nodes, generated children, same-face
pruning, pushes, pops, bound cutoffs, and row selections. The hardest input
still takes six iterations, expands 106,635 nodes, generates 639,792 children,
and cuts off 533,162 of them. The move path is now encoded for the remaining
106,630 children, avoiding 533,162 stores and 2,132,648 instructions relative
to the baseline. This exact reduction was checked for every measured input
after candidate 2.

The hardest case performs 283,897 search row selections. The final pointer
table adds two aligned word loads per selection: 567,794 additional loads in
that case. This saves a further 1,040,421 retired instructions, including
the removed root initialization. Consequently the row table and deferred
path updates together replace 533,162 stores with 567,794 loads: 34,632 more
memory operations in this accounting. The emulator measures retired guest
instructions and has no hardware cache or pipeline timing model, so these
instruction savings do not by themselves establish a hardware speedup.

The table used for heuristic values is unchanged, as are both the cold and
inline heuristic calculations. The original transition values are unchanged;
the new 24-byte table contains row addresses only. Ranking, the public ABI
wrapper, frame layout, frame saves/restores, and stack size are unchanged.
An invariant script compares these source regions and the protected C,
headers, tests, grading scripts, and original read-only tables to the base
commit. The Assembly object has no undefined references and passes the
RV32I implementation check.

## Validation

For **each** candidate and each of -O1, -O2, -O3, and -Os:

- 2,987 target calls pass exact-distance, move replay, and byte-for-byte
  C/Assembly comparisons. They include all 2,644 distinct depth-11 states,
  the 59 official vectors, and additional samples from depths 0 through 10.
  The lower depths are sampled rather than exhaustively solved.
- 8,282 additional calls pass ABI register preservation, stack guard,
  invalid-input, zero-capacity, output-sentinel, NUL and exact-fit checks.
- The unmodified official test suite reports **51 passed, 1 failed**. The
  failure is the depth-11 instruction budget; for the final version its first
  reported input uses 9,597,570 instructions against the 7,500,000 limit.

The host C ASan/UBSan run passes with `LSAN_OPTIONS=detect_leaks=0`; it does
not instrument hand-written Assembly. The target ABI guard and output
checks cover the Assembly behavior separately. Each candidate also passes
the Assembly RV32I check. The official driver reports Rubik as failing due
to the instruction budget, while its toolchain, ISA and footprint checks
pass. No tests, header contract, or grading framework were modified.

Raw per-case instruction and node counts, four-build logs, source snapshots,
disassembly, size and driver reports, audit scripts, and the diagnostic
instrumented copies are retained under
`~/hw2-experiments/rubik/asm-transition/`.
