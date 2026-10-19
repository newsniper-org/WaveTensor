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

# -noGenerateSpecTE: 반례마다 TTrace 재현 스펙을 만들지 않는다. 358 run 중
# 290 개가 의도된 MUST FAIL 이라, 켜 두면 run 마다 파일 두 개씩 쌓인다.
# run 마다 고유 metadir 를 준다. 기본값(./states)을 쓰면 같은 디렉터리에서
# 도는 다른 TLC(병렬 검증·고아 컨테이너)와 상태 풀이 섞여 run 이 pool-read
# 오류·무판정으로 끝난다 — 2026-08-23 실측: 타임아웃으로 클라이언트만 죽은
# 스윕 컨테이너가 살아남아 배터리와 겹쳤고, Payload 구간 6 run 이 오염됐다.
# 선-formal 착지 때 이미 경고된 결함형이었는데 배터리에는 반영돼 있지 않았다.
TLC_BASE="tlc -nowarning -workers 1 -cleanup -noGenerateSpecTE"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

rc=0
runs=0

expect_pass() {
    label="$1"; cfg="$2"; mod="$3"
    runs=$((runs + 1))
    printf '\n=== [%02d] %-42s (MUST PASS) ===\n' "$runs" "$label"
    md=$(mktemp -d "${TMPDIR:-/tmp}/wt-tlc.XXXXXX")
    $TLC_BASE -metadir "$md" -config "$cfg" "$mod" > "$OUT" 2>&1 || true
    rm -rf "$md"
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
    md=$(mktemp -d "${TMPDIR:-/tmp}/wt-tlc.XXXXXX")
    $TLC_BASE -metadir "$md" -config "$cfg" "$mod" > "$OUT" 2>&1 || true
    rm -rf "$md"
    if grep -q "No error has been found" "$OUT"; then
        echo "--> FAIL: 반례가 나와야 하는데 통과했다."
        echo "    가드가 불필요하거나 속성이 부실하다 — 어느 쪽인지 판정할 것."
        rc=1
    elif grep -qE "$want (is|was) violated" "$OUT"; then
        # 어미가 둘인 이유: TLC 의 위반 보고 문구가 *셋*이다 (실측).
        #   불변식     — "Error: Invariant Inv_X is violated."
        #   전이 조건   — "Error: Action property Prop_Y is violated."
        #   시간 속성   — "Error: Temporal property Prop_Z was violated."
        # 이 헬퍼는 속성 *이름*에 앵커하므로 셋을 전부 잡는다. 넓힌 것은 어미뿐이며,
        # "다른 이유로 실패한 run 을 통과로 읽지 않는다" 는 규율은 그대로다.
        # FAB-6(진행성)이 이 배터리의 첫 시간 속성이라 필요해졌다 —
        # 전이 조건은 FAB-3 부터 있었으나 어미가 `is` 라 그동안 드러나지 않았다.
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
# 구현 환류 (2026-08-23) — RTL 의 FIFO 보존이 모델보다 강했고, 모델이 따라왔다.
expect_fail "가드 삭제: no_overtake (추월)"    SharedUnit_del_no_overtake.cfg "$M" Prop_NoOvertake

expect_fail "증인: 경합이 실재하는가"       SharedUnit_witness_NoQueueing.cfg     "$M" Witness_NoQueueing
expect_fail "증인: 배압 경로가 실재하는가"  SharedUnit_witness_NoBackpressure.cfg "$M" Witness_NoBackpressure
expect_fail "증인: 추월 창이 실재하는가"        SharedUnit_witness_NoOvertakeWindow.cfg "$M" Witness_NoOvertakeWindow
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
# HIU-1 · HIU-2 · HIU-3 — 변환 저장 블록 (부록 D.5 우선순위 3번 · HIU-4 는 XlateSurface 절)
#
# 셋을 한 모델에 두는 이유는 셋이 **같은 구조 위의 성질**이기 때문이다.
# 따로 쓰면 저장 블록을 세 벌 모델링하게 되고 그 세 벌이 드리프트한다.
#
# 핵심은 §3.6.3 — flush 는 유효 비트만 지우고 **데이터는 남는다.**
# 유효 비트가 유일한 방벽이다.
# ---------------------------------------------------------------------------
M=XlateStore.tla
expect_pass "HIU-1/2/3 좋은 모델 (파티션 2 · 색인 2)"    XlateStore.cfg       "$M"
expect_pass "HIU-1/2/3 좋은 모델 (파티션 3 · 색인 2)"    XlateStore_large.cfg "$M"

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
# 임대별 마스크 키 — MaskUnit 제어면 (정본 7fa5f2e, 05-security.typ:112 ·
# e-defined.typ:333/351/E.9)
#
# 재구현 착수 시점 RTL 은 키 저장이 파티션별이 아니라 한 벌이었고, 키 기입이
# 전 파티션의 maskValid 를 떨어뜨렸다 — 아래 두 가드 삭제가 정확히 그 형태와
# 동형이다. rekey_explicit_target 은 e-defined.typ:351 7항이 명시적으로
# 기각한 "창이 재키잉 authority 를 겸함" 갈래를 모델링한다.
#
# FAULT_STATUS [12] 논스 재사용 판정 · 0xEC4 MASK_DUP_CAPTURE (v1.0 묶음 · W1,
# 2026-10-11): 변수 dup · cap · ev 를 더했다. [16] 은 결정 W1-4 대로 dup 그
# 자체(구조)라 Inv_CapIffDup 은 가드가 아니라 구조이고, 그것을 깨는 것은 짝
# 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087: CapWired = FALSE — 0xEC4 미디코드, 읽기 0) 하나다. 가드 여덟
# (dup_on_started_rekey · cap_first_event · cap_clear_whole · cap_set_beats_clear ·
# cap_bitmap_exact · cap_bitmap_domain · start_ignores_dup · complete_ignores_dup)의
# 정본 근거(같은 줄 축자 결속)와 RTL 대응 예정 이름은 모델 머리에 있다. RTL 의
# [12] 판정 쪽은 이 배터리가 측정하지 않는다(W1 RTL 의 [12] 는 후-formal engine.sby 가 탐침 축약 아래에서 잰다) — CapWired 는 워드만 바꾸므로 대비 MUST PASS 는
# 모델 자기 정합 이상을 재지 못해 두지 않았다(읽기 대조는 모델 머리).
# 대형 cfg 는 VIEW StateView(쓰기 전용 변수를 지문에서 뺀다 — 모델 「규모」 해설)를
# 건다: VIEW 없이 1회 실측 11분 34초 · 7,881,960 distinct(F4 확장 전), VIEW 를 건 판은
# 수십 초 (판정 같음 — 가드 삭제와 짝을 파티션 3 + VIEW 로 돌려 반례가 그대로 나는
# 것을 따로 확인했다). 비트맵의 겹침 항(maskValid · 논스 동치)은 파티션 3 에서만
# 보이므로 그 측정의 MUST-FAIL 대조 cap_bitmap_domain 삭제 run 도 같은 파티션 3 +
# VIEW 로 돈다 — 대형 설정이나 VIEW 를 바꾸는 편집이 그 측정을 조용히 끄지 못한다.
# 축 누출 (실측 행렬 — 새 가드 여덟 × 속성 하나씩 건 cfg): 각 삭제는 자기 목표만
# 깬다. 예외 둘 — dup_on_started_rekey 삭제는 계약 Prop_DupExact 도, cap_clear_whole
# 삭제는 Prop_RejectedFireInert 의 해제 갈래도 깬다(둘 다 같은 결함의 다른 면이고,
# 목표 속성이 먼저 보고된다). cap_set_beats_clear 와 cap_clear_whole 은 서로를 깨지 않는다.
# ---------------------------------------------------------------------------
M=Mask.tla
expect_pass "임대별 마스크 키 좋은 모델 (파티션 2)"  Mask.cfg       "$M"
expect_pass "임대별 마스크 키 좋은 모델 (파티션 3 · VIEW)"  Mask_large.cfg "$M"

expect_fail "가드 삭제: key_scoped_storage (키 전역 1벌)" \
            Mask_del_key_scoped_storage.cfg "$M" Prop_KeyScoped
expect_fail "가드 삭제: key_write_own_only (전 파티션 무효화)" \
            Mask_del_key_write_own_only.cfg "$M" Prop_MaskValidScoped
expect_fail "가드 삭제: rekey_idle_only (busy 중 수락)" \
            Mask_del_rekey_idle_only.cfg "$M" Prop_RekeyIdleOnly
expect_fail "가드 삭제: rekey_explicit_target (창이 authority 겸함)" \
            Mask_del_rekey_explicit_target.cfg "$M" Prop_RekeyTargetIsRequested

expect_fail "증인: 키 기입이 실재하는가"            Mask_witness_NoKeyWrite.cfg          "$M" Witness_NoKeyWrite
expect_fail "증인: REKEY 수락이 실재하는가"          Mask_witness_NoRekeyAccept.cfg       "$M" Witness_NoRekeyAccept
expect_fail "증인: 창-지목 어긋남이 실재하는가"      Mask_witness_NoWindowTargetDrift.cfg "$M" Witness_NoWindowTargetDrift
expect_fail "증인: busy 중 REKEY 시도가 실재하는가"  Mask_witness_NoBusyRekeyAttempt.cfg  "$M" Witness_NoBusyRekeyAttempt

expect_fail "가드 삭제: dup_on_started_rekey (busy · 거절 발화도 [12] 판정)" \
            Mask_del_dup_on_started_rekey.cfg "$M" Prop_RejectedFireInert
expect_fail "가드 삭제: cap_first_event (둘째 사건이 캡처를 덮음)" \
            Mask_del_cap_first_event.cfg "$M" Prop_CapFirstEvent
expect_fail "가드 삭제: cap_clear_whole (해제가 [7:0] · [15:8] 을 남김)" \
            Mask_del_cap_clear_whole.cfg "$M" Inv_CapClearedZero
expect_fail "가드 삭제: cap_set_beats_clear (같은 사이클 해제가 이김)" \
            Mask_del_cap_set_beats_clear.cfg "$M" Prop_CapSetBeatsClear
expect_fail "가드 삭제: cap_bitmap_exact (비트맵에 p 자신)" \
            Mask_del_cap_bitmap_exact.cfg "$M" Prop_CapBitmapExact
expect_fail "가드 삭제: cap_bitmap_domain (비트맵 = 다른 파티션 전부 · 파티션 3 · VIEW)" \
            Mask_del_cap_bitmap_domain.cfg "$M" Prop_CapBitmapExact
expect_fail "가드 삭제: start_ignores_dup ([12] 가 재키잉을 중단)" \
            Mask_del_start_ignores_dup.cfg "$M" Prop_StartGoesBusy
expect_fail "가드 삭제: complete_ignores_dup ([12] 가 완료를 막음)" \
            Mask_del_complete_ignores_dup.cfg "$M" Inv_BusyCanComplete

expect_fail "증인: [12] 세움이 실재하는가"                 Mask_witness_NoDupEvent.cfg           "$M" Witness_NoDupEvent
expect_fail "증인: 캡처 유효 중 둘째 사건이 실재하는가"     Mask_witness_NoSecondEvent.cfg        "$M" Witness_NoSecondEvent
expect_fail "증인: 해제와 발화의 같은 사이클이 실재하는가" Mask_witness_NoClearFireOverlap.cfg   "$M" Witness_NoClearFireOverlap
expect_fail "증인: 겹침 있는 busy 발화가 실재하는가"       Mask_witness_NoBusyDupAttempt.cfg     "$M" Witness_NoBusyDupAttempt
expect_fail "증인: 겹침 있는 거절 발화가 실재하는가"       Mask_witness_NoRejectedDupAttempt.cfg "$M" Witness_NoRejectedDupAttempt
expect_fail "증인: 거절 · busy 발화와 해제의 겹침이 실재하는가" Mask_witness_NoRejectedClearOverlap.cfg "$M" Witness_NoRejectedClearOverlap
expect_fail "증인: 내부 해제선의 캡처 해제가 실재하는가"   Mask_witness_NoIoClearHeld.cfg        "$M" Witness_NoIoClearHeld
expect_fail "증인: p 자신이 유효한 채 세움이 실재하는가"   Mask_witness_NoSelfValidDup.cfg       "$M" Witness_NoSelfValidDup
expect_fail "증인: 비트맵 다중 비트가 실재하는가 (파티션 3)" Mask_witness_NoMultiBitmap.cfg      "$M" Witness_NoMultiBitmap
expect_fail "증인: 같은 p 재래치의 낡은 비트맵이 실재하는가 (파티션 3)" Mask_witness_NoStaleRelatch.cfg "$M" Witness_NoStaleRelatch

expect_fail "짝: 오늘의 RTL(W1 전 · HEAD 3b80087) — 0xEC4 미디코드 → [16] ⇔ [12] 깨짐" \
            Mask_pair_today.cfg "$M" Inv_CapIffDup

# ---------------------------------------------------------------------------
# CAP_STATUS · CAP_CLEAR — 능력 부재 관측 워드 (파도 B, 정본 1126a38:
# e-defined.typ:500-503 「능력 부재도 관측이 sticky 여야 재시도 주체가 놓치지 않는다」 ·
# e-defined.typ:566-616 「넷은 서로 접지 않는다」 · 01-isa-asm.typ:1540-1563 「관측은 sticky 다」)
#
# 재구현 착수 시점 RTL 은 이 워드를 두 축으로 들고 CAP_CLEAR 예약을 [31:2] 로
# 유도했다 — 정본은 [31:4] 라 [2]·[3] 의 적법한 W1C 가 거절 + loud 된다
# (clear_atomic 의 정의역이 다르다), 그리고 [2] 는 판정 회로만 있고 이 워드에
# 닿지 않는다. Witness_NoClear 는 축 넷 *전부*의 해제 도달성을 요구한다 —
# RTL 마스크 폭의 대조 자체는 후-formal capword.sby 의 a_rsvbad_def 몫이다.
# set_beats_clear 는 StickyFault 규약(해제와 발화가 같은 사이클이면 발화가
# 이긴다)을 이 워드에 승계한 것이다.
# ---------------------------------------------------------------------------
M=CapWord.tla
expect_pass "CAP_STATUS 워드 좋은 모델 (축 4)"  CapWord.cfg "$M"

expect_fail "가드 삭제: axis_isolated (사건이 다른 축도 세움)" \
            CapWord_del_axis_isolated.cfg "$M" Prop_AxisIsolation
expect_fail "가드 삭제: sticky_until_clear (저절로 내려감)" \
            CapWord_del_sticky_until_clear.cfg "$M" Prop_StickyUntilClear
expect_fail "가드 삭제: clear_atomic (예약 위반 부분 수락)" \
            CapWord_del_clear_atomic.cfg "$M" Prop_ClearAtomic
expect_fail "가드 삭제: set_beats_clear (해제가 이김)" \
            CapWord_del_set_beats_clear.cfg "$M" Prop_SetBeatsClear

expect_fail "증인: 사건이 실재하는가"                CapWord_witness_NoEvent.cfg         "$M" Witness_NoEvent
expect_fail "증인: 축 넷 전부의 해제가 실재하는가"   CapWord_witness_NoClear.cfg         "$M" Witness_NoClear
expect_fail "증인: 예약 위반 거절이 실재하는가"      CapWord_witness_NoRejectedWrite.cfg "$M" Witness_NoRejectedWrite
expect_fail "증인: 같은 축 사건+해제 겹침이 실재하는가" CapWord_witness_NoSimultaneous.cfg "$M" Witness_NoSimultaneous

# ---------------------------------------------------------------------------
# MaskUnit 재키잉 엔진 창의 시간 축 — FINAL 엣지 동시 기입 모서리 (파도 D,
# 2026-09-22: e-defined.typ:518 「재키잉 중 입력 기입」 = FAULT_STATUS [13] ·
# e-defined.typ:347 「`[8]` 엔진 busy · `[9]` 재키잉 수락 가능」 ·
# 05-security.typ:384 「소실도 loud 여야 한다」)
#
# Mask.tla(위)은 「어느 파티션」, 이 모델은 「언제」 — E.9 4항의 두 면이다.
# 파도 D 이전 판(1666c7a)의 RTL 은 활성 파티션 기입이 정확히 FINAL 사이클
# (busy=1 · ready=0)에 실리면 compDirty 레지스터가 다음 사이클에야 서서
# dirtyAtFinal 이 0 을 읽었다 — 유효는 텍스트 순서로 떨어지는데 fault 가
# 침묵했다(관측 결손, 안전 결손 아님). dirty_loud 삭제가 그 판과 동형이고
# Prop_MixLoud 가 반례를 낸다. 파도 D 의 RTL 은 같은 사이클 항을 직접 본다.
# busy 는 추상 한 상태다 — 42사이클·라운드·값은 재지 않는다 (모델 머리말).
# ---------------------------------------------------------------------------
M=MaskEngine.tla
expect_pass "엔진 창 시간 축 좋은 모델 (파티션 2)"  MaskEngine.cfg       "$M"
expect_pass "엔진 창 시간 축 좋은 모델 (파티션 3)"  MaskEngine_large.cfg "$M"

expect_fail "가드 삭제: dirty_scoped (타 파티션 기입도 오염)" \
            MaskEngine_del_dirty_scoped.cfg "$M" Prop_DirtyScoped
expect_fail "가드 삭제: dirty_no_validate (오염 완료가 유효화)" \
            MaskEngine_del_dirty_no_validate.cfg "$M" Prop_DirtyNoValidate
expect_fail "가드 삭제: dirty_loud (FINAL 엣지 기입에 fault 침묵)" \
            MaskEngine_del_dirty_loud.cfg "$M" Prop_MixLoud
expect_fail "가드 삭제: invalidate_beats_validate (유효화가 이김)" \
            MaskEngine_del_invalidate_beats_validate.cfg "$M" Prop_InvalidateBeatsValidate

expect_fail "증인: 완료+target 기입 겹침이 실재하는가"   MaskEngine_witness_NoOverlap.cfg        "$M" Witness_NoOverlap
expect_fail "증인: 오염 완료가 실재하는가"               MaskEngine_witness_NoDirtyComplete.cfg  "$M" Witness_NoDirtyComplete
expect_fail "증인: 깨끗한 완료의 유효화가 실재하는가"     MaskEngine_witness_NoCleanComplete.cfg  "$M" Witness_NoCleanComplete
expect_fail "증인: busy 중 타 파티션 기입이 실재하는가"   MaskEngine_witness_NoOtherWriteBusy.cfg "$M" Witness_NoOtherWriteBusy

# ---------------------------------------------------------------------------
# 변환 저장소의 MMIO 문 — 0xC00 형상 비노출 항목 표면(기저마다 VPN · FRAME · COMMIT ·
# VPN_HI · 예약-엄격 28 워드) · 0xE00 XLATE_FLUSH · 0xE10 XLATE_MISS_CLEAR · RO 세 워드
# (3.10 v1.0 묶음 RTL 파도 W3 재작성, 2026-10-13:
# e-defined.typ:297 「호스트는 (VPN, 프레임, 권한)만 기입하고 장치 안 어느 칸에 둘지는 *장치가 정한다*」 ·
# e-defined.typ:310 「같은 (파티션, VPN) 에 두 항목이 동시에 적중하지 않는다 — 뒤 커밋이 앞 항목을 대체한다」 ·
# e-defined.typ:308 「정지 중에는 효과가 없고, 수락되면 커밋되며, 드롭하지 않는다」)
#
# 앞판(파도 3 · 4 — 호스트가 색인을 고르는 LO/HI 직접 배열, 50 run)을 대체한다. 표는
# [Parts -> [Slots -> [vpn, fr, v]]] 이고 COMMIT 의 칸은 장치가 비결정으로 고른다 — 같은
# 파티션에 같은 VPN 의 유효 칸이 있으면 그 칸(대체 탐색). HIU-4 의 진짜 증명이
# Inv_AtMostOneValidPerVpn(XlateStore.tla 의 항진 Inv_AtMostOneCandidate 를 대체 — DP-12)이다 —
# 단 칸 1 cfg(작은 · 대형 · 상한 아래)에서는 공허하고(한 원소 집합의 부분집합), 반증력은 칸 2
# cfg 둘 · commit_replaces_vpn 삭제 · _pair_host_index 가 든다.
# HIU-2 의 V=0 축이 Prop_V0Misses, 하류 정지의 처분 · 풀림이 Prop_StallDataBlind(데이터 사유는
# 정지를 건너뛰지 않는다 ← RefuseDomain full) · Prop_AddrRejectNoWait(주소 · 상태 사유는 기다리지
# 않는다 ← RefuseDomain kind) · Prop_HoldInert · Prop_StallEnds 다. 가드 29 = 앞판 이름 유지 13 · 개명 6(LO/HI 전용 — DP-14) · 신설 10.
# 가드 삭제 cfg 는 가드 속성 전부(28 · stall_independent 는 LiveSpec 의 Prop_StallEnds)를
# 건다 — 지운 가드의 자기 속성이 첫 위반으로 난다. commit_replaces_vpn 삭제 cfg 는
# 귀결 Prop_V0Misses 를 빼고 짝 _pair_v0_replace 가 그 축을 따로 잰다.
# cfg 분할(K2): 작은 cfg(칸 1 · VPN 1)는 VIEW 없이, 대형(칸 1 = 직접 사상 동형 · VPN 2) ·
# 칸 2 전용 둘(파티션 1 · VPN 3 = 축출 깊이 · 파티션 2 · VPN 1 = 대체 탐색의 파티션 선택) ·
# 상한 아래는 VIEW StateView(보조 넷 acc · why · loud ·
# ev 를 접는다 — 모델 StateView 주석). 대안 상수는 대형에서 끈다. 증인은 VIEW 없이.
# 짝 _pair_host_index(형상 노출 — 호스트 칸 지목)는 W3 전 RTL(aa91e86)의 기계가 아니다 —
# 그 RTL 은 저장 키가 태그 ‖ 색인 = VPN 이라 같은 VPN 이 두 색인에 앉지 못한다(모델 머리
# 「짝 · 대안」). W3 전 RTL 이 새 정본에 어기는 것은 예약-엄격 자리 수락(rsvw_rejected 삭제
# run) · VPN_HI · COMMIT 예약 수락 등 문의 처분이다.
# 규모 실측(2026-10-13 · 컨테이너 · -workers 1 · 같은 시각에 다른 TLC 둘):
#   작은 cfg (VIEW 없음)      4,971,953 generated · 169,160 distinct · 6분 52초 — PASS
#   대형 (칸 1 · VPN 2 · VIEW) 2,778,242 generated · 243,949 distinct · 3분 35초 — PASS
#   칸 2 전용 (1 · 2 · 3 · VIEW) 1,098,322 generated · 148,378 distinct · 1분 12초 — PASS
#   칸 2 · 파티션 2 (2 · 2 · 1 · VIEW) 6,566,288 generated · 634,025 distinct · 약 10분 — PASS
#   상한 아래 (VIEW)          280,772 generated · 20,389 distinct · 20초 — PASS
#   진행 (LiveSpec)           4,971,953 generated · 169,160 distinct · 8분 35초 — PASS
#   절 전체 77 run 24분 30초 (수정판 재실측 · 같은 시각 다른 TLC 하나 — 앞판 74 run 20분 14초). 비상주: 파티션 2 · 칸 2 · VPN 2 판은
#   50분에 4,387,451 distinct · 큐 2,144,360 으로 끝나지 않아 중단했다 — 그래서 칸 2 전용 cfg 는
#   파티션 1 · VPN 3 이고, 칸 2 의 파티션 간 몫은 파티션 2 · 칸 2 · VPN 1 cfg 가 든다. 작은 cfg 를 VIEW 로 돌리면
#   20,389 distinct · 14초 — VIEW 가 보조 넷만 접는다는 실측 대조다(같은 속성 · 같은 판정).
# 분리 검사(비상주 실측 2026-10-13 — 가드마다 지운 판에 자기 속성을 뺀 가드 · 고정 속성 전부,
# 위반을 하나씩 빼며 PASS 까지): 28 행 전부 PASS 에 닿는다 (자기 속성의 첫 위반은 위 삭제 run).
#   다른 가드의 속성까지 깨는 삭제 11 행(귀결 — 같은 RTL 항을 나누거나 정본 유령과 어긋난다):
#   frame_stages_only · commit_whole → TableByDoor · commit_needs_vpn → FlushEndsStaging ·
#   commit_needs_frame → VpnDropsFrame · frame_pair_check → FlushEndsStaging · CommitNeedsFrame ·
#   CommitWhole · CommitCommits · VpnDropsFrame · vpnhi_strict → CommitCommits ·
#   commit_replaces_vpn → V0Misses(짝 v0_replace) · flush_part_exists · flush_rsv_strict → CommitCommits
#   (잘린 · 예약 flush 가 장치 스테이징을 내린다) · flush_drops_staging → CommitNeedsFrame ·
#   VpnDropsFrame · ent_part_exists → 여덟(별칭 래치). 나머지 17 행은 고정 속성 귀결만이거나 없음.
#   stall_independent 행은 재지 않았다 — 삭제가 Drain 을 막기만 해 안전 속성의 도달 집합이 줄 뿐이다.
#   행렬 전문은 W3 착지 기록에 싣는다(비상주). 고정 속성 셋(AddrRejectNoWait · HoldInert ·
#   RejectInert)과 StallOnlyByEntry 의 키 항은 독립 검증 뒤 더했다 — 행렬은 그 전 측정이다.
#   변이 실측(비상주 · 2026-10-13): 주소 · 상태 사유 정지(전부 · 기저 항만) → AddrRejectNoWait ·
#   태그 탐색이 다른 파티션을 읽음 → V0Misses(칸 2 · 파티션 2 cfg 만) · 다른 키의 V=1 이 미적중
#   정지를 풂(다른 파티션 · 같은 파티션 다른 VPN — 후자는 대형 cfg) → StallOnlyByEntry · 거절이
#   하류 점유를 세움 · 거절이 sticky 를 내림 → RejectInert · 잡는 스텝이 다른 하류를 비움 → HoldInert.
# ---------------------------------------------------------------------------
M=XlateSurface.tla
expect_pass "MMIO 문 좋은 모델 — 작은 (파티션 2 · 칸 1 · VPN 1 · VIEW 없음)"  XlateSurface.cfg        "$M"
expect_pass "MMIO 문 좋은 모델 — 대형 (칸 1 = 직접 사상 동형 · VPN 2)"       XlateSurface_large.cfg  "$M"
expect_pass "MMIO 문 좋은 모델 — 칸 2 전용 (파티션 1 · 칸 2 · VPN 3 — 축출 실재)"  XlateSurface_slots2.cfg "$M"
expect_pass "MMIO 문 좋은 모델 — 칸 2 · 파티션 2 (VPN 1 — 대체 탐색의 파티션 선택)"  XlateSurface_slots2_parts2.cfg "$M"
expect_pass "MMIO 문 좋은 모델 — 상한 아래 형상 (형상 밖 기저 1)"           XlateSurface_phantom.cfg "$M"

expect_fail "가드 삭제: frame_stages_only (FRAME 이 산 칸을 곧장 덮음)" \
            XlateSurface_del_frame_stages_only.cfg "$M" Prop_StagesOnly
expect_fail "가드 삭제: commit_fires (적법한 COMMIT 흡수)" \
            XlateSurface_del_commit_fires.cfg "$M" Prop_CommitCommits
expect_fail "가드 삭제: commit_base_match (다른 파티션에 커밋)" \
            XlateSurface_del_commit_base_match.cfg "$M" Prop_BaseMismatchRejected
expect_fail "가드 삭제: commit_needs_vpn (쓰이지 않은 VPN 커밋)" \
            XlateSurface_del_commit_needs_vpn.cfg "$M" Prop_NoVpnRejected
expect_fail "가드 삭제: commit_whole (V 먼저 · VPN · 프레임 다음 에지)" \
            XlateSurface_del_commit_whole.cfg "$M" Prop_CommitWhole
expect_fail "가드 삭제: commit_v_carried (V=0 이 유효로 커밋 — HIU-2 V=0 축)" \
            XlateSurface_del_commit_v_carried.cfg "$M" Prop_V0Misses
expect_fail "가드 삭제: vpn_drops_frame (묵은 프레임이 새 VPN 에 묶임)" \
            XlateSurface_del_vpn_drops_frame.cfg "$M" Prop_VpnDropsFrame
expect_fail "가드 삭제: commit_needs_frame (FRAME 없는 V=1 커밋)" \
            XlateSurface_del_commit_needs_frame.cfg "$M" Prop_CommitNeedsFrame
expect_fail "가드 삭제: frame_pair_check (짝 불일치 FRAME 수락)" \
            XlateSurface_del_frame_pair_check.cfg "$M" Prop_FramePairRejected
expect_fail "가드 삭제: vpnhi_strict (비0 VPN_HI 수락)" \
            XlateSurface_del_vpnhi_strict.cfg "$M" Prop_VpnHiStrict
expect_fail "가드 삭제: rsvw_rejected (예약-엄격 워드 쓰기 흡수)" \
            XlateSurface_del_rsvw_rejected.cfg "$M" Prop_RsvwRejected
expect_fail "가드 삭제: commit_rsv_strict (COMMIT [27:0] 비0 커밋)" \
            XlateSurface_del_commit_rsv_strict.cfg "$M" Prop_CommitRsvRejected
expect_fail "가드 삭제: commit_replaces_vpn (같은 VPN 이 두 칸에 유효 — HIU-4)" \
            XlateSurface_del_commit_replaces_vpn.cfg "$M" Inv_AtMostOneValidPerVpn
expect_fail "가드 삭제: evict_in_partition (다른 파티션 칸 축출)" \
            XlateSurface_del_evict_in_partition.cfg "$M" Prop_CommitScoped
expect_fail "가드 삭제: evict_on_commit_only (자발 축출)" \
            XlateSurface_del_evict_on_commit_only.cfg "$M" Prop_TableByDoor
expect_fail "가드 삭제: stall_independent (미적중 정지가 채움 커밋을 막음 → 정지 영구)" \
            XlateSurface_del_stall_independent.cfg "$M" Prop_StallEnds
expect_fail "가드 삭제: flush_fires (적법한 flush 흡수)" \
            XlateSurface_del_flush_fires.cfg "$M" Prop_FlushClears
expect_fail "가드 삭제: flush_scoped (전역 발화)" \
            XlateSurface_del_flush_scoped.cfg "$M" Prop_FlushScoped
expect_fail "가드 삭제: flush_valid_only (데이터까지 지움)" \
            XlateSurface_del_flush_valid_only.cfg "$M" Prop_FlushKeepsData
expect_fail "가드 삭제: flush_part_exists (없는 값이 잘려 실재 파티션 flush)" \
            XlateSurface_del_flush_part_exists.cfg "$M" Prop_PhantomRejected
expect_fail "가드 삭제: flush_rsv_strict (예약 위반 flush 실행)" \
            XlateSurface_del_flush_rsv_strict.cfg "$M" Prop_RsvRejected
expect_fail "가드 삭제: reject_loud (조용한 거절)" \
            XlateSurface_del_reject_loud.cfg "$M" Prop_RejectLoud
expect_fail "가드 삭제: mclr_fires (적법한 0xE10 해제 흡수)" \
            XlateSurface_del_mclr_fires.cfg "$M" Prop_MclrClears
expect_fail "가드 삭제: mclr_needs_one ([0]=0 기입도 해제)" \
            XlateSurface_del_mclr_needs_one.cfg "$M" Prop_MclrZeroKeeps
expect_fail "가드 삭제: mclr_rsv_strict (예약 위반 해제 실행)" \
            XlateSurface_del_mclr_rsv_strict.cfg "$M" Prop_MclrRsvRejected
expect_fail "가드 삭제: mclr_keeps_stall (해제가 미적중 정지를 풂)" \
            XlateSurface_del_mclr_keeps_stall.cfg "$M" Prop_MclrKeepsStall
expect_fail "가드 삭제: ro_rejected (RO 오프셋 쓰기 흡수)" \
            XlateSurface_del_ro_rejected.cfg "$M" Prop_RoRejected
expect_fail "가드 삭제: flush_drops_staging (flush 를 건넌 VPN · FRAME 재사용)" \
            XlateSurface_del_flush_drops_staging.cfg "$M" Prop_FlushEndsStaging
expect_fail "가드 삭제: ent_part_exists (없는 파티션 기저 수락)" \
            XlateSurface_del_ent_part_exists.cfg "$M" Prop_EntPhantomRejected

expect_fail "증인: 산 칸 위 다른 프레임의 FRAME 이 실재하는가"   XlateSurface_witness_NoFrameOverLive.cfg    "$M" Witness_NoFrameOverLive
expect_fail "증인: 산 VPN 의 프레임 대체 커밋이 실재하는가 (칸 2 전용 상수)" XlateSurface_witness_NoFrameChange.cfg   "$M" Witness_NoFrameChange
expect_fail "증인: 래치와 다른 기저의 COMMIT 이 실재하는가"     XlateSurface_witness_NoBaseMismatch.cfg     "$M" Witness_NoBaseMismatch
expect_fail "증인: VPN 없는 COMMIT 이 실재하는가"               XlateSurface_witness_NoVpnless.cfg          "$M" Witness_NoVpnless
expect_fail "증인: V=0 단일 항목 무효화가 실재하는가"           XlateSurface_witness_NoKill.cfg             "$M" Witness_NoKill
expect_fail "증인: FRAME 없는 V=1 COMMIT 이 실재하는가"          XlateSurface_witness_NoFramelessV1.cfg      "$M" Witness_NoFramelessV1
expect_fail "증인: 묵은 프레임 위 V=1 COMMIT 이 실재하는가"      XlateSurface_witness_NoStaleFrameCommit.cfg "$M" Witness_NoStaleFrameCommit
expect_fail "증인: 짝 불일치 FRAME · VPN_HI 가 실재하는가"       XlateSurface_witness_NoPairMismatch.cfg     "$M" Witness_NoPairMismatch
expect_fail "증인: 비0 VPN_HI 가 실재하는가"                     XlateSurface_witness_NoVpnHiRsv.cfg         "$M" Witness_NoVpnHiRsv
expect_fail "증인: 예약-엄격 워드 쓰기가 실재하는가"             XlateSurface_witness_NoRsvw.cfg             "$M" Witness_NoRsvw
expect_fail "증인: COMMIT [27:0] 비0 이 실재하는가"              XlateSurface_witness_NoCommitRsv.cfg        "$M" Witness_NoCommitRsv
expect_fail "증인: 다른 VPN 의 산 칸 축출이 실재하는가 (칸 2 전용 상수)" XlateSurface_witness_NoEvict.cfg            "$M" Witness_NoEvict
expect_fail "증인: 산 항목이 실재하는가 (자발 축출의 전건)"      XlateSurface_witness_NoResident.cfg         "$M" Witness_NoResident
expect_fail "증인: 하류 정지와 미적중 정지가 겹치는가"           XlateSurface_witness_NoStallInMiss.cfg      "$M" Witness_NoStallInMiss
expect_fail "증인: 하류 거부로 버스 정지가 실재하는가"           XlateSurface_witness_NoStall.cfg            "$M" Witness_NoStall
expect_fail "증인: 정지 뒤 수락 사이클의 데이터 사유 거절이 실재하는가" XlateSurface_witness_NoDataHeld.cfg  "$M" Witness_NoDataHeld
expect_fail "증인: 산 파티션의 flush 가 실재하는가"              XlateSurface_witness_NoFlushLive.cfg        "$M" Witness_NoFlushLive
expect_fail "증인: 타 파티션이 산 동안의 flush 가 실재하는가"    XlateSurface_witness_NoFlushOther.cfg       "$M" Witness_NoFlushOther
expect_fail "증인: 없는 파티션 값 flush 가 실재하는가"           XlateSurface_witness_NoPhantom.cfg          "$M" Witness_NoPhantom
expect_fail "증인: 예약 위반 flush 가 실재하는가"                XlateSurface_witness_NoRsv.cfg              "$M" Witness_NoRsv
expect_fail "증인: 정지가 풀린 뒤 선 sticky 의 해제가 실재하는가" XlateSurface_witness_NoClearLive.cfg      "$M" Witness_NoClearLive
expect_fail "증인: 선 sticky 위 [0]=0 기입이 실재하는가"         XlateSurface_witness_NoZeroLive.cfg         "$M" Witness_NoZeroLive
expect_fail "증인: 예약 위반 해제가 실재하는가"                  XlateSurface_witness_NoMclrRsv.cfg          "$M" Witness_NoMclrRsv
expect_fail "증인: 미적중 정지 중의 해제가 실재하는가"           XlateSurface_witness_NoClearInStall.cfg     "$M" Witness_NoClearInStall
expect_fail "증인: RO 오프셋 쓰기가 실재하는가"                  XlateSurface_witness_NoRo.cfg               "$M" Witness_NoRo
expect_fail "증인: 스테이징이 래치한 파티션의 flush 가 실재하는가" XlateSurface_witness_NoFlushStaged.cfg    "$M" Witness_NoFlushStaged
expect_fail "증인: flush 를 건넌 스테이징 위 FRAME · VPN_HI · COMMIT 이 실재하는가" \
            XlateSurface_witness_NoStaleUse.cfg "$M" Witness_NoStaleUse
expect_fail "증인: 없는 파티션 기저의 기입이 실재하는가"         XlateSurface_witness_NoEntPhantom.cfg       "$M" Witness_NoEntPhantom

expect_fail "짝: 형상 노출 — 호스트 칸 지목(HostIndex) → HIU-4 반례 (칸 2)" \
            XlateSurface_pair_host_index.cfg "$M" Inv_AtMostOneValidPerVpn
expect_fail "짝: 대체 탐색 없는 V=0 → 산 같은 VPN 이 남음 (HIU-2 V=0 축 · 칸 2)" \
            XlateSurface_pair_v0_replace.cfg "$M" Prop_V0Misses
expect_fail "대안: 정지 판정이 데이터 필드를 봄 (RefuseDomain = full)" \
            XlateSurface_pair_refuse_full.cfg "$M" Prop_StallDataBlind
expect_fail "대안: 정지 판정이 종류만 봄 — 주소 · 상태 사유도 기다린다 (RefuseDomain = kind)" \
            XlateSurface_pair_refuse_kind.cfg "$M" Prop_AddrRejectNoWait
expect_fail "대안: 하류 거부 → 거절 + loud (옳은 드라이버에 fault)" \
            XlateSurface_pair_refusal_reject.cfg "$M" Prop_RejectOnlyMalformed
expect_fail "대안: 하류 거부 → 조용한 흡수" \
            XlateSurface_pair_refusal_drop.cfg "$M" Prop_CommitCommits
expect_fail "대안: 스테이징 수명 → 커밋 소진 (flush 를 건넌 VPN · FRAME 을 못 막는다)" \
            XlateSurface_pair_stg_consume.cfg "$M" Prop_FlushEndsStaging
expect_fail "대안: 스테이징 수명 → 커밋 소진 (커밋 뒤 같은 스테이징의 재커밋이 거절된다)" \
            XlateSurface_pair_stg_consume_commit.cfg "$M" Prop_CommitCommits
expect_fail "대안: 스테이징 수명 → flush 가 모든 스테이징을 비움 (전역)" \
            XlateSurface_pair_stg_global.cfg "$M" Prop_FlushStagingScoped
expect_fail "짝: 없는 파티션 기저를 잘라 커밋 (격리 위반 — 별칭)" \
            XlateSurface_pair_ent_alias.cfg "$M" Prop_EntNoAlias
expect_fail "짝: 파도 3 이전 RTL — XLATE_FLUSH 가 사라진다 (T1)" \
            XlateSurface_pair_today_flush.cfg "$M" Prop_FlushClears
expect_fail "짝: 파도 3 이전 RTL — 항목 기입이 사라진다" \
            XlateSurface_pair_today_entry.cfg "$M" Prop_CommitCommits
expect_pass "진행: 하류 정지는 호스트 조치 없이 풀린다"   XlateSurface_live.cfg "$M"
expect_fail "짝: 채움 슬롯 Drain 공정성 없음 → 정지 영구" \
            XlateSurface_pair_live_nodrain.cfg "$M" Prop_StallEnds
# 판정 4 (모델 머리 고정 속성) — 정지 중 해제의 유실을 붙잡는 run. set(정지 레벨)이
# 해제를 이기는 RTL 규약의 귀결이고, 정본이 그것을 문면으로 정했다 —
# e-defined.typ:329 「정지 *중에* 쓴 해제는 유실된다」.
expect_fail "발견: 정지 중 0xE10 해제는 sticky 를 내리지 못한다" \
            XlateSurface_pair_clear_in_stall.cfg "$M" Prop_ClearAlwaysLowers

# ---------------------------------------------------------------------------
# 재조립 문맥 소거의 호스트 쪽 문 — 0xF40 구역(ABORT_TAG0/1/2 스테이징 ·
# ABORT_FIRE 발화 · RO 세 워드)과 무장 규율 (파도 4, 2026-09-26:
# e-defined.typ:475 「처분은 셋 다 같다: 거절 + loud fault」 ·
# e-defined.typ:1818 「*워드의 적법성 검사는 무장보다 앞선다*」 ·
# e-defined.typ:1808 「ABORT_FIRE 기입은 소거의 성립 여부와 무관하게 세 무장」)
#
# AbortStaging(결정 A, 2026-08-25)은 선-formal 없이 착지했다 — 6.3 의 1단을
# 건너뛴 모듈이었고, 이 모델이 그 1단이다. Payload.tla 는 소거를 의미론으로
# 추상하고 32b 버스 세 워드의 문은 어느 모델의 상태도 아니었다.
#
# 짝 「D2 이전의 RTL」 둘: TAG1 [27:16] 무검사(poison_trace_zero · epoch_word_rsv_strict
# 삭제) — 거절 사유인 기입이 수락되고(Prop_PoisonTraceRejected), 발화가 trace 를
# 든 태그를 싣는다(Prop_FiredKeyClean — E.12 6항의 호스트 가시 귀결).
# sub-word(하위 두 비트 ≠ 0) 처분은 가드가 아니라 상수 Subword 다 — 판정
# T2 (a) 의 거절 + [6] 은 파도 4 페이지 통합이 착지했고(가드는 MmioPage.unaligned_rejected), 그 전의 RTL(조용한 흡수)이 짝
# 「D2 뒤 · T2 앞」 이다. 대비 MUST PASS 가 그 판에서 가드 속성 열셋이 전부
# 통과함을 보인다 — 남은 간극이 sub-word 하나라는 기계 기록이다.
# 가드 삭제 cfg 는 가드 속성 열셋을 전부 건다 — 지운 가드의 자기 속성이 첫 위반으로 난다
# (TLC 는 첫 위반 하나만 보고한다). 「자기 속성*만*」 은 분리 검사가 잰다 — 비상주,
# 2026-09-26 실측 13/13 (rtl/formal/tla/README.md AbortSurface 절).
# ---------------------------------------------------------------------------
M=AbortSurface.tla
expect_pass "소거 문 좋은 모델 (값 2 · sub-word 거절)"  AbortSurface.cfg       "$M"
expect_pass "소거 문 좋은 모델 (값 3 · 규모)"          AbortSurface_large.cfg "$M"

expect_fail "가드 삭제: poison_trace_zero (poison·trace TAG1 수락)" \
            AbortSurface_del_poison_trace_zero.cfg "$M" Prop_PoisonTraceRejected
expect_fail "가드 삭제: epoch_word_rsv_strict (예약 [25:16] TAG1 수락)" \
            AbortSurface_del_epoch_word_rsv_strict.cfg "$M" Prop_EpochWordRsvRejected
expect_fail "가드 삭제: shape_word_rsv_strict (예약 [31:16] TAG2 수락)" \
            AbortSurface_del_shape_word_rsv_strict.cfg "$M" Prop_ShapeWordRsvRejected
expect_fail "가드 삭제: fire_rsv_strict (예약 [31:1] 발화 수락)" \
            AbortSurface_del_fire_rsv_strict.cfg "$M" Prop_FireRsvRejected
expect_fail "가드 삭제: ro_rejected (RO 세 워드 쓰기 흡수)" \
            AbortSurface_del_ro_rejected.cfg "$M" Prop_RoRejected
expect_fail "가드 삭제: legal_first (거절했는데 무장·발화)" \
            AbortSurface_del_legal_first.cfg "$M" Prop_RejectedNoEffect
expect_fail "가드 삭제: reject_loud (조용한 거절)" \
            AbortSurface_del_reject_loud.cfg "$M" Prop_RejectLoud
expect_fail "가드 삭제: arm_on_accept (수락 기입이 무장 안 세움)" \
            AbortSurface_del_arm_on_accept.cfg "$M" Prop_ArmOnAccept
expect_fail "가드 삭제: arm_own_word (이웃 워드 무장)" \
            AbortSurface_del_arm_own_word.cfg "$M" Prop_ArmOwnWord
expect_fail "가드 삭제: stage_writes_value (재기입이 옛 값 남김)" \
            AbortSurface_del_stage_writes_value.cfg "$M" Prop_StageLatest
expect_fail "가드 삭제: fire_needs_armed (부분 기입 발화)" \
            AbortSurface_del_fire_needs_armed.cfg "$M" Prop_FireNeedsArmed
expect_fail "가드 삭제: fire_needs_one ([0]=0 기입이 발화)" \
            AbortSurface_del_fire_needs_one.cfg "$M" Prop_FireNeedsOne
expect_fail "가드 삭제: fire_drains_arm (성립한 소거만 소진)" \
            AbortSurface_del_fire_drains_arm.cfg "$M" Prop_FireDrains

expect_fail "증인: 소거 발화가 실재하는가"                 AbortSurface_witness_NoFire.cfg          "$M" Witness_NoFire
expect_fail "증인: 무장 미완의 적법 발화가 실재하는가"     AbortSurface_witness_NoUnderarmedFire.cfg "$M" Witness_NoUnderarmedFire
expect_fail "증인: 무장 완비 위 [0]=0 발화 기입이 실재하는가" AbortSurface_witness_NoZeroFire.cfg    "$M" Witness_NoZeroFire
expect_fail "증인: 무장 선 워드의 다른 값 재기입이 실재하는가" AbortSurface_witness_NoRewrite.cfg   "$M" Witness_NoRewrite
expect_fail "증인: 무장 중 거절 사유 발화 기입이 실재하는가" AbortSurface_witness_NoRejectedDrain.cfg "$M" Witness_NoRejectedDrain
expect_fail "증인: poison·trace TAG1 거절이 실재하는가"   AbortSurface_witness_NoPoisonTraceReject.cfg "$M" Witness_NoPoisonTraceReject
expect_fail "증인: 예약 TAG1 거절이 실재하는가"           AbortSurface_witness_NoEpochWordRsvReject.cfg "$M" Witness_NoEpochWordRsvReject
expect_fail "증인: 예약 TAG2 거절이 실재하는가"           AbortSurface_witness_NoShapeWordRsvReject.cfg "$M" Witness_NoShapeWordRsvReject
expect_fail "증인: 예약 발화 거절이 실재하는가"           AbortSurface_witness_NoFireRsvReject.cfg "$M" Witness_NoFireRsvReject
expect_fail "증인: RO 세 워드 쓰기 거절이 실재하는가"     AbortSurface_witness_NoRoReject.cfg      "$M" Witness_NoRoReject
expect_fail "증인: sub-word 쓰기 거절이 실재하는가"       AbortSurface_witness_NoSubReject.cfg     "$M" Witness_NoSubReject

expect_fail "짝: D2 이전의 RTL — TAG1 [27:16] 무검사" \
            AbortSurface_pair_today_tag1.cfg "$M" Prop_PoisonTraceRejected
expect_fail "짝: D2 이전의 RTL — 소거가 trace 든 태그를 싣는다" \
            AbortSurface_pair_today_tag1_key.cfg "$M" Prop_FiredKeyClean
expect_fail "짝: D2 뒤 · T2 앞의 RTL — sub-word 조용한 흡수" \
            AbortSurface_pair_today_subword.cfg "$M" Prop_MalformedRejected
expect_pass "대비: D2 뒤 · T2 앞의 RTL — 가드 속성 전부 통과"  AbortSurface_today.cfg "$M"

# ---------------------------------------------------------------------------
# 4 KiB 구성 페이지의 처분 — 포트 수락·응답 · 방향 · 정렬 · 예약 오프셋 ·
# 물려받은 구역 · 소비 회로가 없는 워드 (파도 4, 2026-09-26:
# 03-hiu.typ:1134 「읽기도 같다 — 수락(ready ∧ 스트로브)되지 않은 접근은 효과도 응답도 없다」 ·
# 03-hiu.typ:874 「비정렬 *읽기*는 0 · fault 없음이다」 ·
# e-defined.typ:743 「*소비 회로가 없는 RW 워드 — 쓰기는 거절, 읽기는 0.*」)
#
# MMIO 워드 표면의 처분은 어느 모델의 상태도 아니었다 — 조립 후-formal 이 VERIFIES
# 로만 잰 자리이고, 파도 4 의 판정 다섯(D1 · T1-i · T1-ii 쓰기 · T2 · T3)이 여기에 새
# 가드를 만든다. 짝 「D1 이전의 조립」 둘: 주소 기준 ready 아래 잡힌 읽기의 응답과
# 수락 전 FP_BIND 예약 거절. 짝 「판정 전의 표면」 하나와 판정의 기각 갈래 넷
# (레지스터만 실물화 둘 · 물려받은 구간 관대 · 비정렬 관대) · ready 만 고친 판.
# 대비 MUST PASS — 주소 기준 ready 에서도 가드 둘이 살아 있으면 안전하다 (ready
# 모양의 선택은 안전이 아니라 측정 가능성의 문제다 — 모델 머리).
# 한계는 모델 머리가 적는다: 고정 속성의 예외 집합(SpecReject · SpecQuiet)이 곧 판정의
# 내용이라 이 배터리는 판정을 유도하지 못한다 — 가드 ↔ 속성 대응 · 증인 · 짝의 반례 ·
# 규범 사이의 공존(예약 관대 ∧ 비정렬 엄격 · CQ_SIZE 같은 값 수락 ∧ 소비 없는 워드 거절)
# 만 기계로 보인다. 가드 삭제 cfg 는 가드 속성 아홉을 전부 건다 — 지운 가드의 자기 속성이
# 첫 위반으로 난다. 「자기 속성*만*」 은 분리 검사가 잰다 — 비상주, 2026-09-26 실측 9/9
# (rtl/formal/tla/README.md MmioPage 절).
# ---------------------------------------------------------------------------
M=MmioPage.tla
expect_pass "페이지 처분 좋은 모델 (정렬 FP 쓰기만 소거를 기다린다)"  MmioPage.cfg        "$M"
expect_pass "대비: 주소 기준 ready — 가드 둘이 살면 안전"            MmioPage_byaddr.cfg "$M"

expect_fail "가드 삭제: rsp_on_accept (잡힌 읽기가 응답)" \
            MmioPage_del_rsp_on_accept.cfg "$M" Prop_RespAnswersAccepted
expect_fail "가드 삭제: effect_on_accept (수락 전 loud)" \
            MmioPage_del_effect_on_accept.cfg "$M" Prop_HeldQuiet
expect_fail "가드 삭제: ro_rejected (RO 쓰기 흡수)" \
            MmioPage_del_ro_rejected.cfg "$M" Prop_RoRejected
expect_fail "가드 삭제: wo_read_zero (WO 되읽기)" \
            MmioPage_del_wo_read_zero.cfg "$M" Prop_WoReadZero
expect_fail "가드 삭제: resv_lenient (예약 오프셋 쓰기가 loud)" \
            MmioPage_del_resv_lenient.cfg "$M" Prop_ResvQuiet
expect_fail "가드 삭제: unaligned_rejected (비정렬 쓰기 무시)" \
            MmioPage_del_unaligned_rejected.cfg "$M" Prop_UnalignedRejected
expect_fail "가드 삭제: leg_write_rejected (물려받은 구간 쓰기 흡수)" \
            MmioPage_del_leg_write_rejected.cfg "$M" Prop_LegacyRejected
expect_fail "가드 삭제: nocons_rejected (소비 없는 워드 쓰기 흡수)" \
            MmioPage_del_nocons_rejected.cfg "$M" Prop_NoConsRejected
expect_fail "가드 삭제: reject_loud (조용한 거절)" \
            MmioPage_del_reject_loud.cfg "$M" Prop_RejectLoud

expect_fail "증인: 소거 중 잡힌 읽기가 실재하는가"           MmioPage_witness_NoHeldRead.cfg      "$M" Witness_NoHeldRead
expect_fail "증인: 잡힌 거절 사유 기입이 실재하는가"         MmioPage_witness_NoHeldBad.cfg       "$M" Witness_NoHeldBad
expect_fail "증인: 잡힌 요청의 늦은 수락이 실재하는가"       MmioPage_witness_NoLateAccept.cfg    "$M" Witness_NoLateAccept
expect_fail "증인: 비정렬 쓰기가 실재하는가"                 MmioPage_witness_NoUnalignedWr.cfg   "$M" Witness_NoUnalignedWr
expect_fail "증인: 물려받은 구간 쓰기가 실재하는가"          MmioPage_witness_NoLegWr.cfg         "$M" Witness_NoLegWr
expect_fail "증인: 소비 없는 워드 쓰기가 실재하는가"         MmioPage_witness_NoNoConsWr.cfg      "$M" Witness_NoNoConsWr
expect_fail "증인: RO 쓰기가 실재하는가"                     MmioPage_witness_NoRoWr.cfg          "$M" Witness_NoRoWr
expect_fail "증인: 예약 오프셋 쓰기가 실재하는가"            MmioPage_witness_NoResvWr.cfg        "$M" Witness_NoResvWr
expect_fail "증인: WO 에 쓴 뒤의 읽기가 실재하는가"          MmioPage_witness_NoWoReadAfterWr.cfg "$M" Witness_NoWoReadAfterWr
expect_fail "증인: CQ_SIZE 같은 값 기입이 실재하는가"        MmioPage_witness_NoSameValueWr.cfg   "$M" Witness_NoSameValueWr

expect_fail "짝: D1 이전의 조립 — 잡힌 읽기의 응답" \
            MmioPage_pair_today_d1.cfg "$M" Prop_RespAnswersAccepted
expect_fail "짝: D1 이전의 조립 — 수락 전 FP_BIND 거절" \
            MmioPage_pair_today_d1_bind.cfg "$M" Prop_LoudOnlySpec
expect_fail "짝: 판정 전의 표면 — 조용한 흡수" \
            MmioPage_pair_today_surface.cfg "$M" Prop_NoSilentDrop
expect_fail "대안: 레지스터만 실물화 — 조용한 저장" \
            MmioPage_pair_nocons_store.cfg "$M" Prop_NoSilentDrop
expect_fail "대안: 레지스터만 실물화 — 확인 읽기의 거짓 증언" \
            MmioPage_pair_nocons_store_rd.cfg "$M" Prop_NoStaleRead
expect_fail "대안: 물려받은 구간 관대" \
            MmioPage_pair_leg_lenient.cfg "$M" Prop_NoSilentDrop
expect_fail "대안: 비정렬 쓰기 관대" \
            MmioPage_pair_unal_lenient.cfg "$M" Prop_NoSilentDrop
expect_fail "짝: ready 만 고친 판 — 응답 가드 없음" \
            MmioPage_pair_fixready_only.cfg "$M" Prop_RespAnswersAccepted

# ---------------------------------------------------------------------------
# 변환 미적중의 관측면 — 0xE04 XLATE_STATUS · 0xE08/0xE0C XLATE_MISS_VPN 의 *값*
# (파도 4, 2026-09-26 — 판정 E04 (A) 정지 게이트 스냅샷:
# e-defined.typ:323 「정지 중(`[0]` = 1)에만 정지한 요청의 값을 내고 정지가 없으면 0 이다」 ·
# e-defined.typ:323 「여러 워드 읽기가 찢기지 않는다」 ·
# e-defined.typ:881 「채널이 없으면 2항은 이행 불가능한」)
# 와 조회 지점의 *판정 시점* — 판정 래치 (3.10 v1.0 묶음 RTL 파도 W2, 2026-10-12:
# 03-hiu.typ:735 「요청이 조회 지점을 떠날 때까지 유지되고, 그 뒤의 커밋 · flush 는 그 요청의」 ·
# e-defined.typ:310 「풀린 그 요청은 그 커밋 항목으로 판정되고」 ·
# e-defined.typ:312 「그러므로 (d) 와 함께 드라이버는 미적중 채움으로 언제나 수렴한다」)
#
# XlateSurface.tla(위)는 문이고 세 RO 워드의 *읽기*는 그 모델의 상태가 아니다. 이
# 모델이 관측 값의 1단이다 — 파도 4 가드 여섯(정지 사실 · sticky · 정지 중의 파티션 ·
# VPN · 정지 없는 0 · 읽기 무해제 — W2 가 셋을 더했다, 아래), 고정 속성 Prop_NoTear(찢김
# 없음 — 몸은 E.4 3항의 일제 정지라 가드가 아니고 짝 「새는 파이프」가 반증력을 든다),
# 그리고 HostSpec(관측면만 보고 채우는 폴링 호스트) 아래의 진행 Prop_StallResolves —
# E.3 채널의 *충분성*.
# 기각 갈래 둘이 반례로 선다: 첫 미적중 포착(B — 끝난 정지의 잔재 · 둘째 정지의 VPN)과
# 비게이트(C — 살아 있는 요청이 샌다). 짝 「파도 3 까지의 RTL」(세 워드 읽기 0)은 :881 의 기계 판.
#
# 원형(스크래치)이 뺀 run 하나 — 「obs_stall_live 를 지운 기계도 호스트가 푼다」(PASS
# 기대)가 FAIL 이었다. 말더듬 인공물이다: [0] 이 sticky 를 내면 정지가 선 그 스텝의
# sticky 는 아직 0 이고 켜진 동작은 Read 뿐인데 원형의 공정성은 HostFill 에만 있었다 —
# 영영 읽지 않는 호스트가 진행을 깼다. 같은 인공물이 나머지 진행 짝(첫 미적중 포착 —
# 첫 정지 스텝에 포착 레지스터가 비어 HostFill 이 꺼진다)에도 열려 있어, 그 FAIL 이
# 「채널이 틀린 것을 말한다」로 났는지 「안 읽었다」로 났는지를 선언이 가르지 못했다.
# 그래서 빼지 않고 뿌리를 고쳤다: HostSpec 에 읽기 공정성(폴링)을 걸었다 — 근거는
# e-defined.typ:874 「정지가 영구가 되지 않을 책임은 호스트에 있다」 — 그리고 원형이 뺀 run 은 대비
# MUST PASS 로 들어온다 (obs_stall_live 는 충분성이 아니라 정지 사실의 가드다).
#
# W2 (판정 래치): 표가 판정 *값*을 들고, COMMIT 이 같은 파티션의 다른 VPN 을 비결정으로
# 축출한다(형상 중립 과근사 — 다른 파티션은 불가). 장치 래치 lat 과 정본 판정 유령 jd 를
# 나눴다 — 가드는 lat 을 짓고 속성의 참 쪽은 jd(와 CanonV)만 읽는다. 래치는 매 스텝 *스텝
# 이전* 조회값을 잡는다(포착 원자성 근거는 모델 머리). 연속 전진 LeaveArrive — 앞 요청이
# 떠나는 에지에 다음 요청이 들어온다 — 가 Next · HostNext 에 있다. 가드 셋과 첫 위반(BFS 최단 깊이):
#   verdict_latch          → Prop_NoReMiss            (깊이 3 — 판정 뒤 철회 · 축출로 재정지)
#   latch_clears_on_leave  → Prop_NoInheritedVerdict  (깊이 3 — 연속 전진의 다음 요청이 판정을 물려받음)
#   latch_one_value        → Prop_OneValue            (깊이 4 — 소유권 조회가 저장을 다시 읽음)
# 고정 속성 셋은 가드가 아니고 반증은 단독 cfg 가 든다: Prop_LatchedSurvivesRetract
# (떠나는 값 = 판정 시점의 스냅샷 — verdict_latch 삭제, 깊이 4) · Prop_V0AfterEdgeMisses
# (V=0 에지 뒤 판정 조회는 미적중 — latch_clears_on_leave 삭제, 깊이 4) · Prop_StickyRiseOnStall
# ([1] 은 판정 없는 요청이 있을 때만 선다 — 대안 sticky_raw_miss, 깊이 4).
# 대안 넷(Alts — 그럴듯하게 *잘못 지은* RTL, 가드 삭제가 아니다)은 각각 상주 MUST FAIL 이다:
#   clear_late          래치 비움이 한 에지 늦다       → Prop_NoInheritedVerdict    (깊이 3)
#   capture_beats_clear 포착이 비움을 이긴다            → Prop_NoInheritedVerdict    (깊이 3)
#   sticky_raw_miss     [1] 의 set 이 원시 미적중       → Prop_StickyRiseOnStall     (깊이 4)
#   value_no_latch      값 쪽 마지막 대입 없음          → Prop_LatchedSurvivesRetract (깊이 4)
# 앞 둘은 W2 첫 판(조회 지점이 비어야 도착 — 떠남과 도착 사이 거품 강제)에서 작은 · 진행 · 큰
# run 을 전부 통과했다(독립 반증 변이 M2b · M18) — 거품 에지가 늦은 비움을 대신 해 줬다.
# 연속 전진을 들인 뒤 둘 다 3 스텝에 운다: 다음 요청이 앞 요청의 판정(다른 파티션 것일 수
# 있다)을 물려받는다.
# 짝 「오늘의 RTL」(W2 전 RTL — HEAD 9b6eee6: missWait = s3.valid ∧ ¬조회 적중, 래치 없음)은
# HostSpec 아래에서 재미적중을 낸다 — 정지 → 호스트 채움 → hold 로 머묾 → 경쟁 커밋 축출.
# BFS 최단 반례는 축출을 풀린 사이클(첫 적중) 끝 에지에 둔다 — 모델의 관대한 인터리빙이고 RTL
# 에서는 그 에지가 같은 파티션 커밋을 받지 않는다(채움 슬롯 점유). RTL 에서 가능한 꼴은
# hold ≥ 2 사이클 뒤의 경쟁 커밋이다(cfg 머리). 끝-끝 음성 대조는 그 꼴을 쓴다.
# 진행: HostSpec 에 경쟁자(정지 중인 요청의 항목 밖의 V=1 · V=0 COMMIT 과 flush — 결과 (h)
# 가 이름한 축출 원인 그대로 · 풀린 · 래치된 요청 자신의 항목의 철회 · 대체 포함)와 하류
# 배압(떠남 Depart = Leave ∨ LeaveArrive 의 약한 공정성 — 환경 가정, 모델 머리 닫힌 목록
# 11)을 더했다. Prop_StallResolves 는 「정지한 *그* 요청은 결국 떠난다」 — 도착마다
# 뒤집히는 요청 꼬리표 tok 로 적는다: (Stalled ∧ tok = b) ~> (~s3.on ∨ tok ≠ b).
# 옛 꼴 둘은 대비 전용이다: Stalled ~> ~Stalled(Prop_StallLifts)는 래치 없는 판의 라이브락을
# 통과시키고(매 정지가 순간이나마 풀린다 — 실측 PASS), Stalled ~> ~s3.on(Prop_StallEmpties)은
# 연속 전진 아래 좋은 모델도 깬다(요청이 끊임없이 이어지면 조회 지점이 영영 비지 않는다 —
# 실측 FAIL). 래치 없는 판은 요청별 꼴을 깬다 — 결과 (d) 가 없으면 (h) 의 수렴이 무너진다는
# 연결이 기계로 선다.
# 가드 삭제 cfg 는 가드 속성 아홉을 전부 건다 — 지운 가드의 자기 속성이 첫 위반으로 난다.
# 고정 속성은 걸지 않는다(Prop_NoTear 와 같은 관례) — Prop_StickyRiseOnStall 을 더한 사본도 아홉
# 판 모두 첫 위반 · 깊이가 같았다(2026-10-12 비상주 실측).
# 소요 (2026-10-12 실측, 컨테이너 · -workers 1 · 다른 세션의 솔버로 기계 부하 load 8–10):
# 작은 좋은 모델 150,784 distinct · 31 s, 큰 좋은 모델 618,496 distinct · 3 분 7 초(VIEW StateView —
# 한 스텝짜리 출력과 요청 꼬리표를 접는다 — 파도 4 판은 13,344 distinct · 4 s), 진행 MUST PASS
# 149,248 distinct · 3 분 25 초, 대비 MUST PASS 둘 4 분 42 초 · 2 분 28 초, 진행 짝 「VPN 첫 미적중
# 포착」 1 분 3 초, 나머지 각 0–3 s. 이 절 41 run 을 뽑아 돌린 전체가 967 s 다.
# ---------------------------------------------------------------------------
M=XlateObs.tla
expect_pass "관측면 좋은 모델 (파티션 2 · VPN 2 · 판정 값 2)"   XlateObs.cfg       "$M"
expect_pass "관측면 좋은 모델 (파티션 3 · 판정 값 2 · 규모 — VIEW StateView)" XlateObs_large.cfg "$M"

expect_fail "가드 삭제: obs_stall_live ([0] 이 sticky 를 냄)" \
            XlateObs_del_obs_stall_live.cfg "$M" Prop_StatusStall
expect_fail "가드 삭제: obs_sticky ([1] 이 살아 있는 정지를 냄)" \
            XlateObs_del_obs_sticky.cfg "$M" Prop_StatusSticky
expect_fail "가드 삭제: obs_part_stalled ([15:8] 상수 0)" \
            XlateObs_del_obs_part_stalled.cfg "$M" Prop_PartStalled
expect_fail "가드 삭제: obs_vpn_stalled (VPN 이 첫 미적중 포착)" \
            XlateObs_del_obs_vpn_stalled.cfg "$M" Prop_VpnStalled
expect_fail "가드 삭제: obs_no_residue (끝난 정지의 잔재)" \
            XlateObs_del_obs_no_residue.cfg "$M" Prop_NoStallNoData
expect_fail "가드 삭제: obs_read_pure (STATUS 읽기가 sticky 를 내림)" \
            XlateObs_del_obs_read_pure.cfg "$M" Prop_ReadPure
expect_fail "대안: 비게이트 (정지 없는 관측이 살아 있는 요청을 냄)" \
            XlateObs_alt_live.cfg "$M" Prop_NoStallNoData
expect_fail "가드 삭제: verdict_latch (래치 없음 — 판정된 요청이 다시 정지)" \
            XlateObs_del_verdict_latch.cfg "$M" Prop_NoReMiss
expect_fail "가드 삭제: latch_clears_on_leave (다음 요청이 판정을 물려받음)" \
            XlateObs_del_latch_clears_on_leave.cfg "$M" Prop_NoInheritedVerdict
expect_fail "가드 삭제: latch_one_value (소유권 조회가 저장을 다시 읽음)" \
            XlateObs_del_latch_one_value.cfg "$M" Prop_OneValue
expect_fail "고정 속성 반증: 래치 없음 → 떠나는 값이 판정 뒤 커밋을 따른다" \
            XlateObs_del_verdict_latch_value.cfg "$M" Prop_LatchedSurvivesRetract
expect_fail "고정 속성 반증: 비우지 않는 래치 → V=0 에지 뒤 도착 요청이 적중" \
            XlateObs_del_latch_clears_on_leave_v0.cfg "$M" Prop_V0AfterEdgeMisses
expect_fail "대안: 래치 비움이 한 에지 늦다 (연속 전진의 다음 요청이 판정을 물려받음)" \
            XlateObs_alt_clear_late.cfg "$M" Prop_NoInheritedVerdict
expect_fail "대안: 포착이 비움을 이긴다 (첫 적중 에지에 떠난 요청의 판정이 남음)" \
            XlateObs_alt_capture_beats_clear.cfg "$M" Prop_NoInheritedVerdict
expect_fail "대안: [1] 의 set 이 원시 미적중 (래치된 요청의 축출이 sticky 를 세움)" \
            XlateObs_alt_sticky_raw_miss.cfg "$M" Prop_StickyRiseOnStall
expect_fail "대안: 값 쪽 래치 없음 (정지만 래치 — 떠나는 값이 판정 뒤 커밋을 따른다)" \
            XlateObs_alt_value_no_latch.cfg "$M" Prop_LatchedSurvivesRetract

expect_pass "진행: 폴링 호스트 아래 정지한 그 요청은 결국 떠난다 (경쟁자 · 하류 배압 · 연속 전진 포함)" \
            XlateObs_live.cfg "$M"
expect_fail "진행 짝: VPN 첫 미적중 포착 → 둘째 정지 영구" \
            XlateObs_live_del_vpn.cfg "$M" Prop_StallResolves
expect_fail "진행 짝: [15:8] 상수 0 → 파티션 0 밖 정지 영구" \
            XlateObs_live_del_part.cfg "$M" Prop_StallResolves
expect_fail "짝: 파도 3 까지의 RTL — 세 워드 읽기 0 → 정지 영구 (:881)" \
            XlateObs_pair_today.cfg "$M" Prop_StallResolves
expect_pass "대비: [0] 이 sticky 여도 폴링 호스트는 푼다 (원형이 뺀 run)" \
            XlateObs_live_del_stall_live.cfg "$M"
expect_fail "진행 짝: 래치 없음 + 경쟁 커밋자 + 하류 배압 → 라이브락 (결과 (d) 없이 (h) 없음)" \
            XlateObs_live_del_verdict_latch.cfg "$M" Prop_StallResolves
expect_pass "대비: 같은 라이브락 판이 옛 진행 꼴(정지가 순간 걷힘)은 통과한다 — 강화의 근거" \
            XlateObs_live_del_verdict_latch_lifts.cfg "$M"
expect_fail "대비: 연속 전진 아래 「조회 지점이 언젠가 빈다」는 좋은 모델도 깬다 — 요청 꼬리표의 근거" \
            XlateObs_live_empties.cfg "$M" Prop_StallEmpties
expect_fail "짝: 새는 파이프 — 스냅샷 뒤 정지한 요청이 밀려나 찢긴다" \
            XlateObs_pair_leaky.cfg "$M" Prop_NoTear
expect_fail "짝: 오늘의 RTL (W2 전 RTL — HEAD 9b6eee6, 래치 없음) — 채움 뒤 경쟁 커밋 축출로 재미적중 (RTL 꼴은 hold ≥ 2 사이클)" \
            XlateObs_pair_today_latch.cfg "$M" Prop_NoReMiss

expect_fail "증인: 정지 중의 읽기가 실재하는가"               XlateObs_witness_NoRdStall.cfg      "$M" Witness_NoRdStall
expect_fail "증인: 정지가 풀린 뒤 sticky 가 선 채의 읽기가 실재하는가" XlateObs_witness_NoRdAfter.cfg "$M" Witness_NoRdAfter
expect_fail "증인: 적중 요청이 조회 지점에 산 채의 읽기가 실재하는가" XlateObs_witness_NoRdLive.cfg  "$M" Witness_NoRdLive
expect_fail "증인: 파티션 값 0 이 아닌 정지의 읽기가 실재하는가" XlateObs_witness_NoRdStallOther.cfg "$M" Witness_NoRdStallOther
expect_fail "증인: 해제 없이 온 둘째 정지의 읽기가 실재하는가"  XlateObs_witness_NoRdNewStall.cfg  "$M" Witness_NoRdNewStall
expect_fail "증인: 스냅샷 뒤 · 항목 기입 전의 읽기가 실재하는가" XlateObs_witness_NoSnapRead.cfg   "$M" Witness_NoSnapRead
expect_fail "증인: 끝난 정지의 파티션 flush(임대 회전)가 실재하는가" XlateObs_witness_NoLease.cfg  "$M" Witness_NoLease
expect_fail "증인: 판정된 요청이 떠나지 않고 머무는가 (하류 배압)" XlateObs_witness_NoHoldAfterHit.cfg "$M" Witness_NoHoldAfterHit
expect_fail "증인: 래치된 요청의 항목을 같은 파티션 다른 VPN 커밋이 축출하는가" XlateObs_witness_NoEvictWhileLatched.cfg "$M" Witness_NoEvictWhileLatched
expect_fail "증인: 래치된 요청의 항목을 V=0 · flush 가 무효로 하는가" XlateObs_witness_NoRetractWhileLatched.cfg "$M" Witness_NoRetractWhileLatched
expect_fail "증인: 래치된 요청의 항목을 다른 값의 V=1 재커밋이 대체하는가" XlateObs_witness_NoReplaceWhileLatched.cfg "$M" Witness_NoReplaceWhileLatched
expect_fail "증인: V=0 이 마지막 커밋인 항목에 요청이 도착하는가" XlateObs_witness_NoArriveAfterV0.cfg "$M" Witness_NoArriveAfterV0
expect_fail "증인 (진행 환경): 래치된 요청의 항목이 경쟁 커밋에 축출되는가" \
            XlateObs_live_witness_NoEvictWhileLatched.cfg "$M" Witness_NoEvictWhileLatched

# ---------------------------------------------------------------------------
# 0xE14 XLATE_ACTIVE_PART — 결속 파티션과 그 수락 판정 (A, D) (3.10 v1.0 묶음 · W4, 2026-10-15)
#
# 요청의 파티션 = 접수 시점의 결속, 결속은 드레인 경계에서만 바뀐다 — 값 검사가 먼저, 다른 값은
# D = 1 일 때만 교체, 같은 값은 fault 없이 무동작이고 D 를 보고, 버스 수락된 기입은 전부 (A, D) 를
# 남긴다. D 는 수락 에지 *직후* 상태(같은 사이클 접수 포함)로 표집한다 (E.1.2 결속 파티션의 수락 판정).
# W4 전 RTL(HEAD f67e3d6)은 0xE14 를 예약 오프셋으로 흡수하고 요청 파티션을 최상위 포트로 받았다 —
# 짝 _pair_today_* 가 그 기계다.
#
# D 표집 꼴(DP-4)의 근거 run: 좋은 모델은 α(t+1 표집 · t+1 동안 접수 · MMIO 정지). 대안 β
# (ALLZERO(t) ∧ ¬접수(t))는 「마지막 일이 기입과 같은 에지에 빠져나가는」 모서리에서 D = 0 을 내
# 적법한 결속 전환을 거절 + [6] 한다(거짓 loud — 상태 3 개: 요청 접수 → 다른 값 기입 ∧ 그 일 퇴장).
# β 는 격리 몸을 지키고(_alt_beta_iso 통과) 그 모서리의 전환을 영영 못 한다(_alt_beta_edge 통과).
# 대안 lag(α 인데 t 접수가 t+1 점유에 아직 안 듦)는 격리를 깬다(_alt_lag → Inv_WorkUnderBound) — α 가
# 기대는 RTL 사실(req.fire(t) ⇒ occupancy(t+1) ≥ 1)의 기록이고 그 측정 몫은 HiuPipeline 태스크다.
# 대안 hold(정지 한 사이클 더)는 Prop_StallOnlyPend 로 실패 — 정지 = actPend 그 자체의 앵커.
# 고정 속성 여섯은 전부 상주 음성 run 을 갖는다(짝 · 대안 · _del_*_{a0d1,iso,stale}).
#
# 실측 2026-10-15 (컨테이너 · -workers 1): 작은 cfg 90,221 생성 · 1,233 distinct · 2 s; 큰 cfg(파티션 4 ·
# 상한 2) 984,733 생성 · 7,359 distinct · 19 s. 삭제 12 · 고정 속성 음성 3 · 증인 18 · 짝 3 · 대안 6 은 각
# 1 s 안팎 (절 44 run · 61 s — 검증 반영 판, Prop_StallOnlyPend · 기입별 grej 를 더한 뒤 같은 상태 수).
# 분리 검사(비상주 — 가드 속성 12 + 고정 5 를 걸고 하나씩 벗김): 가드 속성 사이의 교차는
# Prop_ReadIsSpec 하나뿐이다 — 레지스터를 틀리게 남기는 삭제 여덟이 *다음* 되읽기에서 그것도 깬다
# (pend_stalls_mmio 의 목표 속성이고 삭제 cfg 에서는 늘 자기 속성 뒤에 온다). 고정 속성은 대개 함께
# 깨진다(Inv_ObsIsSpec 여덟 · 격리 몸 넷 — drain_gates_switch · d_includes_same_cycle · pend_stalls_req · req_part_from_bound). reject_loud 만 자기 속성 하나다. 비상주 변이 둘: D 게이트
# 반전 → Prop_A0D1IsValueReject, 값 거절에 D 미표집 → Prop_DIsPostEdge.
# ---------------------------------------------------------------------------
M=ActivePart.tla
expect_pass "결속 좋은 모델 — 작은 (파티션 2 · 일 상한 1 · α)"            ActivePart.cfg       "$M"
expect_pass "결속 좋은 모델 — 큰 (파티션 4 = 인코딩 상한 · 일 상한 2 · α)"  ActivePart_large.cfg "$M"

expect_fail "가드 삭제: value_first (없는 값이 같은 값으로 접혀 수락)" \
            ActivePart_del_value_first.cfg "$M" Prop_ValueFirst
expect_fail "가드 삭제: rsv_strict ([31:10] 비0 수락)" \
            ActivePart_del_rsv_strict.cfg "$M" Prop_RsvRejected
expect_fail "가드 삭제: ro_field_ignored ([9:8] 을 예약-엄격으로 — RMW 드라이버 거절)" \
            ActivePart_del_ro_field_ignored.cfg "$M" Prop_RoFieldIgnored
expect_fail "가드 삭제: drain_gates_switch (D = 0 에서 결속 교체)" \
            ActivePart_del_drain_gates_switch.cfg "$M" Prop_SwitchOnlyDrained
expect_fail "가드 삭제: same_value_noop (같은 값 ∧ D = 0 → 거절 + [6])" \
            ActivePart_del_same_value_noop.cfg "$M" Prop_SameValueNoFault
expect_fail "가드 삭제: ad_every_accept (거절 뒤 앞 기입의 A = 1 이 남음)" \
            ActivePart_del_ad_every_accept.cfg "$M" Prop_AdEveryAccept
expect_fail "가드 삭제: d_includes_same_cycle (기입 사이클 에지 전 표집 — 같은 사이클 접수 누락)" \
            ActivePart_del_d_includes_same_cycle.cfg "$M" Prop_DIsPostEdge
expect_fail "가드 삭제: pend_stalls_req (판정 사이클에 옛 결속으로 접수 → 교체를 건넘)" \
            ActivePart_del_pend_stalls_req.cfg "$M" Prop_NoAcceptAcrossSwitch
expect_fail "가드 삭제: pend_stalls_mmio (판정 전 되읽기)" \
            ActivePart_del_pend_stalls_mmio.cfg "$M" Prop_ReadIsSpec
expect_fail "가드 삭제: req_part_from_bound (요청 파티션이 포트에서 옴)" \
            ActivePart_del_req_part_from_bound.cfg "$M" Prop_ReqPartIsBound
expect_fail "가드 삭제: unaligned_outside (0xE15–0xE17 이 0xE14 기입으로 처리)" \
            ActivePart_del_unaligned_outside.cfg "$M" Prop_UnalignedInert
expect_fail "가드 삭제: reject_loud (조용한 거절)" \
            ActivePart_del_reject_loud.cfg "$M" Prop_RejectLoud
expect_fail "고정 속성 음성: ad_every_accept 삭제 → A = 0 ∧ D = 1 이 값 거절과 어긋남" \
            ActivePart_del_ad_every_accept_a0d1.cfg "$M" Prop_A0D1IsValueReject
expect_fail "고정 속성 음성: pend_stalls_req 삭제 → 옛 결속의 일이 남음 (격리 몸)" \
            ActivePart_del_pend_stalls_req_iso.cfg "$M" Inv_WorkUnderBound
expect_fail "고정 속성 음성: pend_stalls_req 삭제 → 교체 에지 뒤 옛 결속의 일" \
            ActivePart_del_pend_stalls_req_stale.cfg "$M" Prop_NoStaleWorkAfterSwitch

expect_fail "증인: 결속 교체가 실재하는가"                       ActivePart_witness_NoSwitch.cfg "$M" Witness_NoSwitch
expect_fail "증인: 드레인 판정 거절이 실재하는가"                ActivePart_witness_NoDrainReject.cfg "$M" Witness_NoDrainReject
expect_fail "증인: 같은 값 ∧ D = 0 (fault 없음 · D = 0 보고)"   ActivePart_witness_NoSameUndrained.cfg "$M" Witness_NoSameUndrained
expect_fail "증인: A = 0 ∧ D = 1 (드레인된 값 거절)"            ActivePart_witness_NoA0D1.cfg "$M" Witness_NoA0D1
expect_fail "증인: 없는 파티션 값 기입이 도착하는가"            ActivePart_witness_NoPhantomWr.cfg "$M" Witness_NoPhantomWr
expect_fail "증인: 실재 값 ∧ [31:10] 비0 기입이 도착하는가"     ActivePart_witness_NoRsvWr.cfg "$M" Witness_NoRsvWr
expect_fail "증인: [9:8] 을 쓴 기입이 적용되는가"               ActivePart_witness_NoRoApplied.cfg "$M" Witness_NoRoApplied
expect_fail "증인: 같은 사이클 접수만으로 드레인 거절"          ActivePart_witness_NoSameCycleReject.cfg "$M" Witness_NoSameCycleReject
expect_fail "증인: 마지막 일이 같은 에지에 퇴장한 전환 (β 의 모서리)" ActivePart_witness_NoEdgeLeaveSwitch.cfg "$M" Witness_NoEdgeLeaveSwitch
expect_fail "증인: 판정 사이클의 요청 정지가 실재하는가"        ActivePart_witness_NoReqStall.cfg "$M" Witness_NoReqStall
expect_fail "증인: 판정 사이클의 MMIO 정지가 실재하는가"        ActivePart_witness_NoMmioStall.cfg "$M" Witness_NoMmioStall
expect_fail "증인: 교체 뒤 요청이 새 파티션을 다는가"           ActivePart_witness_NoReqAfterSwitch.cfg "$M" Witness_NoReqAfterSwitch
expect_fail "증인: 비정렬 쓰기가 도착하는가"                    ActivePart_witness_NoUnaligned.cfg "$M" Witness_NoUnaligned
expect_fail "증인: 판정 뒤 되읽기가 A = 1 을 보는가"           ActivePart_witness_NoSettledRead.cfg "$M" Witness_NoSettledRead
expect_fail "증인: 거절이 A = 1 을 내리는가"                    ActivePart_witness_NoALowered.cfg "$M" Witness_NoALowered
expect_fail "증인: (0,0) 값 거절 ∧ 드레인 안 됨"                ActivePart_witness_NoValRejUndrained.cfg "$M" Witness_NoValRejUndrained
expect_fail "증인: (1,1) 같은 값 ∧ 드레인됨"                    ActivePart_witness_NoSameDrained.cfg "$M" Witness_NoSameDrained
expect_fail "증인: 값 거절과 같은 사이클의 요청 접수"           ActivePart_witness_NoValRejSameCycle.cfg "$M" Witness_NoValRejSameCycle

expect_fail "짝: W4 전 RTL — 0xE14 쓰기 흡수"                  ActivePart_pair_today_absorb.cfg "$M" Inv_ObsIsSpec
expect_fail "짝: W4 전 RTL — 요청 파티션이 포트"               ActivePart_pair_today_port.cfg "$M" Prop_ReqPartIsBound
expect_fail "짝: 같은 값 ∧ D = 0 → 거절 (기각한 대안)"          ActivePart_pair_same_reject.cfg "$M" Prop_SameValueNoFault
expect_fail "대안 β: D 가 수락 에지 직후 상태와 어긋남"         ActivePart_alt_beta.cfg "$M" Prop_DIsPostEdge
expect_fail "대안 β: 적법한 전환이 거절 + [6] (거짓 loud)"     ActivePart_alt_beta_loud.cfg "$M" Prop_LoudOnlySpec
expect_pass "대안 β: 격리 몸은 지킨다 (관측 결함이지 격리 결함 아님)" ActivePart_alt_beta_iso.cfg "$M"
expect_pass "대안 β: 같은 에지 퇴장 전환을 영영 못 한다"       ActivePart_alt_beta_edge.cfg "$M"
expect_fail "대안 lag: t 접수가 t+1 점유에 안 듦 → 옛 결속의 일이 교체를 건넘" \
            ActivePart_alt_lag.cfg "$M" Inv_WorkUnderBound
expect_fail "대안 hold: 정지를 판정 사이클 밖으로 늘임"         ActivePart_alt_stall_hold.cfg "$M" Prop_StallOnlyPend

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
# 아래 셋은 적대 검증이 지적한 맹점을 메운 뒤 세운 실험이다. 셋 다 처음에는
# *가드조차 아니었고* — 모델이 그 결함형을 표현할 수 없었다는 뜻이다.
expect_fail "가드 삭제: view_sync (뷰 스큐)"      Route_del_view_sync.cfg         "$M" Inv_ViewAgrees
expect_fail "가드 삭제: scope_independent (결합)" Route_del_scope_independent.cfg "$M" Inv_ScopeLocal
expect_fail "가드 삭제: unique_owner (중복 소유)" Route_del_unique_owner.cfg      "$M" Inv_UniqueOwnerPerScope

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
# ---------------------------------------------------------------------------
# HIU-8 · HIU-9 · HIU-10 — 플랫폼 독립 (Platform.tla)
#
# 앞의 넷과 성격이 다르다. 이것은 **관계 속성**이라 두 세계(plain/rich)를
# 같은 동작열로 lockstep 구동하고 관측을 비교한다. 기계 하나가 "잘 도는" 것은
# 플랫폼 독립의 증거가 아니다 — 종속은 고장이 아니라 *다르게 도는 것*이다.
#
# 승인 거부의 보고 비트 [4] · [19] (3.10 v1.0 묶음 · W1, 2026-10-11 —
# e-defined.typ:527 「한 접근에 둘이 함께 서지 않는다」): 사상에 권한 비트를 싣고
# 장치 접근마다 접근자 · 승인 판정 · 원인(자격 · 소유 · 거부 채움)과 보고 비트를
# 기록한다(보고 축은 장치 접근 한정 — 근거는 모델 머리). 가드 넷(entitle_gates_value ·
# perm_entitle_only · entitle_first · own_reported)은 RTL 의 네 자리와 일대일이다 —
# 대응 예정 이름은 모델 머리. 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087: 둘 다 [4] — permViol = ¬(소유 ∧ 자격),
# [19] 원천 없음)이 Inv_ReportBitByCause 를 깨고, 같은 판의 대비 MUST PASS 가 남은
# 간극이 원인 귀속 하나뿐임을 붙잡는다. 좋은 모델 cfg 셋은 새 불변식 일곱을 함께 건다.
#
# OWN_SET 의 거절 · FAULT_STATUS [7] (3.10 v1.0 묶음 · W6, 2026-10-18 —
# e-defined.typ:1387 「장치는 OWN_SET 을 *거절할 수 있다*」): 앞판 Handoff 는 이양을 늘 커밋했다. 거절을 형상 중립
# 비결정 분기 OwnSetReject 로 들이고(SetShape = "any" — 울타리 안의 모든 거절을 탐색) 가드
# 여섯(set_reject_inert · set_reject_loud · set_reject_floor · set_owned_noop · clr_no_reject ·
# seven_reject_only)과 고정 속성 Prop_NoImplicitTransition 을 건다 — 좋은 cfg 셋이 일곱 속성을
# 함께 건다. 대비 SetShape = "direct"(HEAD RTL OwnershipTable 의 직접 사상 — 페이지 셋 · 둘이
# 한 칸)가 울타리가 RTL 을 배제하지 않음과 Inv_SlotExclusive 를 보이고 증인 둘이 그 판의
# 충돌 거절 · 점유 중 비충돌 커밋 도달을 보인다. E.7 7항 읽기 순서는 모델의 원자 스텝 구조라
# 재지 않는다(모델 머리 닫힌 목록 — ownershiptable.sby 몫). 23 → 36 run.
# 측정 범위: base(페이지 1)는 거절 축이 공허하다 — 거절은 하한 울타리(다른 장치 소유 페이지 ∃)
# 때문에 페이지 1 에서 열리지 않는다. 거절 축은 페이지 ≥ 2 판(shapeA · shapeB · direct)이 재고
# 증인 NoSetReject(페이지 2)가 도달을 보인다.
# ---------------------------------------------------------------------------
M=Platform.tla
expect_pass "HIU-8/9/10 기저 — 페이지 1"       Platform_base.cfg   "$M"
expect_pass "형상 sweep — 페이지 2"            Platform_shapeA.cfg "$M"
expect_pass "형상 sweep — 페이지 2 · 주소 2"   Platform_shapeB.cfg "$M"

expect_fail "가드 삭제: xlate_local (호스트 변환 서비스)" \
    Platform_del_xlate_local.cfg        "$M" Inv_SameTranslation
expect_fail "가드 삭제: flush_on_handoff (넘기는 쪽이 비운다)" \
    Platform_del_flush_on_handoff.cfg   "$M" Inv_SameObservation
expect_fail "가드 삭제: state_machine_kept (일관성 있으면 규약 생략)" \
    Platform_del_state_machine_kept.cfg "$M" Inv_SameFaultPolicy
expect_fail "가드 삭제: owner_check (비소유 접근)" \
    Platform_del_owner_check.cfg        "$M" Inv_UnownedFaults
expect_fail "가드 삭제: entitle_gates_value (자격 거부가 값을 받는다)" \
    Platform_del_entitle_gates_value.cfg "$M" Inv_EntDeniedBlocked
expect_fail "가드 삭제: perm_entitle_only ([4] 가 비소유도 접는다)" \
    Platform_del_perm_entitle_only.cfg  "$M" Inv_Bit4EntOnly
expect_fail "가드 삭제: entitle_first (자격 거부 ∧ 비소유 → [4] · [19] 동시)" \
    Platform_del_entitle_first.cfg      "$M" Inv_OneBitPerAccess
expect_fail "가드 삭제: entitle_first — 거부 채움 축 (회수 페이지가 [19] 도 세운다)" \
    Platform_del_entitle_first_fill.cfg "$M" Inv_DenyFillIs4
expect_fail "가드 삭제: own_reported ([19] 원천 없음 — 조용한 비소유 거부)" \
    Platform_del_own_reported.cfg       "$M" Inv_UnownedLoud
expect_fail "가드 삭제: set_reject_inert (거절이 덮어쓰고 축출한다)" \
    Platform_del_set_reject_inert.cfg   "$M" Prop_SetRejectInert
expect_fail "고정 속성 음성: 같은 판 — 축출은 암묵 전이" \
    Platform_del_set_reject_inert_implicit.cfg "$M" Prop_NoImplicitTransition
expect_fail "가드 삭제: set_reject_loud (조용한 OWN_SET 거절)" \
    Platform_del_set_reject_loud.cfg    "$M" Prop_SetRejectLoud
expect_fail "가드 삭제: set_reject_floor (빈 표의 OWN_SET 이 거절된다)" \
    Platform_del_set_reject_floor.cfg   "$M" Prop_SetRejectFloor
expect_fail "가드 삭제: set_owned_noop (이미 소유 페이지의 OWN_SET 이 거절된다)" \
    Platform_del_set_owned_noop.cfg     "$M" Prop_OwnedSetNoop
expect_fail "가드 삭제: clr_no_reject (OWN_CLR 이 거절된다)" \
    Platform_del_clr_no_reject.cfg      "$M" Prop_ClrNoReject
expect_fail "가드 삭제: seven_reject_only (커밋된 OWN_SET 이 [7] 을 세운다)" \
    Platform_del_seven_reject_only.cfg  "$M" Prop_SevenRejectOnly

expect_fail "증인: 값 읽기가 실재하는가"        Platform_witness_NoValueRead.cfg      "$M" Witness_NoValueRead
expect_fail "증인: fault 가 실재하는가"         Platform_witness_NoFault.cfg          "$M" Witness_NoFault
expect_fail "증인: 소유권 이양이 실재하는가"     Platform_witness_NoHandoff.cfg        "$M" Witness_NoHandoff
expect_fail "증인: 지역 사본이 실제로 어긋나는가" Platform_witness_NoDivergentCache.cfg "$M" Witness_NoDivergentCache
expect_fail "증인: 두 세계의 배후 저장이 어긋나는가" Platform_witness_NoMemSkew.cfg     "$M" Witness_NoMemSkew
expect_fail "증인: 자격 거부 [4] 가 실재하는가"       Platform_witness_NoEntDeny.cfg       "$M" Witness_NoEntDeny
expect_fail "증인: 비소유 프레임 접근 [19] 가 실재하는가" Platform_witness_NoOwnDeny.cfg    "$M" Witness_NoOwnDeny
expect_fail "증인: 자격 거부 ∧ 비소유 장치 접근이 실재하는가" Platform_witness_NoBothCauses.cfg  "$M" Witness_NoBothCauses
expect_fail "증인: 장치 소유 프레임 위 거부 채움 장치 접근이 실재하는가" Platform_witness_NoDenyFillOwned.cfg "$M" Witness_NoDenyFillOwned
expect_fail "증인: OWN_SET 거절이 실재하는가"              Platform_witness_NoSetReject.cfg     "$M" Witness_NoSetReject
expect_fail "증인: 이미 소유 페이지의 OWN_SET 무연산이 실재하는가" Platform_witness_NoOwnedSetNoop.cfg "$M" Witness_NoOwnedSetNoop
expect_fail "증인: OWN_CLR 회수 커밋이 실재하는가"         Platform_witness_NoClrCommit.cfg     "$M" Witness_NoClrCommit

expect_fail "짝: 오늘의 RTL(W1 전 · HEAD 3b80087) — 두 원인을 [4] 에 접는다 (HIU-10 원인별 보고)" \
    Platform_pair_today.cfg             "$M" Inv_ReportBitByCause
expect_pass "대비: 오늘의 RTL(W1 전 · HEAD 3b80087) — 원인 귀속 밖의 불변식은 전부 통과"  Platform_today.cfg "$M"
expect_pass "대비: HEAD RTL 형상(직접 사상 — 충돌이면 거절) — 울타리 안 · 한 칸 한 페이지" Platform_direct.cfg "$M"
expect_fail "증인: 직접 사상 판의 충돌 거절이 실재하는가" Platform_direct_witness_NoSetReject.cfg "$M" Witness_NoSetReject
expect_fail "증인: 직접 사상 판의 점유 중 비충돌 커밋이 실재하는가" Platform_direct_witness_NoCoOwned.cfg "$M" Witness_NoCoOwned

# ---------------------------------------------------------------------------
# SEC-3 — 무소실 (NoLoss.tla)
#
# FAB-2 의 상위 형태. FAB-2 는 한 공유 유닛의 무처분 없음이고, SEC-3 은
# 기계 전체의 회계다 — 유닛마다 처분이 있어도 유닛 *사이*에서 새면 깨진다.
# 서문 §0.8 이 적은 네 실패형(드롭·덮어쓰기·절단·완료 조작)이 전부 여기 있다.
# ---------------------------------------------------------------------------
M=NoLoss.tla
expect_pass "SEC-3 기저 — 단 2 · 수용 1"      NoLoss_base.cfg   "$M"
expect_pass "형상 sweep — 단 3"               NoLoss_shapeA.cfg "$M"
expect_pass "형상 sweep — 수용 2"             NoLoss_shapeB.cfg "$M"

expect_fail "가드 삭제: queue_room (조용한 덮어쓰기)" \
    NoLoss_del_queue_room.cfg     "$M" Inv_Conservation
expect_fail "가드 삭제: busy_loud (조용한 드롭)" \
    NoLoss_del_busy_loud.cfg      "$M" Inv_Conservation
expect_fail "가드 삭제: advance_atomic (단 사이 소실)" \
    NoLoss_del_advance_atomic.cfg "$M" Inv_Conservation
expect_fail "가드 삭제: fault_sticky (흔적 없는 fault)" \
    NoLoss_del_fault_sticky.cfg   "$M" Inv_FaultVisible
expect_fail "가드 삭제: width_checked (조용한 절단)" \
    NoLoss_del_width_checked.cfg  "$M" Inv_NoSilentTruncation
expect_fail "가드 삭제: complete_once (없던 완료)" \
    NoLoss_del_complete_once.cfg  "$M" Inv_NoPhantom

expect_fail "증인: 완료가 실재하는가"          NoLoss_witness_NoCompletion.cfg    "$M" Witness_NoCompletion
expect_fail "증인: fault 가 실재하는가"        NoLoss_witness_NoFault.cfg         "$M" Witness_NoFault
expect_fail "증인: 단이 실제로 가득 차는가"     NoLoss_witness_NoFullStage.cfg     "$M" Witness_NoFullStage
expect_fail "증인: 넓은 요청이 실제로 거절되는가" NoLoss_witness_NoWideRejection.cfg "$M" Witness_NoWideRejection

# ---------------------------------------------------------------------------
# EXT-1 · EXT-2 · EXT-3 — 순회와 검산 (Walk.tla)
#
# EXT-3 은 검사들 *자신에 대한* 메타 속성이다 — 검사가 서로를 대신하고 있지
# 않은가. 셋이 겹쳐 있어도 하나가 나머지에 함축되면 실제로는 둘뿐이고, 그
# 사실은 아무 테스트도 드러내지 않는다. 모든 테스트가 여전히 통과하므로.
# ---------------------------------------------------------------------------
M=Walk.tla
expect_pass "EXT-1/2/3 기저 — 상한 3"        Walk_base.cfg   "$M"
expect_pass "형상 sweep — 상한 2"            Walk_shapeA.cfg "$M"
expect_pass "형상 sweep — 상한 4"            Walk_shapeB.cfg "$M"

# 네 가드가 한 불변식을 공유한다 — 그것이 증명하려는 것 그 자체다.
# 넷을 각각 지웠을 때 넷 다 깨진다 = 넷 모두 독립적으로 필요하다.
expect_fail "가드 삭제: end_authority (길이가 종료를 정한다)" \
    Walk_del_end_authority.cfg  "$M" Inv_SoundVerdict
expect_fail "가드 삭제: len_check (길이 검산)" \
    Walk_del_len_check.cfg      "$M" Inv_SoundVerdict
expect_fail "가드 삭제: cap_check (상한 안전장치)" \
    Walk_del_cap_check.cfg      "$M" Inv_SoundVerdict
# END 분류 확정(§4.2.2 개정) — 선언 기준 분기. cap_declared 를 지우면 능력
# 부재(선언 > 구현 상한, 바이너리 옳음)가 malformation 으로 접힌다.
expect_fail "가드 삭제: cap_declared (능력 부재가 오류로)" \
    Walk_del_cap_declared.cfg   "$M" Inv_CapabilityNotMalformed
expect_fail "가드 삭제: junk_check (미지 종류)" \
    Walk_del_junk_check.cfg     "$M" Inv_SoundVerdict
expect_fail "가드 삭제: post_end_gated (종료 뒤 효과)" \
    Walk_del_post_end_gated.cfg "$M" Inv_NoPostEndEffect

expect_fail "증인: 통과가 실재하는가"          Walk_witness_NoOk.cfg          "$M" Witness_NoOk
expect_fail "증인: 거절이 실재하는가"          Walk_witness_NoMalformed.cfg   "$M" Witness_NoMalformed
expect_fail "증인: 능력 종결이 실재하는가"    Walk_witness_NoCapability.cfg  "$M" Witness_NoCapability
# 아래 셋이 EXT-3 「독립성」의 직접 형태다 — 그 검사 *하나만* 잡는 사슬이
# 존재해야 한다. 존재하지 않으면 그 검사는 나머지에 함축된 것이다.
expect_fail "독립성: 길이 검산만 잡는 사슬"     Walk_witness_NoLenOnly.cfg     "$M" Witness_NoLenOnly
expect_fail "독립성: 상한 검사만 잡는 사슬"     Walk_witness_NoCapOnly.cfg     "$M" Witness_NoCapOnly
expect_fail "독립성: 미지 종류만 잡는 사슬"     Walk_witness_NoJunkOnly.cfg    "$M" Witness_NoJunkOnly
expect_fail "증인: 종료 뒤 슬롯이 실재하는가"   Walk_witness_NoPostEndSlot.cfg "$M" Witness_NoPostEndSlot


# ---------------------------------------------------------------------------
# FAB-1 · FAB-5 · FAB-6 — 병합 지점과 배압 (Fabric.tla)
#
# §2.3 규범: 이 설계에 라우터도 중재기도 패킷도 flit 도 없다. 실체는
# 브로드캐스트 + valid 디먹스 + OR 병합 셋뿐이다. FAB-1 은 그 셋째의
# *정확성 전제*이고, §2.3 함정이 피해를 적어 준다 — 전제가 깨지면 결과는
# 두 값의 비트 OR 이 되는데 그것은 어느 쪽도 아닌 값이고 조용하다.
#
# 그래서 이 배터리는 「유효 생산자 <= 1」이 아니라 *병합된 값 자체*를 본다.
# 그렇게 적지 않으면 불변식이 가드와 같은 어휘가 되어 자기지시적으로
# 만족된다 (Route.tla 에서 실측한 M2 실패형).
#
# FAB-6 은 이 배터리의 첫 *진행성* 속성이다 — PROPERTY / ~> 형태이며
# 공정성을 생산자마다 건다.
# ---------------------------------------------------------------------------
M=Fabric.tla
expect_pass "FAB-1 · FAB-5 · FAB-6 기저"                       Fabric_base.cfg "$M"
expect_pass "형상 sweep A"                                     Fabric_shapeA.cfg "$M"
expect_pass "형상 sweep B"                                     Fabric_shapeB.cfg "$M"
# D=2 형상 — 출력 레지스터 깊이 파라미터화(§2.6)의 sweep. D=1 보존은 상태 수
# 일치로 실측했고(2,170 distinct, 파라미터화 전과 동일), 이 네 run 이 D=2 를 덮는다.
expect_pass "형상 sweep — 깊이 D=2"                            Fabric_depth2.cfg "$M"

# 가드 삭제 — 각 가드를 지우면 그 가드 자신의 불변식이 무너진다 (§6.3.2)
expect_fail "가드 삭제: bp_loud"                                 Fabric_del_bp_loud.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: bp_loud · 형상 A"                          Fabric_del_bp_loud_shapeA.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: bp_loud · 형상 B"                          Fabric_del_bp_loud_shapeB.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: bp_no_consumer_write"                    Fabric_del_bp_no_consumer_write.cfg "$M" Prop_ConsumerQuiet
expect_fail "가드 삭제: bp_no_consumer_write · 형상 A"             Fabric_del_bp_no_consumer_write_shapeA.cfg "$M" Prop_ConsumerQuiet
expect_fail "가드 삭제: bp_no_consumer_write · 형상 B"             Fabric_del_bp_no_consumer_write_shapeB.cfg "$M" Prop_ConsumerQuiet
expect_fail "가드 삭제: bp_relief"                               Fabric_del_bp_relief.cfg "$M" Prop_Progress
expect_fail "가드 삭제: bp_relief · 형상 A"                        Fabric_del_bp_relief_shapeA.cfg "$M" Prop_Progress
expect_fail "가드 삭제: bp_relief · 형상 B"                        Fabric_del_bp_relief_shapeB.cfg "$M" Prop_Progress
expect_fail "가드 삭제: capture_atomic"                          Fabric_del_capture_atomic.cfg "$M" Inv_ArrivalFromProducer
expect_fail "가드 삭제: capture_atomic · 형상 A"                   Fabric_del_capture_atomic_shapeA.cfg "$M" Inv_ArrivalFromProducer
expect_fail "가드 삭제: capture_atomic · 형상 B"                   Fabric_del_capture_atomic_shapeB.cfg "$M" Inv_ArrivalFromProducer
expect_fail "가드 삭제: fair_grant"                              Fabric_del_fair_grant.cfg "$M" Prop_Progress
expect_fail "가드 삭제: fair_grant · 형상 A"                       Fabric_del_fair_grant_shapeA.cfg "$M" Prop_Progress
expect_fail "가드 삭제: fair_grant · 형상 B"                       Fabric_del_fair_grant_shapeB.cfg "$M" Prop_Progress
expect_fail "가드 삭제: fault_raised"                            Fabric_del_fault_raised.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: fault_raised · 형상 A"                     Fabric_del_fault_raised_shapeA.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: fault_raised · 형상 B"                     Fabric_del_fault_raised_shapeB.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: fault_sticky"                            Fabric_del_fault_sticky.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: fault_sticky · 형상 A"                     Fabric_del_fault_sticky_shapeA.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: fault_sticky · 형상 B"                     Fabric_del_fault_sticky_shapeB.cfg "$M" Inv_FaultVisible
expect_fail "가드 삭제: single_producer"                         Fabric_del_single_producer.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: single_producer · 손상 축"                  Fabric_del_single_producer_damage.cfg "$M" Inv_MergeFaithful
expect_fail "가드 삭제: single_producer · 형상 A"                  Fabric_del_single_producer_shapeA.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: single_producer · 형상 B"                  Fabric_del_single_producer_shapeB.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: stall_on_pending"                        Fabric_del_stall_on_pending.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: stall_on_pending · 형상 A"                 Fabric_del_stall_on_pending_shapeA.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: stall_on_pending · 형상 B"                 Fabric_del_stall_on_pending_shapeB.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: valid_gated"                             Fabric_del_valid_gated.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: valid_gated · 형상 A"                      Fabric_del_valid_gated_shapeA.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: valid_gated · 형상 B"                      Fabric_del_valid_gated_shapeB.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: valid_gated · 경합 없음"                     Fabric_del_valid_gated_solo.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: valid_tracks_data"                       Fabric_del_valid_tracks_data.cfg "$M" Prop_ArrivalHasSource
expect_fail "가드 삭제: stall_on_pending · D=2"                 Fabric_del_stall_on_pending_depth2.cfg "$M" Prop_NoSilentLoss
expect_fail "가드 삭제: capture_atomic · D=2"                   Fabric_del_capture_atomic_depth2.cfg "$M" Inv_ArrivalFromProducer
expect_fail "가드 삭제: valid_gated · D=2"                      Fabric_del_valid_gated_depth2.cfg "$M" Inv_SingleValidProducer
expect_fail "가드 삭제: valid_tracks_data · 형상 A"                Fabric_del_valid_tracks_data_shapeA.cfg "$M" Prop_ArrivalHasSource
expect_fail "가드 삭제: valid_tracks_data · 형상 B"                Fabric_del_valid_tracks_data_shapeB.cfg "$M" Prop_ArrivalHasSource

# 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다
expect_fail "증인: NoArrival"                                  Fabric_witness_NoArrival.cfg "$M" Witness_NoArrival
expect_fail "증인: NoArrival · 형상 A"                           Fabric_witness_NoArrival_shapeA.cfg "$M" Witness_NoArrival
expect_fail "증인: NoArrival · 형상 B"                           Fabric_witness_NoArrival_shapeB.cfg "$M" Witness_NoArrival
expect_fail "증인: NoBackpressure"                             Fabric_witness_NoBackpressure.cfg "$M" Witness_NoBackpressure
expect_fail "증인: NoBackpressure · 형상 A"                      Fabric_witness_NoBackpressure_shapeA.cfg "$M" Witness_NoBackpressure
expect_fail "증인: NoBackpressure · 형상 B"                      Fabric_witness_NoBackpressure_shapeB.cfg "$M" Witness_NoBackpressure
expect_fail "증인: NoContention"                               Fabric_witness_NoContention.cfg "$M" Witness_NoContention
expect_fail "증인: NoContention · 형상 A"                        Fabric_witness_NoContention_shapeA.cfg "$M" Witness_NoContention
expect_fail "증인: NoContention · 형상 B"                        Fabric_witness_NoContention_shapeB.cfg "$M" Witness_NoContention
expect_fail "증인: NoFault"                                    Fabric_witness_NoFault.cfg "$M" Witness_NoFault
expect_fail "증인: NoFault · 형상 A"                             Fabric_witness_NoFault_shapeA.cfg "$M" Witness_NoFault
expect_fail "증인: NoFault · 형상 B"                             Fabric_witness_NoFault_shapeB.cfg "$M" Witness_NoFault
expect_fail "증인: NoOrHazard"                                 Fabric_witness_NoOrHazard.cfg "$M" Witness_NoOrHazard
expect_fail "증인: NoOrHazard · 형상 A"                          Fabric_witness_NoOrHazard_shapeA.cfg "$M" Witness_NoOrHazard
expect_fail "증인: NoOrHazard · 형상 B"                          Fabric_witness_NoOrHazard_shapeB.cfg "$M" Witness_NoOrHazard
expect_fail "증인: NoStaleRegister"                            Fabric_witness_NoStaleRegister.cfg "$M" Witness_NoStaleRegister
expect_fail "증인: NoStaleRegister · 형상 A"                     Fabric_witness_NoStaleRegister_shapeA.cfg "$M" Witness_NoStaleRegister
expect_fail "증인: NoStaleRegister · 형상 B"                     Fabric_witness_NoStaleRegister_shapeB.cfg "$M" Witness_NoStaleRegister

# 짝 run — 축의 분리를 확정한다. 같은 제약 아래 하나는 깨지고 하나는 안 깨진다
expect_pass "짝: shovefair_bp_relief"                         Fabric_pair_shovefair_bp_relief.cfg "$M"
expect_fail "짝: shovefair_fair_grant"                        Fabric_pair_shovefair_fair_grant.cfg "$M" Prop_Progress
expect_pass "짝: solo_single_producer"                        Fabric_pair_solo_single_producer.cfg "$M"

# ---------------------------------------------------------------------------
# SEC-4 · HIU-11 — 비간섭과 선택적 경로 (Isolation.tla)
#
# 둘 다 관계 속성이다. SEC-4 는 「출력이 남의 상태에 의존하지 *않는다*」이므로
# 한 실행 안에서 말할 수 없고, HIU-11 은 선택적 경로가 *있는* 구성과 *없는*
# 구성의 비교다. Platform.tla 의 lockstep 구조를 승계한다 (§3.4.2).
# ---------------------------------------------------------------------------
M=Isolation.tla
expect_pass "SEC-4 · HIU-11 기저"                              Isolation_base.cfg "$M"
expect_pass "형상 sweep A"                                     Isolation_shapeA.cfg "$M"
expect_pass "형상 sweep B"                                     Isolation_shapeB.cfg "$M"

# 가드 삭제 — 각 가드를 지우면 그 가드 자신의 불변식이 무너진다 (§6.3.2)
expect_fail "가드 삭제: approve_gates_value"                     Isolation_del_approve_gates_value.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: approve_gates_value · 형상 A"              Isolation_del_approve_gates_value_shapeA.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: approve_gates_value · 형상 B"              Isolation_del_approve_gates_value_shapeB.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: capacity_partitioned"                    Isolation_del_capacity_partitioned.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: capacity_partitioned · 형상 A"             Isolation_del_capacity_partitioned_shapeA.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: capacity_partitioned · 형상 B"             Isolation_del_capacity_partitioned_shapeB.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: coh_no_shortcut"                         Isolation_del_coh_no_shortcut.cfg "$M" Inv_OptionalPathNeutral
expect_pass "가드 삭제: coh_no_shortcut · 사이클만 관측"               Isolation_del_coh_no_shortcut_cyclesonly.cfg "$M"
expect_fail "가드 삭제: coh_no_shortcut · 형상 A"                  Isolation_del_coh_no_shortcut_shapeA.cfg "$M" Inv_OptionalPathNeutral
expect_fail "가드 삭제: coh_no_shortcut · 형상 B"                  Isolation_del_coh_no_shortcut_shapeB.cfg "$M" Inv_OptionalPathNeutral
expect_fail "가드 삭제: fill_offpath"                            Isolation_del_fill_offpath.cfg "$M" Inv_TraceNonInterference
expect_fail "가드 삭제: fill_offpath · 형상 A"                     Isolation_del_fill_offpath_shapeA.cfg "$M" Inv_TraceNonInterference
expect_fail "가드 삭제: fill_offpath · 형상 B"                     Isolation_del_fill_offpath_shapeB.cfg "$M" Inv_TraceNonInterference
expect_fail "가드 삭제: fill_slot_per_partition"                 Isolation_del_fill_slot_per_partition.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: fill_slot_per_partition · 형상 A"          Isolation_del_fill_slot_per_partition_shapeA.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: fill_slot_per_partition · 형상 B"          Isolation_del_fill_slot_per_partition_shapeB.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: fill_tagged"                             Isolation_del_fill_tagged.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: fill_tagged · 형상 A"                      Isolation_del_fill_tagged_shapeA.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: fill_tagged · 형상 B"                      Isolation_del_fill_tagged_shapeB.cfg "$M" Inv_VerdictNonInterference
expect_fail "가드 삭제: install_scoped"                          Isolation_del_install_scoped.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: install_scoped · 형상 A"                   Isolation_del_install_scoped_shapeA.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: install_scoped · 형상 B"                   Isolation_del_install_scoped_shapeB.cfg "$M" Inv_ValueNonInterference
expect_fail "가드 삭제: no_early_forward"                        Isolation_del_no_early_forward.cfg "$M" Inv_ForwardNonInterference
expect_fail "가드 삭제: no_early_forward · 형상 A"                 Isolation_del_no_early_forward_shapeA.cfg "$M" Inv_ForwardNonInterference
expect_fail "가드 삭제: no_early_forward · 형상 B"                 Isolation_del_no_early_forward_shapeB.cfg "$M" Inv_ForwardNonInterference
expect_pass "가드 삭제: no_early_forward · 값만 관측"                Isolation_del_no_early_forward_valueonly.cfg "$M"
expect_fail "가드 삭제: query_no_serve"                          Isolation_del_query_no_serve.cfg "$M" Inv_OptSameVerdict
expect_fail "가드 삭제: query_no_serve · 형상 A"                   Isolation_del_query_no_serve_shapeA.cfg "$M" Inv_OptSameVerdict
expect_fail "가드 삭제: query_no_serve · 형상 B"                   Isolation_del_query_no_serve_shapeB.cfg "$M" Inv_OptSameVerdict
expect_fail "가드 삭제: query_no_serve · 값 축"                    Isolation_del_query_no_serve_valueaxis.cfg "$M" Inv_OptSameValue
expect_fail "가드 삭제: query_offpath"                           Isolation_del_query_offpath.cfg "$M" Inv_OptionalPathNeutral
expect_fail "가드 삭제: query_offpath · 형상 A"                    Isolation_del_query_offpath_shapeA.cfg "$M" Inv_OptionalPathNeutral
expect_fail "가드 삭제: query_offpath · 형상 B"                    Isolation_del_query_offpath_shapeB.cfg "$M" Inv_OptionalPathNeutral

# 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다
expect_fail "증인: NoForeignFill"                              Isolation_witness_NoForeignFill.cfg "$M" Witness_NoForeignFill
expect_fail "증인: NoInflightBypass"                           Isolation_witness_NoInflightBypass.cfg "$M" Witness_NoInflightBypass
expect_fail "증인: NoOptStateSkew"                             Isolation_witness_NoOptStateSkew.cfg "$M" Witness_NoOptStateSkew
expect_fail "증인: NoQSkew"                                    Isolation_witness_NoQSkew.cfg "$M" Witness_NoQSkew
expect_fail "증인: NoRawSkew"                                  Isolation_witness_NoRawSkew.cfg "$M" Witness_NoRawSkew
expect_fail "증인: NoSubjectMiss"                              Isolation_witness_NoSubjectMiss.cfg "$M" Witness_NoSubjectMiss
expect_fail "증인: NoSubjectValue"                             Isolation_witness_NoSubjectValue.cfg "$M" Witness_NoSubjectValue

# ---------------------------------------------------------------------------
# EXT-4 — 재조립 배타성 (Payload.tla)
#
# NoLoss.tla 가 덮지 못한 축이다. 그 모델은 개수만 세므로 「A 를 잃고 B 를
# 두 번 완료」를 보지 못하고, 자기 머리가 그 공백을 EXT-4 의 몫으로 남겼다.
# 그래서 이 모델은 조각에 *정체성*을 준다 — 개수 보존이 아니라 어느 조각이
# 어느 슬롯에 들어갔는가를 본다.
# ---------------------------------------------------------------------------
M=Payload.tla
expect_pass "EXT-4 기저 (Tags 정제 — trace 축)"                Payload_base.cfg "$M"
expect_pass "EXT-4 기저 (Tags 정제 — poison 축)"               Payload_side_poison.cfg "$M"
expect_pass "형상 sweep A"                                     Payload_shapeA.cfg "$M"
expect_pass "형상 sweep B"                                     Payload_shapeB.cfg "$M"

# 가드 삭제 — 각 가드를 지우면 그 가드 자신의 불변식이 무너진다 (§6.3.2)
expect_fail "가드 삭제: base_from_tag"                           Payload_del_base_from_tag.cfg "$M" Inv_NoCrossWindow
expect_fail "가드 삭제: cap_check"                               Payload_del_cap_check.cfg "$M" Inv_NoCrossWindow
expect_fail "가드 삭제: capability_check"                        Payload_del_capability_check.cfg "$M" Inv_NoCrossWindow
expect_fail "가드 삭제: capability_not_fault"                    Payload_del_capability_not_fault.cfg "$M" Inv_CapabilityNotMalformed
expect_fail "가드 삭제: key_is_tag"                              Payload_del_key_is_tag.cfg "$M" Inv_ReassemblyExclusive
expect_fail "가드 삭제: loud_reject"                             Payload_del_loud_reject.cfg "$M" Inv_RejectLoud
expect_fail "가드 삭제: no_dup_seq"                              Payload_del_no_dup_seq.cfg "$M" Inv_ReassemblyExclusive
expect_fail "가드 삭제: no_restart"                              Payload_del_no_restart.cfg "$M" Inv_ReassemblyExclusive
expect_fail "가드 삭제: reset_on_deliver"                        Payload_del_reset_on_deliver.cfg "$M" Inv_NoStaleRedeliver
# D9(마지막 조각 표시) — 표시가 종료 authority, 접수 시점 완전성 판정 (§4.3).
expect_fail "가드 삭제: last_judges (누락이 무언)"               Payload_del_last_judges.cfg "$M" Inv_EndIncompleteLoud
# E.12 문맥 소거 (드레인 규약) — 소거는 회계를 남기되 fault 가 아니다.
expect_fail "가드 삭제: abort_erases (잔여 회계)"              Payload_del_abort_erases.cfg "$M" Inv_ReassemblyExclusive
expect_fail "가드 삭제: abort_clears_window (잔여 구간)"        Payload_del_abort_clears_window.cfg "$M" Prop_NoSilentOverwrite
expect_fail "가드 삭제: abort_leaves_trace (조용한 소거)"      Payload_del_abort_leaves_trace.cfg "$M" Inv_AbortLoud
expect_fail "가드 삭제: abort_not_fault (소거가 오류로)"        Payload_del_abort_not_fault.cfg "$M" Inv_AbortNotFault
expect_fail "가드 삭제: write_atomic"                            Payload_del_write_atomic.cfg "$M" Inv_ReassemblyExclusive
# 태그 코덱 전파 파도 (2026-09-26 · D2b) — Tags = Key × Trace × Poison. 매칭 키는 poison · trace
# 를 뺀다 (04-ext-payload 4.3 · E.12 6항). 이 축을 켠 run 은 이 절의 여섯뿐이다 — 다른 가드의
# 삭제 · 증인 · 형상 sweep 은 Traces = Poisons = {0} 의 접힌 판(1차 판과 같은 기계)으로 돈다.
expect_fail "가드 삭제: key_drops_side (소거가 trace 든 문맥에 못 닿는다)" Payload_del_key_drops_side.cfg "$M" Inv_AbortReachesKey

# 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다
expect_fail "증인: NoCapabilityAbsence"                        Payload_witness_NoCapabilityAbsence.cfg "$M" Witness_NoCapabilityAbsence
expect_fail "증인: NoCapabilityOnlyRejection"                  Payload_witness_NoCapabilityOnlyRejection.cfg "$M" Witness_NoCapabilityOnlyRejection
expect_fail "증인: NoDelivery"                                 Payload_witness_NoDelivery.cfg "$M" Witness_NoDelivery
expect_fail "증인: NoDupSeq"                                   Payload_witness_NoDupSeq.cfg "$M" Witness_NoDupSeq
expect_fail "증인: NoOverLimit"                                Payload_witness_NoOverLimit.cfg "$M" Witness_NoOverLimit
expect_fail "증인: NoPartialReassembly"                        Payload_witness_NoPartialReassembly.cfg "$M" Witness_NoPartialReassembly
expect_fail "증인: NoRestartClash"                             Payload_witness_NoRestartClash.cfg "$M" Witness_NoRestartClash
expect_fail "증인: NoTagReuse"                                 Payload_witness_NoTagReuse.cfg "$M" Witness_NoTagReuse
expect_fail "증인: NoTwoActiveCtx"                             Payload_witness_NoTwoActiveCtx.cfg "$M" Witness_NoTwoActiveCtx
expect_fail "증인: 표시 시점 누락이 실재하는가"                  Payload_witness_NoMissAtEnd.cfg "$M" Witness_NoMissAtEnd
expect_fail "증인: 표시 유실 미완 문맥이 실재하는가"              Payload_witness_NoMarkerLoss.cfg "$M" Witness_NoMarkerLoss
expect_fail "증인: 소거가 실재하는가"                          Payload_witness_NoAbort.cfg "$M" Witness_NoAbort
expect_fail "증인: 소거 흔적만 남은 상태가 실재하는가"           Payload_witness_NoAbortOnlyHistory.cfg "$M" Witness_NoAbortOnlyHistory
expect_fail "증인: trace·poison 만 다른 조각이 문맥에 닿는가"     Payload_witness_NoSideFragHit.cfg "$M" Witness_NoSideFragHit
expect_fail "증인: Clean 소거가 trace·poison 든 문맥을 지우는가" Payload_witness_NoSideAbortHit.cfg "$M" Witness_NoSideAbortHit

# 짝 run — 축의 분리를 확정한다. 같은 제약 아래 하나는 깨지고 하나는 안 깨진다
expect_fail "짝: silent_overwrite"                            Payload_pair_silent_overwrite.cfg "$M" Prop_NoSilentOverwrite
# 오늘의 RTL 짝 (태그 코덱 전파 파도 착지 *전*의 Reassembly — 번들 통비교 = key_drops_side 삭제).
# 삭제 run 이 소거 절반을 재고, 이 둘이 조각 조회 절반의 호스트 가시 귀결을 한 비트씩 잰다.
expect_fail "짝: 오늘의 RTL — trace 만 다른 도착이 덮어쓴다"     Payload_pair_today_trace.cfg "$M" Prop_NoSilentOverwrite
expect_fail "짝: 오늘의 RTL — poison 만 다른 도착이 덮어쓴다"    Payload_pair_today_poison.cfg "$M" Prop_NoSilentOverwrite

# ---------------------------------------------------------------------------
# SEC-7 · SEC-2 — 예약 필드 불투과와 경로 간 동일성 (Decode.tla)
#
# SEC-7 의 함정은 「판정 이전」이다. "예약이 0 이 아니면 거절한다" 만 적으면
# 속성이 자명하게 참이 된다 — 정본이 경고하는 것은 거절 판정이 내려지기
# *전에* 그 비트가 상태·타이밍·부수효과에 이미 반영되는 경우다.
#
# SEC-2 는 「사이클 수」가 아니라 *상태열*이다. 정본이 인과를 명시한다 —
# 상태열이 같다, *따라서* 사이클 수가 같다. 사이클 수만 비교하면 상태열이
# 다른데 길이만 같은 구현을 통과시키고, 그 차이가 곧 부채널이다.
# ---------------------------------------------------------------------------
M=Decode.tla
expect_pass "SEC-7 · SEC-2 기저"                               Decode_base.cfg "$M"
expect_pass "형상 sweep A"                                     Decode_shapeA.cfg "$M"
expect_pass "형상 sweep B"                                     Decode_shapeB.cfg "$M"
expect_pass "형상 sweep C"                                     Decode_shapeC.cfg "$M"
expect_pass "형상 sweep D"                                     Decode_shapeD.cfg "$M"

# 가드 삭제 — 각 가드를 지우면 그 가드 자신의 불변식이 무너진다 (§6.3.2)
# ch_judged (W8): CH 판정 축 — EH-조건부라 "absent" 레인은 대상이 아니고,
# 지우면 재계산 대조 불일치("bad")가 조용히 통과한다. 배터리 형상은
# resv_judged 와 같은 4벌 (기저 · 판정 늦춤 · 형상 B · 형상 C).
expect_fail "가드 삭제: ch_judged"                               Decode_del_ch_judged.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: ch_judged · 판정 늦춤"                       Decode_del_ch_judged_judgelate.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: ch_judged · 형상 B"                        Decode_del_ch_judged_shapeB.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: ch_judged · 형상 C"                        Decode_del_ch_judged_shapeC.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: evict_inline"                            Decode_del_evict_inline.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: evict_inline · 형상 B"                     Decode_del_evict_inline_shapeB.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: evict_inline · 형상 C"                     Decode_del_evict_inline_shapeC.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: fault_not_folded"                        Decode_del_fault_not_folded.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: fault_not_folded · 판정 늦춤"                Decode_del_fault_not_folded_judgelate.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: fault_not_folded · 형상 B"                 Decode_del_fault_not_folded_shapeB.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: fault_not_folded · 형상 C"                 Decode_del_fault_not_folded_shapeC.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: lookup_unbranched"                       Decode_del_lookup_unbranched.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: lookup_unbranched · 형상 B"                Decode_del_lookup_unbranched_shapeB.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: lookup_unbranched · 형상 C"                Decode_del_lookup_unbranched_shapeC.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: mal_carried"                             Decode_del_mal_carried.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: mal_carried · 형상 B"                      Decode_del_mal_carried_shapeB.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: mal_carried · 형상 C"                      Decode_del_mal_carried_shapeC.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: out_no_reason"                           Decode_del_out_no_reason.cfg "$M" Inv_OutVerdictOnly
expect_fail "가드 삭제: out_no_reason · 판정 늦춤"                   Decode_del_out_no_reason_judgelate.cfg "$M" Inv_OutVerdictOnly
expect_fail "가드 삭제: out_no_reason · 형상 B"                    Decode_del_out_no_reason_shapeB.cfg "$M" Inv_OutVerdictOnly
expect_fail "가드 삭제: out_no_reason · 형상 C"                    Decode_del_out_no_reason_shapeC.cfg "$M" Inv_OutVerdictOnly
expect_fail "가드 삭제: resv_judged"                             Decode_del_resv_judged.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: resv_judged · 판정 늦춤"                     Decode_del_resv_judged_judgelate.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: resv_judged · 형상 B"                      Decode_del_resv_judged_shapeB.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: resv_judged · 형상 C"                      Decode_del_resv_judged_shapeC.cfg "$M" Inv_MalformedRejected
expect_fail "가드 삭제: resv_not_echoed"                         Decode_del_resv_not_echoed.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_echoed · 판정 늦춤"                 Decode_del_resv_not_echoed_judgelate.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_echoed · 형상 B"                  Decode_del_resv_not_echoed_shapeB.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_echoed · 형상 C"                  Decode_del_resv_not_echoed_shapeC.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_indexed"                        Decode_del_resv_not_indexed.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_indexed · 판정 늦춤"                Decode_del_resv_not_indexed_judgelate.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_indexed · 형상 B"                 Decode_del_resv_not_indexed_shapeB.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_indexed · 형상 C"                 Decode_del_resv_not_indexed_shapeC.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_timed"                          Decode_del_resv_not_timed.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_timed · 판정 늦춤"                  Decode_del_resv_not_timed_judgelate.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_timed · 형상 B"                   Decode_del_resv_not_timed_shapeB.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: resv_not_timed · 형상 C"                   Decode_del_resv_not_timed_shapeC.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: stall_uniform"                           Decode_del_stall_uniform.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: stall_uniform · 형상 B"                    Decode_del_stall_uniform_shapeB.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: stall_uniform · 형상 C"                    Decode_del_stall_uniform_shapeC.cfg "$M" Inv_SamePathTrace
expect_fail "가드 삭제: verdict_ungated"                         Decode_del_verdict_ungated.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: verdict_ungated · 형상 B"                  Decode_del_verdict_ungated_shapeB.cfg "$M" Inv_ResvOpaque
expect_fail "가드 삭제: verdict_ungated · 형상 C"                  Decode_del_verdict_ungated_shapeC.cfg "$M" Inv_ResvOpaque

# 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다
# NoChBadOnly: CH 축이 *혼자서* 거절을 만드는 궤적의 실재 (예약 축의
# 그림자가 아님) — 없으면 위 ch_judged 삭제 반례가 어느 축을 지나는지
# 구별되지 않는다.
expect_fail "증인: NoChBadOnly"                                Decode_witness_NoChBadOnly.cfg "$M" Witness_NoChBadOnly
expect_fail "증인: NoEarlyJudgment"                            Decode_witness_NoEarlyJudgment.cfg "$M" Witness_NoEarlyJudgment
expect_fail "증인: NoEarlyObs"                                 Decode_witness_NoEarlyObs.cfg "$M" Witness_NoEarlyObs
expect_fail "증인: NoHitPath"                                  Decode_witness_NoHitPath.cfg "$M" Witness_NoHitPath
expect_fail "증인: NoMalformed"                                Decode_witness_NoMalformed.cfg "$M" Witness_NoMalformed
expect_fail "증인: NoMissPath"                                 Decode_witness_NoMissPath.cfg "$M" Witness_NoMissPath
expect_fail "증인: NoOk"                                       Decode_witness_NoOk.cfg "$M" Witness_NoOk
expect_fail "증인: NoReplacePath"                              Decode_witness_NoReplacePath.cfg "$M" Witness_NoReplacePath
expect_fail "증인: NoStall"                                    Decode_witness_NoStall.cfg "$M" Witness_NoStall
expect_fail "증인: NoStickyMiss"                               Decode_witness_NoStickyMiss.cfg "$M" Witness_NoStickyMiss

# 짝 run — 축의 분리를 확정한다. 같은 제약 아래 하나는 깨지고 하나는 안 깨진다
expect_pass "짝: branch_resvaxis"                             Decode_pair_branch_resvaxis.cfg "$M"
expect_pass "짝: branch_resvaxis · 형상 C"                      Decode_pair_branch_resvaxis_shapeC.cfg "$M"
expect_pass "짝: evict_resvaxis"                              Decode_pair_evict_resvaxis.cfg "$M"
expect_pass "짝: evict_resvaxis · 형상 C"                       Decode_pair_evict_resvaxis_shapeC.cfg "$M"
expect_fail "짝: indexed_kind"                                Decode_pair_indexed_kind.cfg "$M" Inv_KindRealized
expect_fail "짝: indexed_kind · 형상 C"                         Decode_pair_indexed_kind_shapeC.cfg "$M" Inv_KindRealized
expect_pass "짝: indexed_postjudge"                           Decode_pair_indexed_postjudge.cfg "$M"
expect_pass "짝: indexed_postjudge · 형상 C"                    Decode_pair_indexed_postjudge_shapeC.cfg "$M"
expect_pass "짝: judge_late"                                  Decode_pair_judge_late.cfg "$M"
expect_fail "짝: len_strong"                                  Decode_pair_len_strong.cfg "$M" Strong_SamePathSeq
expect_fail "짝: len_strong · 형상 C"                           Decode_pair_len_strong_shapeC.cfg "$M" Strong_SamePathSeq
expect_pass "짝: len_weak"                                    Decode_pair_len_weak.cfg "$M"
expect_pass "짝: len_weak · 형상 C"                             Decode_pair_len_weak_shapeC.cfg "$M"
expect_pass "짝: reason_prejudge"                             Decode_pair_reason_prejudge.cfg "$M"
expect_pass "짝: reason_prejudge · 형상 C"                      Decode_pair_reason_prejudge_shapeC.cfg "$M"
expect_pass "짝: stall_resvaxis"                              Decode_pair_stall_resvaxis.cfg "$M"
expect_pass "짝: stall_resvaxis · 형상 C"                       Decode_pair_stall_resvaxis_shapeC.cfg "$M"
expect_pass "짝: timed_pathaxis"                              Decode_pair_timed_pathaxis.cfg "$M"
expect_pass "짝: timed_pathaxis · 형상 C"                       Decode_pair_timed_pathaxis_shapeC.cfg "$M"

# ---------------------------------------------------------------------------
# EXT-6 — 메모리 순서 (MemOrder.tla)
#
# §4.4.4 가 확정한 기전(명시적 순서 의존)의 형식화. 두 얼굴을 가른다 —
# 발화 계약(Inv_DepRespected: 이어진 쌍은 선행 완료 뒤에만 발화)과
# 관측 계약(Inv_ObservedOrder: EXT-6 문면 그대로, 완료 순서 일치).
# 한 이름에 두 얼굴을 담으면 BFS 가 얕은 얼굴에서 멈춰 깊은 얼굴이 영원히
# 무판정으로 남는다 — 이 배터리가 그 실측의 기록이다.
#
# 과잉 게이팅 축(wave·addr·inflight)과 완료측 결박(응답 FIFO)이 각각
# 가드로 존재한다 — 지울 가드가 없는 결함형은 검출되지 않기 때문이다.
# 이 모델은 한 번 죽었다 — 1차 판의 Inv_OnlyTokenBlocks 는 좋은 모델에서
# 측정된 항진명제였다 (Route.tla M2 실패형의 재발). 어휘 분리로 고쳤다.
# ---------------------------------------------------------------------------
M=MemOrder.tla
expect_pass "EXT-6 base"                                     MemOrder_base.cfg "$M"
expect_pass "EXT-6 shapeA"                                   MemOrder_shapeA.cfg "$M"
expect_pass "EXT-6 shapeB"                                   MemOrder_shapeB.cfg "$M"
expect_pass "EXT-6 shapeC"                                   MemOrder_shapeC.cfg "$M"

# 가드 삭제 — 각 가드를 지우면 그 가드 자신의 불변식이 무너진다 (§6.3.2)
expect_fail "가드 삭제: addr_not_gating"                         MemOrder_del_addr_not_gating.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: addr_not_gating_shapeA"                  MemOrder_del_addr_not_gating_shapeA.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: addr_not_gating_shapeB"                  MemOrder_del_addr_not_gating_shapeB.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: addr_not_gating_shapeC"                  MemOrder_del_addr_not_gating_shapeC.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: complete_not_ordered"                    MemOrder_del_complete_not_ordered.cfg "$M" Inv_CompleteUngated
expect_fail "가드 삭제: complete_not_ordered_shapeA"             MemOrder_del_complete_not_ordered_shapeA.cfg "$M" Inv_CompleteUngated
expect_fail "가드 삭제: complete_not_ordered_shapeB"             MemOrder_del_complete_not_ordered_shapeB.cfg "$M" Inv_CompleteUngated
expect_fail "가드 삭제: gate_matches_dep"                        MemOrder_del_gate_matches_dep.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: gate_matches_dep_over"                   MemOrder_del_gate_matches_dep_over.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: gate_matches_dep_over_shapeA"            MemOrder_del_gate_matches_dep_over_shapeA.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: gate_matches_dep_over_shapeB"            MemOrder_del_gate_matches_dep_over_shapeB.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: gate_matches_dep_shapeA"                 MemOrder_del_gate_matches_dep_shapeA.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: gate_matches_dep_shapeC"                 MemOrder_del_gate_matches_dep_shapeC.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: gate_matches_dep_stuck"                  MemOrder_del_gate_matches_dep_stuck.cfg "$M" Inv_NoCircularWait
expect_fail "가드 삭제: gate_matches_dep_stuck_shapeA"           MemOrder_del_gate_matches_dep_stuck_shapeA.cfg "$M" Inv_NoCircularWait
expect_fail "가드 삭제: inflight_not_gating"                     MemOrder_del_inflight_not_gating.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: inflight_not_gating_shapeA"              MemOrder_del_inflight_not_gating_shapeA.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: inflight_not_gating_shapeB"              MemOrder_del_inflight_not_gating_shapeB.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: token_gate"                              MemOrder_del_token_gate.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: token_gate_shapeA"                       MemOrder_del_token_gate_shapeA.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: token_gate_shapeB"                       MemOrder_del_token_gate_shapeB.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: token_on_complete"                       MemOrder_del_token_on_complete.cfg "$M" Inv_ObservedOrder
expect_fail "가드 삭제: token_on_complete_fire"                  MemOrder_del_token_on_complete_fire.cfg "$M" Inv_DepRespected
expect_fail "가드 삭제: token_on_complete_shapeA"                MemOrder_del_token_on_complete_shapeA.cfg "$M" Inv_ObservedOrder
expect_fail "가드 삭제: token_on_complete_shapeB"                MemOrder_del_token_on_complete_shapeB.cfg "$M" Inv_ObservedOrder
expect_fail "가드 삭제: wave_not_gating"                         MemOrder_del_wave_not_gating.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: wave_not_gating_shapeA"                  MemOrder_del_wave_not_gating_shapeA.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: wave_not_gating_shapeB"                  MemOrder_del_wave_not_gating_shapeB.cfg "$M" Inv_OnlyTokenBlocks
expect_fail "가드 삭제: wave_not_gating_stuck"                   MemOrder_del_wave_not_gating_stuck.cfg "$M" Inv_NoCircularWait
expect_fail "가드 삭제: wave_not_gating_stuck_shapeA"            MemOrder_del_wave_not_gating_stuck_shapeA.cfg "$M" Inv_NoCircularWait
expect_fail "가드 삭제: wave_not_gating_stuck_shapeB"            MemOrder_del_wave_not_gating_stuck_shapeB.cfg "$M" Inv_NoCircularWait

# 위험 도달성 증인 — 전부 *구성된 기계*에서 반증된다
expect_fail "증인: NoAddrInversion"                            MemOrder_witness_NoAddrInversion.cfg "$M" Witness_NoAddrInversion
expect_fail "증인: NoAddrInversion_shapeB"                     MemOrder_witness_NoAddrInversion_shapeB.cfg "$M" Witness_NoAddrInversion
expect_fail "증인: NoCompletion"                               MemOrder_witness_NoCompletion.cfg "$M" Witness_NoCompletion
expect_fail "증인: NoCompletion_shapeB"                        MemOrder_witness_NoCompletion_shapeB.cfg "$M" Witness_NoCompletion
expect_fail "증인: NoConcurrentInflight"                       MemOrder_witness_NoConcurrentInflight.cfg "$M" Witness_NoConcurrentInflight
expect_fail "증인: NoConcurrentInflight_shapeB"                MemOrder_witness_NoConcurrentInflight_shapeB.cfg "$M" Witness_NoConcurrentInflight
expect_fail "증인: NoDepEnforced"                              MemOrder_witness_NoDepEnforced.cfg "$M" Witness_NoDepEnforced
expect_fail "증인: NoDepEnforced_shapeB"                       MemOrder_witness_NoDepEnforced_shapeB.cfg "$M" Witness_NoDepEnforced
expect_fail "증인: NoFireOrderCoupling"                        MemOrder_witness_NoFireOrderCoupling.cfg "$M" Witness_NoFireOrderCoupling
expect_fail "증인: NoFireOrderCoupling_shapeB"                 MemOrder_witness_NoFireOrderCoupling_shapeB.cfg "$M" Witness_NoFireOrderCoupling
expect_fail "증인: NoInflightPredecessor"                      MemOrder_witness_NoInflightPredecessor.cfg "$M" Witness_NoInflightPredecessor
expect_fail "증인: NoInflightPredecessor_shapeB"               MemOrder_witness_NoInflightPredecessor_shapeB.cfg "$M" Witness_NoInflightPredecessor
expect_fail "증인: NoWaveInversion"                            MemOrder_witness_NoWaveInversion.cfg "$M" Witness_NoWaveInversion
expect_fail "증인: NoWaveInversion_shapeB"                     MemOrder_witness_NoWaveInversion_shapeB.cfg "$M" Witness_NoWaveInversion

# 짝 run — 축의 분리를 확정한다
expect_pass "짝: addr_freedom_lost"                           MemOrder_pair_addr_freedom_lost.cfg "$M"
expect_pass "짝: addr_freedom_lost_shapeC"                    MemOrder_pair_addr_freedom_lost_shapeC.cfg "$M"
expect_fail "짝: addr_wave_axis"                              MemOrder_pair_addr_wave_axis.cfg "$M" Witness_NoWaveInversion
expect_fail "짝: addr_wave_axis_shapeC"                       MemOrder_pair_addr_wave_axis_shapeC.cfg "$M" Witness_NoWaveInversion
expect_fail "짝: complete_order_axis"                         MemOrder_pair_complete_order_axis.cfg "$M" Witness_NoAddrInversion
expect_pass "짝: fire_order_freedom_lost"                     MemOrder_pair_fire_order_freedom_lost.cfg "$M"
expect_pass "짝: gate_equals_contract"                        MemOrder_pair_gate_equals_contract.cfg "$M"
expect_pass "짝: gate_equals_contract_shapeA"                 MemOrder_pair_gate_equals_contract_shapeA.cfg "$M"
expect_pass "짝: gate_equals_contract_shapeB"                 MemOrder_pair_gate_equals_contract_shapeB.cfg "$M"
expect_pass "짝: gate_equals_contract_shapeC"                 MemOrder_pair_gate_equals_contract_shapeC.cfg "$M"
expect_pass "짝: inflight_freedom_lost"                       MemOrder_pair_inflight_freedom_lost.cfg "$M"
expect_fail "짝: inflight_order_axis"                         MemOrder_pair_inflight_order_axis.cfg "$M" Witness_NoAddrInversion

if [ "$rc" -eq 0 ]; then
    echo " 전체 $runs run 이 선언대로 행동했다 — 게이트 GREEN"
else
    echo " 선언과 다르게 행동한 run 이 있다 — 게이트 RED"
fi
echo "======================================================================="
exit "$rc"
