#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# WT64v1 재구현 — 선-formal 게이트.
#
# 정본 §6.3 「개발 순서 — 구속력 있음」:
#   선-formal → RTL → 후-formal. **1단을 건너뛴 모듈은 완료로 간주하지 않는다.**
#
# 이 러너는 기존 `proofs/tla/run.sh` (ACC bank) 의 규약을 승계하되 **분리**돼
# 있다 — 기존 게이트 계보를 건드리지 않는 것이 목적이다.
#
# 구성 (모델당):
#   MUST PASS  — 좋은 모델. 작은 설정 + 큰 설정(규모 검사).
#   MUST FAIL  — 가드 삭제 실험. 가드 하나를 지우고 **그 가드 자신의 불변식**이
#                무너지는지 본다. 지워도 통과하는 가드는 불필요하거나 속성이
#                부실한 것이며, 어느 쪽인지 판정하기 전에는 검증됐다고 하지
#                않는다 (§6.3.2).
#   MUST FAIL  — 위험 도달성 증인. 좋은 모델이 통과하는 이유가 "계약이 위험을
#                담고 있어서" 인지 "설정이 그 위험을 한 번도 만들지 않아서"
#                인지를 가른다. 후자면 그 통과는 아무것도 뜻하지 않는다.
#
# `-workers 1` 은 **PIN** 이다: 여러 워커에서는 BFS 방문 순서가 스레드 스케줄에
# 의존해 MUST-FAIL run 이 멈추는 상태 수가 재현되지 않는다.
#
# 선언과 다르게 행동한 run 이 하나라도 있으면 non-zero 로 끝난다 — merge gate 로
# 그대로 쓸 수 있어야 하기 때문이다.

set -eu
cd "$(dirname "$0")"

TLC="tlc -nowarning -workers 1 -cleanup"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

rc=0
runs=0

expect_pass() {
    label="$1"; cfg="$2"; mod="$3"
    runs=$((runs + 1))
    printf '\n=== [%02d] %-42s (MUST PASS) ===\n' "$runs" "$label"
    $TLC -config "$cfg" "$mod" > "$OUT" 2>&1 || true
    if grep -q "Model checking completed. No error has been found." "$OUT"; then
        grep -E "states generated" "$OUT" | tail -1
        echo "--> OK"
    else
        tail -20 "$OUT"
        echo "--> FAIL: 깨끗한 run 이어야 한다"; rc=1
    fi
}

# expect_fail <label> <cfg> <module> <위반해야 하는 속성>
expect_fail() {
    label="$1"; cfg="$2"; mod="$3"; want="$4"
    runs=$((runs + 1))
    printf '\n=== [%02d] %-42s (MUST FAIL: %s) ===\n' "$runs" "$label" "$want"
    $TLC -config "$cfg" "$mod" > "$OUT" 2>&1 || true
    if grep -q "No error has been found" "$OUT"; then
        echo "--> FAIL: 반례가 나와야 하는데 통과했다."
        echo "    가드가 불필요하거나 속성이 부실하다 — 어느 쪽인지 판정할 것."
        rc=1
    elif grep -q "$want is violated" "$OUT"; then
        echo "--> OK (반례 생성됨 — 선언대로)"
    else
        echo "--> FAIL: 실패는 했으나 **다른 이유**다. 기대: $want"
        grep -E "Error|violated" "$OUT" | head -4
        rc=1
    fi
}

echo "======================================================================="
echo " WT64v1 재구현 선-formal 게이트"
echo "======================================================================="

# ---------------------------------------------------------------------------
# FAB-2 — 공유 자원 배타성 + 무처분 없음 (부록 D.5 우선순위 1번)
#
# 1번인 이유는 이 프로젝트가 실제로 여기서 무너졌기 때문이다: 공유 디코더가
# 점유 중일 때 도착한 명령이 어떤 오류 비트도 세우지 않고 사라졌다.
# ---------------------------------------------------------------------------
M=SharedUnit.tla
expect_pass "FAB-2 좋은 모델 (깊이 1 · 요청자 3)"  SharedUnit.cfg        "$M"
expect_pass "FAB-2 좋은 모델 (깊이 2 · 요청자 4)"  SharedUnit_large.cfg  "$M"

