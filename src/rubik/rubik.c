#include "rubik.h"

#include <limits.h>

#include "rubik_tables.h"

/* Ported from gy0719/minirubik my_solver.c (da6a286ace69).
 * IDA* searches the target, using only 7! and 3^6 abstractions (37,499
 * table bytes). No full-state table, heap, runtime setup, or recursion.
 * An abstract distance is a lower bound on the concrete distance; their
 * maximum remains admissible. Increasing the bound to the smallest exceeded
 * f therefore finds a shortest HTM solution. Consecutive moves on the same
 * face combine into one move, so pruning them preserves every shortest path.
 */
enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    MOVES = 9,
    MAX_DEPTH = 11,
    NONE = 3,
    FOUND = -1,
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/* Search coordinates: p < PERMUTATIONS and o < ORIENTATIONS. */
typedef struct {
    uint16_t p, o;
} ranked_state_t;

/* Pointer views avoid variable large-stride multiplication on RV32I. */
static const uint16_t *const perm_transition[3] = {
    perm_move_table[0],
    perm_move_table[1],
    perm_move_table[2],
};
static const uint16_t *const ori_transition[3] = {
    ori_move_table[0],
    ori_move_table[1],
    ori_move_table[2],
};
static const char move_names[MOVES][3] = {
    "R", "R2", "R'", "B", "B2", "B'", "D", "D2", "D'",
};
/* Each destination takes a cubie from source[face][destination]. */
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

/* Each operand is 0..2, so a sum needs at most one subtraction. */
static uint8_t reduce_three(uint8_t value)
{
    return value >= 3 ? (uint8_t) (value - 3U) : value;
}

static state_t quarter_turn(state_t state, uint8_t face)
{
    state_t result;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t from = source[face][i];
        result.p[i] = state.p[from];
        result.o[i] = reduce_three((uint8_t) (state.o[from] + twist[face][i]));
    }
    return result;
}

/* Lehmer digits use fixed factorial weights: 720, 120, 24, 6, 2, 1. */
static uint16_t rank_permutation(const uint8_t permutation[CUBIES])
{
    uint32_t digit[6];

    for (uint8_t i = 0; i < 6; ++i) {
        uint32_t smaller = 0;
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j) {
            if (permutation[j] < permutation[i])
                ++smaller;
        }
        digit[i] = smaller;
    }
    uint32_t rank =
        (digit[0] << 9) + (digit[0] << 7) + (digit[0] << 6) + (digit[0] << 4);
    rank += (digit[1] << 7) - (digit[1] << 3);
    rank += (digit[2] << 4) + (digit[2] << 3);
    rank += (digit[3] << 2) + (digit[3] << 1);
    rank += (digit[4] << 1) + digit[5];
    return (uint16_t) rank;
}

static uint16_t rank_orientation(const uint8_t orientation[CUBIES])
{
    uint16_t rank = 0;

    for (uint8_t i = 0; i < 6; ++i) {
        rank = (uint16_t) ((rank << 1) + rank + orientation[i]);
    }
    return rank;
}

static int valid(const state_t *state)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (state->p[i] >= CUBIES || state->o[i] >= 3)
            return 0;
        for (uint8_t j = 0; j < i; ++j)
            if (state->p[j] == state->p[i])
                return 0;
        sum = reduce_three((uint8_t) (sum + state->o[i]));
    }
    return sum == 0;
}

static ranked_state_t rank_coordinates(const state_t *state)
{
    ranked_state_t coordinates = {rank_permutation(state->p),
                                  rank_orientation(state->o)};
    return coordinates;
}
/* Even indices use the low nibble; odd indices use the high nibble. */
static uint8_t packed_get(const uint8_t *table, uint16_t index)
{
    unsigned shift = (index & 1U) << 2;
    return (uint8_t) ((table[index >> 1] >> shift) & 0xFU);
}
typedef struct {
    uint8_t moves[MAX_DEPTH];
    uint8_t length;
} solution_t;

static uint8_t heuristic(ranked_state_t state)
{
    uint8_t p = packed_get(hp_packed, state.p);
    uint8_t o = packed_get(ho_packed, state.o);
    /* Both abstractions charge for the same moves: use max, never sum. */
    return p > o ? p : o;
}

/* Eight 32-bit fields per suspended node, independent of pointer width.
 * Coordinates and cursors stay in locals while a node is active. Only an
 * expanded child suspends its parent; cutoff/goal leaves need no frame writes.
 */
typedef struct {
    uint32_t p, o;
    uint32_t quarter_p, quarter_o;
    uint32_t face, turn;
    uint32_t previous, minimum;
} search_frame_t;

_Static_assert(sizeof(search_frame_t) == 32, "search frame must be 32 bytes");

/* Return FOUND, or the minimum f that exceeded the current bound.
 * One loop generates children, enters expanded nodes and restores parents.
 */
