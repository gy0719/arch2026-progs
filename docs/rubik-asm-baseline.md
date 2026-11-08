# RV32I Rubik baseline

This stage ports the existing IDA* algorithm to an independent hand-written
`rubik_solve_asm`. Functional checks pass. **The 7,500,000-instruction budget
does not pass**, so the full Rubik grade remains failing. This commit is the
correct baseline authorized for later performance work.

## Algorithm and ABI

The port retains the C implementation's Lehmer permutation rank, six base-3
orientation digits, quarter-turn transition rows, nibble-packed abstract
distances, `max(hp, ho)`, same-face pruning, minimum-exceeded IDA* bounds, and
fixed explicit search stack. Its private core comes from the hand-written
`gy0719/minirubik/solver.S` snapshot used in stage 1, blob
`7f76bff6aff18df1d38cf9eda935d4c36b9efe3a`.

The public entry validates the complete input before touching output, saves
and restores s0 through s11 and ra, and keeps sp 16-byte aligned. All mutable
state is in one 496-byte frame: 384 bytes for suspended search nodes, 12 for
the path, the length and saved input/output coordinates, and the ABI save
area. Helpers leave sp unchanged; the search is iterative. There is no heap,
writable global storage, C call, environment call, or CSR access.

Internal helpers use the original private register convention within the ABI
wrapper: s0 through s11 hold the active search fields and transition rows;
a2/a3/t3/t4 hold table bases, t5 the frame cursor, and a7 the path cursor.
a4/a5 preserve the roots, a6 holds the solve return address, and t6 holds the
search or replay return address. ra holds the constant 3 in the hot loop.
These private helpers are local symbols, not public ABI entry points.

The wrapper adds the contract's invalid-input and capacity handling. It
replays the resulting path through the ranked transitions before computing
the entire output length. An insufficient nonzero buffer receives only NUL
at out[0]; cap zero returns -2 without writing. Invalid input returns -1
without writing, including when cap is zero. An exact fit includes the NUL,
and a solved cube writes an empty string and returns zero.

## Read-only tables

Both versions use the same generator, rank order, entries, and nibble layout:

| Table | Entries | Bytes |
|---|---:|---:|
| Permutation quarter turns | 3 x 5,040 | 30,240 |
| Orientation quarter turns | 3 x 729 | 4,374 |
| Packed permutation distances | 5,040 nibbles | 2,520 |
| Packed orientation distances | 729 nibbles | 365 |
| Total | | 37,499 |

Every entry was compared with both the C constants and the old
`solver_tables.S`. The grader requires each implementation object to be
self-contained, so they share definitions and values through the generator,
but have **separate physical copies**. Assembly does not reference the C
object. Generate its tables with:

```sh
python3 tools/gen-rubik-tables.py --assembly > /tmp/rubik_asm_tables.S
cmp /tmp/rubik_asm_tables.S src/rubik/rubik_asm_tables.S
```

The existing C generator mode and C sources are unchanged.

## Correctness and resource results

Measured on 2026-11-08 with GNU RISC-V GCC 15.2.0 and GNU binutils 2.45,
`-march=rv32i_zicsr -mabi=ilp32`, and rv32emu
`ffb041bab9d1513e5329f25f486378778dceed13` in system interpreter mode with
M/A/F/C disabled. Counters measure guest instructions, not hardware latency.

The unmodified official tests report **51 passed, 1 failed at each of -O1,
-O2, -O3 and -Os**. Every C test, the C/Assembly agreement test, and all
Assembly tests except depth 11 pass. The depth-11 test stops because
`21345671111111` exceeds the instruction budget, not because its solution is
incorrect. `scripts/driver.py --prog rubik` therefore correctly reports FAIL;
the ISA, footprint and benchmark checks pass. No test, header, budget, hook,
runtime or grading script was changed.

A separate experimental target harness verifies all cases even if they are
over budget, and records those budget violations separately. Its 2,987 calls
include the hardest input, all 59 official vectors, and the stage-1 oracle's
2,927 cases. These cover every one of the 2,644 distinct depth-11 states and
stratified samples at depths 0 through 10. Every returned length is the exact
oracle distance, every token sequence replays to solved, and every output
matches the C version byte for byte. Lower depths are sampled, not exhausted.

