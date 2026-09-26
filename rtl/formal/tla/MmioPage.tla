\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
------------------------------- MODULE MmioPage -------------------------------
\* 4 KiB 구성 페이지의 *처분* — 포트의 수락·응답, 방향(RO 쓰기 · WO 읽기),
\* 정렬(비정렬 쓰기), 예약 오프셋, 물려받은 구역, 소비 회로가 없는 워드의
\* 선-formal 모델. 파도 4 (2026-09-26).
\*
\* ## 왜 이제 있는가 — MMIO 워드 표면은 어느 모델의 상태도 아니었다
\*
\* 조립층 후-formal(rtl/formal/sby/Wt64Top/assembly.sby)은 페이지 처분을 VERIFIES
\* 로만 쟀다 — 「MMIO 워드 표면은 어느 TLA 모델의 상태도 아니다」가 그 머리의
\* 자백이었다. 정본 6.3 은 「1단을 건너뛴 모듈은 완료로 간주하지 않는다」 이고
\* 파도 4 판정 다섯(D1 · T1-i · T1-ii 쓰기 · T2 · T3)이 이 표면에 새 가드를 만든다.
\* 이 모델이 그 1단이다. XlateSurface.tla(0xC00 · 0xE00 구역의 문)와
\* AbortSurface.tla(0xF40 구역의 문)는 자기 구역 문의 *의미*를 모델링하고, 이
\* 모델은 페이지 전역의 *처분 규칙* — 어느 접근이 수락되고, 수락된 접근이 효과 ·
\* 거절 + loud · 조용한 무시 · 응답 중 무엇이 되는가 — 을 모델링한다.
\*
\* ## 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다)
\*
\*   수락과 응답 (D1)
\*   03-hiu.typ:989 「수락 중에는 ready 가 내려가 있으므로 중간 상태는 관측되지」
\*   03-hiu.typ:990 「읽기도 같다 — 수락(ready ∧ 스트로브)되지 않은 접근은 효과도 응답도 없다」
\*   02-fabric-alu.typ:557 「배압이 걸린 동안 *소비자 레지스터는 쓰이지 않는다.*」
\*   03-hiu.typ:983 「기입을 수락하지 않는다(ready 강하)」
\*   MmioConfig.scala:171 「ready 가 높을 때만 접근이 수락된다」 — RTL 포트 계약 (정본은
\*     버스 핸드셰이크를 규정하지 않는다 — 어댑터는 정본 경계 밖이다).
\*   MmioConfig.scala:173 「읽기: 수락 다음 사이클에 rdata 유효 (rvalid 1펄스)」
\*   방향 (E.1.1)
\*   e-defined.typ:198 「*WO 오프셋의 읽기* — 0 을 반환하고 fault 를 내지 않는다」
\*   e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」
\*   e-defined.typ:203 「조용히 무시하면 드라이버는 자기 쓰기가 먹혔다고 믿는다」
\*   e-defined.typ:283 「[SQ_HEAD], [RO]」 — T1-i 의 RO 절반 (0x38C).
\*   예약 오프셋 (3.7) — 관대는 *워드* 오프셋에 한한다 (판정 T2)
\*   e-defined.typ:205 「표에 *없는* 오프셋은 이 규범의 대상이 아니다」
\*   e-defined.typ:206 「그 관대는 *워드* 오프셋의 처분이다」
\*   03-hiu.typ:719 「이 절의 예약 *오프셋*은 관대하다 — 쓰기 무시·읽기 0.」
\*   비정렬 쓰기 (3.7 sub-word 규범 끝줄 — 판정 T2 (a))
\*   03-hiu.typ:747 「*sub-word 쓰기는 수락하지 않는다* — *거절 + loud」
\*   03-hiu.typ:754 「하위 두 비트가 0 이 아닌 *쓰기*는 어댑터가 새게 한 sub-word 쓰기의 잔재이고 이 규범의 정의역이다」
\*   03-hiu.typ:754 「비정렬 *읽기*는 0 · fault 없음이다」
\*   물려받은 구역 · 판 워드 (3.10 「합의 전의 처분」 — 판정 T3 (d) · T1-ii (iv))
\*   03-hiu.typ:1337 「이 장치는 거기 워드를 두지 않는다. 쓰기는」
\*   03-hiu.typ:1338 「거절 + loud fault (FAULT_STATUS `[6]`), 읽기는 0 · fault 없음이다」
\*   e-defined.typ:505 「쓰기는 E.1.1 RO 규범대로 거절 + loud fault 다」 — 0xFFC.
\*   소비 회로가 없는 RW 워드 (E.1.3 규범 끝 — 판정 T1-i (β) · CQ_BASE 포함)
\*   e-defined.typ:743 「*소비 회로가 없는 RW 워드 — 쓰기는 거절, 읽기는 0.*」
\*   e-defined.typ:743 「레지스터만 실물화해 되읽기를 주는 것은 금지다」
\*   e-defined.typ:743 「CQ_SIZE 행의 같은 값 수락(무동작)과 모순이 아니다」
\*   e-defined.typ:726 「현재 값과 같은 기입만 수락(무동작)하고 다른 값은 *거절 + loud* 다」
\*   조용한 무시 금지 — 고정 속성 Prop_NoSilentDrop 의 근거
\*   e-defined.typ:419 「*조용한 무시는 금지다.*」
\*
\* ## 이 모델이 잡는 정확한 결함 — D1 (rtl/README.md) 과 판정 전의 표면
\*
\* D1: 파도 4 착지 이전의 조립은 0xF00–0xF07 에서 ready 를 *주소*로 내렸다
\* (FP_PROG · FP_BIND 두 워드의 모든 접근 — 읽기 · 비정렬 포함 — 이 선택자 표 초기화
\* 소거를 기다렸다) 그런데 응답 경로(rvalid)는 ready 를 보지 않았고, FP_BIND 예약
\* 거절([6])은 수락 *전에* sticky 를 세웠다. 짝 today_d1 · today_d1_bind 가 그 기계다.
\* 상수 FpWaitByAddr = TRUE 가 주소 기준 ready 이고, 가드 둘(rsp_on_accept ·
\* effect_on_accept)을 지운 판이 그 응답·효과 경로다.
\* ready 의 *모양*은 안전의 문제가 아니다 — 대비 run MmioPage_byaddr 가 주소 기준 ready
\* 에서도 가드 둘이 살아 있으면 가드 속성 전부와 고정 속성이 통과함을 보인다. 수리
\* 갈래 (b)(ready 하강을 정렬 FP 쓰기로 좁힘)를 고른 것은 측정 가능성이다 — (a)
\* (응답·거절을 loadReady 로 게이트)는 조립 cover 의 절단 무관 증인 콘에 절단 핀을
\* 넣는다 (rtl/README.md 끝 장 「페이지 처분」). 짝 fixready_only 는 반대 방향이다: ready
\* 만 고치고 응답 가드를 지우면 여전히 운다 — 사상표(gateR)는 읽기도 기다리므로 ready
\* 모양과 무관하게 가드 자체가 필요하다.
\*
\* T1-i · T1-ii · T2 · T3 는 결함이 아니라 판정이었다 (정본 f229c8b). 판정 전의 RTL 은
\* 비정렬 쓰기 · 물려받은 구간 쓰기 · 0x38C/0xFFC RO 쓰기 · 소비 회로 없는 RW 워드 쓰기를
\* 전부 조용히 흡수했다 — 짝 today_surface 가 그 기계와 동형이다 (RO 부류는 모델에서
\* 하나라 0x38C/0xFFC 밖의 RO 워드까지 흡수로 과대근사한다 — 반례 하나면 충분하다).
\*
\* ## 한계 — 정직하게: 이 모델은 판정을 *유도*하지 못한다
\*
\* 고정 속성의 예외 집합 — SpecReject(거절 + loud 여야 하는 수락 기입)와 SpecQuiet
\* (조용한 무시가 허용되는 수락 기입 — 표에 없는 *정렬* 워드 오프셋 하나뿐) — 은 판정의
\* *내용 그 자체*다. 판정이 달랐다면(예: T3 를 관대로) 두 집합을 바꿔 적었을 것이고
\* 모델은 똑같이 통과했을 것이다. 기계로 보이는 것은 넷이다: (1) 가드마다 자기 속성
\* 하나가 서고 지우면 그것이 운다(가드 ↔ 속성 대응) (2) 증인 — 가드가 막는 입력이 실재
\* 한다 (3) 「오늘의 RTL」 짝이 반례를 낸다 (4) 규범 사이의 공존 — 예약 오프셋의 관대
\* (resv_lenient)와 비정렬 쓰기의 엄격(unaligned_rejected), CQ_SIZE 의 같은 값 수락과
\* 소비 회로 없는 워드의 거절이 한 기계에서 모순 없이 선다.
\*
\* ## CQ_SIZE 의 같은 값 무동작 — 효과로 센다 (부류 "cqsz")
\*
\* 고정 속성 Prop_NoSilentDrop(「SpecQuiet 밖의 수락 기입은 효과 또는 loud」)은 그대로
\* 두면 CQ_SIZE 의 같은 값 수락(위 정본 목록 끝 — 무동작 · fault 없음)을 반례로 셀 것이다 —
\* 모델의 고정 속성이 기존 규범과 모순이 된다. 그래서 부류 cqsz 를 두고 그 같은 값
\* 기입의 처분을 "same" 으로 적어 *효과*로 센다(Effective): 되읽기가 돌려주는 실물 값이
\* 있어 그 기입이 참말이 되기 때문이다 (e-defined.typ:743 의 「모순이 아니다」 문장 그대로
\* — 소비 회로 없는 워드에는 저장이 없어 맞출 값이 없다). 다른 값(bad)은 거절 + loud 다.
\* 증인 Witness_NoSameValueWr 가 그 예외가 공허하지 않음을 보인다.
\*
\* ## 가드 — 각각 정본 한 문장. 삭제 run(run.sh)은 자기 속성이 첫 위반으로 난다.
\*    「자기 속성*만*」 은 분리 검사가 잰다 — 비상주 9/9 (rtl/formal/tla/README.md MmioPage 절)
\*
\*   rsp_on_accept      :990 · RTL 포트 계약(위 :173) — 응답(rvalid)은 수락된 읽기에만.
\*                      지우면 잡혀 있는 읽기가 응답을 낸다(D1). → Prop_RespAnswersAccepted
\*   effect_on_accept   :989 · 02:557 — 수락되지 않은 접근은 효과도 loud 도 없다.
\*                      지우면 잡혀 있는 거절 사유 기입이 수락 전에 [6] 을 세운다(D1 의
\*                      FP_BIND 예약 거절). → Prop_HeldQuiet
\*   ro_rejected        e:202 — RO 워드의 정렬 쓰기는 거절 (0x38C · 0xFFC 포함). → Prop_RoRejected
\*   wo_read_zero       e:198 — WO 워드의 읽기는 0 (쓴 값을 되읽지 않는다). → Prop_WoReadZero
\*   resv_lenient       e:205 · e:206 — 표에 없는 *정렬* 워드 오프셋의 쓰기는 거절하지 않는다.
\*                      지우면 예약 오프셋 쓰기가 loud 가 된다. → Prop_ResvQuiet
\*   unaligned_rejected 03:754 — 하위 두 비트 ≠ 0 쓰기는 페이지 어디서든 거절 (예약 · 물려받은
\*                      구역 포함). → Prop_UnalignedRejected
\*   leg_write_rejected 03:1337 — 물려받은 0x000–0x11F 의 정렬 쓰기는 거절. → Prop_LegacyRejected
\*   nocons_rejected    e:743 — 소비 회로 없는 RW 워드(두 링의 base 넷 · SQ_SIZE · SQ_TAIL)의
\*                      정렬 쓰기는 거절. → Prop_NoConsRejected
\*   reject_loud        e:202 · 03:747 — 거절은 전부 FAULT_STATUS [6] 을 발화. → Prop_RejectLoud
\*
\* 고정 의미의 속성(가드 아님 — 좋은 모델 cfg 와 짝이 건다):
\*   Prop_LoudOnlySpec  loud 는 수락된 거절 사유 기입에서만 (수락 전 loud 없음 · 허위 fault 없음).
\*   Prop_NoSilentDrop  SpecQuiet 밖의 수락 기입은 효과(같은 값 무동작 포함) 또는 loud 다.
\*   Prop_SpecAgrees    수락 기입의 거절 ⟺ SpecReject — 거절이 판정의 정의역과 정확히 같다.
\*   Prop_NoStaleRead   응답 값은 0 이거나 실물 값이다 — 되읽기가 먹히지 않은 기입을 증언
\*                      하지 않는다(e:743 「레지스터만 실물화」 금지)와 WO 되읽기 없음.
\*
\* ## 처분 대안 상수 — 오늘의 RTL 손잡이
\*
\*   NoConsPolicy  소비 회로 없는 RW 워드 쓰기의 처분 — "reject"(판정 T1-i β) · "absorb"
\*                 (판정 전의 RTL — 조용한 흡수) · "store"(레지스터만 실물화 — 금지된 「형태만」).
\*                 absorb 는 Prop_NoSilentDrop 을, store 는 Prop_NoSilentDrop 과
\*                 Prop_NoStaleRead 를 깬다 (짝 셋).
\*   FpWaitByAddr  TRUE = D1 이전의 조립 — FP_PROG/FP_BIND 워드의 *모든* 접근이 초기화
\*                 소거를 기다린다. FALSE = 수리 갈래 (b) — 정렬 쓰기만 기다린다.
\*
\* ## 주소 부류 (E.1 페이지의 추상 — 어느 오프셋이 어느 부류인가는 모델 밖)
\*
\*   rw     소비자 있는 RW 워드 (MASK_PART 등)
\*   cqsz   CQ_SIZE — 돌려줄 실물 값이 있고 같은 값 기입만 수락(무동작)
\*   wo     WO 워드 (키 · 논스 · FLUSH 등) — 읽기 0
\*   ro     RO 워드 (0x38C SQ_HEAD · 0xFFC HIU_ABI_VERSION 포함)
\*   gate   쓰기가 유닛 ready 를 기다리는 WO 워드 (FP_PROG · FP_BIND — 선택자 표 소거)
\*   gateR  읽기·쓰기 모두 유닛 ready 를 기다리는 RW 워드 (사상표 — 초기화 소거 · CHECK)
\*   nocons 소비 회로 없는 RW 워드 (0x300/0x304 · 0x380/0x384 · 0x388 · 0x390)
\*   resv   표에 없는 워드 오프셋 (3.7 예약)
\*   leg    물려받은 0x000–0x11F
\* 요청의 bad 는 「워드 안의 거절 사유」다 — 정의 부류(rw · cqsz · wo · gate · gateR)에서만
\* 뜻이 있다 (예약 비트 비0 · FP_BIND [30:24] · CQ_SIZE 의 다른 값). 그 거절은 가드가 아니다 —
\* 각 표면의 모델(XlateSurface · AbortSurface)과 유닛 계약이 진다. 여기서는 고정 처분이다.
\*
\* ## 이 모델이 다루지 않는 것 (「안 잰다」 — 닫힌 목록)
\*
\* · 어느 오프셋이 어느 부류인가 — 주소 디코드와 구역 배타는 조립 후-formal(assembly.sby
\*   의 구역 분류 · surfMust)의 몫이다. 모델의 요청은 부류를 직접 지목한다.
\* · 수락된 기입의 *의미* — 스테이징 · 무장 · 커밋 · 발화는 XlateSurface · AbortSurface ·
\*   유닛 모델의 몫이다. 여기서 효과는 불투명 사건 하나(eff)다.
\* · 읽기 *값*의 뜻 — "data" 는 불투명한 실물 값이다. 0xE04–0xE0C 관측 값 · 0xFFC 의 판 값
\*   (합의 전 0 은 값 의미라 가드가 아니다 — 판정 T1-ii) · CAP/FAULT 워드 배치는 모델 밖.
\* · 바이트 인에이블 — 장치 포트에 없다. 이 모델의 비정렬(al = FALSE)은 그 잔재(주소 하위
\*   두 비트)의 처분만 재고, 어댑터 쪽 이행(정본 경계 밖)은 재지 않는다.
\* · [6] 의 sticky · W1C · 발화 우선 — loud 는 그 스텝의 발화 펄스다 (CapWord 와 같은 부류).
\* · 시간 — 모델의 스텝은 원자적이다. 소거 구간의 길이 · 수락 지연의 사이클 수는 없다.
\*   rdy 는 한 번 서면 내려가지 않는 추상이다 (CHECK 1사이클 busy 는 gateR 의 잡힘으로 흡수).
\* · 한 스텝에 접근 여럿 — 버스는 한 번에 하나다.
\*
EXTENDS Naturals, FiniteSets

