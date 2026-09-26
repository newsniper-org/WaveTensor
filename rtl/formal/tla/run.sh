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
# 임대별 마스크 키 — MaskUnit 제어면 (정본 7fa5f2e, 05-security.typ:112 ·
# e-defined.typ:333/351/E.9)
#
# 재구현 착수 시점 RTL 은 키 저장이 파티션별이 아니라 한 벌이었고, 키 기입이
# 전 파티션의 maskValid 를 떨어뜨렸다 — 아래 두 가드 삭제가 정확히 그 형태와
# 동형이다. rekey_explicit_target 은 e-defined.typ:351 7항이 명시적으로
# 기각한 "창이 재키잉 authority 를 겸함" 갈래를 모델링한다.
# ---------------------------------------------------------------------------
M=Mask.tla
expect_pass "임대별 마스크 키 좋은 모델 (파티션 2)"  Mask.cfg       "$M"
expect_pass "임대별 마스크 키 좋은 모델 (파티션 3)"  Mask_large.cfg "$M"

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
# 변환 저장소의 MMIO 문 — 0xC00 항목 배열(XLATE_ENTRY_LO/HI) · 0xE00 XLATE_FLUSH
# (파도 3, 2026-09-26:
# e-defined.typ:308 「기입이 항목 전체(스테이징 LO + 이 워드)를 단일 에지에 커밋한다」 ·
# e-defined.typ:321 「기입이 곧 발화」 · e-defined.typ:419 「조용한 무시는 금지다」)
#
# XlateStore.tla(위)은 저장 블록, Isolation.tla 는 조회·채움의 비간섭이고, 이
# 모델은 호스트가 두드리는 문이다 — 32b 버스가 64b 항목을 두 워드로 쪼개는
# 자리의 스테이징·커밋 원자성, flush 발화의 범위, 거절의 처분. 오늘의 RTL 은
# 두 구역을 selUnwired 로 열거만 하고 쓰기를 조용히 흡수한다(파도 2 의 T1) —
# 짝 「오늘의 RTL」 둘이 그 기계와 동형이다. flush 쪽 짝은 항목을 HI 문으로
# 세운다: 문을 둘 다 지우면 표에 산 항목이 없어 flush 결함이 공허하게 숨는다
# (실측 — 그 판은 통과했다).
#
# 하류 거부(XlateStore install.ready = 0)의 처분은 설계 결정이라 대안 셋을 다
# 돌린다 — 버스 정지(좋은 모델) · 거절 + loud(옳은 드라이버가 FAULT [6] 을
# 받는다) · 조용한 흡수. 그리고 정지가 호스트 조치 없이 풀린다는 진행 속성과,
# 그 공정성(채움 슬롯은 버스와 독립으로 비워진다)을 뺀 대조군.
# 가드 삭제 cfg 는 가드 속성 열일곱을 전부 건다 — 지운 가드의 자기 속성이 첫 위반으로 난다
# (TLC 는 첫 위반 하나만 보고한다 — 「자기 속성*만*」 은 이 러너가 재지 않는다).
#
# 같은 날 수리 — 0xE10 XLATE_MISS_CLEAR 와 RO 세 워드(0xE04–0xE0C)의 쓰기 처분
# (e-defined.typ:329 「`[0]` 에 1 기입 = 미적중 sticky 해제 · `[31:1]` 예약 = 0 (엄격)」 ·
# e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」). RTL 이 모델보다
# 먼저 배선한 결정(검토자 D-7)을 6.3 규율대로 모델로 돌려보냈다: 가드 다섯 ·
# 증인 다섯 · 발견 run 하나(정지 중 해제의 유실 — set 이 해제를 이긴다).
# ---------------------------------------------------------------------------
M=XlateSurface.tla
expect_pass "MMIO 문 좋은 모델 (파티션 2 · 색인 1 · 정지)"  XlateSurface.cfg       "$M"
expect_pass "MMIO 문 좋은 모델 (파티션 2 · 색인 2 · 정지)"  XlateSurface_large.cfg "$M"

expect_fail "가드 삭제: lo_stages_only (LO 가 표를 곧장 덮음)" \
            XlateSurface_del_lo_stages_only.cfg "$M" Prop_LoStagesOnly
expect_fail "가드 삭제: hi_fires (적법한 HI 흡수)" \
            XlateSurface_del_hi_fires.cfg "$M" Prop_HiCommits
expect_fail "가드 삭제: hi_entry_match (번호 불일치 커밋)" \
            XlateSurface_del_hi_entry_match.cfg "$M" Prop_MismatchRejected
expect_fail "가드 삭제: hi_needs_staging (HI 만 쓴 부분 기입 커밋)" \
            XlateSurface_del_hi_needs_staging.cfg "$M" Prop_UnstagedRejected
expect_fail "가드 삭제: hi_commit_whole (V 먼저 · 프레임 다음 에지)" \
            XlateSurface_del_hi_commit_whole.cfg "$M" Prop_HiCommitWhole
expect_fail "가드 삭제: hi_v_carried (커밋이 언제나 유효)" \
            XlateSurface_del_hi_v_carried.cfg "$M" Prop_ValidFromV
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