An additional target checker passes **8,282 ABI-checked calls**, including
3,570 invalid single-byte mutations with zero and nonzero capacities, all 13
official invalid inputs, every capacity from zero through one byte beyond
exact fit for every official vector, and the hardest input. It checks buffer
sentinels, zero-capacity NULL output, preservation of all callee-saved and
reserved registers, restoration of sp, and a 16-byte guard immediately below
the implementation's 496-byte frame.

The repository-wide C ASan/UBSan run also passes with
`LSAN_OPTIONS=detect_leaks=0`, as required by this traced environment.
Sanitizers do not instrument hand-written Assembly; the target checks above
validate its ABI and output behavior. Both implementation objects pass
`scripts/rvcheck.py`; `nm -u impl_asm.o` is empty.

| Metric | Observation |
|---|---:|
| Official six-input benchmark average, Assembly in -O2 ELF | 143,512.0 instructions/call |
| Average over 59 official vectors, fixed -O2 measurement caller | 1,491,435.63 instructions/call |
| Average over 2,987 measured calls | 8,466,846.48 instructions/call |
| Worst observed instructions | 29,409,443 |
| Budget | 7,500,000 |
| Excess over budget | 21,909,443 |
| Worst/budget ratio | 3.9213 |
| Reduction needed from this baseline | 74.50% |
| .text | 1,748 bytes |
| .rodata, including move names and alignment | 37,527 bytes |
| .data / .bss | 0 / 0 bytes |
| All allocated implementation sections | 39,275 bytes |
| Maximum implementation stack frame | 496 bytes |

The worst observed state is `54721631111111`. The same Assembly object is
linked into all four optimization builds. The official six-input benchmark
averages are 143,513.17 / 143,512.00 / 143,514.50 / 143,512.33 instructions
for -O1/-O2/-O3/-Os. Small caller differences explain this variation; the
canonical per-case measurements use one caller compiled at -O2. The initial
pilot reports one fewer instruction for the hardest input because its caller
differs. Of the 2,987 canonical measured calls, 2,312 exceed the budget.

The implementation plus its stack uses 39,771 bytes, below 128 KiB. Allocated
section totals follow the driver's `size -A` accounting, including code and
excluding debug information and the harness. The tables are abstract lookup
tables, never a full 3,674,160-state solution table.

## Search work and hotspots

An experimental instrumented Assembly copy counts events without changing
search order, bounds or pruning. It is never linked into the submission, and
its instruction counts are not used as production performance measurements.
Its paths are also checked against C over the full measured set.

For the hardest state:

| Event | Count |
|---|---:|
| IDA* iterations | 6 |
| Expanded nodes, including each expanded iteration root | 106,635 |
| Generated children | 639,792 |
| Same-face skips | 106,624 |
| Frame pushes / pops | 106,629 / 106,619 |
| Bound cutoffs | 533,162 |
| Transition row selections, including restoration | 283,897 |

Average expanded nodes are 5,409.41 over the 59 vectors and 30,728.14 over
all 2,987 calls. Ranking happens once per input and is outside the hot loop.
Each generated child uses two halfword transition loads (six instructions)
and two nibble heuristic loads (15 or 16 instructions including the maximum
comparison). At the worst input these account for 3,838,752 transition
instructions and 9,596,880 to 10,236,672 heuristic instructions, before other
search control work. This is static instruction accounting multiplied by
measured events, not a hardware cache profile.

Only expanded children suspend parents, but the worst case still writes
853,032 frame words and reads 852,952. Same-face pruning skips 319,872
immediate candidate children, about one third of generated-plus-skipped
candidates; that is a local pruning count, not an estimate of the entire
unpruned search tree. The core already has no per-node function calls or
recursive stack frames. The inherited search work and repeated table
extraction dominate this baseline; no further micro-optimization or search
redesign was attempted in this stage.

All raw logs, per-case instruction/node CSV, source snapshots, ABI checker,
instrumented copy, disassembly, driver charts, sizes, and rerun instructions
are preserved in `~/hw2-experiments/rubik/asm-baseline/`.