CONSTANTS
    DisabledGuards,
    NoConsPolicy,    \* 소비 회로 없는 RW 워드 쓰기의 처분 — "reject" | "absorb" | "store"
    FpWaitByAddr     \* TRUE = D1 이전: FP_PROG/FP_BIND 워드의 *모든* 접근(읽기 · 비정렬 포함)이 소거를 기다린다

ASSUME NoConsPolicy \in {"reject", "absorb", "store"}
ASSUME FpWaitByAddr \in BOOLEAN

AllGuards == {"rsp_on_accept", "effect_on_accept", "ro_rejected", "wo_read_zero",
              "resv_lenient", "unaligned_rejected", "leg_write_rejected",
              "nocons_rejected", "reject_loud"}
On(g) == g \notin DisabledGuards

Classes == {"rw", "cqsz", "wo", "ro", "gate", "gateR", "nocons", "resv", "leg"}
\* 워드 안 거절 사유(bad)가 뜻을 갖는 부류 — 정의된 워드
Defined == {"rw", "cqsz", "wo", "gate", "gateR"}

Req(k, c, a, b) == [kind |-> k, cls |-> c, al |-> a, bad |-> b]
NoReq == Req("none", "resv", TRUE, FALSE)
Reqs == {Req("rd", c, a, FALSE) : c \in Classes, a \in BOOLEAN}
        \cup {Req("wr", c, a, b) : c \in Classes, a \in BOOLEAN, b \in BOOLEAN}