expect_fail "증인: 살아 있는 항목 위 LO 가 실재하는가"      XlateSurface_witness_NoLoOverLive.cfg    "$M" Witness_NoLoOverLive
expect_fail "증인: 번호 불일치 HI 가 실재하는가"           XlateSurface_witness_NoMismatch.cfg      "$M" Witness_NoMismatch
expect_fail "증인: 스테이징이 빈 HI 가 실재하는가"         XlateSurface_witness_NoUnstaged.cfg      "$M" Witness_NoUnstaged
expect_fail "증인: 프레임을 바꾸는 커밋이 실재하는가"       XlateSurface_witness_NoFrameChange.cfg   "$M" Witness_NoFrameChange
expect_fail "증인: V=0 단일 항목 무효화가 실재하는가"      XlateSurface_witness_NoKill.cfg          "$M" Witness_NoKill
expect_fail "증인: 산 파티션의 flush 가 실재하는가"        XlateSurface_witness_NoFlushLive.cfg     "$M" Witness_NoFlushLive
expect_fail "증인: 타 파티션이 산 동안의 flush 가 실재하는가" XlateSurface_witness_NoFlushOther.cfg "$M" Witness_NoFlushOther
expect_fail "증인: 없는 파티션 값 flush 가 실재하는가"     XlateSurface_witness_NoPhantom.cfg       "$M" Witness_NoPhantom
expect_fail "증인: 예약 위반 flush 가 실재하는가"          XlateSurface_witness_NoRsv.cfg           "$M" Witness_NoRsv
expect_fail "증인: 하류 거부로 버스 정지가 실재하는가"     XlateSurface_witness_NoStall.cfg         "$M" Witness_NoStall
expect_fail "증인: 정지가 풀린 뒤 선 sticky 의 해제가 실재하는가" XlateSurface_witness_NoClearLive.cfg "$M" Witness_NoClearLive
expect_fail "증인: 선 sticky 위 [0]=0 기입이 실재하는가"   XlateSurface_witness_NoZeroLive.cfg      "$M" Witness_NoZeroLive
expect_fail "증인: 예약 위반 해제가 실재하는가"            XlateSurface_witness_NoMclrRsv.cfg       "$M" Witness_NoMclrRsv
expect_fail "증인: 미적중 정지 중의 해제가 실재하는가"     XlateSurface_witness_NoClearInStall.cfg  "$M" Witness_NoClearInStall
expect_fail "증인: RO 오프셋 쓰기가 실재하는가"            XlateSurface_witness_NoRo.cfg            "$M" Witness_NoRo
# 발견 1 (모델 머리말) — 정본 문면의 귀결을 붙잡는 증인. 정본이 스테이징
# 소진을 정하면 이 run 이 실패하게 되고, 그때 모델을 고친다.
expect_fail "증인: flush 를 건넌 스테이징 잔재 커밋이 실재하는가" \
            XlateSurface_witness_NoStaleRecommit.cfg "$M" Witness_NoStaleRecommit

expect_fail "짝: 오늘의 RTL — XLATE_FLUSH 가 사라진다 (T1)" \
            XlateSurface_pair_today_flush.cfg "$M" Prop_FlushClears
expect_fail "짝: 오늘의 RTL — 항목 기입이 사라진다" \
            XlateSurface_pair_today_entry.cfg "$M" Prop_HiCommits
expect_fail "대안: 하류 거부 → 거절 + loud (옳은 드라이버에 fault)" \
            XlateSurface_pair_refusal_reject.cfg "$M" Prop_RejectOnlyMalformed
expect_fail "대안: 하류 거부 → 조용한 흡수" \
            XlateSurface_pair_refusal_drop.cfg "$M" Prop_HiCommits
expect_pass "진행: 버스 정지는 호스트 조치 없이 풀린다"   XlateSurface_live.cfg "$M"
expect_fail "짝: 채움 슬롯 Drain 공정성 없음 → 정지 영구" \
            XlateSurface_pair_live_nodrain.cfg "$M" Prop_StallEnds
# 발견 4 (모델 머리말) — 정지 중 해제의 유실을 붙잡는 run. set(정지 레벨)이
# 해제를 이기는 RTL 규약의 귀결이다. 정본이 정지 중 해제의 처분을 정하면 다시 본다.
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
# T2 (a) 의 거절 + [6] 은 W4 가 착지하고, 그 전의 RTL(조용한 흡수)이 짝
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

expect_fail "증인: 값 읽기가 실재하는가"        Platform_witness_NoValueRead.cfg      "$M" Witness_NoValueRead
expect_fail "증인: fault 가 실재하는가"         Platform_witness_NoFault.cfg          "$M" Witness_NoFault
expect_fail "증인: 소유권 이양이 실재하는가"     Platform_witness_NoHandoff.cfg        "$M" Witness_NoHandoff
expect_fail "증인: 지역 사본이 실제로 어긋나는가" Platform_witness_NoDivergentCache.cfg "$M" Witness_NoDivergentCache
expect_fail "증인: 두 세계의 배후 저장이 어긋나는가" Platform_witness_NoMemSkew.cfg     "$M" Witness_NoMemSkew

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
expect_pass "EXT-4 기저"                                       Payload_base.cfg "$M"
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

# 짝 run — 축의 분리를 확정한다. 같은 제약 아래 하나는 깨지고 하나는 안 깨진다
expect_fail "짝: silent_overwrite"                            Payload_pair_silent_overwrite.cfg "$M" Prop_NoSilentOverwrite

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
