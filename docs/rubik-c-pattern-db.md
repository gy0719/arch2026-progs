# Rubik C four-corner heuristic

The solver tracks four named corners among seven movable positions. Each
abstract state stores an ordered P(7,4) position rank and four base-3 twists,
for 840 * 81 = 68,040 states. Reverse breadth-first search over all nine
unit-cost moves generates the 34,020-byte nibble-packed distance table. The
remaining read-only tables map existing permutation ranks to pattern ranks and
advance positions and twists. Generate the header with:

```
python3 tools/gen-rubik-c-pdb.py 4 /tmp/rubik-c-pdb
clang-format-20 /tmp/rubik-c-pdb/pdb.h > /tmp/rubik_c_pdb.h
cmp /tmp/rubik_c_pdb.h src/rubik/rubik_c_pdb.h
```

Every concrete move has the corresponding abstract move, so projecting a
concrete solution yields an abstract solution of the same length. The exact
abstract distance is a lower bound. The maximum of the permutation,
orientation, and pattern distances is therefore admissible. The search still
uses the minimum exceeded bound, the same move order and same-face pruning.
No full-state search table or runtime initialization is needed.

An independent verifier checked all 3,674,160 concrete states, all 11,022,480
quarter-turn projections, and pattern distances against exact concrete
breadth-first distances. The C data matches the earlier assembly experiment's
generated values. Instrumented C node counts also matched an independent
pattern search on all 2,987 measured calls.

Each measurement includes the hardest previous input and all 2,644 distance-11
states. Every one of the 2,987 calls checks length, replay, and exact agreement
with the existing assembly. All four builds pass 8,282 ABI, buffer and stack
guard checks, the official 52-test suite, ASan/UBSan, and the RV32I checker.

| Build | Previous maximum | New maximum | New mean | Text | Allocated |
| --- | ---: | ---: | ---: | ---: | ---: |
| O1 | 42,150,588 | 13,254,098 | 2,984,277 | 2,896 B | 99,784 B |
| O2 | 30,308,345 | 12,947,920 | 2,919,469 | 2,412 B | 99,300 B |
| O3 | 31,976,825 | 11,005,271 | 2,480,954 | 6,136 B | 102,976 B |
| Os | 45,089,423 | 14,012,546 | 3,161,944 | 2,312 B | 99,200 B |

For `54721631111111`, the O2 count falls to 11,932,859 and the expanded
nodes fall from 106,635 to 18,241. The maximum figures are observations over
the test set; they do not measure every valid state's instruction count.
Allocated sizes follow the per-implementation header contract and include
code and read-only data. Writable global storage is zero. All four are below
128 KiB even with the harness's entire 4 KiB stack reserve added.