\* 응답 값 — zero · data(실물 값) · secret(WO 되읽기 — 쓴 값) · stale(저장만 있고 소비자 없는 값)
Vals == {"none", "zero", "data", "secret", "stale"}
\* 처분 — hold(수락 안 됨) · read · reject · effect · same(CQ_SIZE 같은 값 — 무동작) · store · absorb
Whys == {"none", "hold", "read", "reject", "effect", "same", "store", "absorb"}
Events == {"heldRd", "heldBad", "lateAcc"}

VARIABLES
    rdy,    \* 유닛 ready — reset 뒤 소거 구간 동안 FALSE, 끝나면 TRUE
    held,   \* 버스 마스터가 잡고 있는(수락되지 않은) 요청
    woW,    \* WO 워드에 수락된 기입이 있었는가 (되읽기 누설의 전건)
    ncS,    \* 소비 회로 없는 RW 레지스터에 값이 저장됐는가 ("store" 갈래)
    acc,    \* 보조 — 이 스텝에 수락된 요청 (NoReq = 수락 없음)
    why,    \* 보조 — 처분
    loud,   \* 보조 — FAULT_STATUS [6] 발화 펄스
    eff,    \* 보조 — 효과 (소비자 효과 · CQ_SIZE 같은 값 무동작)
    rsp,    \* 보조 — 이 스텝이 읽기 응답(rvalid)을 냈는가
    val,    \* 보조 — 응답 값
    ev      \* 보조 — 증인 사건