expect_fail "가드 삭제: busy_check"    SharedUnit_del_busy_check.cfg   "$M" Inv_Exclusive
expect_fail "가드 삭제: queue_room"    SharedUnit_del_queue_room.cfg   "$M" Inv_NoLoss
expect_fail "가드 삭제: backpressure"  SharedUnit_del_backpressure.cfg "$M" Inv_NoUndisposed

expect_fail "증인: 경합이 실재하는가"       SharedUnit_witness_NoQueueing.cfg     "$M" Witness_NoQueueing
expect_fail "증인: 배압 경로가 실재하는가"  SharedUnit_witness_NoBackpressure.cfg "$M" Witness_NoBackpressure
expect_fail "증인: 처리 완료가 실재하는가"  SharedUnit_witness_NoCompletion.cfg   "$M" Witness_NoCompletion

# ---------------------------------------------------------------------------
# FAB-3 · FAB-4 — 기입 자격과 소유 구간 (부록 D.5 우선순위 2번)
#
# 2번인 이유도 1번과 같다: 이 프로젝트가 실제로 여기서 무너졌다. 기입 자격을
# 강제하던 실행 시점 검사가 모듈 삭제와 함께 사라졌고 정적 검사도 회귀도
# 전부 통과했다 (§2.4 함정).
#
# L 은 상수가 아니라 **파라미터**다 (§2.4) — 서로 다른 두 값으로 돌린다.
# ---------------------------------------------------------------------------
M=ResultBank.tla
expect_pass "FAB-3/4 좋은 모델 (L=1 · 슬롯 2 · 생산자 2)"  ResultBank.cfg       "$M"
expect_pass "FAB-3/4 좋은 모델 (L=2 · 슬롯 2 · 생산자 3)"  ResultBank_large.cfg "$M"

expect_fail "가드 삭제: owner_check"    ResultBank_del_owner_check.cfg   "$M" Prop_WriteQualified
expect_fail "가드 삭제: acquire_free"   ResultBank_del_acquire_free.cfg  "$M" Prop_IntervalStable
expect_fail "가드 삭제: interval_end"   ResultBank_del_interval_end.cfg  "$M" Inv_IntervalBounded

expect_fail "증인: 소유가 실재하는가"       ResultBank_witness_NoOwnership.cfg    "$M" Witness_NoOwnership
expect_fail "증인: 기입이 실재하는가"       ResultBank_witness_NoWrite.cfg        "$M" Witness_NoWrite
expect_fail "증인: 구간 만료가 실재하는가"  ResultBank_witness_NoFullInterval.cfg "$M" Witness_NoFullInterval

# ---------------------------------------------------------------------------
# HIU-1 · HIU-2 · HIU-3 · HIU-4 — 변환 저장 블록 (부록 D.5 우선순위 3번)
#
# 넷을 한 모델에 두는 이유는 넷이 **같은 구조 위의 성질**이기 때문이다.
# 따로 쓰면 저장 블록을 네 벌 모델링하게 되고 그 네 벌이 드리프트한다.
#
# 핵심은 §3.6.3 — flush 는 유효 비트만 지우고 **데이터는 남는다.**
# 유효 비트가 유일한 방벽이다.
# ---------------------------------------------------------------------------
M=XlateStore.tla
expect_pass "HIU-1/2/3/4 좋은 모델 (파티션 2 · 색인 2)"  XlateStore.cfg       "$M"
expect_pass "HIU-1/2/3/4 좋은 모델 (파티션 3 · 색인 2)"  XlateStore_large.cfg "$M"

expect_fail "가드 삭제: valid_check"     XlateStore_del_valid_check.cfg     "$M" Inv_ValidGated
expect_fail "가드 삭제: partition_check" XlateStore_del_partition_check.cfg "$M" Inv_PartitionIsolated

expect_fail "증인: 적중이 실재하는가"          XlateStore_witness_NoHit.cfg              "$M" Witness_NoHit
expect_fail "증인: flush 후 데이터가 남는가"   XlateStore_witness_DataSurvivesFlush.cfg  "$M" Witness_DataSurvivesFlush

