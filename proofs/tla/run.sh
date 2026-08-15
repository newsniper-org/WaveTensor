#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# Runs the full ACC-bank formal gate:
#
#   2 runs that MUST PASS  — the good model, exhaustive (small + large cfg);
#   7 runs that MUST FAIL  — per-guard deletion experiments.  These are the
#                            MEASUREMENT behind README §5's load-bearing
#                            guard table: a guard is only called
#                            load-bearing because deleting it (and it
#                            alone) makes TLC produce a counterexample
#                            violating that guard's own invariant;
#   1 run  that MUST FAIL  — all guards deleted at once: the refuted
#                            "requester ID" design of spec §23.1, shown as
#                            end-to-end silent value corruption;
#   6 runs that MUST FAIL  — hazard-reachability witnesses: each guarded
#                            hazard genuinely occurs in the good model, so
#                            the good model passes because the contract
#                            CONTAINS the hazards, not because the config
#                            never exercises them.
#
# Exits non-zero if any run does not behave as declared, so this script is
# usable directly as a merge gate.
#
#   ./run.sh          run everything
#
# -workers 1 is PINNED: with multiple workers the BFS visit order (and
# therefore the states-generated count at which a MUST-FAIL run stops)
# depends on thread scheduling.  Single-worker runs make every number in
# README §4 exactly reproducible.  MUST-PASS state counts are exhaustive
# and scheduling-independent either way.
#
# Requires: tla2tools (tlc2.TLC).  Run from anywhere — the script cd's to
# its own location.

set -eu
cd "$(dirname "$0")"

TLC="java -XX:+UseParallelGC -cp /usr/share/java/tla2tools.jar tlc2.TLC -nowarning -workers 1 -cleanup"
rc=0
runs=0

# expect_pass <label> <args...>
expect_pass() {
    label="$1"; shift
    runs=$((runs + 1))
    printf '\n=== [%02d] %s  (MUST PASS) ===\n' "$runs" "$label"
    if $TLC "$@" 2>&1 | tee /tmp/wt_tla_out.txt | tail -12; then :; fi
    if grep -q "Model checking completed. No error has been found." /tmp/wt_tla_out.txt; then
        echo "--> OK"
    else
        echo "--> FAIL: expected a clean run"; rc=1
    fi
}

# expect_fail <label> <expected-violated-property> <args...>
expect_fail() {
    label="$1"; want="$2"; shift 2
    runs=$((runs + 1))
    printf '\n=== [%02d] %s  (MUST FAIL: %s) ===\n' "$runs" "$label" "$want"
    if $TLC -difftrace "$@" 2>&1 | tee /tmp/wt_tla_out.txt | tail -30; then :; fi
    if grep -q "Invariant $want is violated" /tmp/wt_tla_out.txt; then
        echo "--> OK (counterexample produced, as required)"
    else
        echo "--> FAIL: expected $want to be violated"; rc=1
    fi
}

# ---- MUST PASS: the good model, exhaustively -----------------------------

expect_pass "GOOD model — full safety + liveness" AccBank

expect_pass "GOOD model — 4 streams / K=3 / both banks contended (safety only)" \
    -config AccBank_large.cfg AccBank

# ---- MUST FAIL: per-guard deletion experiments ---------------------------
# One guard deleted per run, via CONSTANT DisabledGuards.  Each failure is
# attributable to exactly that guard.  This is the load-bearing measurement.

expect_fail "DELETE commit_free  — claim steals a live bank" \
    Inv_OwnerAgreement    -config AccBank_del_commit_free.cfg   AccBank

expect_fail "DELETE commit_zero  — stale SRAM folds into the new owner" \
    NoSilentAliasing      -config AccBank_del_commit_zero.cfg   AccBank

expect_fail "DELETE acc_owner    — stray VFMA_ACC lands in a foreign bank" \
    NoSilentAliasing      -config AccBank_del_acc_owner.cfg     AccBank

expect_fail "DELETE drain_owner  — stray drain reads out a foreign partial" \
    Inv_NoCrossContextLeak -config AccBank_del_drain_owner.cfg  AccBank

expect_fail "DELETE fill_owner   — fill restores a foreign spill image" \
    Inv_NoCrossContextLeak -config AccBank_del_fill_owner.cfg   AccBank

expect_fail "DELETE fill_bankfree — fill lands on a live foreign owner" \
    Inv_OwnerAgreement    -config AccBank_del_fill_bankfree.cfg AccBank

expect_fail "DELETE zero_owner   — raw 0x7E zero race, silent wrong drain" \
    Inv_Value             -config AccBank_del_zero_owner.cfg    AccBank

# ---- MUST FAIL: the refuted design (all guards off at once) --------------

expect_fail "REQUESTER-ID design (all guards deleted) — end-to-end corruption" \
    Inv_Value             -config AccBank_requesterid.cfg       AccBank

# ---- MUST FAIL: hazard-reachability witnesses (good model) ---------------

expect_fail "WITNESS — acquire claim contends with a live foreign owner" \
    Witness_NoAcquireContention -config AccBank_witness_reject.cfg       AccBank

expect_fail "WITNESS — stray accumulate attempt reaches a foreign bank" \
    Witness_NoStrayAccumulate   -config AccBank_witness_stray_acc.cfg    AccBank

expect_fail "WITNESS — stray drain attempt reaches a foreign bank" \
    Witness_NoStrayDrain        -config AccBank_witness_stray_drain.cfg  AccBank

expect_fail "WITNESS — a fill can address a foreign spill image" \
    Witness_NoForeignFillTarget -config AccBank_witness_fill_foreign.cfg AccBank

expect_fail "WITNESS — own image ready while the bank is foreign-owned" \
    Witness_NoBusyFill          -config AccBank_witness_fill_busy.cfg    AccBank

expect_fail "WITNESS — the raw-0x7E zero-race window is open" \
    Witness_NoZeroRaceWindow    -config AccBank_witness_zero_window.cfg  AccBank

printf '\n=====================================\n'
if [ "$rc" -eq 0 ]; then
    echo "ALL $runs RUNS BEHAVED AS DECLARED — gate GREEN"
else
    echo "GATE RED"
fi
exit "$rc"