vars == <<rdy, held, woW, ncS, acc, why, loud, eff, rsp, val, ev>>

TypeOK ==
    /\ rdy \in BOOLEAN
    /\ held \in Reqs \cup {NoReq}
    /\ woW \in BOOLEAN /\ ncS \in BOOLEAN
    /\ acc \in Reqs \cup {NoReq}
    /\ why \in Whys
    /\ loud \in BOOLEAN /\ eff \in BOOLEAN /\ rsp \in BOOLEAN
    /\ val \in Vals
    /\ ev \in SUBSET Events

Init ==
    /\ rdy = FALSE
    /\ held = NoReq
    /\ woW = FALSE /\ ncS = FALSE
    /\ acc = NoReq /\ why = "none" /\ loud = FALSE /\ eff = FALSE
    /\ rsp = FALSE /\ val = "none" /\ ev = {}

\* 장치의 수락 술어
Ready(r) ==
    CASE r.cls = "gateR"                                   -> rdy
      [] r.cls = "gate" /\ r.kind = "wr" /\ r.al           -> rdy
      [] r.cls = "gate" /\ FpWaitByAddr                    -> rdy   \* D1 이전: 주소로 — 읽기·비정렬도 기다린다
      [] OTHER                                             -> TRUE

\* 판정(정본 f229c8b) — 수락된 기입 중 거절 + loud 여야 하는 것. 가드와 무관하다.
SpecReject(r) ==
    /\ r.kind = "wr"
    /\ \/ ~r.al                                   \* T2 — 워드 하나가 아닌 쓰기 (sub-word 의 장치 포트 표현)
       \/ r.cls \in {"ro", "leg", "nocons"}       \* E.1.1 RO · T3 합의 전 처분 · T1-i 소비 회로 없음
       \/ (r.cls \in Defined /\ r.bad)            \* 워드 안 거절 사유 (예약 비0 · CQ_SIZE 다른 값)
