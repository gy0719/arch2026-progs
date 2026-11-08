# Mini-Rubik C baseline

The C function ports `gy0719/minirubik`'s `my_solver.c` (blob
`da6a286ace691e1b9dff56fe84b16d0cd8834cc0`). It retains optimal HTM IDA*,
Lehmer permutation ranking, six base-3 orientation digits, same-face pruning,
the minimum-exceeded bound, and the explicit stack of 12 32-byte frames.
The heuristic is `max(hp, ho)`, never their sum. Each face stores only its
quarter turn; repeated lookups produce half and inverse turns.

The 37,499 bytes of abstract tables are C constants, with every entry checked
against the old `solver_tables.S`. Rebuild them from the cube model with:

```sh
python3 tools/gen-rubik-tables.py | clang-format-20 > /tmp/rubik_tables.h
cmp /tmp/rubik_tables.h src/rubik/rubik_tables.h
```

Only the offline generator uses BFS over the 5,040 permutation and 729
orientation coordinates. The target searches each input, has no full-state
solution table, needs no initialization, and allocates no heap or global
writable storage. Independent concrete replay checks the path before output.

Input validation precedes all output writes. Invalid strings return -1 without
touching the buffer, including when cap is zero. Valid inputs with cap zero
return -2 without dereferencing out. For other capacities the complete solution
length is computed before emitting text: insufficient capacity writes only
out[0] = NUL and returns -2. An exact fit includes the terminating NUL. A solved
cube produces an empty string and returns zero when cap is at least one.

## Measured results

Measured on 2026-11-08 with GNU RISC-V GCC 15.2.0, RV32I/Zicsr/ILP32, and
rv32emu `ffb041bab9d1513e5329f25f486378778dceed13` in system interpreter mode
with M/A/F/C disabled. Instruction counts use the unchanged harness's
`PERF_CALL` and a measurement caller compiled once at -O2. They count guest
instructions, not physical CPU pipeline cycles. Host sanitizers use GCC 15.2.0.

| Build | Official C tests | ASan/UBSan | Maximum instructions | Code bytes | Read-only bytes | Allocated bytes | Solver stack bound |
|---|---:|---|---:|---:|---:|---:|---:|
| -O1 | 17/17 | PASS | 42,150,588 | 2,472 | 37,604 | 40,076 | 656 |
| -O2 | 17/17 | PASS | 30,308,345 | 2,060 | 37,604 | 39,664 | 576 |
| -O3 | 17/17 | PASS | 31,976,825 | 4,636 | 37,556 | 42,192 | 592 |
| -Os | 17/17 | PASS | 45,089,423 | 1,916 | 37,604 | 39,520 | 672 |

Every build has zero .data and .bss bytes. Allocated bytes use the driver's
`size -A` accounting, including code and all allocated sections. Stack bounds
sum GCC `-fstack-usage` reports along the longest solver call chain, including
the search frames; they fit the harness's 4 KiB stack. Even adding the entire
4 KiB stack reserve to the largest implementation is below 128 KiB.

The worst measured input for every build is `54721631111111`, at distance 11.
Each build passed 2,986 measured calls: the 59 supplied vectors and 2,927
oracle cases covering all 2,644 distinct distance-11 states and stratified
samples at distances 0 through 10. Each call checks the shortest distance,
move token grammar, concrete replay, and 50,000,000-instruction budget. The
duplicate depth-11 vectors are included in the call count.

A host-only independent BFS enumerated all 3,674,160 states, confirmed the
published distance histogram and every supplied vector's distance, and
generated the extra cases. Its full-state distance table and queue are
experimental verification tools and are never linked into the target.
Solving and instruction measurement do not exhaust the states at depths
0 through 10; the resource maxima above are observations over the stated set.

At each optimization level, combined ASan/UBSan also passed the unchanged
17 C tests, all 2,927 extra cases, 3,570 single-byte invalid mutations (each
with cap zero and nonzero), 14 short strings allocated exactly through their
NUL, and every capacity from zero through one byte beyond exact fit for all
59 vectors. Error paths check untouched bytes and buffer sentinels.
LeakSanitizer is disabled because it cannot run under this environment's
tracing; AddressSanitizer and UndefinedBehaviorSanitizer remain enabled.
The repository-wide `make sanitize` passed with `LSAN_OPTIONS=detect_leaks=0`.

All four implementation objects pass `scripts/rvcheck.py --impl c`. The
official target test logs each report 35 passes and 17 failures: every C test
passes, and every failure belongs to the Assembly skeleton or C/Assembly
agreement. The Assembly invalid-input test passes because its stub returns -1.
This stage does not claim that the complete HW2 dual implementation passes.
No tests, contract budgets, hooks, or Assembly sources were modified.

Raw logs, CSV/JSON summaries, source snapshots, disassembly, section sizes,
stack reports, the independent oracle, measurement harness and rerun script
are saved in `~/hw2-experiments/rubik/c-baseline/`. The upstream Assembly and
report snapshots remain there for the next stage. No push is part of this work.