# 위 증인의 **유효성**을 짝으로 확인한다. 데이터를 지우는 모델에서는 그 증인이
# 성립해야 하며, 성립한다는 사실이 곧 "좋은 모델에서 반증된 이유는 데이터가
# 실제로 남기 때문" 이라는 증명이다. 증인이 부실해서 반증된 것이 아니다.
expect_pass "증인 유효성: 데이터를 지우면 증인이 선다" \
            XlateStore_del_flush_keeps_data.cfg "$M"

# ---------------------------------------------------------------------------
# ISA-3 · ISA-4 — route fault 의 판정 주체와 범위 (부록 D.5 우선순위 4번)
#
# 앞의 셋과 성격이 다르다. 이미 일어난 결함이 아니라 **일어나면 설계를
# 망가뜨리는** 것이다 — "잘못 구현하면 정상 워크로드가 죽는다".
#
# 발화 조건은 **둘**이다 (§1.6.3): LNID 합집합 미스 · src_kind=1 의 LBID 미사상.
# 하나만 모델링하면 ISA-4 「최대 1회」가 검사할 것이 없다.
#
# 형상 sweep 을 돈다 (§1.2 「유일한 직접 검사」). 깊이 축뿐 아니라 이름 수·지점
# 수도 바꾼다 — |Names| = |Points| 인 형상에서는 구성이 끝나면 합집합이 이름
# 공간 전체가 되어 **LNID 미스가 원리적으로 도달 불가**가 된다 (적대 검증 실측).
#
# 계층: 기저(깊이 1·2·3)는 TLC 전수 검사, 임의 깊이는 `Inv_ScopeLocal`
# (범위 간 비간섭) 위에 선 **귀납 논증**이다. TLAPS 기계 증명이 아니다.
# ---------------------------------------------------------------------------
M=Route.tla
expect_pass "ISA-3/4 기저 — 깊이 1"          Route_depth1.cfg "$M"
expect_pass "ISA-3/4 기저 — 깊이 2"          Route_depth2.cfg "$M"
expect_pass "ISA-3/4 기저 — 깊이 3"          Route_depth3.cfg "$M"
expect_pass "형상 sweep — 이름 4 · 지점 2"   Route_shapeA.cfg "$M"
expect_pass "형상 sweep — 이름 3 · 지점 3"   Route_shapeB.cfg "$M"

expect_fail "가드 삭제: global_judge (지역 판정)" Route_del_global_judge.cfg "$M" Inv_CleanNeverFaults
expect_fail "가드 삭제: fault_once"               Route_del_fault_once.cfg   "$M" Inv_FaultAtMostOncePerScope
expect_fail "가드 삭제: loud_fault (무언 드롭)"   Route_del_loud_fault.cfg   "$M" Inv_MissAlwaysFaults

expect_fail "증인: fault 가 실재하는가"            Route_witness_NoFault.cfg             "$M" Witness_NoFault
expect_fail "증인: 무결 통과가 실재하는가"         Route_witness_NoClean.cfg             "$M" Witness_NoClean
expect_fail "증인: 지역 비소유가 실재하는가"       Route_witness_NoLocalNonOwnership.cfg "$M" Witness_NoLocalNonOwnership
expect_fail "증인: 두 조건 동시 발화가 실재하는가" Route_witness_NoDoubleMiss.cfg        "$M" Witness_NoDoubleMiss

# 위 넷과 짝이 되는 **MUST PASS**. 좋은 모델에서 무언 드롭은 도달 불가여야 한다.
# 위 `del_loud_fault` 의 MUST FAIL 과 짝으로 읽어야 뜻이 선다 — 그 상태가
# 표현 가능하되(mutant 에서 도달) 좋은 모델에서는 도달 불가(여기서 통과)임을
# 두 run 이 함께 말한다. 이 짝이 없어서 Inv_MissAlwaysFaults 가 **어떤 형상
# 에서도 반증 불가**였다 (적대 검증이 잡은 blocking 지적).
expect_pass "무언 드롭이 좋은 모델에서 도달 불가"  Route_witness_NoSilentDrop.cfg "$M"

echo
echo "======================================================================="
if [ "$rc" -eq 0 ]; then
    echo " 전체 $runs run 이 선언대로 행동했다 — 게이트 GREEN"
else
    echo " 선언과 다르게 행동한 run 이 있다 — 게이트 RED"
fi
echo "======================================================================="
exit "$rc"