\* 조용한 무시가 허용되는 수락 기입 — 표에 없는 *정렬* 워드 오프셋 하나뿐 (3.7 · E.1.1 3항)
SpecQuiet(r) == r.kind = "wr" /\ r.al /\ r.cls = "resv"

\* 장치의 판정 — 가드 의존
DevReject(r) ==
    /\ r.kind = "wr"
    /\ \/ (~r.al /\ On("unaligned_rejected"))
       \/ (r.al /\ r.cls = "ro"     /\ On("ro_rejected"))
       \/ (r.al /\ r.cls = "leg"    /\ On("leg_write_rejected"))
       \/ (r.al /\ r.cls = "nocons" /\ NoConsPolicy = "reject" /\ On("nocons_rejected"))
       \/ (r.al /\ r.cls = "resv"   /\ ~On("resv_lenient"))
       \/ (r.al /\ r.cls \in Defined /\ r.bad)

Why(r) ==
    IF r.kind = "rd" THEN "read"
    ELSE IF DevReject(r) THEN "reject"
    ELSE IF r.al /\ r.cls = "cqsz" THEN "same"
    ELSE IF r.al /\ r.cls \in Defined THEN "effect"
    ELSE IF r.al /\ r.cls = "nocons" /\ NoConsPolicy = "store" THEN "store"
    ELSE "absorb"