static int search(ranked_state_t state, int bound, solution_t *solution)
{
    search_frame_t frames[MAX_DEPTH + 1];
    int f = heuristic(state);
    if (f > bound) {
        return f;
    }
    if (state.p == 0 && state.o == 0) {
        solution->length = 0;
        return FOUND;
    }
    uint32_t depth = 0, p = state.p, o = state.o;
    uint32_t quarter_p = p, quarter_o = o;
    uint32_t face = 0, turn = 0, previous = NONE, minimum = INT_MAX;
    const uint16_t *perm_row = NULL, *ori_row = NULL;

    for (;;) {
        if (turn == 3) {
            ++face;
            turn = 0;
        }
        if (face == 3) {
            if (depth == 0)
                return (int) minimum;
            uint32_t result = minimum;
            const search_frame_t *parent = &frames[--depth];
            p = parent->p;
            o = parent->o;
            quarter_p = parent->quarter_p;
            quarter_o = parent->quarter_o;
            face = parent->face;
            turn = parent->turn;
            previous = parent->previous;
            minimum = parent->minimum;
            if (result < minimum)
                minimum = result;
            /* A completed face needs no row restoration: the next face
             * obtains its rows normally on the next loop iteration.
             */
            if (turn < 3) {
                perm_row = perm_transition[face];
                ori_row = ori_transition[face];
            }
            continue;
        }
        if (turn == 0) {
            /* Adjacent moves of one face combine into at most one HTM move. */
            if (face == previous) {
                ++face;
                continue;
            }
            perm_row = perm_transition[face];
            ori_row = ori_transition[face];

            quarter_p = p;
            quarter_o = o;
        }
        quarter_p = perm_row[quarter_p];
        quarter_o = ori_row[quarter_o];

        solution->moves[depth] = (uint8_t) ((face << 1) + face + turn);
        ++turn;
        ranked_state_t next = {(uint16_t) quarter_p, (uint16_t) quarter_o};
        f = (int) (depth + 1U) + heuristic(next);
        if (f > bound) {
            if ((uint32_t) f < minimum)
                minimum = (uint32_t) f;
            continue;
        }
        if (quarter_p == 0 && quarter_o == 0) {
            solution->length = (uint8_t) (depth + 1U);
            return FOUND;
        }
        if (depth + 1U == MAX_DEPTH) {
            continue;
        }
        search_frame_t *parent = &frames[depth];
        parent->p = p;
        parent->o = o;
        parent->quarter_p = quarter_p;
        parent->quarter_o = quarter_o;
        parent->face = face;
        parent->turn = turn;
        parent->previous = previous;
        parent->minimum = minimum;

        ++depth;
        p = quarter_p;
        o = quarter_o;
        previous = face;
        face = 0;
        turn = 0;
        minimum = INT_MAX;
    }
}

static int solve(ranked_state_t start, solution_t *solution)
{
    int bound = heuristic(start);
    while (bound <= MAX_DEPTH) {
        int result = search(start, bound, solution);
        if (result == FOUND)
            return 1;
        if (result == INT_MAX)
            break;
        bound = result;
    }
    return 0;
}

static int parse_state(const char *input, state_t *state)
{
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (input[i] < '1' || input[i] > '7')
            return 0;
        state->p[i] = (uint8_t) (input[i] - '1');
    }
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (input[i + CUBIES] < '1' || input[i + CUBIES] > '3')
            return 0;
        state->o[i] = (uint8_t) (input[i + CUBIES] - '1');
    }
    return input[RUBIK_STATE_LEN] == '\0' && valid(state);
}

/* Replay the original concrete input without ranked transition lookups. */
static int replay_solution(const state_t *original, const solution_t *solution)
{
    if (solution->length > MAX_DEPTH)
        return 0;
    state_t state = *original;
    for (uint8_t i = 0; i < solution->length; ++i) {
        uint8_t move = solution->moves[i], face, turns;
        if (move >= MOVES)
            return 0;
        if (move < 3) {
            face = 0;
            turns = (uint8_t) (move + 1U);
        } else if (move < 6) {
            face = 1;
            turns = (uint8_t) (move - 2U);
        } else {
            face = 2;
            turns = (uint8_t) (move - 5U);
        }
        for (uint8_t turn = 0; turn < turns; ++turn)
            state = quarter_turn(state, face);
    }
    for (uint8_t i = 0; i < CUBIES; ++i)
        if (state.p[i] != i || state.o[i] != 0)
            return 0;
    return 1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    state_t original;
    /* Each digit is checked before reading the next, including short strings.
     * Validate completely before touching out, even when cap is zero.
     */
    if (!parse_state(state, &original))
        return -1;
    if (cap == 0)
        return -2;

    solution_t solution;
    if (!solve(rank_coordinates(&original), &solution) ||
        !replay_solution(&original, &solution))
        return -1;

    size_t length = 0;
    for (unsigned i = 0; i < solution.length; ++i) {
        const char *name = move_names[solution.moves[i]];
        length += (i != 0) + 1U + (name[1] != '\0');
    }
    /* Compute the entire length first: -2 writes only an empty string. */
    if (length >= cap) {
        out[0] = '\0';
        return -2;
    }
    size_t at = 0;
    for (unsigned i = 0; i < solution.length; ++i) {
        const char *name = move_names[solution.moves[i]];
        if (i != 0)
            out[at++] = ' ';
        out[at++] = name[0];
        if (name[1])
            out[at++] = name[1];
    }
    out[at] = '\0';
    return solution.length;
}
