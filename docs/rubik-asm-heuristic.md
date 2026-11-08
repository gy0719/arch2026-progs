# Rubik heuristic lookup experiments

This stage starts from `59ffc654a1ae6b5c06fb6d3dc9608f7e86ead4fc`. It
changes only the Assembly heuristic lookup and its table representation.
Both candidates retain the same distance values, IDA* order, search frame,
transition values, output paths, and shortest-solution guarantee.

## Lookup cost and candidates

The baseline stores each abstract distance in four bits. For each permutation
or orientation coordinate, the hot loop executes seven instructions: halve
the index, add the table base, load one byte, select the nibble, shift, and
mask. It then compares the two distances and conditionally selects the
maximum. Thus each child executes 14 instructions for the two lookups plus
one or two for the maximum. The cold root helper performs the same lookup
using two private helper calls.

Two candidates were measured independently:

1. **Conditional nibble extraction.** Keep the original packed tables, but
   branch around a constant four-bit shift for the low nibble. A lookup uses
   six instructions for an even index and seven for an odd index. The
   heuristic values and data footprint are unchanged.
2. **Byte distances.** Expand both Assembly distance tables to one byte per
   coordinate. Each hot lookup then needs just an address addition and a
   byte load. The cold helper also uses direct loads and no helper calls.
   The existing generator emits these byte values for Assembly while its C
   mode continues to emit the original packed tables. Transition tables and
   C sources are unchanged.

The second candidate is retained. The 5,040 permutation and 729 orientation
distances require 5,769 bytes instead of 2,885 packed bytes, an increase of
2,884 read-only bytes. The code shrinks by 84 bytes, so total allocated
implementation size rises by 2,800 bytes. The hot loop still performs two
heuristic loads per child; only index and nibble extraction work is removed.

## Measurements

Measured on 2026-11-08 with GNU RISC-V GCC 15.2.0, RV32I/Zicsr/ILP32, and rv32emu
`ffb041bab9d1513e5329f25f486378778dceed13` in system interpreter mode with
M/A/F/C disabled. The maximum and averages use the same fixed -O2 caller and
the same 2,987 calls as the preceding stage. The maximum in each version is
the depth-11 input `54721631111111`.

| Version | Maximum instructions | Mean, 2,987 calls | Expanded nodes at maximum | Code | Read-only | Total allocated | Stack |
|---|---:|---:|---:|---:|---:|---:|---:|
| Baseline packed | 26,236,374 | 7,552,145.87 | 106,635 | 1,688 B | 37,551 B | 39,239 B | 496 B |
| Conditional extraction | 25,562,713 | 7,359,841.78 | 106,635 | 1,688 B | 37,551 B | 39,239 B | 496 B |
| Byte distances | **19,838,321** | **5,708,469.25** | 106,635 | 1,604 B | 40,435 B | 42,039 B | 496 B |

The retained version saves 6,398,053 instructions, or 24.39%, on the hardest
input. It is faster on every one of the 2,987 measured calls. The mean over
the 59 official vectors falls from 1,330,491.25 to 1,005,945.78 instructions;
the official six-input -O2 benchmark falls from 128,165.17 to 97,115.17.
These are means over the specified input sets, not uniform-state averages.

For the hardest input there are still six search iterations, 106,635 expanded
nodes, 639,792 generated children, and 533,162 cutoffs. Ten fewer hot lookup
instructions per child save 6,397,920 instructions; seven cold-helper calls
save another 133. For every measured input, the exact observed saving equals
`10 * generated_children + 19 * (iterations + 1)`. Search event counts match
the baseline for every measured call.

The implementation has no heap or writable global data and still uses its
496-byte stack frame. Allocated sections plus that frame use 42,535 bytes,
below 128 KiB. The larger read-only tables may behave differently in a real
cache; rv32emu counts instructions and does not model hardware cache or
pipeline latency.

## Verification and budget

The table generator was checked entry by entry: all 15,120 permutation and
2,187 orientation transition values match the baseline, and all 5,040 plus
729 byte distances equal the original packed nibbles. Separately, a target
probe exposes the actual cold helper and a copy of the actual inline hot
lookup block. Both were checked against the C packed tables for **all
3,674,160 permutation/orientation coordinate pairs**, for each candidate.
Identical abstract distances preserve the admissibility of their maximum.

For each candidate and each of -O1, -O2, -O3, and -Os, the target runs pass
2,987 exact-distance, replay, and byte-for-byte C/Assembly comparisons,
including all 2,644 distinct distance-11 states. Each build also passes 8,282
ABI, stack guard, invalid-input, output buffer, and NUL checks. Distances
0 through 10 are otherwise sampled, not exhaustively solved. Instrumented
search events match the baseline across all 2,987 calls. The C ASan/UBSan
suite passes with `LSAN_OPTIONS=detect_leaks=0`; sanitizers do not instrument
hand-written Assembly.

The final unmodified official test suite reports **52 passed, 0 failed** at
all four optimization levels, and `scripts/driver.py --prog rubik` reports
55/55. This official vector set does not establish the contract's budget for
every state: **510 distinct distance-11 states** in the expanded test exceed
7,500,000 instructions. The hardest input is **12,338,321 instructions over**
that limit; it would need a further 62.19% reduction. The larger run contains
511 over-budget calls because it measures the hardest state twice.

The Assembly object passes `scripts/rvcheck.py --impl asm` and has no
undefined symbols. A source invariant check confirms all executable code
outside heuristic lookup is unchanged, including state transitions and
search-frame operations. No test, contract, or grading script was modified.

Raw logs, independent lookup probes, diagnostic search counts, four-build
test results, disassembly, size reports and audit scripts are saved in
`~/hw2-experiments/rubik/asm-heuristic/`.

From the repository, recheck the current implementation with:

```sh
bash ~/hw2-experiments/rubik/asm-heuristic/run-all.sh /tmp/rubik-recheck
```