\* 효과로 세는 처분 — 소비자 효과와 CQ_SIZE 같은 값 무동작 (머리 「효과로 센다」)
Effective(w) == w \in {"effect", "same"}

ReadVal(r) ==
    IF ~r.al THEN "zero"
    ELSE CASE r.cls \in {"rw", "cqsz", "gateR", "ro"} -> "data"
           [] r.cls \in {"wo", "gate"}                -> (IF On("wo_read_zero") \/ ~woW THEN "zero" ELSE "secret")
           [] r.cls = "nocons"                        -> (IF ncS THEN "stale" ELSE "zero")
           [] OTHER                                   -> "zero"

Accept(r, late) ==
    LET w == Why(r) IN
    /\ acc' = r
    /\ why' = w
    /\ loud' = (w = "reject" /\ On("reject_loud"))
    /\ eff' = Effective(w)
    /\ rsp' = (r.kind = "rd")
    /\ val' = (IF r.kind = "rd" THEN ReadVal(r) ELSE "none")
    /\ woW' = (woW \/ (w = "effect" /\ r.cls \in {"wo", "gate"}))
    /\ ncS' = (ncS \/ w = "store")
    /\ held' = NoReq
    /\ ev' = (IF late THEN {"lateAcc"} ELSE {})

\* 수락되지 않은 제시 — 버스 마스터가 잡아 둔다. 가드가 살아 있으면 아무 것도
\* 일어나지 않는다. D1 이전의 조립 = 두 가드를 지운 것.
Hold(r) ==
    /\ acc' = NoReq
    /\ why' = "hold"
    /\ loud' = (~On("effect_on_accept") /\ DevReject(r) /\ On("reject_loud"))
    /\ eff' = FALSE
    /\ rsp' = (~On("rsp_on_accept") /\ r.kind = "rd")
    /\ val' = (IF ~On("rsp_on_accept") /\ r.kind = "rd" THEN "zero" ELSE "none")
    /\ held' = r
    /\ UNCHANGED <<woW, ncS>>
    /\ ev' = (IF r.kind = "rd" THEN {"heldRd"} ELSE {})
             \cup (IF r.kind = "wr" /\ SpecReject(r) THEN {"heldBad"} ELSE {})

