# Rubik assembly: corner pattern database

The solver fixes the eighth corner. Its coordinates therefore contain seven
movable corners, not eight. The existing permutation table forgets all corner
twists; the orientation table forgets which corner is in each position. Their
maximum can miss information carried by the combination of position and twist.

The new pattern tracks the positions and twists of corners 1 through 4. Its
ordered position rank has P(7,4) = 840 possibilities and its base-3 twist rank
has 81 possibilities. Reverse breadth-first search from the solved pattern,
with all nine face turns at unit cost, gives 68,040 exact abstract distances.
The maximum distance is 8, so two distances fit in each byte. The generated
read-only data also includes position transitions, twist transitions, and a map
from the existing 7-corner permutation rank to the pattern position rank.
Regenerate the checked-in assembly data with:

```
python3 tools/gen-rubik-pdb.py 4 /tmp/rubik-pdb4
cmp /tmp/rubik-pdb4/pdb.S src/rubik/rubik_pdb_tables.S
```

Every concrete face turn maps each tracked corner's position and twist to
exactly the position and twist represented by the corresponding abstract
transition. Hence any concrete solution projects to an abstract solution with
the same number of moves. Exact abstract distance is therefore at most the
concrete distance, and max(permutation, orientation, pattern) remains
admissible. No heuristic values are added. An independent exhaustive verifier
checked all 3,674,160 concrete coordinates, all 11,022,480 quarter-turn
projections, and the pattern distance against the concrete shortest distance.
A target-side probe also checked every abstract quarter turn and both assembly
lookup paths for all 68,040 pattern states.

The C solver retains its original heuristic. Both versions use the same move
order. At the optimal IDA* bound, admissibility preserves every prefix of every
optimal solution, so both visit optimal solutions in the same order; an earlier
bound cannot contain a solution. All 2,987 test calls also compare their exact
output bytes and lengths.

## Experiments

All instruction counts are RV32I retired instructions from the same test
harness and include the call overhead as in the previous stage. The average is
across 2,987 calls; it is not an average over the entire cube state space.
Node counts are expanded nodes, excluding cutoff children. The maximum is over
the complete test set, including all 2,644 distance-11 states.

| Variant | Worst instructions | Average | Hard-input nodes | Code | Allocated | PDB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Previous | 18,579,542 | See previous experiment | 106,635 | 1,596 B | 42,031 B | 0 B |
| 3 corners | 16,355,976 | 4,866,490 | 45,493 | 1,952 B | 58,522 B | 2,835 B |
| 4 corners | 7,143,519 | 1,607,394 | 18,241 | 1,952 B | 101,696 B | 34,020 B |

The 3-corner abstraction has P(7,3) * 3^3 = 5,670 states. It passed the
same correctness checks, but 186 of the 2,987 calls exceeded 7,500,000
instructions. The 4-corner variant exceeded the budget in none of these calls.
Its worst state was `12347651111111` with 19,786 expanded nodes. The original
hard input `54721631111111` took 6,586,901 instructions, expanded 18,241
nodes, and generated 109,428 children in the same harness.

The 4-corner PDB is 34,020 bytes; position transition rows use 10,080 bytes,
twist transitions 5,103 bytes, and the permutation-to-pattern map 10,080
bytes. Alignment and other assembly data are included in the reported total.
The implementation's allocated sections total 101,696 bytes (1,952 text and
99,744 read-only data), with no writable global data. Its 496-byte stack frame
brings this conservative sum to 102,192 bytes, below 128 KiB. The header budget
is per implementation; the linked test program also contains the C solver and
its tables, which are measured separately.

The inline pattern position/twist transition costs 14 instructions per child,
including the two-instruction table address load. The packed pattern lookup and
maximum cost 15 instructions, or 16 when the maximum changes. A face-row load
and frame save/restore also support the extra coordinate. These are static path
counts; the overall measurements above include all search and setup work.

For both candidate sizes, O1, O2, O3, and Os passed the official 52 tests and
2,987 independent shortest-path/replay/exact-C-comparison calls; each level also
passed 8,282 ABI, buffer, and stack-guard calls. The 4-corner driver passed all
checks, including instruction budget, footprint, and RV32I disassembly. Host
ASan/UBSan checks passed. Detailed scripts, raw logs, generated candidate data,
and measurements are stored in `~/hw2-experiments/rubik/asm-pattern-db/`.
An additional host-side run solved all 3,674,160 valid coordinates and checked
every resulting length against independent concrete BFS distances. This is a
correctness check, not an instruction measurement for every coordinate.
