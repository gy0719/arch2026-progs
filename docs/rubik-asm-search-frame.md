# Rubik Assembly search-frame experiments

This stage starts from `9e4199e9ffeedacf7bc478696a639e64e07e1bc8`. It
changes only search-frame handling and the storage of the current iteration's
minimum exceeded bound. Transition and heuristic code and tables are
unchanged. The IDA* move order, bounds and shortest solutions remain the
same. The measured maximum improves, but still exceeds the instruction budget.

## Frame analysis and experiments

At the baseline, each expanded child suspends its parent by storing eight
words: parent permutation, orientation, current quarter-turn permutation and
orientation, face, turn, previous face, and local minimum exceeded bound. A
completed child restores the same eight words. On `54721631111111`, the
search has 106,629 pushes and 106,619 pops: 853,032 search-frame stores and
852,952 search-frame loads. These counts exclude the output path, public ABI
save area and other stack accesses.

Four changes were tested in order, with the full validation run after each:

1. **Recover quarter coordinates.** When a child is exhausted, its root
   permutation and orientation are exactly the parent's last generated
   quarter-turn coordinates. Copy those two registers before loading the
   parent root, instead of saving and loading two frame words. Two moves
   replace the two loads, and two stores disappear per push.
2. **Keep one minimum per iteration.** The next IDA* bound is the minimum of
   all exceeded `f` values in that iteration. The old per-node minima and
   their return-time merges compute that same minimum. Keeping it in `s8`
   throughout the iteration removes one saved word, one restored word, and
   per-child initialization and merging. This changes bookkeeping, not the
   move traversal or the resulting next bound.
3. **Recover the parent face.** A child's `previous face` register is its
   parent's current face. Copy it before restoring the parent's previous
   face, eliminating another frame store and load.
4. **Specialize the last-turn pop.** A suspended turn is in the range 1 to 3.
   When it is 3, the next face will initialize quarter coordinates from the
   parent root, so the two quarter-coordinate copies are unnecessary. A
   separate pop path saves one instruction on those returns and adds 32 code
   bytes. There are 35,990 such returns for the hardest input.

The original 32-byte slot stride and 496-byte public stack frame remain in
place. The final slot uses four words: parent permutation, parent orientation,
turn and previous face. No heap or writable global storage is introduced.

## Measurements

Measured on 2026-11-08 using GNU RISC-V GCC 15.2.0 and rv32emu
`ffb041bab9d1513e5329f25f486378778dceed13`, with RV32I/Zicsr/ILP32 and
M/A/F/C disabled. Maximum and mean counts use the same fixed -O2 caller and
2,987 calls used by the previous stage. The maximum in every row is the
distance-11 input `54721631111111`.

| Version | Maximum instructions | Mean, 2,987 calls | Expanded nodes at maximum | Code | Total allocated | Stack |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | 19,838,321 | 5,708,469.25 | 106,635 | 1,604 B | 42,039 B | 496 B |
| 1: recover coordinates | 19,625,063 | 5,647,025.29 | 106,635 | 1,596 B | 42,031 B | 496 B |
| 2: iteration minimum | 18,722,161 | 5,386,588.76 | 106,635 | 1,568 B | 42,003 B | 496 B |
| 3: recover face | 18,615,532 | 5,355,866.78 | 106,635 | 1,564 B | 41,999 B | 496 B |
| 4: last-turn pop | **18,579,542** | **5,345,580.01** | 106,635 | 1,596 B | 42,031 B | 496 B |

The final version saves 1,258,779 instructions, or 6.35%, on the hardest
input. Of the 2,987 measured calls, 2,972 improve, 15 are unchanged and none
regress. The mean over the 59 official vectors drops from 1,005,945.78 to
942,071.97 instructions per call; it is a mean over that particular set.

All versions have 40,435 bytes of read-only data and zero .data/.bss bytes.
The final allocated implementation plus its stack frame is 42,527 bytes,
under 128 KiB. The totals include all allocated implementation sections but
exclude the test harness and debug information.

| Version | Frame stores at maximum | Frame loads at maximum |
|---|---:|---:|
| Baseline | 853,032 | 852,952 |
| 1: recover coordinates | 639,774 | 639,714 |
| 2: iteration minimum | 533,145 | 533,095 |
| 3: recover face | 426,516 | 426,476 |
| 4: last-turn pop | 426,516 | 426,476 |

The first, second and third changes reduce each frame's stores/loads from
8/8 to 6/6, 5/5 and 4/4. The fourth reduces register moves, not frame memory
accesses. These figures multiply the measured push/pop counts by the actual
frame instructions; they do not count ABI, path, or other stack accesses.

An independent diagnostic copy records minimum updates. For the hardest
input the baseline makes 121,796 cutoff-minimum updates and 19,580 parent
merge updates; the iteration-wide version makes seven cutoff updates and no
parent merges. The second candidate's 902,902-instruction improvement over
the first is accounted for by three saved instructions per push and per pop,
the 19,580 removed merge moves, and two instructions for each avoided cutoff
update: `3*(106629+106619) + 19580 + 2*(121796-7) = 902902`.
The first and third candidates save exactly two and one instructions per
push, respectively, across all 2,987 measured calls.

## Correctness and budget

For every candidate and each of -O1, -O2, -O3 and -Os, all 2,987 target
solves pass exact-distance, replay and byte-for-byte C/Assembly comparisons,
including all 2,644 distinct distance-11 states. Each build also passes 8,282
ABI, stack guard, invalid-input, output-buffer and NUL checks. Distances 0
through 10 are otherwise sampled rather than exhaustively solved.

Separately instrumented copies record all bounds for each iteration. Every
one of the 2,987 bound sequences matches the baseline for every candidate;
the hardest sequence is `6, 7, 8, 9, 10, 11`. Search event counts also match
for every case: expanded and generated nodes, same-face pruning, pushes,
pops, cutoffs and row selections. The instrumentation is not included in
the submitted implementation or its instruction measurements.

The unmodified official suite reports **52 passed, 0 failed** for all four
optimization levels, and `scripts/driver.py --prog rubik` reports 55/55.
That vector set does not establish the budget for every state: the expanded
test still contains **339 distinct distance-11 states** over 7,500,000
instructions. The worst input exceeds the limit by **11,079,542**, and would
need a further 59.63% reduction. It is counted twice in the 340 over-budget
calls of the 2,987-call measurement set.

The implementation object passes `scripts/rvcheck.py --impl asm` and has no
undefined symbols. The C ASan/UBSan suite passes with
`LSAN_OPTIONS=detect_leaks=0`; sanitizers do not instrument hand-written
Assembly. An invariant check confirms that the public entry, ranking,
heuristic, transition lookup and tables, and solve/replay logic are unchanged.
No tests, contract, or grading scripts were modified.

The raw logs, frame and bound probes, node counts, four-build test results,
source snapshots, disassembly, sizes and audit scripts are saved under
`~/hw2-experiments/rubik/asm-search-frame/`. Recheck the current version with:

```sh
bash ~/hw2-experiments/rubik/asm-search-frame/run-all.sh /tmp/rubik-frame-check
```