Present(r) ==
    /\ held = NoReq
    /\ UNCHANGED rdy
    /\ IF Ready(r) THEN Accept(r, FALSE) ELSE Hold(r)

Retry ==
    /\ held # NoReq
    /\ UNCHANGED rdy
    /\ IF Ready(held) THEN Accept(held, TRUE) ELSE Hold(held)

ClearDone ==
    /\ ~rdy
    /\ rdy' = TRUE
    /\ acc' = NoReq /\ why' = "none" /\ loud' = FALSE /\ eff' = FALSE
    /\ rsp' = FALSE /\ val' = "none" /\ ev' = {}
    /\ UNCHANGED <<held, woW, ncS>>

Next == \/ \E r \in Reqs : Present(r)
        \/ Retry
        \/ ClearDone

Spec == Init /\ [][Next]_vars

\* ── 가드 속성 — 가드마다 하나. 지우면 자기 속성이 운다 ──

\* rsp_on_accept — 응답은 수락된 읽기에만.
Prop_RespAnswersAccepted == [][ rsp' => acc'.kind = "rd" ]_vars
\* effect_on_accept — 수락되지 않은 스텝은 효과도 loud 도 없다.
Prop_HeldQuiet           == [][ (acc' = NoReq) => (~loud' /\ ~eff') ]_vars
\* ro_rejected — RO 워드의 정렬 쓰기는 거절된다.
Prop_RoRejected          == [][ (acc'.kind = "wr" /\ acc'.al /\ acc'.cls = "ro") => why' = "reject" ]_vars
\* wo_read_zero — WO 워드의 읽기는 0 이다 (쓴 뒤에도).
Prop_WoReadZero          == [][ (acc'.kind = "rd" /\ acc'.cls \in {"wo", "gate"}) => val' = "zero" ]_vars
\* resv_lenient — 표에 없는 정렬 워드 오프셋의 쓰기는 거절되지 않는다.
Prop_ResvQuiet           == [][ (acc'.kind = "wr" /\ acc'.al /\ acc'.cls = "resv") => why' # "reject" ]_vars
\* unaligned_rejected — 비정렬 쓰기는 부류와 무관하게 거절된다.
Prop_UnalignedRejected   == [][ (acc'.kind = "wr" /\ ~acc'.al) => why' = "reject" ]_vars
\* leg_write_rejected — 물려받은 구간의 정렬 쓰기는 거절된다.
Prop_LegacyRejected      == [][ (acc'.kind = "wr" /\ acc'.al /\ acc'.cls = "leg") => why' = "reject" ]_vars
\* nocons_rejected — 소비 회로 없는 RW 워드의 정렬 쓰기는 거절된다.
Prop_NoConsRejected      == [][ (acc'.kind = "wr" /\ acc'.al /\ acc'.cls = "nocons") => why' = "reject" ]_vars
\* reject_loud — 거절은 전부 [6] 을 발화한다.
Prop_RejectLoud          == [][ why' = "reject" => loud' ]_vars

\* ── 고정 속성 — 좋은 모델 · 처분 대안 짝 ──

\* loud 는 수락된 거절 사유 기입에서만 — 수락 전의 loud · 허위 fault 없음.
Prop_LoudOnlySpec  == [][ loud' => (acc' # NoReq /\ SpecReject(acc')) ]_vars
\* 조용한 무시 금지 — SpecQuiet 밖의 수락 기입은 효과(같은 값 무동작 포함) 또는 loud.
Prop_NoSilentDrop  == [][ (acc'.kind = "wr" /\ ~SpecQuiet(acc')) => (eff' \/ loud') ]_vars
\* 수락 기입의 거절은 판정의 정의역과 정확히 같다.
Prop_SpecAgrees    == [][ acc'.kind = "wr" => ((why' = "reject") <=> SpecReject(acc')) ]_vars
\* 응답 값은 0 이거나 실물 값 — 먹히지 않은 기입을 되읽기로 증언하지 않는다 · WO 되읽기 없음.
Prop_NoStaleRead   == [][ rsp' => val' \in {"zero", "data"} ]_vars

\* ── 증인 — 좋은 모델에서 반드시 반증 ──

\* rsp_on_accept — 소거 중 읽기가 잡힌다 (사상표).
Witness_NoHeldRead     == "heldRd" \notin ev
\* effect_on_accept — 거절 사유인 기입이 잡힌다 (FP_BIND 예약 비0 · 소거 중).
Witness_NoHeldBad      == "heldBad" \notin ev
\* rsp_on_accept · effect_on_accept — 잡힌 요청이 소거 뒤 수락된다.
Witness_NoLateAccept   == "lateAcc" \notin ev
\* unaligned_rejected · reject_loud — 비정렬 쓰기가 수락된다.
Witness_NoUnalignedWr  == ~(acc.kind = "wr" /\ ~acc.al)
\* leg_write_rejected — 물려받은 구간의 정렬 쓰기가 수락된다.
Witness_NoLegWr        == ~(acc.kind = "wr" /\ acc.al /\ acc.cls = "leg")
\* nocons_rejected — 소비 회로 없는 RW 워드의 정렬 쓰기가 수락된다.
Witness_NoNoConsWr     == ~(acc.kind = "wr" /\ acc.al /\ acc.cls = "nocons")
\* ro_rejected — RO 워드의 정렬 쓰기가 수락된다.
Witness_NoRoWr         == ~(acc.kind = "wr" /\ acc.al /\ acc.cls = "ro")
\* resv_lenient — 표에 없는 정렬 워드 오프셋의 쓰기가 수락된다.
Witness_NoResvWr       == ~(acc.kind = "wr" /\ acc.al /\ acc.cls = "resv")
\* wo_read_zero — WO 워드에 쓴 뒤의 읽기가 수락된다.
Witness_NoWoReadAfterWr == ~(acc.kind = "rd" /\ acc.al /\ acc.cls \in {"wo", "gate"} /\ woW)
\* Prop_NoSilentDrop 의 효과 계수 — CQ_SIZE 같은 값 기입(무동작)이 실재한다.
Witness_NoSameValueWr  == ~(acc.kind = "wr" /\ acc.al /\ acc.cls = "cqsz" /\ ~acc.bad)
=============================================================================
