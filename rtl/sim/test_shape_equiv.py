# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""test_shape_equiv.py — ISA-1 형상 등가 · ISA-2 사상 경유.

DUT 는 `rtl/generated/Wt64Top.sv` (형상 A, `Wt64Config()` 기본값 —
`nPoints=4` ⇒ `viewEntries=16`).

═══════════════════════════════════════════════════════════════════════════
## 정본 문면과 이 하네스의 층위
═══════════════════════════════════════════════════════════════════════════

`docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ` §1.8:
  · **ISA-1** 형상 등가 — 「같은 바이너리를 서로 다른 형상 두 개에 걸었을 때,
    **사상표만 적절히 구성하면** 관측 가능한 결과가 같다.」(:1271)
  · **ISA-2** 사상 경유 — 「논리 ID 는 반드시 사상표를 경유해 해석된다.
    사상표를 항등이 아닌 순열로 바꾸면 결과가 바뀐다.」(:1276)
  · 함정 (:1353) — 「항등 사상을 건 기계에서는 수치가 우연히 맞는다. ISA-1 만
    검사하면 사상표를 우회하는 구현도 통과한다. **ISA-2 의 순열 변이가 그것을
    잡는 유일한 수단이다.**」

⚠ **「관측 가능한 결과」의 외연을 정본이 정하지 않았다.** ⓐ결과값만 /
ⓑ관측 가능한 출력 전부 / ⓒⓑ+사이클 타이밍 — 셋 다 문면과 양립한다. 이
하네스는 **ⓒ(사이클 정확)로 잰다.** 근거: ⓒ ⊃ ⓑ ⊃ ⓐ 이므로 나중에 더
약한 정의로 완화하는 것은 무해하고 그 역은 편도다. 그리고 ⓒ가 깨지는데
값은 맞는 경우가 나오면 그 실패 자체가 **정본이 답해야 할 질문의 반례**다 —
삼키지 말고 크게 실패시켜 올린다. 이 선택은 정본 결정 대기 항목이지 하네스의
재량이 아니다.

═══════════════════════════════════════════════════════════════════════════
## ⛔ 이 하네스의 층위 — 호스트 ABI 가 아니다
═══════════════════════════════════════════════════════════════════════════

호스트 명령 링(E.5 투입 방향)은 **미배선**이다: `Wt64Top.scala:1180` 「private val selSq    = sel(R_SQ)」 —
`selSq` 가 `R_SQ`(0x380–0x3FF)를 「명령 방향 실물 0건」이라 열거하고,
생성물에 `io_instr_ready` 가 없다. ⇒ 이 하네스는 설계 **내부 포트
`io.instr` 를 직접 때린다.** 그러므로 여기서 확인되는 ISA-1/ISA-2 는

    호스트 ABI 층위의 등가가 아니라 **디코드 진입 층위의 등가**다.

이 문장을 지우지 마라. 지우면 다음 사람이 「끝-끝 등가가 확인됐다」로 읽는다.

═══════════════════════════════════════════════════════════════════════════
## 재는 것 / 재지 못하는 것
═══════════════════════════════════════════════════════════════════════════

**잰다**
  · ISA-2 α — LBID 존재 집합의 순열. `F(σ(S)) == predict(σ, F(S))` **정확 비교**
  · ISA-2 β — LNID 뷰 집합의 순열. 같은 형태의 정확 비교
  · ISA-1 자리 무관성 — 같은 논리 LNID 집합을 **다른 슬롯·다른 소유 지점**에
    앉혀도 궤적이 바이트 동일. 형상 하나 안에서 확인 가능한 ISA-1 의 몫이다
  · 구성 표면 무결성 — 소거 구간 대기 · 수락 · 거절 4부류가 실제로 loud
  · 궤적 비교기의 양·음성 자기대조
  · **변환 저장소의 MMIO 문** (파도 3) — `0xC00` XLATE_ENTRY_LO/HI · `0xE00`
    XLATE_FLUSH · `0xE10` XLATE_MISS_CLEAR 를 *호스트 ABI 오프셋으로* 기입하고
    HIU 요청(`io.hiuReq`, 내부 제시 포트)의 적중·정지·승인 프레임으로 잰다.
    정본이 상주를 요구하는 시험(03-hiu.typ:802 「항목 설치 → 컨텍스트 전환 → *같은 주소*의 변환이 미적중하는지 확인한다」)의
    기입 쪽이 처음으로 MMIO 로 표현 가능해졌다 — 설치 → flush → 같은 주소 미적중.
    같은 항목 HI 두 워드를 쉬는 사이클 없이 잇는 원시 구동(`mmio_burst`)으로
    하류 거부의 처분(D-2 버스 정지 — 정확히 한 사이클 · `[6]` 무발화 · 풀린
    기입의 커밋)도 값 수준에서 잰다.
    조회 쪽은 여전히 내부 포트이므로 이것도 **끝-끝 호스트 ABI 등가는 아니다**
    (호스트 쪽 문 · 디코드 진입 층위의 요청).
  · **표면 비트 · 워드** (W1 — 3.10 v1.0 묶음의 RTL 파도 첫 하위 파도) —
    `0xFF8` HIU_SHAPE 의 값과 RO 처분(`hiu_shape_word`), `0xEC4`
    MASK_DUP_CAPTURE 의 래치 · 첫 사건 보존 · 해제 · 같은 사이클 해제 + 발화 ·
    거절/미수락 발화 불변 · 읽기 무부작용(`mask_dup_capture`), FAULT_STATUS
    `[4]`/`[19]` 의 원인별 보고와 `0xF84` 예약 `[31:20]` 엄격
    (`fault19_nonowned_access`). 기대값은 정본 표에서 유도한다 — RTL 상수를
    import 하지 않는다 (파일 끝 W1 절 머리).
  · **판정 래치** (W2 — 같은 묶음의 둘째 하위 파도) — 미적중 정지를 커밋이 풀고 요청이 하류
    hold 로 조회 지점에 머무는 동안 같은 칸의 다른 VPN 커밋이 그 항목을 밀어내도 다시
    미적중하지 않고 그 커밋 항목으로 승인된다(`xlate_released_judgment_survives_eviction`).
    판정이 래치된 요청은 hold 중의 V=0 COMMIT · flush · 대체 커밋을 건너 래치된 값으로 승인되고,
    그 에지 뒤에 판정된 요청만 철회 · 대체를 본다 · 떠난 요청의 판정을 다음 요청이 물려받지
    않는다(`xlate_latched_hit_survives_retire`). 칸 고르기 하나가 화이트박스다 (파일 끝 W2 절 머리).
  · **입력 포트 정의역** — `zero_inputs` 가 생성물 머리의 입력 포트 집합과
    `SHAPE_INPUTS`(+ `io_faultClear_*`)를 매 부팅 기계로 대조한다. 포트가 늘거나
    줄면 전 시험이 크게 죽는다 (Mask `generated_input_ports()` 의 Shape 판).

**재지 못한다 (이름을 적는다 — 여기 없는 것은 미측정이지 통과가 아니다)**
  1. **형상 B/C 와의 실제 대조** — `Wt64Config(nPoints=2)` 로 두 번째 SV 를
     내는 생성기가 없다 (`rtl/spinal/.../gen/` 에 `GenWt64TopShape.scala`
     부재 — 실측). 선례는 있다 (`GenSharedUnit.scala:23-26` 이 같은 패턴으로
     `SharedUnitDepth0.sv` 를 낸다). 그 20줄이 착지하기 전까지 ISA-1 의
     **형상 축은 미측정**이다. 이 파일은 비교기를 세우고 그것이 살아 있음을
     `isa1_comparator_selfcheck` 로 매 실행 증명하되, **형상 축을 잰 척하지
     않는다.**
  2. **ISA-2 자리 축** — LNID 엔트리의 소유 지점 `[23:16]` 순열과 LBID
     엔트리의 슬롯 구간 `[15:0]` 순열은 **관측면이 없다.** RouteJudge 는
     지점별 소유를 구조적으로 모르고(`RouteJudge.scala:145` — missLnid 는
     `!viewHit` 뿐), 구간값의 소비자인 `Reassembly.wr → ResultBank.write` 가
     미배선이다(`Wt64Top.scala:83` 「Reassembly.wr → ResultBank.write 는 **미배선**이다」 — TODO 1항). MMIO 되읽기는 *저장* 확인이지
     *사상 경유* 확인이 아니다. ⇒ **ISA-2 는 「존재 축」만 닫히고 「자리 축」은
     열린 채 남는다.** 부록 D 에 ISA-2 를 「증명됨」으로 올리면 안 되고
     「부분 — 존재 축만」이 정직한 지위다.
  3. **OPREF B 참조의 LBID 축** — 제시 자체가 없다 (`Wt64Top.scala:86` 「OPREF B 토큰의 RouteJudge 제시는 미배선」 · TODO 2항,
     tokIn 은 사이클당 하나). ISA-2 α 는 **OPREF A 축만** 덮는다.
  4. **끝-끝 수치 등가** — 데이터패스 소비자 다수가 미착지 IO 수출이다
     (`Wt64Top.scala:97` 「SharedUnit 요청(dispatch 방향)」 — 같은 TODO 5항). 지금 대조 가능한 「결과」는 판정·fault·디코드
     방출면이지 **연산 결과값이 아니다.** ISA-1 을 「수치가 같다」로 인쇄하면
     거짓이다.
  5. **`slotCap`·`outDepth`·`ownL`·`bodyW` 축의 두-형상** — 이들은 관측면의
     *폭*이나 *지연*을 바꾸므로 위 등가 정의(ⓐ/ⓑ/ⓒ)가 정본에서 닫히기 전에는
     비교 규칙 자체가 정해지지 않는다. 1라운드 형상축을 `nPoints` 로 한정하는
     이유가 이것이고, 이 한정은 결함이 아니라 미확정에 대한 정직한 처분이다.

**금지** — 마스크·통계·`!=` 형태의 판정. ISA-2 를 `F(S') != F(S)` 로 쓰면
그것이 정본이 이름한 「틀린 값도 다르다」 그 자체다. 판정은 언제나
**예측 벡터와의 바이트 동일성**이다.
"""

import os
import re
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

REPO = Path(os.environ["WT_REPO"])
TOP_SV = REPO / "rtl" / "generated" / "Wt64Top.sv"

CLK_NS = 4
SETTLE_NS = 1

# ── MMIO 구역 (정본 §3.7.1 배치, RTL 이행 `hiu/MmioConfig.scala:144-145`) ──
LNID_TBL_BASE = 0x400   # 256 × 4B — [31]V [30:24]예약0 [23:16]소유지점 [15:0]LNID
LBID_TBL_BASE = 0x800   # 256 × 4B — [31]V [30:16]예약0 [15:8]슬롯구간 [7:0]길이

# 형상 A 의 용량 — `MmioConfig.scala:199` capSlots = viewEntries.min(256),
# `Common.scala` viewEntries = 4 * nPoints = 16. 형상축이 바뀌면 이 수가 바뀐다.
N_POINTS = 4
CAP_SLOTS = 4 * N_POINTS

# ── 소거 구간 — **실측으로 못박은 상수** ──────────────────────────────────
# `MmioConfig.scala:239-245` 의 `initCnt` 폭이 `Isa.LNID_W`=16 이고
# `io.ready := initDone && !busy` (:283). 그 전 기입은 수락되지 않는다.
#
# ⚠ 함정 (이 하네스를 짜다 실제로 밟았다): `io.mmio.ready` 의 **기본값은
#   True** 이고 (`Wt64Top.scala:1593` 「io.mmio.ready := True」) 몇 구역에서만 덮인다
#   (구성 구역은 `cfgBlk.io.ready`). ⇒ 예약 오프셋(예: addr=0)에서 ready 를 폴링하면 **reset
#   해제 직후 0 사이클 만에 1 이 읽힌다.** 그것을 「소거 끝」으로 읽으면 이후
#   구성 기입이 통째로 무시된 채 본시험이 돌고, 그 결과는 「구성했다고 믿는데
#   안 된」 상태다. 폴링은 반드시 **구성 구역 주소로** 한다.
INIT_SWEEP = 1 << 16

# ── ISA-1 대조면 ──────────────────────────────────────────────────────────
# 형상 의존 출력은 `io_push_i_stall` 뿐이다 (형상 A 는 lane 0..2, 형상 C
# (nPoints=2)는 lane 0 만 — 나머지 출력의 존재도 폭도 nPoints 의 함수가
# 아니다). 그 둘을 대조면에서 빼고 나머지 전부를 사이클마다 통째로 비교한다.
SHAPE_DEPENDENT = {"io_push_1_stall", "io_push_2_stall"}
# 드리프트가 조용하지 않게 못박는다 — 포트가 늘거나 줄면 여기서 크게 깨진다.
# 재유도 기록 (인코딩 개정 파도 W4): io_dec_acctgtTotal 신설 (+1) — ACCTGT
# [23:16] = 조각열 선언 총개수 T 의 관측 수출 (§1.4.7, 무소비). 형상 무관
# 출력이라 대조면에 든다 — 117/115 → 118/116.
# 재유도 기록 (CAP_STATUS 파도): io_fault_ehCapAbsent 신설 (+1) — 형상 무관
# 출력이라 대조면에 든다 — 118/116 → 119/117.
# 재유도 기록 (파도 3 — 변환 저장소의 MMIO 문): 최상위 IO `io.install` ·
# `io.flush` 은퇴 (설치 authority 는 0xC00/0xE00 MMIO 문 하나). 출력 하나
# (io_install_ready) 가 사라지고 입력 열 개(install 여덟 — valid · part · idx
# · tag · frame · perm_r/w/x — 와 flush 둘 — valid · part)가 사라진다 —
# 119/117 → 118/116. (착지판 문면은 「열한 개」였다 — 출력 하나까지 센 포트
# 선언 줄 수였다. HEAD e90d3f1 생성물 포트 목록에서 재계수, 2026-09-26.)
# 재유도 기록 (파도 4 페이지 통합 — D1 (b)): io_fault_fpCfgBadWrite 신설 (+1) — FP_BIND
# 예약 거절의 수락 게이트된 sticky. 형상 무관 출력이라 대조면에 든다 — 118/116 → 119/117.
# 재유도 기록 (태그 코덱 전파 파도): 태그 번들의 thread 16b 한 포트가 epoch · poison · trace
# 세 포트가 됐다 — 출력 쪽은 io_route_tokOut_payload_tag_* 하나(+2). 형상 무관 — 119/117 → 121/119.
# 재유도 기록 (W1 표면 비트·워드 — 3.10 v1.0 묶음): io_fault_hiuOwn 신설 (+1) — FAULT_STATUS
# [19] 원천별 수출, IO 해제선 없음(0xF84 [19] 로만 내려간다 → NO_IO_CLEAR 6 → 7). 0xEC4 캡처는
# MaskUnit 안이라 최상위 포트가 늘지 않았고 입력 집합도 그대로다(120). 형상 무관 — 121/119 →
# 122/120 (W1 통합 생성물 포트 목록에서 실측, 2026-10-11).
EXPECT_OUTPUTS = 122
EXPECT_COMPARE_FACE = 120


def parse_clear_ports():
    """`io_faultClear_*` 입력 전량. 손 표를 두지 않는다 — 축이 하나 늘면
    손 표는 조용히 옛 축만 해제하고, 그러면 궤적 대조가 **역사 차이**를
    형상 차이로 오독한다 (아래 `clear_all_faults` 주석)."""
    names = []
    for line in TOP_SV.read_text().splitlines():
        m = re.match(r"^\s{2}input\s+wire\s*(?:\[[^\]]+\])?\s*(io_faultClear_\w+)\s*,?\s*$", line)
        if m:
            names.append(m.group(1))
        if line.startswith(");"):
            break
    return names


def parse_output_ports():
    """생성물의 포트 선언에서 출력 이름을 뽑는다.

    표를 손으로 적지 않는다 — 손 표는 생성물이 바뀌어도 조용히 옛 면을 본다.
    대신 **개수를 못박아** 드리프트를 크게 만든다.
    """
    names = []
    for line in TOP_SV.read_text().splitlines():
        m = re.match(r"^\s{2}output\s+(?:wire|reg)\s*(?:\[[^\]]+\])?\s*(\w+)\s*,?\s*$", line)
        if m:
            names.append(m.group(1))
        if line.startswith(");"):
            break
    return names


def parse_input_ports():
    """생성물 머리(첫 모듈 = Wt64Top)의 입력 이름 전량과 `input` 줄 수.

    둘을 함께 돌려주는 이유: 정규식이 어떤 `input` 줄(예: 새 꼴의 폭 선언)을
    흘리면 그 포트는 정의역 대조 밖에 조용히 태어난다. `zero_inputs` 가 두 수의
    등식을 매번 본다.
    """
    names, raw = [], 0
    for line in TOP_SV.read_text().splitlines():
        if re.match(r"^\s*input\b", line):
            raw += 1
        m = re.match(r"^\s{2}input\s+wire\s*(?:\[[^\]]+\])?\s*(\w+)\s*,?\s*$", line)
        if m:
            names.append(m.group(1))
        if line.startswith(");"):
            break
    return names, raw


OUT_PORTS = parse_output_ports()
CLEAR_PORTS = parse_clear_ports()
IN_PORTS, IN_PORT_LINES = parse_input_ports()
COMPARE_FACE = [n for n in OUT_PORTS if n not in SHAPE_DEPENDENT]

# 해제선이 없는 sticky — 여기 있는 것은 IO 해제선이 아니라 **MMIO 로만**
# 내려간다 (Wt64Top: `own.io.faultClearBadWrite`·`cq.io.faultClearOverflow`·
# `cq.io.faultClearBadWrite` 는 `fclr(…)` 만 받고, `fpCapAbsent`·`ehCapAbsent`
# 는 `capWord.io.word` 라 해제가 `capWord.io.clrAcc` 뿐). 궤적 대조 전에 IO 만
# 흔들면 이 축들은 sticky 로 남고, 그 잔재가 다음 궤적의 시작 상태를 바꾼다.
# `fpCfgBadWrite` 는 0xF84[6] 로만 내려간다 (D1 (b) — IO 해제선을 새로 만들지 않았다). 궤적 대조
# 시험의 자극은 이 일곱을 세우지 않으므로 지금은 무해하지만, 세우는 자극이
# 추가되면 여기가 먼저 깨져야 한다 — 그래서 이름으로 적어 둔다.
# W1 의 `hiuOwn`([19])도 이 부류다 — `hiu.faultOwnClear` 는 `fclr(19)` 하나만 받는다(IO 해제선을
# 만들지 않는다는 표면 이후 축의 규율). 이 목록의 *이름*도 `compare_face_is_pinned` 가 생성물의
# 「같은 이름 해제선이 없는 fault 출력」 집합과 등식으로 대조한다 — 수의 등식만으로는 이름이
# 바뀐 축을 못 본다.
NO_IO_CLEAR = ["io_fault_ownBadWrite", "io_fault_cqOverflow",
               "io_fault_cqBadWrite", "io_fault_fpCapAbsent",
               "io_fault_ehCapAbsent", "io_fault_fpCfgBadWrite",
               "io_fault_hiuOwn"]
EXPECT_CLEAR_PORTS = 19

# 자주 보는 자리의 색인 — 매번 `.index()` 하면 이름 오타가 ValueError 로만
# 드러나고 그것은 실행 중반이다. 임포트 시점에 크게 깨지게 둔다.
_IX_TOK = COMPARE_FACE.index("io_route_tokOut_valid")
_IX_FF = COMPARE_FACE.index("io_route_faultFire")
_IX_DECV = COMPARE_FACE.index("io_dec_valid")
_IX_EXEC = COMPARE_FACE.index("io_dec_execValid")
_IX_MAL = COMPARE_FACE.index("io_dec_malformed")
_IX_CAP = COMPARE_FACE.index("io_dec_capAbsent")


# ── 명령 공급 ─────────────────────────────────────────────────────────────
# `asm/wavetensor_asm.py` `encode_pass` 가 명령마다 448비트 정수를 낸다
# (인코딩 개정 파도 W8 — EH≥1 이면 word1 = CH, 최대 14워드). top 의 명령
# 포트는 14워드 × 32b = 448b (`Wt64Top.scala` io.instr.words = walk.maxWords)
# — 정확히 맞는다. 워드 0 이 최하위다.
#
# ⚠ **「같은 바이너리」의 단위는 (명령 워드열, 태그) 쌍이다.** 라우팅되는
#   LNID 는 **태그**의 것이지 명령 인코딩의 것이 아니다 (`Wt64Top.scala:965` 「rj.io.tokIn.payload.tag     := tagQ」
#   — `tagQ = RegNext(io.instr.tag)`).
#   정본 §1.1 이 태그를 「명령어 인코딩의 일부가 아니라」고 못박았으므로
#   어셈블러는 태그를 방출하지 않는다. 「어셈블러가 다 준다」고 적으면 거짓이다.
#   ⇒ 태그는 이 하네스가 벡터로 든다. 그리고 **80b 로 팩하지 않는다** — 팩킹
#   순서는 구현 자유이고 ABI 가 아니다(`Common.scala:120-127` — 정본 1.4.4), top 이 필드별
#   포트로 받으므로 팩킹을 알 필요가 없다. 팩하는 순간 장치 내부 표현이 시험 코드로 굳는다.
INSTR_WORDS = 14
ASM_SRC = ("ACC_ELEMWISE prec .port dest=0x10 .precision mode=0x14 "
           ".opref kind={kind} route={lbid}")

_enc_cache = {}


def descriptor(lbid, src_kind):
    """명령 워드열 하나. 어셈블러가 유일한 인코딩 출처다."""
    key = (lbid, src_kind)
    if key not in _enc_cache:
        import wavetensor_asm
        enc = wavetensor_asm.assemble(
            ASM_SRC.format(kind=src_kind, lbid=hex(lbid)))
        assert len(enc) == 1, f"명령 1개를 기대했는데 {len(enc)}개가 나왔다"
        _enc_cache[key] = [(enc[0] >> (32 * i)) & 0xFFFFFFFF
                           for i in range(INSTR_WORDS)]
    return _enc_cache[key]


# ═══════════════════════════════════════════════════════════════════════════
# 구동 원시 연산
# ═══════════════════════════════════════════════════════════════════════════

async def step(dut, n=1):
    for _ in range(n):
        await RisingEdge(dut.clk)
        await Timer(SETTLE_NS, "ns")


async def settle(dut):
    """드라이브 뒤 조합 정착 — 다음 엣지까지는 여전히 여유가 있다."""
    await Timer(SETTLE_NS, "ns")


# ⚠ 이 목록이 `zero_inputs` 의 초기화 정의역이다 (W1 — Mask 하네스
#   `generated_input_ports()` 의 Shape 판). 포트가 늘었는데 여기 없으면 Verilator
#   미구동 입력은 0 으로 남고, 그 0 이 *뜻을 가진 채* 시험이 조용히 다른 계약을
#   잰다 — Mask 의 `io_keyWr_part` 가 정확히 그렇게 빠져 있었다 (README 함정 ⑥).
#   이 파도들은 최상위 입력을 빼고(`io_hiuReq_part` 은퇴 예정) 더한다. 그래서
#   `zero_inputs` 가 생성물 머리의 입력 집합과 이 목록을 **매 부팅 기계로**
#   대조한다 (누락 · 잉여 = 전 시험 FAIL). 주석은 호출이 아니다.
#   `io_faultClear_*` 는 여기 적지 않는다 — 위 `parse_clear_ports()` 가 접두로
#   거두고(손 표 금지 — 그 주석), 0 이 곧 제품 결선 값이며(해제선은 0 으로
#   묶인다), 그 계수는 `compare_face_is_pinned` 가 못박는다.
_TAG_FIELDS = ("wave", "epoch", "poison", "trace", "lnid", "precision", "dim")
SHAPE_INPUTS = (
    ["io_instr_valid"]
    + [f"io_instr_words_{i}" for i in range(INSTR_WORDS)]
    + [f"io_instr_tag_{n}" for n in _TAG_FIELDS]
    + [f"io_mem_cfgPreds_{i}" for i in range(4)]
    + ["io_mem_epochClear", "io_mem_complete", "io_mem_slotSel"]
    + [f"io_mem_down_{i}_ready" for i in range(4)]
    + ["io_hiuReq_valid", "io_hiuReq_part", "io_hiuReq_vpn", "io_hiuReq_write",
       "io_hiuHold", "io_hostRsp_valid", "io_hostRsp_frame",
       "io_hostRsp_perm_r", "io_hostRsp_perm_w", "io_hostRsp_perm_x"]
    + [f"io_push_{i}_{n}" for i in range(3)
       for n in (["strb"] + [f"result_head_tag_{t}" for t in _TAG_FIELDS]
                 + ["result_head_seq", "result_head_total", "result_head_last",
                    "result_body"])]
    + ["io_sharedReq_valid", "io_sharedReq_payload"]
    + ["io_bank_acqValid", "io_bank_acqSlot", "io_bank_acqProd", "io_bank_wrValid",
       "io_bank_wrSlot", "io_bank_wrProd", "io_bank_wrData", "io_bank_rdSlot"]
    + ["io_fp_reqValid", "io_fp_opKind", "io_fp_precision", "io_fp_a", "io_fp_b", "io_fp_c"]
    + ["io_mmio_addr", "io_mmio_wstrobe", "io_mmio_wdata", "io_mmio_rstrobe"]
)


def zero_inputs(dut):
    # 포트 정의역 대조 — 위 `SHAPE_INPUTS` 주석. 파서가 줄을 흘리지 않았는지가 먼저다.
    assert len(IN_PORTS) == IN_PORT_LINES, (
        f"생성물 머리의 input 줄 {IN_PORT_LINES} 중 {len(IN_PORTS)} 만 읽었다 — "
        f"파서가 줄을 흘리면 그 포트는 정의역 대조 밖에 태어난다")
    assert len(set(SHAPE_INPUTS)) == len(SHAPE_INPUTS), "SHAPE_INPUTS 에 중복 이름이 있다"
    gen = set(IN_PORTS) - {"clk", "reset"}
    want = set(SHAPE_INPUTS) | set(CLEAR_PORTS)
    assert gen == want, (
        f"SHAPE_INPUTS(+ io_faultClear_*) 가 생성물 입력 포트와 다르다 — 누락 "
        f"{sorted(gen - want)} · 잉여 {sorted(want - gen)}. 미구동 입력은 0 으로 남아 "
        f"그 0 이 뜻을 가진 채 시험이 조용히 다른 계약을 잰다 (README 함정 ⑥ 의 Shape 판)")
    for n in SHAPE_INPUTS:
        getattr(dut, n).value = 0
    for n in CLEAR_PORTS:
        getattr(dut, n).value = 0


async def boot(dut):
    """reset + **구성 구역 주소로** 소거 완료 대기.

    소거 대기를 예약 오프셋에서 하면 0 사이클에 끝난 것처럼 보인다 (위
    `INIT_SWEEP` 주석의 함정). 그래서 폴링 주소를 구성 구역에 둔다.
    """
    zero_inputs(dut)
    # 클럭은 **테스트마다** 새로 띄운다. cocotb 2.0 은 테스트가 끝날 때 그
    # 테스트가 `start_soon` 한 태스크를 전부 취소하므로, 「한 번만 띄우고
    # 재사용」은 성립하지 않는다 — 두 번째 테스트에서 클럭이 죽은 채로 돌고,
    # 그 실패는 **예외 없이** 온다 (RisingEdge 가 영영 안 와서 시뮬이
    # $finish 하고 남은 테스트가 message 빈 FAIL 로 무너진다. 실측으로 밟았다).
    # 미완료 로그를 통과로 읽지 않는 것과 같은 자리다 — 조용한 정지가 가장 나쁘다.
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.reset.value = 1
    await step(dut, 3)
    dut.reset.value = 0
    await step(dut)

    dut.io_mmio_addr.value = LNID_TBL_BASE
    await settle(dut)
    n = 0
    while int(dut.io_mmio_ready.value) == 0:
        await step(dut)
        n += 1
        if n > INIT_SWEEP + 64:
            raise AssertionError(
                f"구성 구역 ready 가 {n} 엣지 안에 서지 않았다 — 미완료는 통과가 아니다")
    assert n >= INIT_SWEEP - 8, (
        f"소거 구간이 {n} 엣지밖에 안 됐다 (기대 ≈{INIT_SWEEP}). ready 를 구성 "
        f"구역 밖 주소에서 읽고 있지 않은지 확인하라 — 그 오독이 구성 전량을 "
        f"무시된 채로 만든다")
    dut.io_mmio_addr.value = 0
    await step(dut)
    return n


async def mmio_write(dut, addr, data):
    """워드 하나 기입. `ready` 가 설 때까지 wstrobe 를 유지한다.

    `acceptW = wstrobe && ready` (`MmioConfig.scala`) — ready 를 안 보고
    한 박만 쏘면 LNID 기입의 CHECK 사이클(busy)과 겹쳤을 때 **조용히 사라진다.**
    """
    dut.io_mmio_addr.value = addr
    dut.io_mmio_wdata.value = data
    dut.io_mmio_wstrobe.value = 1
    await settle(dut)
    for _ in range(8):
        if int(dut.io_mmio_ready.value):
            break
        await step(dut)
    else:
        raise AssertionError(f"mmio_write(0x{addr:03X}): ready 가 8엣지 안에 안 섰다")
    await step(dut)          # 수락 엣지
    dut.io_mmio_wstrobe.value = 0
    await step(dut)          # LNID 축의 CHECK(busy) 사이클
    await settle(dut)


async def mmio_read(dut, addr):
    dut.io_mmio_addr.value = addr
    dut.io_mmio_rstrobe.value = 1
    await settle(dut)
    await step(dut)
    dut.io_mmio_rstrobe.value = 0
    assert int(dut.io_mmio_rvalid.value) == 1, f"읽기 0x{addr:03X} 에 rvalid 가 없다"
    v = int(dut.io_mmio_rdata.value)
    await step(dut)
    return v


def lnid_word(valid, point, lnid):
    return (int(valid) << 31) | ((point & 0xFF) << 16) | (lnid & 0xFFFF)


def lbid_word(valid, span=0, length=0):
    return (int(valid) << 31) | ((span & 0xFF) << 8) | (length & 0xFF)


async def clear_all_faults(dut):
    """IO 해제선 전량을 한 박 세운다 — **궤적 대조의 전제**.

    ⚠ sticky fault 는 *역사의 누적*이다. 두 궤적을 따로 돌려 사이클 정확
      비교를 하려면 시작 상태가 같아야 하는데, 앞 궤적이 세운 sticky 가
      남으면 **역사 차이가 형상 차이로 오독된다.** 이 하네스를 짜다 실제로
      밟았다 — `isa1_place_independence` 가 `io_fault_route` 한 자리에서
      갈렸고, 그것은 배치 A 에서 뷰 미적중이 세워 둔 잔재였지 자리 결속이
      아니었다.

      sticky 를 대조면에서 **빼는** 것으로 풀지 않는다. 그것은 관측면을
      줄이는 것이고, 줄인 만큼이 미측정이 된다. 역사를 맞추는 것이 옳다.
    """
    for n in CLEAR_PORTS:
        getattr(dut, n).value = 1
    await step(dut)
    for n in CLEAR_PORTS:
        getattr(dut, n).value = 0
    await step(dut)
    for n in NO_IO_CLEAR:
        assert int(getattr(dut, n).value) == 0, (
            f"{n} 이 서 있는데 IO 해제선이 없다 — 이 축은 MMIO(0xF84/0xF90)로만 "
            f"내려간다. 궤적의 시작 상태가 어긋난 채 대조가 돈다")


async def clear_cfg_faults(dut):
    dut.io_faultClear_cfgBadWrite.value = 1
    dut.io_faultClear_cfgDupOwner.value = 1
    await step(dut)
    dut.io_faultClear_cfgBadWrite.value = 0
    dut.io_faultClear_cfgDupOwner.value = 0
    await step(dut)
    assert int(dut.io_fault_cfgBadWrite.value) == 0
    assert int(dut.io_fault_cfgDupOwner.value) == 0


async def assert_cfg_clean(dut, what):
    """**구성 무결성 게이트.** 매 구성 뒤에 부른다.

    이것이 없으면 「구성했다고 믿는데 안 된」 상태로 본시험이 돌고, 0건
    불일치가 「일치했다」와 「구성이 통째로 거절됐다」를 구별하지 못한다.
    """
    bad = int(dut.io_fault_cfgBadWrite.value)
    dup = int(dut.io_fault_cfgDupOwner.value)
    assert bad == 0 and dup == 0, (
        f"{what}: 구성 기입이 거절됐다 (cfgBadWrite={bad} cfgDupOwner={dup}) — "
        f"이 상태로 이어지는 판정은 무의미하다")


async def install_view(dut, pairs):
    """LNID 뷰 구성. `pairs` = [(slot, point, lnid), …]"""
    for slot, point, lnid in pairs:
        assert slot < CAP_SLOTS, f"슬롯 {slot} ≥ capSlots {CAP_SLOTS} — 거절될 기입이다"
        assert point < N_POINTS, f"지점 {point} ≥ nPoints {N_POINTS} — 거절될 기입이다"
        await mmio_write(dut, LNID_TBL_BASE + 4 * slot, lnid_word(1, point, lnid))
    await assert_cfg_clean(dut, f"install_view({len(pairs)}건)")


async def clear_view(dut, slots):
    for slot in slots:
        await mmio_write(dut, LNID_TBL_BASE + 4 * slot, lnid_word(0, 0, 0))
    await assert_cfg_clean(dut, "clear_view")


async def install_banks(dut, lbids, universe):
    """LBID 사상 존재 집합 구성 — `universe` 안에서 `lbids` 만 존재로 만든다."""
    for b in universe:
        await mmio_write(dut, LBID_TBL_BASE + 4 * b,
                         lbid_word(1 if b in lbids else 0))
    await assert_cfg_clean(dut, f"install_banks({len(lbids)}/{len(universe)})")


# ═══════════════════════════════════════════════════════════════════════════
# 궤적 — ISA-1/ISA-2 의 공통 관측 원시 연산
# ═══════════════════════════════════════════════════════════════════════════

async def present(dut, words, lnid, epoch=0, wave=0):
    """명령 디스크립터 하나를 제시하고 **그 엣지**의 관측면 전체를 뜬다.

    ⚠ **표본 엣지 = 방출 엣지다 (실측).** 디코드 사슬은 레지스터 한 단이고
      (`DecodeWalk` 방출단 + `tagQ = RegNext(io.instr.tag)` 정렬,
      `Wt64Top.scala:929` 「private val tagQ = RegNext(io.instr.tag)」), `OperandDecode` 는 그 위의 조합이다. 값을
      엣지 **전에** 세워 두면 그 엣지에서 `io_dec_valid` ·
      `io_route_tokOut_valid` · `io_route_faultFire` 가 함께 선다.

      한 엣지 늦게 뜨면 관측면은 전부 0 이고 — **그리고 궤적 비교는 그래도
      통과한다.** 0 == 0 이기 때문이다. 이 하네스를 짜다 실제로 밟았고,
      `isa1_place_independence` 가 공허하게 초록이었다. 그 형태를 막는 것이
      아래 `require_token` 이다: 전건이 실제로 성립했는지를 **매 제시마다**
      확인한다. 전건 없는 비교는 비교가 아니다.
    """
    for i, w in enumerate(words):
        getattr(dut, f"io_instr_words_{i}").value = w
    dut.io_instr_tag_lnid.value = lnid
    dut.io_instr_tag_epoch.value = epoch
    dut.io_instr_tag_wave.value = wave
    dut.io_instr_valid.value = 1
    await step(dut)                     # ← 표본 엣지이자 방출 엣지
    snap = snapshot(dut)
    dut.io_instr_valid.value = 0
    for i in range(INSTR_WORDS):
        getattr(dut, f"io_instr_words_{i}").value = 0
    dut.io_instr_tag_lnid.value = 0
    dut.io_instr_tag_epoch.value = 0
    dut.io_instr_tag_wave.value = 0

    # 전건 확인 — 궤적이 통째로 0 인 채 「일치」하는 공허를 여기서 끊는다.
    if snap[_IX_TOK] != 1:
        raise AssertionError(
            f"lnid={lnid:#x}: 제시 엣지에 토큰이 나오지 않았다 "
            f"(dec_valid={snap[_IX_DECV]} exec={snap[_IX_EXEC]} "
            f"malformed={snap[_IX_MAL]} capAbsent={snap[_IX_CAP]}). "
            f"전건이 성립하지 않은 궤적은 비교 대상이 아니다 — 0끼리 일치하는 "
            f"것을 통과로 읽는 자리다")
    if snap[_IX_MAL] or snap[_IX_CAP]:
        raise AssertionError(
            f"lnid={lnid:#x}: 디코드가 malformed={snap[_IX_MAL]} "
            f"capAbsent={snap[_IX_CAP]} — 자극이 의도한 명령이 아니다")
    return snap


def snapshot(dut):
    """대조면 전량을 한 튜플로. 사이클 정확 비교(ⓒ)의 단위다."""
    return tuple(int(getattr(dut, n).value) for n in COMPARE_FACE)


async def judge_vector(dut, lbids, src_kind, lnid):
    """LBID 축 훑기 — 각 lbid 에 대한 `io_route_faultFire` 1비트 벡터.

    faultFire 는 **사이클 발화**다. sticky `io_fault_route` 를 보면 첫 미스
    이후 전부 1 이라 벡터가 무의미해진다 — 여기서 sticky 를 쓰지 않는 이유다.
    """
    out = []
    for b in lbids:
        snap = await present(dut, descriptor(b, src_kind), lnid)
        out.append(snap[_IX_FF])
    return tuple(out)


async def judge_vector_lnid(dut, lnids):
    """LNID 축 훑기 — srcKind=0 이라 LBID 축은 불참한다
    (`Wt64Top.scala:960` 「OPREF 부재 명령은 srcKind = 0(직접, 게이트 산출 0)이라」)."""
    words = descriptor(0, 0)
    out = []
    for n in lnids:
        snap = await present(dut, words, n)
        out.append(snap[_IX_FF])
    return tuple(out)


# ═══════════════════════════════════════════════════════════════════════════
# 테스트
# ═══════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def cfg_surface_integrity(dut):
    """**반-공허 게이트.** 구성 표면이 실제로 살아 있는가.

    이것이 먼저 서지 않으면 이하 ISA-2 의 「예측과 일치」는 「구성이 통째로
    거절됐고 전부 미스라 예측이 우연히 맞았다」와 구별되지 않는다.

    보는 것 넷:
      ① 소거 구간이 실제로 존재한다 (예약 오프셋 폴링 함정의 차단)
      ② 합법 기입이 수락되고 되읽힌다
      ③ 거절 4부류가 **전부** `cfgBadWrite` 를 세운다 — 거절선이 죽어 있으면
         「용량 밖 슬롯에 썼는데 조용히 통과」가 된다
      ④ 서로소 위반(D2)이 `cfgDupOwner` 를 세운다
    """
    sweep = await boot(dut)
    dut._log.info(f"소거 구간 실측: 구성 구역 ready 까지 {sweep} 엣지 "
                  f"(initCnt 폭 = Isa.LNID_W = 16 ⇒ {INIT_SWEEP})")
    assert int(dut.io_fault_cfgBadWrite.value) == 0

    # ② 합법 기입 → 되읽기
    await mmio_write(dut, LNID_TBL_BASE + 4 * 3, lnid_word(1, 2, 0xBEEF))
    await assert_cfg_clean(dut, "합법 LNID 기입")
    rb = await mmio_read(dut, LNID_TBL_BASE + 4 * 3)
    assert rb == lnid_word(1, 2, 0xBEEF), (
        f"되읽기 0x{rb:08X} ≠ 기입 0x{lnid_word(1,2,0xBEEF):08X}")

    # ③ 거절 4부류 — 하나씩, 매번 해제하고 다시 본다.
    rejects = [
        ("용량 밖 슬롯", LNID_TBL_BASE + 4 * CAP_SLOTS, lnid_word(1, 0, 0x11)),
        ("없는 지점", LNID_TBL_BASE + 4 * 5, lnid_word(1, N_POINTS, 0x12)),
        ("예약 비트 비0", LNID_TBL_BASE + 4 * 6, lnid_word(1, 0, 0x13) | (1 << 24)),
        ("점유 슬롯 재기입", LNID_TBL_BASE + 4 * 3, lnid_word(1, 1, 0x14)),
        ("LBID 예약 비트 비0", LBID_TBL_BASE + 4 * 7, lbid_word(1) | (1 << 16)),
    ]
    for what, addr, word in rejects:
        await clear_cfg_faults(dut)
        await mmio_write(dut, addr, word)
        assert int(dut.io_fault_cfgBadWrite.value) == 1, (
            f"거절 부류 「{what}」 (0x{addr:03X} ← 0x{word:08X}) 가 "
            f"cfgBadWrite 를 세우지 않았다 — 거절선이 죽어 있으면 이후 모든 "
            f"구성이 조용히 무시될 수 있다")

    # ④ 서로소 위반 — 이미 슬롯 3 이 소유한 LNID 를 슬롯 4 에 등록
    await clear_cfg_faults(dut)
    await mmio_write(dut, LNID_TBL_BASE + 4 * 4, lnid_word(1, 0, 0xBEEF))
    assert int(dut.io_fault_cfgDupOwner.value) == 1, (
        "같은 LNID 를 두 슬롯이 소유하는데 cfgDupOwner 가 서지 않았다 (D2)")
    assert int(dut.io_fault_cfgBadWrite.value) == 0, (
        "D2 가 cfgBadWrite 로 접혔다 — 두 축은 수리 동작이 다르므로 접지 않는다")

    dut._log.info(
        f"구성 표면: 소거 {sweep}엣지 · 수락+되읽기 · 거절 {len(rejects)}부류 loud · "
        f"D2 분리 확인. 대조면 {len(COMPARE_FACE)}/{len(OUT_PORTS)} 출력")


@cocotb.test()
async def compare_face_is_pinned(dut):
    """대조면의 크기를 못박는다 — 드리프트가 조용하지 않게.

    ISA-1 비교가 「무엇을 보지 않는가」를 코드에 두는 자리다. 형상 의존 출력
    둘(`io_push_1_stall`·`io_push_2_stall`)만 빠지고 나머지 전부가 비교면이다.
    """
    assert len(OUT_PORTS) == EXPECT_OUTPUTS, (
        f"생성물 출력 포트 {len(OUT_PORTS)} ≠ 못박은 {EXPECT_OUTPUTS} — "
        f"생성물이 바뀌었다. 대조면 정의를 다시 유도하라")
    assert len(COMPARE_FACE) == EXPECT_COMPARE_FACE, (
        f"대조면 {len(COMPARE_FACE)} ≠ 못박은 {EXPECT_COMPARE_FACE}")
    assert len(CLEAR_PORTS) == EXPECT_CLEAR_PORTS, (
        f"IO 해제선 {len(CLEAR_PORTS)} ≠ 못박은 {EXPECT_CLEAR_PORTS} — 역사 정렬이 "
        f"덮지 못하는 sticky 가 생겼을 수 있다")
    n_fault_out = len([n for n in OUT_PORTS if n.startswith("io_fault_")])
    assert n_fault_out - len(CLEAR_PORTS) == len(NO_IO_CLEAR), (
        f"fault 출력 {n_fault_out} − IO 해제선 {len(CLEAR_PORTS)} ≠ "
        f"MMIO 전용 {len(NO_IO_CLEAR)}축 — 해제 경로 비대칭 표가 낡았다")
    # 이름 등식 (W1) — 해제선 `io_faultClear_X` 는 fault 출력 `io_fault_X` 의 해제다. 짝 없는
    # 해제선이 없어야 하고, 짝 없는 fault 출력의 집합이 곧 NO_IO_CLEAR 다.
    axes = {n[len("io_faultClear_"):] for n in CLEAR_PORTS}
    orphan = sorted(a for a in axes if f"io_fault_{a}" not in OUT_PORTS)
    assert not orphan, f"짝 fault 출력이 없는 IO 해제선: {orphan}"
    no_clr = sorted(n for n in OUT_PORTS
                    if n.startswith("io_fault_") and n[len("io_fault_"):] not in axes)
    assert no_clr == sorted(NO_IO_CLEAR), (
        f"해제선이 없는 fault 출력 {no_clr} ≠ NO_IO_CLEAR {sorted(NO_IO_CLEAR)} — 해제 경로 "
        f"비대칭 표의 이름이 낡았다 (clear_all_faults 가 MMIO 전용 축을 잘못 지목한다)")
    for n in SHAPE_DEPENDENT:
        assert n in OUT_PORTS, f"형상 의존 출력 {n} 이 생성물에 없다 — 표가 낡았다"
        assert n not in COMPARE_FACE
    # 관측 핸들이 실제로 존재하는가 — 이름만 맞고 peek 이 안 되면 비교가 죽는다.
    missing = [n for n in COMPARE_FACE if not hasattr(dut, n)]
    assert not missing, f"대조면 포트인데 핸들이 없다: {missing}"
    dut._log.info(
        f"대조면 고정: 출력 {len(OUT_PORTS)} 중 {len(COMPARE_FACE)} 비교 · "
        f"제외 {sorted(SHAPE_DEPENDENT)} (형상 의존 — nPoints 의 함수)")


@cocotb.test()
async def isa2_alpha_lbid_permutation(dut):
    """ISA-2 α — LBID 존재 집합의 순열. **예측 벡터와 정확 비교.**

    판정식: lbid b 에 대해 fault ⟺ b ∉ S. 순열 σ 를 걸어 S' = σ(S) 로 재구성
    하면 벡터는 `predict(σ(S))` 여야 한다. `F(S') != F(S)` 로 쓰지 않는다 —
    그것이 「틀린 값도 다르다」다.
    """
    await boot(dut)
    lnid = 0x0A0A
    await install_view(dut, [(0, 0, lnid)])

    universe = list(range(32))
    S = {1, 4, 5, 9, 16, 17, 30}
    await install_banks(dut, S, universe)
    F = await judge_vector(dut, universe, src_kind=1, lnid=lnid)
    pred = tuple(0 if b in S else 1 for b in universe)
    assert F == pred, (
        f"기준 구성에서 판정 벡터가 예측과 다르다\n  got  {F}\n  pred {pred}")

    # σ — 항등이 아닌 순열. 존재 집합의 상(image)이 실제로 다른지 먼저 본다.
    sigma = {b: (b * 7 + 3) % 32 for b in universe}
    assert len(set(sigma.values())) == 32, "σ 가 순열이 아니다"
    S2 = {sigma[b] for b in S}
    assert S2 != S, "σ(S) == S — 순열 변이가 공허하다 (항등 사상 함정)"

    await install_banks(dut, S2, universe)
    F2 = await judge_vector(dut, universe, src_kind=1, lnid=lnid)
    pred2 = tuple(0 if b in S2 else 1 for b in universe)
    assert F2 == pred2, (
        f"σ 적용 후 판정 벡터가 예측과 다르다 — 사상표를 경유하지 않는 경로가 "
        f"있다\n  got  {F2}\n  pred {pred2}")
    assert F2 != F, (
        "σ(S) ≠ S 인데 판정 벡터가 같다 — 사상표를 우회하는 구현이다 (ISA-2 위반). "
        "※ 이 비교는 판정이 아니라 **σ 가 관측 가능함**의 확인이다. 판정은 위 "
        "두 정확 비교가 이미 했다")
    dut._log.info(
        f"ISA-2 α: |S|={len(S)} → |σ(S)|={len(S2)}, universe {len(universe)}, "
        f"두 구성 모두 예측 벡터와 바이트 동일")


@cocotb.test()
async def isa2_beta_lnid_permutation(dut):
    """ISA-2 β — LNID 뷰 집합의 순열. srcKind=0 이라 LBID 축은 불참한다."""
    await boot(dut)
    names = [0x1000 + i for i in range(24)]
    V = {names[i] for i in (0, 3, 4, 9, 15, 23)}
    assert len(V) <= CAP_SLOTS

    await install_view(dut, [(s, s % N_POINTS, n) for s, n in enumerate(sorted(V))])
    F = await judge_vector_lnid(dut, names)
    pred = tuple(0 if n in V else 1 for n in names)
    assert F == pred, f"기준 뷰의 판정 벡터 불일치\n  got  {F}\n  pred {pred}"

    await clear_view(dut, range(len(V)))
    sigma = {n: names[(names.index(n) * 5 + 2) % len(names)] for n in names}
    assert len(set(sigma.values())) == len(names), "σ 가 순열이 아니다"
    V2 = {sigma[n] for n in V}
    assert V2 != V, "σ(V) == V — 순열 변이가 공허하다"

    await install_view(dut, [(s, s % N_POINTS, n) for s, n in enumerate(sorted(V2))])
    F2 = await judge_vector_lnid(dut, names)
    pred2 = tuple(0 if n in V2 else 1 for n in names)
    assert F2 == pred2, (
        f"σ 적용 후 뷰 판정이 예측과 다르다\n  got  {F2}\n  pred {pred2}")
    dut._log.info(
        f"ISA-2 β: |V|={len(V)} → |σ(V)|={len(V2)}, 이름 {len(names)}종, "
        f"두 구성 모두 예측 벡터와 바이트 동일")


@cocotb.test()
async def isa1_place_independence(dut):
    """ISA-1 의 **한 형상 안에서 확인 가능한 몫** — 물리 자리 무관성.

    같은 논리 LNID 집합을 *다른 슬롯 색인·다른 소유 지점*에 앉혀도 관측 궤적이
    **바이트 동일**해야 한다. 물리 자리는 논리 이름의 함수가 아니다.

    ⚠ 이것은 ISA-1 의 **형상 축이 아니다.** 형상 축(nPoints 4↔2)은 두 번째
      SV 가 없어 미측정이다 — `run_wt64.py` 의 미측정 원장 2번이 그 자리다.
      여기서 확인되는 것은 「같은 형상 안에서 자리를 바꿔도 같다」뿐이고,
      그것을 「형상 등가를 확인했다」로 적으면 거짓이다.
    """
    await boot(dut)
    names = [0x2000 + i for i in range(12)]
    V = sorted({names[i] for i in (1, 2, 6, 11)})

    layout_a = [(i, 0, n) for i, n in enumerate(V)]                 # 슬롯 0.. · 지점 0
    layout_b = [(CAP_SLOTS - 1 - i, (i + 1) % N_POINTS, n)          # 역순 슬롯 · 지점 순환
                for i, n in enumerate(V)]
    # 두 배치가 실제로 다른 자리인지 — 같으면 시험이 공허하다.
    assert {(s, p) for s, p, _ in layout_a} & {(s, p) for s, p, _ in layout_b} == set(), (
        "두 배치가 자리를 공유한다 — 자리 무관성 시험이 공허해진다")

    await install_view(dut, layout_a)
    await clear_all_faults(dut)          # 역사 정렬 — 위 clear_all_faults 주석
    traj_a = [await present(dut, descriptor(0, 0), n) for n in names]
    await clear_view(dut, [s for s, _, _ in layout_a])

    await install_view(dut, layout_b)
    await clear_all_faults(dut)
    traj_b = [await present(dut, descriptor(0, 0), n) for n in names]

    diff = [(i, names[i]) for i in range(len(names)) if traj_a[i] != traj_b[i]]
    assert not diff, (
        f"물리 자리를 바꾸자 궤적이 갈렸다 — 논리 이름이 자리에 결속돼 있다 "
        f"(ISA-1 위반). 갈린 지점: {diff[:4]}\n"
        f"  첫 차이 필드: "
        f"{[COMPARE_FACE[k] for k in range(len(COMPARE_FACE)) if traj_a[diff[0][0]][k] != traj_b[diff[0][0]][k]] if diff else []}")
    dut._log.info(
        f"ISA-1 자리 무관성: 이름 {len(V)}개를 (슬롯 0..{len(V)-1}, 지점 0) ↔ "
        f"(슬롯 {CAP_SLOTS-1}..{CAP_SLOTS-len(V)}, 지점 순환) 두 배치로 앉히고 "
        f"{len(names)} 제시 × {len(COMPARE_FACE)} 출력 궤적이 바이트 동일. "
        f"⚠ 형상 축(nPoints 4↔2)은 여전히 미측정이다")


@cocotb.test()
async def isa1_comparator_selfcheck(dut):
    """궤적 비교기의 **양성·음성 대조**.

    형상 축이 미측정인 동안 이 파일이 정직하게 주장할 수 있는 것은 「비교기가
    살아 있다」뿐이다. 그것을 매 실행 증명한다 — 없으면 나중에 형상 B 가
    착지했을 때 「0건 불일치」가 「비교가 죽었다」와 구별되지 않는다.

    이것은 self-skip 이 아니다. 실제로 값을 보고 두 방향으로 판정한다.
    """
    await boot(dut)
    await install_view(dut, [(0, 0, 0x3333)])
    words = descriptor(0, 0)

    # 양성 — 같은 자극을 두 번 걸면 궤적이 바이트 동일해야 한다 (결정성).
    t1 = [await present(dut, words, 0x3333) for _ in range(4)]
    t2 = [await present(dut, words, 0x3333) for _ in range(4)]
    assert t1 == t2, (
        f"같은 자극의 두 궤적이 다르다 — 결정성이 없으면 형상 대조가 성립하지 "
        f"않는다. 첫 차이: "
        f"{[(i, COMPARE_FACE[k]) for i in range(len(t1)) for k in range(len(COMPARE_FACE)) if t1[i][k] != t2[i][k]][:4]}")

    # 음성 — 비교기가 실제로 차이를 잡는가. **변수를 하나만 흔든다.**
    #
    # 자극(명령 워드열 + 태그)을 바꾸면 태그가 관측면 여러 자리로 그대로
    # 전파되므로(`io_route_tokOut_payload_tag_lnid` · `io_mem_down_*_payload`)
    # 「faultFire 를 잡았다」가 우연일 수 있다 — 실측으로 확인했다: lnid 만
    # 바꿔도 여섯 자리가 함께 움직인다.
    # ⇒ **자극을 바이트 동일하게 두고 구성만 바꾼다.** 그러면 움직여야 하는
    #   자리가 정확히 하나(`io_route_faultFire`)로 특정되고, 그 하나가
    #   움직였는지를 exact 로 판정할 수 있다. 그것이 「사상표를 경유한다」의
    #   가장 좁은 관측이기도 하다.
    lb_words = descriptor(0x11, 1)                       # srcKind=1 — LBID 축 참여
    await install_banks(dut, {0x11}, [0x11])
    await clear_all_faults(dut)
    hit = await present(dut, lb_words, 0x3333)
    await install_banks(dut, set(), [0x11])              # 같은 자극, 사상만 제거
    await clear_all_faults(dut)
    miss = await present(dut, lb_words, 0x3333)

    moved = [COMPARE_FACE[k] for k in range(len(COMPARE_FACE))
             if hit[k] != miss[k]]
    assert moved == ["io_route_faultFire"], (
        f"자극이 바이트 동일한데 움직인 자리가 {moved} — 정확히 "
        f"`io_route_faultFire` 하나여야 한다")
    assert hit[_IX_FF] == 0 and miss[_IX_FF] == 1, (
        f"사상 존재/부재가 판정을 가르지 않았다 (hit={hit[_IX_FF]} "
        f"miss={miss[_IX_FF]}) — 사상표를 우회하는 경로다")
    dut._log.info(
        f"비교기 자기대조: 양성(같은 자극 4박이 바이트 재현) + 음성(자극 고정 · "
        f"사상만 제거 → 움직인 자리가 정확히 io_route_faultFire 하나). "
        f"대조면 {len(COMPARE_FACE)} 출력 전량 비교")



# ═══════════════════════════════════════════════════════════════════════════
# 변환 저장소의 MMIO 문 — 0xC00 항목 배열 · 0xE00 저장소 제어 (파도 3)
# ═══════════════════════════════════════════════════════════════════════════
#
# 기입은 호스트 ABI 오프셋이고, 관측은 HIU 요청 경로의 내부 제시 포트다
# (`io.hiuReq` — 요청 원천인 메모리 파이프가 미착지). 적중·미적중은 파이프가
# 드러내는 두 사실로 잰다: 적중이면 요청이 여섯 단을 지나 `io.hiuRsp.valid` 로
# 나오고, 미적중이면 조회 단(s3)에서 **정지**한다(`io.hiuReq.ready` = 0 ·
# `io.fault.hiuMiss` sticky — E.3 「요청은 배압으로 정지하고」). 승인은
# 소유권 표(E.7)를 거치므로 설치한 프레임을 `0x208` OWN_SET 으로 장치 소유로
# 먼저 넘긴다. 마스크 키를 싣지 않았으므로 마스킹 단은 항등(미준비 파티션의
# 마스크는 reset 값 0)이고 `io.phys.frame` 이 설치한 프레임 그대로다.
#
# 이 시험들은 구성 소거 구간(`boot`)을 기다리지 않는다 — 두 구역은 MmioConfig 를
# 거치지 않고 ready 가 하류 install.ready(HI 쓰기) 아니면 1 이다.

XENT_BASE = 0xC00
XCTL_FLUSH = 0xE00
XCTL_STATUS = 0xE04
XCTL_MISS_CLEAR = 0xE10
OWN_SET = 0x208
FAULT_STATUS = 0xF80
FAULT_CLEAR = 0xF84
B_CFG_BADWRITE = 6

# 조회 관측 창 (접수 뒤 사이클 수) · 미적중 요청이 조회 단(s3)에 닿아 ready 를
# 떨어뜨리기까지의 사이클 수 — **실측으로 못박은 상수** (2026-09-26, 무변이
# 생성물). 파이프 깊이가 바뀌면 `assert_miss` 가 등식으로 크게 깨진다.
LOOKUP_WINDOW = 20
MISS_LEAD = 2


def xent(part, idx):
    """03-hiu.typ:1552 「오늘 문의 항목 기저 주소는 `0xC00` + (파티션 ≪ 7) + (색인 ≪ 3) 이다」"""
    return XENT_BASE + (part << 7) + (idx << 3)


def hi_word(tag, v=1, r=1, w=0, x=0):
    """XLATE_ENTRY_HI — `[31]` V · `[30:28]` R·W·X · `[27:0]` 태그."""
    return (v << 31) | (r << 30) | (w << 29) | (x << 28) | (tag & 0x0FFFFFFF)


def vpn_of(tag, idx):
    """VPN = {태그 28b, 색인 4b} — XlateStore reqIdx = vpn[3:0] · reqTag = vpn[31:4]."""
    return ((tag & 0x0FFFFFFF) << 4) | (idx & 0xF)


async def boot_hiu(dut):
    zero_inputs(dut)
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.reset.value = 1
    await step(dut, 3)
    dut.reset.value = 0
    await step(dut)


async def install_entry(dut, part, idx, tag, frame, v=1, r=1, w=0, x=0):
    await mmio_write(dut, xent(part, idx), frame)            # LO — 스테이징
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag, v=v, r=r, w=w, x=x))  # HI — 커밋 발화


async def hiu_lookup(dut, part, vpn, window=LOOKUP_WINDOW, write=0):
    """읽기 요청 하나를 제시하고 결과를 돌려준다.

    반환: dict(rsp, granted, frame, phys, stalled, trace, fromFill). `write` 는 요청
    종류(자격 판정이 R 대신 W 를 본다 — W1 N14). `rsp=0` 이면 창 안에 응답이
    없었고 `stalled` 는 그동안 `io.hiuReq.ready` 가 0 이던 사이클 수다 — 미적중
    정지다. `trace` 는 접수 뒤 사이클마다의 ready 표본이다 (`assert_miss` 가
    정지의 *모양*을 등식으로 잰다).
    """
    dut.io_hiuReq_part.value = part
    dut.io_hiuReq_vpn.value = vpn
    dut.io_hiuReq_write.value = write
    dut.io_hiuReq_valid.value = 1
    await settle(dut)
    n = 0
    while int(dut.io_hiuReq_ready.value) == 0:
        await step(dut)
        n += 1
        if n > window:
            raise AssertionError("hiu_lookup: 요청 접수 ready 가 안 선다 — 앞 요청이 정지 중이다")
    await step(dut)                                         # 접수 엣지
    dut.io_hiuReq_valid.value = 0
    dut.io_hiuReq_write.value = 0
    stalled = 0
    trace = []
    for _ in range(window):
        await settle(dut)
        if int(dut.io_hiuRsp_valid.value):
            return dict(rsp=1, granted=int(dut.io_hiuRsp_granted.value),
                        frame=int(dut.io_phys_frame.value),
                        phys=int(dut.io_phys_valid.value), stalled=stalled,
                        trace=trace, fromFill=int(dut.io_hiuRsp_fromFill.value))
        rdy = int(dut.io_hiuReq_ready.value)
        trace.append(rdy)
        if rdy == 0:
            stalled += 1
        await step(dut)
    return dict(rsp=0, granted=0, frame=0, phys=0, stalled=stalled, trace=trace, fromFill=0)


async def wait_rsp(dut, window=20):
    """정지가 풀린 뒤 그 요청의 응답을 기다린다. `wait` 는 응답까지의 엣지 수다."""
    for n in range(window):
        await settle(dut)
        if int(dut.io_hiuRsp_valid.value):
            return dict(rsp=1, granted=int(dut.io_hiuRsp_granted.value),
                        frame=int(dut.io_phys_frame.value),
                        phys=int(dut.io_phys_valid.value),
                        fromFill=int(dut.io_hiuRsp_fromFill.value), wait=n)
        await step(dut)
    return dict(rsp=0, granted=0, frame=0, phys=0, fromFill=0, wait=window)


async def fault6(dut):
    return (await mmio_read(dut, FAULT_STATUS) >> B_CFG_BADWRITE) & 1


async def clear_fault6(dut):
    await mmio_write(dut, FAULT_CLEAR, 1 << B_CFG_BADWRITE)
    assert await fault6(dut) == 0, "0xF84[6] W1C 가 [6] 을 내리지 못했다"


def assert_hit(res, frame, what):
    assert res["rsp"] == 1 and res["stalled"] == 0, (
        f"{what}: 적중을 기대했는데 응답 {res['rsp']} · 정지 {res['stalled']} 사이클")
    assert res["granted"] == 1 and res["phys"] == 1, f"{what}: 승인이 없다 ({res})"
    assert res["frame"] == frame, (
        f"{what}: 승인 프레임 0x{res['frame']:08X} ≠ 설치한 LO 프레임 0x{frame:08X}")


def assert_miss(dut, res, what):
    """미적중 = 조회 단 도달 뒤 **창 끝까지 이어지는** 정지.

    착지판은 `stalled >= 8` 이었다 — 정지가 여덟 사이클 뒤 풀리고 응답 없이
    끝나는 판(정지가 새다)도 통과시키는 하한이다. 여기서는 ready 표본열을
    등식으로 잰다: 접수 뒤 `MISS_LEAD` 사이클은 요청이 조회 단으로 가는 길이라
    ready = 1 이고, 그 뒤 창 끝까지 전부 0 이다 (창 끝의 ready = 0 을 포함한다).
    """
    want = [1] * MISS_LEAD + [0] * (LOOKUP_WINDOW - MISS_LEAD)
    assert res["rsp"] == 0 and res["trace"] == want, (
        f"{what}: 미적중(조회 정지가 창 끝까지)을 기대했는데 응답 {res['rsp']} · "
        f"정지 {res['stalled']} 사이클 · ready 표본열 {res['trace']} "
        f"(기대 {want})")
    assert int(dut.io_fault_hiuMiss.value) == 1, f"{what}: 미적중인데 hiuMiss sticky 가 서지 않았다"


@cocotb.test()
async def xlate_mmio_install_hits(dut):
    """(1) LO → HI 두 워드 기입으로 설치한 항목에 조회가 적중하고, 승인된
    프레임이 LO 로 실은 값 그대로다. 적법한 두 기입은 [6] 을 세우지 않는다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 1, 5, 0x0ABCDEF, 0x1234_5678
    await mmio_write(dut, OWN_SET, frame)
    await install_entry(dut, part, idx, tag, frame)
    assert await fault6(dut) == 0, "적법한 LO/HI 기입이 [6] 을 세웠다 (허위 fault)"
    res = await hiu_lookup(dut, part, vpn_of(tag, idx))
    assert_hit(res, frame, "MMIO 설치 뒤 조회")
    # 다른 파티션의 같은 (색인, 태그) 는 미적중이다 — 항목 주소 addr[8:7] 이 곧 파티션.
    res = await hiu_lookup(dut, 0, vpn_of(tag, idx))
    assert_miss(dut, res, "타 파티션의 같은 VPN")
    dut._log.info("MMIO LO/HI 설치 → 적중 · 프레임 일치 · 타 파티션 미적중 (항목 주소 = 파티션)")


@cocotb.test()
async def xlate_flush_then_miss(dut):
    """(2) 0xE00 XLATE_FLUSH 가 그 파티션의 유효 비트를 지운다 — 같은 VPN 의
    다음 조회가 미적중으로 정지하고 hiuMiss 가 선다 — 정본이 회귀 상주를 요구하는
    「검증 방법」 규범의 기입 쪽이다: 설치 → 컨텍스트 전환 flush → 같은 주소 미적중.

    값 수준 두 단계를 더 잰다 (반증 검토 뒤 수리):
    · flush 는 *그 파티션만* 지운다 — 같은 (색인, 태그)를 다른 파티션에 세워 두고
      flush 를 건넌 뒤 그 항목이 적중함을 본다 (전역 발화 금지 · flush_scoped).
      이 단계는 flush 파티션의 미적중 조회 *앞*에 둔다 — 미적중은 파이프를 정지시켜
      다음 조회를 받지 않는다.
    · LO 는 스테이징일 뿐이다 — 산 항목 위에 다른 프레임의 LO 를 써도 HI 전까지
      조회는 옛 프레임을 승인하고 [6] 도 없다 (lo_stages_only). LO 가 표를 곧장
      덮는 기계라면 여기서 새 프레임(또는 미승인)이 나온다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 2, 3, 0x00C0FFE, 0x0000_BEEF
    opart, oframe = 1, 0x0000_F00D          # 다른 파티션 — 같은 색인 · 같은 태그
    await mmio_write(dut, OWN_SET, frame)
    await mmio_write(dut, OWN_SET, oframe)
    await install_entry(dut, part, idx, tag, frame)
    await install_entry(dut, opart, idx, tag, oframe)
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag, idx)), frame, "flush 전")
    # LO over live — 스테이징만 움직이고 표의 옛 판은 그대로다.
    await mmio_write(dut, xent(part, idx), 0x0000_DEAD)
    assert await fault6(dut) == 0, "산 항목 위의 적법한 LO 가 [6] 을 세웠다"
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag, idx)), frame,
               "산 항목 위 LO 뒤 (HI 전) — LO 가 표에 닿았다")
    await mmio_write(dut, XCTL_FLUSH, part)
    assert await fault6(dut) == 0, "적법한 XLATE_FLUSH 가 [6] 을 세웠다"
    assert_hit(await hiu_lookup(dut, opart, vpn_of(tag, idx)), oframe,
               f"파티션 {part} flush 뒤 파티션 {opart} 의 같은 (색인, 태그) — flush 가 번졌다")
    assert_miss(dut, await hiu_lookup(dut, part, vpn_of(tag, idx)), "flush 뒤 같은 VPN")
    dut._log.info("산 항목 위 LO → 옛 프레임 유지 · 0xE00 flush → 같은 VPN 미적중(정지 + hiuMiss) · "
                  "타 파티션 항목 생존")


@cocotb.test()
async def xlate_flush_ends_staging(dut):
    """(3) 판정 T5 (a) — 래치 파티션의 *수락된* 0xE00 flush 가 스테이징 유효를 내린다
    (E.1.2 `0xC00` · `0xE00` 행 · E.9 6항 ⑵). 그리고 정지를 푸는 것은 항목
    기입이다 (E.3 2항).

    설치 → flush(p) → 같은 VPN 미적중 정지 → LO 없이 HI 한 워드(V=1). 판정 전 RTL 은
    이 HI 가 flush 를 건넌 스테이징 잔재(옛 임대의 LO 프레임)를 새 태그 · V=1 로 커밋해
    정지를 풀었다 — 조용한 옛 프레임 재커밋(이 시험의 옛 이름 xlate_hi_releases_stall 이
    인계철선으로 들던 귀결)이다. 판정 뒤에는 그 HI 가 빈 스테이징의 HI 라 거절 +
    `[6]` 이고 아무것도 커밋하지 않는다 — 정지가 그대로다. 새 임대의 항목은 LO 부터
    쓴다: `[6]` 을 지우고 LO(새 프레임) → HI 를 쓰면 정지한 요청이 풀려 *새* 프레임으로
    승인된다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 3, 9, 0x0123456, 0x0BAD_F00D
    nframe = 0x0C0D_E000                      # 새 임대의 프레임
    await mmio_write(dut, OWN_SET, frame)
    await mmio_write(dut, OWN_SET, nframe)
    await install_entry(dut, part, idx, tag, frame)
    await mmio_write(dut, XCTL_FLUSH, part)
    assert await fault6(dut) == 0, "적법한 XLATE_FLUSH 가 [6] 을 세웠다"
    res = await hiu_lookup(dut, part, vpn_of(tag, idx))
    assert_miss(dut, res, "flush 뒤")
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag))   # HI 만 — LO 없음
    assert await fault6(dut) == 1, (
        "flush 를 건넌 스테이징 위의 HI 한 워드가 거절되지 않았다 — 옛 임대의 LO 프레임이 "
        "새 임대의 태그·V 로 다시 커밋된다 (판정 T5 (a) 위반 · E.1.2 `0xC00` 행)")
    rsp = await wait_rsp(dut)
    assert rsp["rsp"] == 0, (
        f"거절된 HI 뒤에 정지한 요청이 풀렸다 — 무언가가 커밋됐다 ({rsp})")
    await clear_fault6(dut)
    await install_entry(dut, part, idx, tag, nframe)            # 새 임대 — LO 부터
    assert await fault6(dut) == 0, "새 임대의 LO → HI 가 [6] 을 세웠다 (허위 fault)"
    rsp = await wait_rsp(dut)
    assert rsp["rsp"] == 1 and rsp["granted"] == 1 and rsp["frame"] == nframe, (
        f"LO → HI 가 정지를 풀지 못했거나 승인 프레임이 새 LO 프레임 0x{nframe:08X} 와 "
        f"다르다 ({rsp})")
    dut._log.info("flush 뒤 HI 한 워드 → 거절 + [6] · 정지 유지(재커밋 없음) · "
                  "LO → HI 가 정지를 풀고 새 프레임으로 승인 (판정 T5 (a) · E.3 2항)")


@cocotb.test()
async def xlate_v0_invalidates(dut):
    """(4) HI `[31]` V=0 은 단일 항목 무효화다 — 그 항목의 다음 조회가 미적중이다.
    설치 포트가 V 를 무시하고 언제나 유효를 세우면(수리 전 XlateStore) 이 조회가
    적중한다 — HIU-3 형 격리 결함."""
    await boot_hiu(dut)
    part, idx, tag, frame = 0, 7, 0x0FEDCBA, 0x7777_0001
    await mmio_write(dut, OWN_SET, frame)
    await install_entry(dut, part, idx, tag, frame)
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag, idx)), frame, "V=1 설치 뒤")
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag, v=0))
    assert await fault6(dut) == 0, "V=0 HI 는 적법한 기입인데 [6] 을 세웠다"
    assert_miss(dut, await hiu_lookup(dut, part, vpn_of(tag, idx)), "V=0 HI 뒤")
    dut._log.info("V=0 HI → 그 항목 미적중 (단일 항목 무효화)")


@cocotb.test()
async def xlate_hi_rejects_are_loud(dut):
    """(5) HI 의 거절 둘 — reset 직후 LO 없이 온 HI(빈 스테이징) · 스테이징된
    번호와 다른 항목의 HI — 가 0xF80[6] 을 세우고 아무것도 커밋하지 않는다.
    거절은 스테이징을 움직이지 않는다: 불일치 HI 뒤에도 원래 항목의 HI 는 그
    LO 프레임으로 커밋된다."""
    await boot_hiu(dut)
    fa, fb = 0x0000_A0A0, 0x0000_B0B0
    await mmio_write(dut, OWN_SET, fa)
    await mmio_write(dut, OWN_SET, fb)
    # 빈 스테이징 — reset 래치 번호(항목 0)와 같은 항목 0 의 HI 도 거절이다.
    await mmio_write(dut, xent(0, 0) + 4, hi_word(0x11))
    assert await fault6(dut) == 1, "LO 없이 온 HI(reset 직후 항목 0)가 [6] 을 세우지 않았다"
    await clear_fault6(dut)
    # 번호 불일치 — LO 는 (0,1), HI 는 (0,2).
    await mmio_write(dut, xent(0, 1), fa)
    await mmio_write(dut, xent(0, 2) + 4, hi_word(0x22))
    assert await fault6(dut) == 1, "번호 불일치 HI 가 [6] 을 세우지 않았다"
    await clear_fault6(dut)
    # 거절은 스테이징을 움직이지 않았다 — (0,1) 의 HI 가 fa 로 커밋된다.
    await mmio_write(dut, xent(0, 1) + 4, hi_word(0x33))
    assert await fault6(dut) == 0
    assert_hit(await hiu_lookup(dut, 0, vpn_of(0x33, 1)), fa, "거절 뒤 원래 항목의 커밋")
    # 거절된 두 HI 는 아무것도 커밋하지 않았다.
    assert_miss(dut, await hiu_lookup(dut, 0, vpn_of(0x22, 2)), "번호 불일치 HI 의 항목")
    dut._log.info("빈 스테이징 HI · 번호 불일치 HI → [6] · 무커밋 · 스테이징 부동")


@cocotb.test()
async def xlate_flush_reject_no_alias(dut):
    """(6) 없는 파티션 값([7:0]=4)과 예약 위반([31:8]≠0)의 XLATE_FLUSH 는 거절 +
    [6] 이고 flush 가 없다 — 8b 필드를 2b 로 잘라 파티션 0 을 지우는 별칭이
    없다. RO 오프셋(0xE04) 쓰기도 거절 + [6] 이다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 0, 4, 0x0055AA5, 0x0CAF_E000
    await mmio_write(dut, OWN_SET, frame)
    await install_entry(dut, part, idx, tag, frame)
    for what, word in (("없는 파티션 4", 0x0000_0004), ("예약 [31:8] 비0 · 파티션 0", 0x0000_0100)):
        await mmio_write(dut, XCTL_FLUSH, word)
        assert await fault6(dut) == 1, f"XLATE_FLUSH({what}) 가 [6] 을 세우지 않았다"
        await clear_fault6(dut)
        assert_hit(await hiu_lookup(dut, part, vpn_of(tag, idx)), frame,
                   f"XLATE_FLUSH({what}) 뒤 파티션 0 항목")
    await mmio_write(dut, XCTL_STATUS, 0)
    assert await fault6(dut) == 1, "RO 오프셋 0xE04 쓰기가 [6] 을 세우지 않았다"
    dut._log.info("없는 파티션 · 예약 위반 flush → [6] · 파티션 0 항목 생존 · RO 쓰기 loud")


@cocotb.test()
async def xlate_missclear_keeps_stall(dut):
    """(7) 0xE10 XLATE_MISS_CLEAR 는 정지를 풀지 않는다 — e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다*」.
    예약 [31:1] 비0 은 거절 + [6] 이다. 정지는 뒤이은 항목 기입이 풀고, 그 뒤의
    `[0]`=1 기입이 미적중 sticky 를 내린다.

    ⚠ 정지 *중*의 해제는 sticky 를 내리지 못한다 (실측): 미적중 sticky 의 set 이
    정지 레벨(missWait)이고 StickyFault 규약에서 발화가 해제를 이긴다 — 미적중이
    아직 살아 있는 동안 「미적중이 있었다」를 지우는 것은 규약상 불가능하다.
    그래서 이 시험은 정지 중 해제가 *정지도 sticky 도* 풀지 않음을, 정지가 풀린
    뒤 해제가 sticky 를 실제로 내림을 따로 잰다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 1, 1, 0x0000777, 0x0000_1111
    await mmio_write(dut, OWN_SET, frame)
    res = await hiu_lookup(dut, part, vpn_of(tag, idx))
    assert_miss(dut, res, "빈 표")
    await mmio_write(dut, XCTL_MISS_CLEAR, 0x3)
    assert await fault6(dut) == 1, "MISS_CLEAR 예약 [31:1] 비0 이 [6] 을 세우지 않았다"
    await mmio_write(dut, XCTL_MISS_CLEAR, 0x1)
    await step(dut, 4)
    assert int(dut.io_hiuReq_ready.value) == 0, "0xE10 해제가 정지를 풀었다 — 정지를 푸는 것은 항목 기입뿐이다"
    assert int(dut.io_hiuRsp_valid.value) == 0
    assert int(dut.io_fault_hiuMiss.value) == 1, (
        "정지 중인데 미적중 sticky 가 내려갔다 — set(정지 레벨)이 해제를 이겨야 한다")
    await install_entry(dut, part, idx, tag, frame)
    rsp = await wait_rsp(dut)
    assert rsp["rsp"] == 1 and rsp["granted"] == 1 and rsp["frame"] == frame, (
        f"항목 기입이 정지를 풀지 못했다 ({rsp})")
    await step(dut, 2)
    assert int(dut.io_fault_hiuMiss.value) == 1, "정지가 풀리자 sticky 가 스스로 내려갔다 — sticky 가 아니다"
    # 해제의 원천은 수락된 0xE10 `[0]`=1 하나다 — 거절된 0xE10 · 같은 구역의 다른
    # 워드 기입은 sticky 를 내리지 않는다 (정지가 풀려 set 이 0 인 지금이 그것을 잴 자리).
    await mmio_write(dut, XCTL_MISS_CLEAR, 0x3)
    await mmio_write(dut, XCTL_FLUSH, 3)
    assert int(dut.io_fault_hiuMiss.value) == 1, "거절된 0xE10 또는 0xE00 기입이 미적중 sticky 를 내렸다"
    await mmio_write(dut, XCTL_MISS_CLEAR, 0x1)
    assert int(dut.io_fault_hiuMiss.value) == 0, "0xE10 [0]=1 이 미적중 sticky 를 내리지 못했다"
    dut._log.info("0xE10 → 정지 유지 · 정지 뒤 sticky 해제 · 예약 비0 은 loud · 항목 기입이 정지를 푼다")


# ── 인접 HI — D-2 버스 정지의 값 수준 시험 (파도 3 반증 검토 뒤 수리) ─────────
#
# `mmio_write` 는 기입마다 쉬는 엣지를 하나 남긴다 (LNID 축의 CHECK 사이클) —
# 그래서 위 일곱은 HI 두 워드를 *인접*시키지 못하고, 정지가 실제로 서는 유일한
# 경우(모델 머리 「같은 항목 HI 연속만 만난다」 — XlateSurface.tla 「안 잰다」
# 의 시간 항)를 한 번도 만들지 않는다. 실측(검토 세션): 생성물 사본에서 ready
# 덮어쓰기를 끊으면(`assign when_Wt64Top_l1714 = 1'b0;`) 둘째 HI 가 조용히
# 드롭되는데 위 일곱은 7/7 PASS 였다 — 「정지하고, 같은 기입이 커밋된다」는
# 어디서도 재지 않았다. 아래 원시 구동기는 쉬는 사이클 없이 기입을 잇고
# ready = 0 동안 같은 기입(주소·데이터·스트로브)을 잡아 둔다 — 버스 마스터가
# 정지에 대해 지는 의무 그대로다.

async def mmio_burst(dut, ops, max_stall=8):
    """쓰기 열을 **인접** 구동한다 — 수락 엣지 바로 다음 사이클에 다음 기입.

    반환: 기입마다 ready = 0 으로 잡혀 있던 사이클 수 (정지 계수). 정지 중에는
    스트로브를 내리지 않는다 — 내리면 그것은 정지가 아니라 철회이고, 철회된
    기입의 효과를 재는 것은 이 시험이 아니다.
    """
    stalls = []
    for addr, data in ops:
        dut.io_mmio_addr.value = addr
        dut.io_mmio_wdata.value = data
        dut.io_mmio_wstrobe.value = 1
        await settle(dut)
        n = 0
        while int(dut.io_mmio_ready.value) == 0:
            n += 1
            if n > max_stall:
                raise AssertionError(
                    f"mmio_burst(0x{addr:03X}): ready 가 {max_stall} 엣지 넘게 0 이다 — "
                    f"정지가 풀리지 않는다 (D-2 정지는 유계여야 한다)")
            await step(dut)          # 같은 기입을 잡아 둔 채 한 엣지
        stalls.append(n)
        await step(dut)              # 수락 엣지 — 다음 기입이 곧바로 잇는다
    dut.io_mmio_wstrobe.value = 0
    await step(dut)
    await settle(dut)
    return stalls


@cocotb.test()
async def xlate_adjacent_hi_stalls_then_commits(dut):
    """(8) 같은 항목의 인접 HI 둘 — 둘째 HI 는 첫 HI 가 채운 채움 슬롯 때문에
    하류가 거부하고(install.ready = 0), 문은 그것을 거절도 드롭도 아닌 **버스
    정지**로 처분한다(D-2): 정확히 한 사이클 ready = 0, `[6]` 무발화, 그리고
    풀린 그 기입이 LO 프레임으로 커밋된다 — tagB 가 F 로 적중하고 tagA 는 덮였다.

    정지 계수 [0, 0, 1] 은 첫 HI 가 실제로 커밋했다는 증거이기도 하다 (슬롯을
    채운 것은 그 커밋뿐이다)."""
    await boot_hiu(dut)
    part, idx, fr = 1, 2, 0x0000_A000
    tag_a, tag_b = 0x0000111, 0x0000222
    await mmio_write(dut, OWN_SET, fr)
    stalls = await mmio_burst(dut, [(xent(part, idx), fr),
                                    (xent(part, idx) + 4, hi_word(tag_a)),
                                    (xent(part, idx) + 4, hi_word(tag_b))])
    assert stalls == [0, 0, 1], (
        f"LO · HI(tagA) · HI(tagB) 인접 — 정지 계수 {stalls} ≠ [0, 0, 1]. "
        f"둘째 HI 의 정지가 없으면 그 기입은 하류가 거부한 사이클에 수락돼 조용히 "
        f"사라진다 (:419)")
    assert await fault6(dut) == 0, "적법한 HI 의 하류 거부가 [6] 을 세웠다 — 정지여야 한다 (D-2)"
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag_b, idx)), fr,
               "정지 뒤 수락된 둘째 HI(tagB)")
    assert_miss(dut, await hiu_lookup(dut, part, vpn_of(tag_a, idx)),
                "둘째 HI 가 덮은 첫 HI(tagA)")
    dut._log.info("인접 HI 둘 → 둘째 HI 한 사이클 정지 · [6]=0 · tagB 가 LO 프레임으로 적중 · tagA 덮임")


@cocotb.test()
async def xlate_adjacent_v0_stalls_then_invalidates(dut):
    """(9) 같은 항목의 인접 HI(V=1) · HI(V=0) — 무효화 워드가 정지를 건너서도
    사라지지 않는다. 정지 계수 [0, 0, 1] · `[6]` 무발화 · 그 항목의 다음 조회는
    미적중이다. V=0 이 드롭되면 앞 HI 의 유효 항목이 남아 적중한다 — 드라이버가
    무효화했다고 믿는 항목이 살아 있는 HIU-3 형 결함이다."""
    await boot_hiu(dut)
    part, idx, tag, fr = 0, 3, 0x0000333, 0x0000_A100
    await mmio_write(dut, OWN_SET, fr)
    stalls = await mmio_burst(dut, [(xent(part, idx), fr),
                                    (xent(part, idx) + 4, hi_word(tag, v=1)),
                                    (xent(part, idx) + 4, hi_word(tag, v=0))])
    assert stalls == [0, 0, 1], (
        f"LO · HI(V=1) · HI(V=0) 인접 — 정지 계수 {stalls} ≠ [0, 0, 1]")
    assert await fault6(dut) == 0, "적법한 V=0 HI 의 하류 거부가 [6] 을 세웠다 — 정지여야 한다 (D-2)"
    assert_miss(dut, await hiu_lookup(dut, part, vpn_of(tag, idx)),
                "정지 뒤 수락된 V=0 HI 의 항목")
    dut._log.info("인접 HI(V=1) · HI(V=0) → 한 사이클 정지 · [6]=0 · 무효화 생존(미적중)")


# ═══════════════════════════════════════════════════════════════════════════
# 재조립 문맥 소거 — ABORT_TAG1 워드의 적법성 (D2 수리의 끝-끝 시험)
# ═══════════════════════════════════════════════════════════════════════════
# 정본 E.1.2 `0xF44`: `[27]` poison = 0 · `[26]` trace = 0 · `[25:16]` 예약 = 0 (엄격)
# — 처분은 셋 다 같다: 거절 + FAULT_STATUS `[6]`. E.12.1 1항: 거절된 기입은
# 무장을 세우지 않는다 · 5항: 워드의 적법성 검사는 무장보다 앞선다.
# 스테이징 값은 WO 라 MMIO 로 보이지 않는다 — 「거절된 기입이 값을 덮지 않는다」는
# 후-formal(AbortStaging_props.sv t_tag1_hold)이 잰다. 여기는 호스트가 보는 셋
# (0xF80[6] · 0xF58[1] · 0xF50)만 잰다.
ABORT_TAG1 = 0xF44
ABORT_FIRE = 0xF4C
ABORT_COUNT = 0xF50
ABORT_ARM = 0xF58


@cocotb.test()
async def abort_tag1_word_legality(dut):
    await boot(dut)
    await clear_all_faults(dut)
    if await fault6(dut):
        await clear_fault6(dut)
    lnid = 0x1234
    for why, bits in (("[27] poison", 1 << 27), ("[26] trace", 1 << 26),
                      ("[16] 예약 최하위", 1 << 16), ("[25:16] 예약 전폭", 0x3FF << 16)):
        await mmio_write(dut, ABORT_TAG1, bits | lnid)
        assert await fault6(dut) == 1, f"ABORT_TAG1 {why} 비0 기입에 [6] 이 서지 않았다 — 조용한 수락"
        arm = await mmio_read(dut, ABORT_ARM)
        assert arm & 0b010 == 0, f"ABORT_TAG1 {why}: 거절된 기입이 무장 [1] 을 세웠다 (ARM={arm:#05b})"
        await clear_fault6(dut)
    # 에포크 [31:28] 는 거절 사유가 아니다 — 수락되어 무장 [1] 만 선다
    await mmio_write(dut, ABORT_TAG1, (0xA << 28) | lnid)
    assert await fault6(dut) == 0, "에포크 비0 의 ABORT_TAG1 이 거절됐다 — 거절 마스크가 에포크를 삼킨다"
    assert await mmio_read(dut, ABORT_ARM) == 0b010, "수락된 ABORT_TAG1 이 무장 [1] 을 세우지 않았다"
    # 거절은 무동작 — 선 무장을 내리지도 않는다
    await mmio_write(dut, ABORT_TAG1, (1 << 26) | lnid)
    assert await fault6(dut) == 1
    assert await mmio_read(dut, ABORT_ARM) == 0b010, "거절된 ABORT_TAG1 이 기존 무장을 움직였다"
    await clear_fault6(dut)
    # 무장 미완 발화 — 무시(거절 아님) · 무장 전부 하강 · 소거 카운트 0 (E.12.1 2·3항)
    await mmio_write(dut, ABORT_FIRE, 1)
    assert await mmio_read(dut, ABORT_ARM) == 0
    assert await mmio_read(dut, ABORT_COUNT) == 0
    assert await fault6(dut) == 0, "무장 미완 발화가 [6] 을 세웠다 — 무시가 거절로 접혔다"


# ═══════════════════════════════════════════════════════════════════════════
# 파도 4 페이지 통합 — 페이지 처분(판정 T1-i · T1-ii · T2 · T3)과 FP 소거 창(D1 (b))
# ═══════════════════════════════════════════════════════════════════════════
#
# 선-formal 은 rtl/formal/tla/MmioPage.tla 이고 후-formal 조립 절반은 Wt64Top/assembly.sby
# (surfMust · a_rv_acc · a_fpbad_* · a_rd_abi)다. 여기는 호스트가 보는 값으로 잰다 —
# 0xF80[6] · 되읽기 · 무장 마스크 · 창 레지스터 · rvalid 의 개수.
#
# 정본 (f229c8b 판정):
#   03-hiu.typ:1623 「이 장치는 거기 워드를 두지 않는다. 쓰기는」 — 물려받은 0x000–0x11F
#   e-defined.typ:743 「*소비 회로가 없는 RW 워드 — 쓰기는 거절, 읽기는 0.*」
#   03-hiu.typ:874 「비정렬 *읽기*는 0 · fault 없음이다」
#   03-hiu.typ:1134 「읽기도 같다 — 수락(ready ∧ 스트로브)되지 않은 접근은 효과도 응답도 없다」

MASK_PART = 0xEA0
FP_PROG = 0xF00
FP_BIND = 0xF04
FP_STATUS = 0xF08


async def page_expect_loud(dut, addr, data, what):
    """쓰기 하나가 [6] 을 세운다 — 앞뒤로 [6] 을 비워 원천을 이 쓰기 하나로 좁힌다."""
    if await fault6(dut):
        await clear_fault6(dut)
    await mmio_write(dut, addr, data)
    assert await fault6(dut) == 1, f"{what}: 0x{addr:03X} 쓰기에 [6] 이 서지 않았다 — 조용한 흡수"
    await clear_fault6(dut)


async def page_expect_quiet(dut, addr, data, what):
    if await fault6(dut):
        await clear_fault6(dut)
    await mmio_write(dut, addr, data)
    assert await fault6(dut) == 0, f"{what}: 0x{addr:03X} 쓰기가 [6] 을 세웠다 — 예약 오프셋 관대 위반"


async def page_expect_read0(dut, addr, what):
    v = await mmio_read(dut, addr)
    assert v == 0, f"{what}: 0x{addr:03X} 읽기가 0x{v:08X} — 0 이어야 한다"
    assert await fault6(dut) == 0, f"{what}: 0x{addr:03X} 읽기가 [6] 을 세웠다 — 읽기는 관대다"


@cocotb.test()
async def page_disposition(dut):
    await boot(dut)                 # 사상표 구역(0x401)의 비정렬 쓰기가 유닛 ready 를 기다리지 않게
    await clear_all_faults(dut)
    if await fault6(dut):
        await clear_fault6(dut)
    # T3 (d) — 물려받은 0x000–0x11F: 쓰기 거절 + [6] (정렬 무관) · 읽기 0
    for a in (0x000, 0x040, 0x100, 0x11C, 0x101):
        await page_expect_loud(dut, a, 0xFFFFFFFF, "물려받은 구간")
    for a in (0x014, 0x100, 0x101):
        await page_expect_read0(dut, a, "물려받은 구간 읽기")
    # 예약 오프셋의 관대는 *정렬 워드* 오프셋에 한한다 — 0x120 · 0x1FC 는 조용하다
    for a in (0x120, 0x1FC):
        await page_expect_quiet(dut, a, 0xFFFFFFFF, "예약 오프셋")
    # T1-i (β) — 명령 링 RW 넷 · SQ_HEAD(RO): 쓰기 거절 + [6] · 저장 없음(되읽기 0)
    for a in (0x380, 0x384, 0x388, 0x38C, 0x390):
        await page_expect_loud(dut, a, 0xFFFFFFFF, "명령 링 표 워드")
        await page_expect_read0(dut, a, "명령 링 표 워드 되읽기")
    await page_expect_quiet(dut, 0x394, 0xFFFFFFFF, "명령 링 구역의 표에 없는 워드")
    # T1-i (β) CQ_BASE 확장 — 완료 링 base 둘도 같은 처분 (CompletionUnit)
    for a in (0x300, 0x304):
        await page_expect_loud(dut, a, 0x12345678, "CQ_BASE")
        await page_expect_read0(dut, a, "CQ_BASE 되읽기")
    # T1-ii — 0xFFC HIU_ABI_VERSION: RO 쓰기 거절 + [6] · 읽기는 합의 전 값 0
    await page_expect_loud(dut, 0xFFC, 0x00010000, "HIU_ABI_VERSION")
    await page_expect_read0(dut, 0xFFC, "HIU_ABI_VERSION 읽기 (합의 전 0)")
    # T2 (a) — 비정렬 쓰기: 페이지 어디서든 거절 + [6] · 효과 없음
    for a in (0xE81, 0xF01, 0x122, 0x381, 0x041, 0xFC1, 0xF85, 0x201, 0x301, 0x401):
        await page_expect_loud(dut, a, 0x3, "비정렬 쓰기")
    await page_expect_loud(dut, MASK_PART + 1, 0x3, "비정렬 MASK_PART")
    assert await mmio_read(dut, MASK_PART) == 0, "비정렬 MASK_PART 쓰기가 창을 움직였다"
    await page_expect_loud(dut, 0xF41, 0xDEADBEEF, "비정렬 ABORT_TAG0")
    assert await mmio_read(dut, ABORT_ARM) == 0, "비정렬 ABORT_TAG0 쓰기가 무장을 세웠다 (E.12.1 1항)"
    # 비정렬 읽기는 0 · fault 없음
    for a in (0xE81, 0xFFD, 0x3FD):
        await page_expect_read0(dut, a, "비정렬 읽기")


@cocotb.test()
async def fp_clear_window(dut):
    """선택자 표 초기화 소거(2^16 사이클) 중의 FP 구역 — D1 (b).

    버스 마스터 규약대로 스트로브를 ready 까지 붙든다. 주소 기준 ready(D1 이전)에서는 ①
    의 읽기가 잡힌 채 매 사이클 응답한다 — 음성 대조는 그 생성물 사본에서 ① 이 운다.
    """
    await boot_hiu(dut)             # 소거를 기다리지 않는다 — 창 *안*에서 잰다
    st = await mmio_read(dut, FP_STATUS)
    assert st & 1 == 0, f"FP_STATUS [0] loadReady = 1 — 소거 창 밖이다 (0x{st:08X})"
    # ① 0xF00 정렬 읽기 → 기다리지 않는다 · rvalid 정확히 1회 · 값 0 (WO 읽기)
    dut.io_mmio_addr.value = FP_PROG
    dut.io_mmio_rstrobe.value = 1
    await settle(dut)
    held, rv, vals = 0, 0, []
    while int(dut.io_mmio_ready.value) == 0 and held < 64:
        await step(dut)
        held += 1
        if int(dut.io_mmio_rvalid.value):     # 잡혀 있는 동안의 응답도 센다
            rv += 1
            vals.append(int(dut.io_mmio_rdata.value))
    await step(dut)                                  # 수락 엣지
    dut.io_mmio_rstrobe.value = 0
    for _ in range(4):
        await settle(dut)
        if int(dut.io_mmio_rvalid.value):
            rv += 1
            vals.append(int(dut.io_mmio_rdata.value))
        await step(dut)
    assert held == 0, (f"① 소거 중 0xF00 읽기가 {held} 사이클 잡혔다 (그동안 rvalid {rv} 회) — "
                       f"읽기는 소거를 기다리지 않는다 (D1 (b))")
    assert rv == 1 and vals == [0], f"① rvalid {rv} 회 · 값 {vals} — 정확히 1회 · 0 이어야 한다"
    # ③ 0xF01 비정렬 쓰기 → 정지 없이 [6] (판정 T2 (a))
    dut.io_mmio_addr.value = FP_PROG + 1
    dut.io_mmio_wdata.value = 0x12345678
    dut.io_mmio_wstrobe.value = 1
    await settle(dut)
    assert int(dut.io_mmio_ready.value) == 1, "③ 소거 중 0xF01 비정렬 쓰기가 정지했다 — 정렬 FP 쓰기만 기다린다"
    await step(dut)
    dut.io_mmio_wstrobe.value = 0
    await step(dut)
    assert await fault6(dut) == 1, "③ 0xF01 비정렬 쓰기에 [6] 이 서지 않았다"
    await clear_fault6(dut)
    assert int(dut.io_fault_fpCfgBadWrite.value) == 0
    # ② [30:24] ≠ 0 FP_BIND 를 소거 중에 제시 → loadReady 전까지 ready = 0 · 어느 sticky 도 안 선다 ·
    #   수락 뒤 fpCfgBadWrite = 1 · 0xF80[6] = 1
    dut.io_mmio_addr.value = FP_BIND
    dut.io_mmio_wdata.value = (1 << 24) | 0x1234
    dut.io_mmio_wstrobe.value = 1
    await settle(dut)
    n = 0
    while int(dut.io_mmio_ready.value) == 0:
        assert int(dut.io_fault_fpCfgBadWrite.value) == 0, (
            f"② 잡힌 FP_BIND 가 {n} 사이클에 fpCfgBadWrite 를 세웠다 — 수락 전 loud")
        assert int(dut.io_fault_cfgSurfBadWrite.value) == 0, (
            f"② 잡힌 FP_BIND 가 {n} 사이클에 조립 sticky 를 세웠다 — 수락 전 loud")
        await step(dut)
        n += 1
        if n > INIT_SWEEP + 64:
            raise AssertionError(f"② FP_BIND 가 {n} 엣지 안에 수락되지 않았다 — 미완료는 통과가 아니다")
    assert n > 1000, f"② FP_BIND 가 {n} 사이클 만에 수락됐다 — 소거 창 안에서 제시하지 못했다"
    await step(dut)                                  # 수락 엣지 (loadReady = 1)
    dut.io_mmio_wstrobe.value = 0
    await settle(dut)
    assert int(dut.io_fault_fpCfgBadWrite.value) == 1, "② 수락된 FP_BIND 예약 비0 에 fpCfgBadWrite 가 서지 않았다"
    assert int(dut.io_fault_cfgSurfBadWrite.value) == 0, "② FP_BIND 거절이 조립 sticky 로 새었다 (원천별 수출)"
    await step(dut)
    assert await fault6(dut) == 1, "② 0xF80[6] 에 FP_BIND 거절이 합류하지 않았다"
    await clear_fault6(dut)
    assert int(dut.io_fault_fpCfgBadWrite.value) == 0, "0xF84[6] W1C 가 fpCfgBadWrite 를 내리지 못했다"


# ── 미적중 관측 값 — 0xE04 XLATE_STATUS · 0xE08/0xE0C XLATE_MISS_VPN (파도 4 · 판정 E04 (A)) ──
#
# 정본 e-defined.typ:323 「정지 중(`[0]` = 1)에만 정지한 요청의 값을 내고 정지가 없으면 0 이다」 —
# 정지 게이트 스냅샷. 선-formal rtl/formal/tla/XlateObs.tla · 후-formal hiumask.sby(파이프라인
# 절반) · assembly.sby(포장 절반). 여기는 값 수준이다: 호스트가 관측면만 보고 무엇을 기입할지
# 알 수 있는가 (E.3 파생 요건 — e-defined.typ:881 「채널이 없으면 2항은 이행 불가능한」).
XCTL_MISS_VPN_LO = 0xE08
XCTL_MISS_VPN_HI = 0xE0C


def xstatus_word(stall, sticky, part):
    """XLATE_STATUS — `[0]` 정지 · `[1]` sticky · `[15:8]` 파티션 · 나머지 0."""
    return (int(stall) & 1) | ((int(sticky) & 1) << 1) | ((part & 0xFF) << 8)


async def read_obs(dut):
    return (await mmio_read(dut, XCTL_STATUS), await mmio_read(dut, XCTL_MISS_VPN_LO),
            await mmio_read(dut, XCTL_MISS_VPN_HI))


@cocotb.test()
async def xlate_miss_observed(dut):
    """(E04-1) 정지 게이트 스냅샷의 값 — 정지 전 0 · 정지 중 [0]=1 · [1]=1 · [15:8] 파티션 ·
    VPN 두 워드 · 재읽기 불변(읽기는 해제하지 않는다) · 정지한 파티션의 flush 도 스냅샷을
    바꾸지 않는다(정지한 요청을 바꾸는 것은 항목 기입뿐) · 항목 기입 뒤 [0]=0 · [15:8] · VPN
    0 (잔재 없음) · sticky [1] 은 0xE10 까지 남는다."""
    await boot_hiu(dut)
    part, idx, tag, frame = 2, 5, 0x0ABC123, 0x0000_5A5A
    vpn = vpn_of(tag, idx)
    await mmio_write(dut, OWN_SET, frame)
    assert await read_obs(dut) == (0, 0, 0), "정지 전의 관측 세 워드는 0 이어야 한다"
    res = await hiu_lookup(dut, part, vpn)
    assert_miss(dut, res, "빈 표")
    want = (xstatus_word(1, 1, part), vpn, 0)
    got = await read_obs(dut)
    assert got == want, (
        f"정지 중 관측 {tuple(hex(v) for v in got)} ≠ 기대 {tuple(hex(v) for v in want)} — "
        f"[0] 정지 · [1] sticky · [15:8] 파티션 {part} · VPN 0x{vpn:08X} · VPN_HI 0 (VA 44b)")
    assert await read_obs(dut) == want, "재읽기가 달라졌다 — 읽기가 무엇인가를 해제했거나 스냅샷이 찢겼다"
    assert int(dut.io_hiuReq_ready.value) == 0, "관측 읽기가 정지를 풀었다"
    await mmio_write(dut, XCTL_FLUSH, part)
    assert await read_obs(dut) == want, "정지한 파티션의 flush 가 스냅샷을 바꿨다 — 정지한 요청을 바꾸는 것은 항목 기입뿐이다"
    assert int(dut.io_hiuReq_ready.value) == 0
    # 호스트는 관측면만으로 항목을 안다 — 읽은 파티션 · VPN 그대로 기입한다.
    status, vlo, _ = got
    hpart, hvpn = (status >> 8) & 0xFF, vlo
    await install_entry(dut, hpart, hvpn & 0xF, hvpn >> 4, frame)
    rsp = await wait_rsp(dut)
    assert rsp["rsp"] == 1 and rsp["granted"] == 1 and rsp["frame"] == frame, (
        f"관측면이 알려 준 항목을 기입했는데 정지가 풀리지 않았다 ({rsp})")
    await step(dut, 2)
    assert await read_obs(dut) == (xstatus_word(0, 1, 0), 0, 0), (
        "정지가 풀린 뒤: [0] 0 · [1] sticky 1 · [15:8] 과 VPN 0 이어야 한다 — 끝난 정지의 잔재가 남았다")
    await mmio_write(dut, XCTL_MISS_CLEAR, 1)
    assert await read_obs(dut) == (0, 0, 0), "0xE10 해제 뒤 관측 세 워드는 0 이어야 한다"
    dut._log.info("미적중 관측: 정지 전 0 · 정지 중 스냅샷 · 재읽기 · flush 불변 · 관측면만으로 채움 · "
                  "해제 뒤 잔재 없음 · sticky 는 0xE10 까지")


@cocotb.test()
async def xlate_miss_obs_second_stall(dut):
    """(E04-2) 해제 없이 온 둘째 정지는 *둘째* 요청을 낸다 — 첫 미적중 포착(sticky 상승 때
    래치하는 구현)이면 여기서 첫 요청의 VPN 이 읽혀 호스트가 엉뚱한 항목을 채우고 정지가
    영구가 된다 (XlateObs.tla 진행 짝 live_del_vpn 의 값 판)."""
    await boot_hiu(dut)
    f1, f2 = 0x0000_1111, 0x0000_2222
    p1, i1, t1 = 1, 3, 0x0000ABC
    p2, i2, t2 = 3, 7, 0x0DEF000
    v1, v2 = vpn_of(t1, i1), vpn_of(t2, i2)
    await mmio_write(dut, OWN_SET, f1)
    await mmio_write(dut, OWN_SET, f2)
    assert_miss(dut, await hiu_lookup(dut, p1, v1), "첫 요청")
    assert await read_obs(dut) == (xstatus_word(1, 1, p1), v1, 0)
    await install_entry(dut, p1, i1, t1, f1)
    r = await wait_rsp(dut)
    assert r["rsp"] == 1 and r["frame"] == f1, f"첫 항목 기입이 정지를 풀지 못했다 ({r})"
    await step(dut, 2)
    # 해제(0xE10) 없이 둘째 미적중 — sticky 는 선 채다.
    assert_miss(dut, await hiu_lookup(dut, p2, v2), "둘째 요청")
    got = await read_obs(dut)
    assert got == (xstatus_word(1, 1, p2), v2, 0), (
        f"둘째 정지의 관측 {tuple(hex(v) for v in got)} — 파티션 {p2} · VPN 0x{v2:08X} 이어야 한다 "
        f"(첫 요청 0x{v1:08X} 가 읽히면 첫 미적중 포착이다)")
    await install_entry(dut, (got[0] >> 8) & 0xFF, got[1] & 0xF, got[1] >> 4, f2)
    r = await wait_rsp(dut)
    assert r["rsp"] == 1 and r["frame"] == f2, f"둘째 관측으로 채운 항목이 정지를 풀지 못했다 ({r})"
    dut._log.info("둘째 정지 → 둘째 요청의 파티션 · VPN (첫 미적중 포착 아님) · 관측면만으로 두 정지를 다 푼다")


# ═══════════════════════════════════════════════════════════════════════════
# 판정 T5 (a) 의 범위 — flush 가 스테이징을 비우는 것은 *래치 파티션*의 *수락된* flush 뿐
# ═══════════════════════════════════════════════════════════════════════════
# e-defined.typ:321 「다른 파티션을 래치한 스테이징은 건드리지 않는다」 · 거절된 flush 는
# 효과가 없다 (「없는 파티션 값의 처분」 1항 · E.12.1 1항과 같은 형태). xlate_flush_ends_staging 의 짝이다 —
# 파티션을 가리지 않고 비우는 판(전역 비움)이나 거절된 flush 로도 비우는 판은 여기서
# 적법한 LO → HI 를 거절 + [6] 으로 만든다.

@cocotb.test()
async def xlate_other_flush_keeps_staging(dut):
    """LO{p}(F) → flush(q ≠ p) → HI{p} 는 거절 없이 커밋되어 F 로 적중한다. 이어서
    LO{p}(F2) → 예약 위반 flush(p)(거절 + [6]) → [6] 해제 → HI{p} 도 커밋되어 F2 로
    적중한다 — 거절된 flush 는 스테이징에 닿지 않는다."""
    await boot_hiu(dut)
    part, opart, idx = 2, 1, 4
    tag, frame = 0x0055AA5, 0x0000_C0DE
    tag2, frame2 = 0x0066BB6, 0x0000_C1E5    # 소유권 표 직접 사상 — frame 과 다른 슬롯(하위 6b)
    await mmio_write(dut, OWN_SET, frame)
    await mmio_write(dut, OWN_SET, frame2)
    await mmio_write(dut, xent(part, idx), frame)              # LO{p}
    await mmio_write(dut, XCTL_FLUSH, opart)                   # flush(q ≠ p) — 수락
    assert await fault6(dut) == 0, "적법한 XLATE_FLUSH 가 [6] 을 세웠다"
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag))   # HI{p}
    assert await fault6(dut) == 0, (
        f"파티션 {opart} 의 flush 뒤 파티션 {part} 을 래치한 스테이징의 HI 가 거절됐다 — "
        f"flush 가 다른 파티션의 스테이징까지 비웠다 (E.1.2 `0xE00` 행 위반 · 전역 비움)")
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag, idx)), frame,
               "타 파티션 flush 를 건넌 스테이징의 커밋")
    await mmio_write(dut, xent(part, idx), frame2)             # LO{p}(F2)
    await mmio_write(dut, XCTL_FLUSH, (1 << 8) | part)         # 예약 [31:8] 비0 — 거절
    assert await fault6(dut) == 1, "예약 위반 XLATE_FLUSH 가 거절되지 않았다"
    await clear_fault6(dut)
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag2))  # HI{p}
    assert await fault6(dut) == 0, (
        "거절된 XLATE_FLUSH 뒤의 적법한 HI 가 거절됐다 — 거절된 flush 가 스테이징을 비웠다 "
        "(거절된 기입은 기입이 아니다)")
    assert_hit(await hiu_lookup(dut, part, vpn_of(tag2, idx)), frame2,
               "거절된 flush 를 건넌 스테이징의 커밋")
    dut._log.info("타 파티션 flush · 거절된 flush 는 스테이징에 닿지 않는다 — HI 커밋 · 적중 (판정 T5 (a) 범위)")


# ═══════════════════════════════════════════════════════════════════════════
# W1 — 표면 비트 · 워드: 0xFF8 HIU_SHAPE · 0xEC4 MASK_DUP_CAPTURE · FAULT_STATUS [19]
# ═══════════════════════════════════════════════════════════════════════════
#
# 3.10 v1.0 묶음이 신설한 세 표면의 *호스트가 보는 값* 시험 (N12 · N13 · N14).
# 선-formal 은 rtl/formal/tla/ 의 Platform.tla(원인별 보고 [4]/[19]) · Mask.tla(캡처) ·
# MmioPage.tla(RO 처분)이고, 후-formal 은 hiumask · engine · assembly 하네스다. 여기는
# 그 결과가 0xF80 · 0xEC4 · 0xFF8 의 값으로 나타나는지를 잰다.
#
# **기대값은 정본 표에서 독립 유도한다** — RTL companion 의 상수(비트 자리 · 오프셋 ·
# 형상 · 비트 수)를 import 하지도 옮겨 적지도 않는다. 기대측이 RTL 에서 오면 RTL 과
# 함께 틀리고, 시험은 실패하지 않고 *부재*로 침묵한다 (차등 정의역 함정). 비트 자리는
# 정본 「FAULT_STATUS 비트 배정」 표, 오프셋은 E.1.2 표, 형상은 E.2 의 참조 구현 문장이다:
#   e-defined.typ:765 「파티션 4 × 항목 16 = 64 항목 · 직접 사상 · 항목 8 B」
#   e-defined.typ:503 「두 필드 다 *개수*로 인코딩한다」
#
# 표 시험(N13 · N14)은 행마다 관측을 모으고 **끝에 정본 모형의 행 표와 통째로 등가
# 비교**한다 — 어긋난 행이 한 번에 전부 보이게(음성 대조의 기록이 「첫 실패 한 줄」로
# 줄지 않게). 자극의 전건(엔진 유휴 · 키 기입의 유효 하강 · 정지 도달)은 행 표가 아니라
# 그 자리에서 단언한다 — 전건이 무너진 행은 비교 대상이 아니다.

B_XLATE_PERM = 4         # [4]  변환 권한 위반 — 자격(권한 비트) 거부
B_MASK_NONCE_DUP = 12    # [12] 논스 재사용 재키잉
B_OWN_FRAME = 19         # [19] 비소유 프레임 접근 — 3.10 v1.0 묶음이 [4] 에서 갈라 신설
FLT_RSV_LO = 20          # 0xF84 예약 [31:20] (엄격) 의 최하위 비트
FAULT_SUMMARY = 0xF88    # RO — [0] = FAULT_STATUS 의 정의 비트 어느 하나라도 1 (E.1.2 `0xF88` 행)

HIU_SHAPE = 0xFF8
REF_PARTS = 4            # 참조 구현의 파티션 수
REF_SLOTS_PER_PART = 16  # 직접 사상이라 파티션당 저장 칸 = 파티션당 항목 16
HIU_SHAPE_REF = (REF_SLOTS_PER_PART << 8) | REF_PARTS   # [23:8] 칸 수 · [7:0] 파티션 수 — 0x0000_1004

MASK_KEY0 = 0xE80          # MASK_KEY[0..7]   WO — MASK_PART 창이 대상 파티션
MASK_NONCE0 = 0xEA4        # MASK_NONCE[0..5] WO — 같은 창
MASK_REKEY = 0xEBC         # WO — 기입이 발화 · [7:0] 파티션 · [31:8] 예약(엄격)
MASK_STATUS = 0xEC0        # RO — [7:0] 파티션별 준비 · [8] busy · [9] 재키잉 수락 가능
MASK_DUP_CAPTURE = 0xEC4   # RO — [7:0] p · [15:8] 비트맵 · [16] 캡처 유효 · [31:17] 0
MASK_KEY_WORDS = 8
MASK_NONCE_WORDS = 6


def bit(v, b):
    return (v >> b) & 1


def table_diff(rows, want):
    """행 표 대조의 실패 문면 — 어긋난 행에 `!!` 를 단다. 32b 값은 16진으로."""
    def fmt(t):
        return "(" + ", ".join(f"0x{x:08X}" if isinstance(x, int) and x > 0xFF else repr(x)
                               for x in t) + ")"
    out = []
    for (lg, *g), (lw, *w) in zip(rows, want):
        mark = "  " if (lg, g) == (lw, w) else "!!"
        out.append(f"  {mark} {lg}: 관측 {fmt(g)} · 기대 {fmt(w)}")
    if len(rows) != len(want):
        out.append(f"  !! 행 수 {len(rows)} ≠ 기대 {len(want)}")
    return "\n".join(out)


@cocotb.test()
async def hiu_shape_word(dut):
    """N12 — `0xFF8` HIU_SHAPE (W1-3 · DP-7). 정본 E.1.2 `0xFF8` 행: RO · `[7:0]` 실재
    파티션 수 · `[23:8]` 파티션당 저장 칸 수 · `[31:24]` 0 · 두 필드 다 개수 인코딩 ·
    쓰기는 거절 + `[6]`.

    재는 것: ① 읽기 값 == 참조 형상에서 유도한 0x0000_1004 (재읽기 불변 · 읽기는 fault
    없음) ② 쓰기 셋(전폭 1 · 읽은 값 그대로 · 0)이 *값과 무관하게* 거절 + `[6]` 이고 값을
    움직이지 않는다 ③ `[7:0]` 이 「실재 파티션 수」라는 뜻을 다른 표면과 맞물려 본다 —
    그 수 미만의 XLATE_FLUSH 는 수락, 그 수 자체는 없는 파티션 값이라 거절 + `[6]`.

    재지 않는 것: `[23:8]` 의 칸 수는 *정보*이고 정합성이 거기 기대지 않는다(정본
    `0xC00` (g)) — 임의 VPN 집합의 동시 상주는 보장이 아니므로 칸 수를 상주 실험으로
    재지 않는다. DUT 는 기본 형상(참조 구현) 하나뿐이라 다른 형상의 값은 미측정이다.
    HEAD 생성물에서는 `0xFF8` 이 예약 오프셋이라 ① 이 0 을 읽어 죽는다 — 정본상
    `[7:0]` = 0 은 「표면 없음」이므로 장치가 자기 표면을 부인하는 꼴이다.
    """
    await boot_hiu(dut)
    v = await mmio_read(dut, HIU_SHAPE)
    assert v == HIU_SHAPE_REF, (
        f"0xFF8 HIU_SHAPE = 0x{v:08X} ≠ 참조 형상 0x{HIU_SHAPE_REF:08X} — 읽은 값의 [7:0] "
        f"파티션 {v & 0xFF} · [23:8] 칸 {(v >> 8) & 0xFFFF} · [31:24] {v >> 24} (기대 "
        f"{REF_PARTS} · {REF_SLOTS_PER_PART} · 0 — 개수 인코딩이지 log2 가 아니다)")
    assert await mmio_read(dut, HIU_SHAPE) == v, "0xFF8 재읽기가 달라졌다"
    assert await fault6(dut) == 0, "0xFF8 읽기가 [6] 을 세웠다 — 읽기는 fault 가 없다"
    for what, data in (("전폭 1", 0xFFFF_FFFF), ("읽은 값 그대로", v), ("0", 0)):
        await mmio_write(dut, HIU_SHAPE, data)
        assert await fault6(dut) == 1, (
            f"0xFF8 쓰기({what} 0x{data:08X})가 거절 + [6] 이 아니다 — RO 워드의 쓰기는 "
            f"값과 무관하게 거절이다 (조용한 흡수)")
        await clear_fault6(dut)
        got = await mmio_read(dut, HIU_SHAPE)
        assert got == v, f"거절된 0xFF8 쓰기({what})가 값을 움직였다: 0x{got:08X} ≠ 0x{v:08X}"
    parts = v & 0xFF
    for p in range(parts):
        await mmio_write(dut, XCTL_FLUSH, p)
        assert await fault6(dut) == 0, (
            f"0xFF8 [7:0] = {parts} 인데 파티션 {p} 의 XLATE_FLUSH 가 거절됐다 — 「실재 "
            f"파티션 수」가 파티션을 받는 표면과 맞물리지 않는다")
    await mmio_write(dut, XCTL_FLUSH, parts)
    assert await fault6(dut) == 1, (
        f"0xFF8 [7:0] = {parts} 인데 파티션 값 {parts} 의 XLATE_FLUSH 가 수락됐다 — "
        f"[7:0] 이 실재 파티션 수보다 작다")
    await clear_fault6(dut)
    dut._log.info(f"HIU_SHAPE 0x{v:08X} — 파티션 {parts} · 칸 {(v >> 8) & 0xFFFF} · RO 쓰기 셋 "
                  f"거절 + [6] · 값 불변 · [7:0] 이 XLATE_FLUSH 수락 정의역과 일치")


# ── N13 — 0xEC4 MASK_DUP_CAPTURE (W1-4 · DP-8) ─────────────────────────────
#
# 기대 모형은 정본 E.1.2 `0xEC4` 행 · `0xEBC` 행의 문장을 그대로 옮긴 것이다:
#   e-defined.typ:347 「`[16]` = 1 동안의 새 발화는 캡처를 덮지 않는다」
#   e-defined.typ:347 「해제와 새 발화가 같은 사이클이면 새 사건을 래치한다」
#   e-defined.typ:345 「거절 + `[6]` 인 발화는 `[12]` 도 `0xEC4` 도 움직이지 않는다」
# 비트맵의 정의역(마스크가 유효한 *다른* 파티션 중 논스가 p 의 새 논스와 같은 것)에서
# 「마스크 유효」는 발화 직전에 호스트가 보는 MASK_STATUS `[7:0]` 이고, 논스는 하네스가
# 쓴 값이다. `[12]` 를 동반한 재키잉 뒤의 준비 비트는 정본상 구현 정의라 가정하지 않고
# 읽는다 — 대신 시나리오가 발화를 요구하는 행마다 모형이 실제로 발화를 예측했는지를
# 그 자리에서 단언한다 (전건 확인 — 준비 비트가 바뀌어 행이 공허해지면 크게 죽는다).

class DupCaptureModel:
    """`[12]`(= `0xEC4` `[16]`)와 캡처 필드의 정본 모형 — RTL 을 보지 않는다."""

    def __init__(self):
        self.dup = False      # [12] — 불변식 [16] ⇔ [12] 라 둘이 한 변수다
        self.cap = (0, 0)     # (p, 비트맵) — dup 일 때만 뜻이 있다

    def word(self):
        p, bm = self.cap
        return ((1 << 16) | (bm << 8) | p) if self.dup else 0

    def started(self, p, ready, nonce, clear=False):
        """*재키잉이 시작된* 발화(엔진 유휴에서 수락 · 값 검사 통과)의 수락 사이클.
        `clear` 는 같은 사이클의 해제다. 발화(겹침)가 있었는지를 돌려준다."""
        mine = nonce.get(p)
        hits = [q for q in sorted(ready)
                if q != p and mine is not None and nonce.get(q) == mine]
        fire, held = bool(hits), self.dup
        if clear:
            self.cap = (0, 0)
        if fire and (not held or clear):
            self.cap = (p, sum(1 << q for q in hits))
        self.dup = fire or (held and not clear)
        return fire

    def inert(self, clear=False):
        """거절 + [6] 인 발화 · 엔진 바쁨으로 수락되지 않은 발화 · 해제 단독.
        세움도 래치도 없다 — 같은 사이클 해제만 일어날 수 있다."""
        if clear:
            self.dup, self.cap = False, (0, 0)


async def mask_cfg(dut, part, nonce_words, key_words=None):
    """MASK_PART 창을 `part` 로 두고 (키와) 논스를 쓴다 — 둘 다 그 파티션의 준비를 내린다."""
    await mmio_write(dut, MASK_PART, part)
    for i, k in enumerate(key_words or ()):
        await mmio_write(dut, MASK_KEY0 + 4 * i, k)
    for i, n in enumerate(nonce_words):
        await mmio_write(dut, MASK_NONCE0 + 4 * i, n)


async def mask_status(dut):
    """MASK_STATUS → (준비 파티션 집합, busy, 재키잉 수락 가능)."""
    v = await mmio_read(dut, MASK_STATUS)
    return {q for q in range(8) if bit(v, q)}, bit(v, 8), bit(v, 9)


async def mask_rekey(dut, word, io_clear=False):
    """MASK_REKEY 한 기입. 수락 에지에 내부 해제선 `io_faultClear_maskNonceDup` 을 맞출 수 있다.

    그 선은 호스트 계약 밖의 조립 IO 다 (E.1.2 `0xF84` 행 — 제품 결선은 0). 0xF84 W1C 와
    MASK_REKEY 는 버스가 하나라 같은 사이클에 올 수 없으므로 「같은 사이클 해제 + 발화」는
    이 선으로만 만든다 — 정본 `0xEC4` 행이 이 선도 `[12]` 와 같은 해제 신호라고 적는다.
    """
    dut.io_mmio_addr.value = MASK_REKEY
    dut.io_mmio_wdata.value = word
    dut.io_mmio_wstrobe.value = 1
    if io_clear:
        dut.io_faultClear_maskNonceDup.value = 1
    await settle(dut)
    assert int(dut.io_mmio_ready.value) == 1, (
        "MASK_REKEY 기입이 버스에서 잡혔다 — 해제선을 수락 에지에 맞출 수 없다")
    await step(dut)            # 수락 에지 — 발화(와 해제)가 이 에지 하나에 실린다
    dut.io_mmio_wstrobe.value = 0
    dut.io_faultClear_maskNonceDup.value = 0
    await step(dut)
    await settle(dut)


async def mask_wait_idle(dut, limit=64):
    """MASK_STATUS `[8]` 하강까지 — 준비 집합을 돌려준다. 상한 초과는 FAIL."""
    for _ in range(limit):
        ready, busy, _ = await mask_status(dut)
        if not busy:
            return ready
    raise AssertionError(
        f"MASK_STATUS [8] busy 가 {limit} 회 읽기 안에 내려가지 않았다 — 미완료는 통과가 아니다")


@cocotb.test()
async def mask_dup_capture(dut):
    """N13 — `0xEC4` MASK_DUP_CAPTURE 의 MMIO 판 (W1-4 · DP-8 · 선-formal Mask.tla).

    재는 것 (행 표 — 행마다 `0xF80` `[12]` · `[6]` · `0xEC4` 를 뜬다):
      · reset 0 · 겹침 없는 재키잉은 0 · 첫 겹침에서 p · 비트맵(다른 유효 파티션 중
        같은 논스) · `[16]` 래치, 불변식 `[16]` ⇔ `[12]` (기대 행이 한 변수에서 나온다)
      · 읽기 무부작용 — `0xEC4` · `0xF80` 읽기가 `[12]` · 캡처를 내리지 않는다
      · `0xEC4` 쓰기 → 거절 + `[6]` · 캡처 불변
      · 첫 사건 보존 — `[16]` = 1 동안의 새 겹침 발화는 덮지 않는다
      · `0xF84` `[12]` 해제가 워드 전체(p · 비트맵 포함)를 지운다
      · 비트맵 정의역 셋 — 유효한 p 자신(재재키잉) · 유효가 내려간 같은 논스 파티션 ·
        유효하지만 논스가 다른 파티션은 들지 않는다
      · 거절 + `[6]` 인 발화(예약 비트 · 없는 파티션 값)와 엔진 바쁨으로 미수락된
        발화는 전건이 서 있어도 `[12]` · `0xEC4` 를 움직이지 않는다
      · 같은 사이클 해제(내부 해제선) + 발화 → 세움이 이기고 *새* 사건을 래치한다 —
        p 와 비트맵이 *둘 다* 앞 사건과 다르게 골라, 한쪽만 새로 담는 판을 가른다
      · 내부 해제선 단독도 워드를 지운다 · 바쁨 미수락 발화 · 거절 발화에 해제선이
        겹치면 해제만 일어난다

    재지 않는 것: 논스 192b 의 전폭 비교(여기 논스는 두 값뿐 — engine.sby 몫) ·
    reset 형식 단언(W1-8 미실시 — reset 직후 0 은 한 점 관측일 뿐) · 0xF84 W1C 와 발화의
    같은 사이클(버스가 하나라 만들 수 없다).
    HEAD 생성물에서는 `0xEC4` 가 디코드되지 않아 읽기 0 · 쓰기 무시다 — `[12]` 열은 모형과
    같고 `0xEC4` 열 · 쓰기 거절 행만 어긋날 것으로 예상한다 (음성 대조).
    """
    await boot_hiu(dut)
    NA = [0xA5A5_0000 | i for i in range(MASK_NONCE_WORDS)]
    NB = [0xB4B4_0000 | i for i in range(MASK_NONCE_WORDS)]

    def key(p):
        return [0x1000_0000 | (p << 8) | i for i in range(MASK_KEY_WORDS)]

    model, nonce = DupCaptureModel(), {}
    rows, want = [], []

    async def note(label, exp6=0):
        f = await mmio_read(dut, FAULT_STATUS)
        c = await mmio_read(dut, MASK_DUP_CAPTURE)
        rows.append((label, bit(f, B_MASK_NONCE_DUP), bit(f, B_CFG_BADWRITE), c))
        want.append((label, int(model.dup), exp6, model.word()))

    async def started(p, label, must_fire, io_clear=False, wait=True):
        ready, busy, rk = await mask_status(dut)
        assert (busy, rk) == (0, 1), (
            f"[{label}] 발화 직전 엔진이 유휴가 아니다 (busy={busy} · 수락 가능={rk}) — 자극이 계약 밖")
        fire = model.started(p, ready, nonce, clear=io_clear)
        assert fire == must_fire, (
            f"[{label}] 전건 불성립 — 준비 {sorted(ready)} · 논스 모형으로 겹침 예측 {fire} ≠ "
            f"시나리오 {must_fire}. 공허한 행은 비교 대상이 아니다")
        await mask_rekey(dut, p, io_clear=io_clear)
        await note(label)
        if wait:
            after = await mask_wait_idle(dut)
            if not must_fire:
                assert p in after, (
                    f"[{label}] 겹침 없는 재키잉이 끝났는데 파티션 {p} 준비가 서지 않았다 (준비 {sorted(after)})")

    async def clear12(label):
        await mmio_write(dut, FAULT_CLEAR, 1 << B_MASK_NONCE_DUP)
        model.inert(clear=True)
        await note(label)

    async def pulse_io_clear(label):
        dut.io_faultClear_maskNonceDup.value = 1
        await step(dut)
        dut.io_faultClear_maskNonceDup.value = 0
        await step(dut)
        model.inert(clear=True)
        await note(label)

    await note("reset — [12] · 0xEC4 0")
    nonce[0] = tuple(NA)
    await mask_cfg(dut, 0, NA, key(0))
    await started(0, "p0 재키잉 — 겹침 없음", must_fire=False)
    nonce[2] = tuple(NB)
    await mask_cfg(dut, 2, NB, key(2))
    await started(2, "p2 재키잉 — 다른 논스", must_fire=False)
    nonce[1] = tuple(NA)
    await mask_cfg(dut, 1, NA, key(1))
    await started(1, "p1 재키잉 — p0 과 같은 논스: 래치", must_fire=True)
    for _ in range(2):
        await mmio_read(dut, MASK_DUP_CAPTURE)
        await mmio_read(dut, FAULT_STATUS)
    await note("0xEC4 · 0xF80 재읽기 둘 — 읽기는 아무것도 해제하지 않는다")
    await mmio_write(dut, MASK_DUP_CAPTURE, 0xFFFF_FFFF)
    await note("0xEC4 쓰기 — 거절 + [6] · 캡처 불변", exp6=1)
    await clear_fault6(dut)
    nonce[3] = tuple(NA)
    await mask_cfg(dut, 3, NA, key(3))
    await started(3, "p3 재키잉 — [16]=1 동안의 새 겹침 발화는 덮지 않는다", must_fire=True)
    await clear12("0xF84 [12] — [12] 와 워드 전체 해제")
    await started(3, "p3 재재키잉 — 유효한 p 자신은 비트맵에 들지 않는다", must_fire=True)
    await clear12("0xF84 [12] — 해제")
    await mmio_write(dut, MASK_PART, 1)
    await mmio_write(dut, MASK_KEY0, 0x5A5A_5A5A)
    ready, _, _ = await mask_status(dut)
    assert 1 not in ready, (
        f"p1 키 기입 뒤 준비 {sorted(ready)} — 키 기입이 그 파티션의 마스크 유효를 떨어뜨리지 "
        f"않았다: 자극이 계약 밖")
    await started(3, "p3 재재키잉 — 유효가 내려간 p1(같은 논스) · 논스가 다른 p2 는 들지 않는다",
                  must_fire=True)
    await clear12("0xF84 [12] — 해제")
    for what, word in (("예약 [31:8] 비0", (1 << 8) | 3), ("없는 파티션 값", REF_PARTS)):
        await mask_rekey(dut, word)
        model.inert()
        await note(f"MASK_REKEY {what} — 거절 + [6] · [12] · 0xEC4 불변", exp6=1)
        await clear_fault6(dut)
    await started(2, "p2 재재키잉 — 겹침 없음 (엔진 바쁨을 만든다)", must_fire=False, wait=False)
    _, busy, rk = await mask_status(dut)
    assert (busy, rk) == (1, 0), f"엔진 바쁨 창이 아니다 (busy={busy} · 수락 가능={rk}) — 자극이 계약 밖"
    await mask_rekey(dut, 3)
    model.inert()
    await note("엔진 바쁨 중 MASK_REKEY(p3, 겹칠 전건) — 미수락: [12] · 0xEC4 불변")
    after = await mask_wait_idle(dut)
    assert 2 in after, f"p2 재키잉이 끝났는데 준비가 서지 않았다 (준비 {sorted(after)})"
    await started(0, "p0 재재키잉 — p3 과 겹침: 래치", must_fire=True)
    held = model.cap
    await started(3, "내부 해제선 + p3 발화가 같은 사이클 — 세움이 이기고 새 사건을 래치",
                  must_fire=True, io_clear=True)
    assert model.cap[0] != held[0] and model.cap[1] != held[1], (
        f"시나리오 결함 — 새 사건 {model.cap} 이 앞 사건 {held} 와 p 또는 비트맵이 같다. "
        f"한쪽만 새로 담는 판을 가르지 못한다 (이것은 DUT 판정이 아니라 자극의 비공허 확인이다)")
    await pulse_io_clear("내부 해제선 단독 — [12] 와 워드 전체 해제")
    await started(0, "p0 재재키잉 — 다시 붙든다 (엔진 바쁨)", must_fire=True, wait=False)
    _, busy, rk = await mask_status(dut)
    assert (busy, rk) == (1, 0), f"엔진 바쁨 창이 아니다 (busy={busy} · 수락 가능={rk}) — 자극이 계약 밖"
    await mask_rekey(dut, 3, io_clear=True)
    model.inert(clear=True)
    await note("엔진 바쁨 미수락 발화 + 내부 해제선 — 해제만 (세움 · 래치 없음)")
    await mask_wait_idle(dut)
    await started(0, "p0 재재키잉 — 다시 붙든다", must_fire=True)
    await mask_rekey(dut, (1 << 8) | 3, io_clear=True)
    model.inert(clear=True)
    await note("거절 + [6] 발화 + 내부 해제선 — 해제만", exp6=1)
    await clear_fault6(dut)

    assert rows == want, (
        "0xEC4 MASK_DUP_CAPTURE 행 표가 정본 모형과 다르다 — 열은 ([12], [6], 0xEC4):\n"
        + table_diff(rows, want))
    dut._log.info(f"MASK_DUP_CAPTURE: {len(rows)} 행 전부 정본 모형과 등가 — 래치 · 첫 사건 보존 · "
                  f"해제(0xF84 · 내부 선) · 비트맵 정의역 셋 · 거절/미수락 불변 · 같은 사이클 세움 승리 · "
                  f"읽기 무부작용 · RO 쓰기 거절")


# ── N14 — FAULT_STATUS [19] 비소유 프레임 접근 (W1-1 · W1-2 · 선-formal Platform.tla) ──
#
#   e-defined.typ:527 「자격이 허용된 접근이 장치 소유가 아닌 프레임에 닿을 때만 `[19]` 가 선다」
#   e-defined.typ:527 「프레임이 무엇이든 `[4]` 로만 선다」
#   e-defined.typ:497 「예약 비트가 0 이 아니면 기입 전체를 거절(+ `[6]`)하고 한 비트도 내리지 않는다」
# 자격 = 요청 종류(읽기 · 쓰기)에 대한 권한 비트(R · W). 처분(값 차단 · 승인 거부 ·
# 상태열)은 두 원인이 같고 갈리는 것은 보고 비트뿐이다 — 그래서 행마다 승인 · 값 ·
# 응답까지의 사이클 수도 함께 뜬다(사이클 수의 기준은 같은 경로의 양성 대조 행).

FRAME_DEV = 0x0000_1040    # OWN_SET 으로 장치에 넘긴다
FRAME_HOST = 0x0000_2081   # 아무에게도 넘기지 않는다 — reset 소유는 호스트. 소유권 표의
                           # 직접 사상 슬롯(하위 비트)이 FRAME_DEV 와 겹치지 않게 골랐다

# (이름, 파티션, 색인, 태그, 프레임, (R, W, X), 쓰기, 경로, 기대 (승인, [4], [19]))
#   경로 "hit"  = 미리 커밋한 항목에 적중
#   경로 "fill" = 미적중 정지를 그 VPN 의 항목 커밋(채움)이 풀어 판정 (E.3 2항 — 거부 채움 포함)
N14_CASES = [
    ("소유 · 자격 허용 읽기 (적중 양성 대조)",          0, 1, 0x00A0001, FRAME_DEV, (1, 0, 0), 0, "hit", (1, 0, 0)),
    ("소유 · R=0 읽기 — 자격 거부",                     0, 2, 0x00A0002, FRAME_DEV, (0, 1, 1), 0, "hit", (0, 1, 0)),
    ("소유 · W=0 쓰기 — 자격 거부",                     0, 3, 0x00A0003, FRAME_DEV, (1, 0, 1), 1, "hit", (0, 1, 0)),
    ("비소유 · 자격 허용 읽기",                         1, 4, 0x00B0004, FRAME_HOST, (1, 0, 0), 0, "hit", (0, 0, 1)),
    ("비소유 · 자격 허용 쓰기",                         1, 5, 0x00B0005, FRAME_HOST, (0, 1, 0), 1, "hit", (0, 0, 1)),
    ("비소유 · R=0 읽기 — 자격이 먼저",                 1, 6, 0x00B0006, FRAME_HOST, (0, 1, 1), 0, "hit", (0, 1, 0)),
    ("비소유 · W=0 쓰기 — 자격이 먼저",                 1, 7, 0x00B0007, FRAME_HOST, (1, 0, 1), 1, "hit", (0, 1, 0)),
    ("거부 채움(RWX=0) · 소유 프레임 읽기",             2, 8, 0x00C0008, FRAME_DEV, (0, 0, 0), 0, "hit", (0, 1, 0)),
    ("거부 채움(RWX=0) · 비소유 프레임 쓰기",           2, 9, 0x00C0009, FRAME_HOST, (0, 0, 0), 1, "hit", (0, 1, 0)),
    ("정지 → 자격 허용 채움 · 소유 (채움 양성 대조)",   3, 10, 0x00D000A, FRAME_DEV, (1, 0, 0), 0, "fill", (1, 0, 0)),
    ("정지 → 자격 허용 채움 · 비소유",                  3, 11, 0x00D000B, FRAME_HOST, (1, 0, 0), 0, "fill", (0, 0, 1)),
    ("정지 → 거부 채움 · 비소유",                       3, 12, 0x00D000C, FRAME_HOST, (0, 0, 0), 0, "fill", (0, 1, 0)),
]


async def hiu_report(dut):
    """FAULT_STATUS 의 ([4], [19], [6]). 응답 사이클 뒤 sticky 가 앉고 MMIO 읽기가 한 에지
    늦으므로(실측) 두 에지를 먼저 흘린다."""
    await step(dut, 2)
    f = await mmio_read(dut, FAULT_STATUS)
    return bit(f, B_XLATE_PERM), bit(f, B_OWN_FRAME), bit(f, B_CFG_BADWRITE)


async def clear_hiu_report(dut, what):
    """[4] · [19] 를 0xF84 로 한 비트씩 — 선 것만 — 내리고 셋 다 0 인지 본다. 한 비트씩인
    이유: 한 기입에 섞으면 [19] 의 예약 거절(HEAD)이 [4] 해제까지 삼켜 행이 서로 번진다."""
    f = await mmio_read(dut, FAULT_STATUS)
    for b in (B_XLATE_PERM, B_OWN_FRAME):
        if bit(f, b):
            await mmio_write(dut, FAULT_CLEAR, 1 << b)
    got = await hiu_report(dut)
    assert got == (0, 0, 0), (
        f"[{what}] 앞 정리: 0xF84 한 비트 해제 뒤 ([4], [19], [6]) = {got} — 해제가 거절됐거나 "
        f"비트가 내려가지 않았다")


@cocotb.test()
async def fault19_nonowned_access(dut):
    """N14 — FAULT_STATUS `[19]` 비소유 프레임 접근 · 원인별 보고 (W1-1 · W1-2 · DP-9 · DP-11).

    재는 것 (행 표):
      · 접근 12 행 — 자격 거부(R=0 읽기 · W=0 쓰기) → `[4]` 만 · 자격 허용 ∧ 비소유
        → `[19]` 만 · 자격 거부 ∧ 비소유 → `[4]` 만(자격이 먼저) · 거부 채움(V=1 · RWX=0) →
        프레임과 무관하게 `[4]` 만. 적중 경로 9 행(양성 대조 포함)과 「미적중 정지를 채움이
        풀어 판정」 경로 3 행(양성 대조 · 자격 허용 비소유 · 거부 채움 비소유).
        행마다 승인 0 · 값 0(값 차단) · 응답까지의 사이클 수가 같은 경로의 양성 대조와
        같음(상태열 균일)을 함께 본다. 한 접근에 `[4]` · `[19]` 가 함께 서지 않는다.
      · reset 직후 — 어떤 해제도 하기 전에 `[4]` · `[19]` · `[6]` = 0 이고 원천별 수출 둘도 0
        (W1 검증 결함 X21 — `[19]` 원천의 reset 값 1 을 이 시험이 놓쳤다. 행마다 먼저 해제하는
        정리 헬퍼가 그 1 을 지워 버렸다. reset 의 *형식* 단언은 W1-8 로 미뤘고, 이것은 한 점 관측이다)
      · `[19]` sticky — 사이클이 흘러도 · 승인된 접근 뒤에도 · `0xF80` 재읽기 뒤에도 선다
      · `0xF84` — 예약 `[31:20]` 비0 기입은 거절 + `[6]` 이고 한 비트도 내리지 않는다
        (`[4]` 를 함께 실은 기입도) · `[19]` = 1 인 채 `1 << 4` 는 `[4]` 만 내리고 `[19]` 는 남는다
        (검증 결함 X04 — `[4]` 해제가 `[19]` 원천까지 내리는 판) · `1 << 19` 는 `[6]` 없이 `[19]` 만
        내린다 (`[4]` 는 남는다)
      · `0xF88` FAULT_SUMMARY — `[19]` *하나만* 선 상태(0xF84 로 `[18:0]` 을 지운 뒤)에서
        FAULT_STATUS = `1 << 19` · FAULT_SUMMARY = 1 (검증 결함 X02 — 요약이 `[19]` 를 빼는 판)
      · 원천별 수출 — `io_fault_hiuOwn` = `[19]` · `io_fault_hiuPerm` = `[4]` (포트 계약)

    재지 않는 것: 호스트 쪽 접근(HIU 요청 경로는 장치 쪽뿐이다) · `[19]` 해제와 발화의
    같은 사이클(assembly `a_fclr_b19` · StickyFault 공용 규약 몫) · 표현 불가 프레임 ·
    X 권한(요청 종류에 실행이 없다 — 판정 불참). 마스크는 구성하지 않았다 — 마스킹
    단은 항등이고 `[11]` 이 서지만 접근 · sticky 행은 `[4]` · `[19]` · `[6]` 만 본다 (요약 행은
    `[18:0]` 을 지운 뒤 FAULT_STATUS 워드 전체를 본다). reset 값은 한 점 관측이다(형식 단언 아님).
    HEAD 생성물에서는 비소유 · 자격 허용 행이 `[4]` 를 세우고(`[19]` 원천 없음),
    `0xF84` 의 `1 << 19` · `1 << 20` 이 `[31:19]` 예약으로 거절될 것으로 예상한다.
    """
    await boot_hiu(dut)
    rows, want = [], []
    # reset 직후 — 어떤 해제도 하기 전 (W1 검증 결함 X21). 열은 ([4], [19], [6], hiuPerm, hiuOwn).
    rst = await hiu_report(dut)
    rows.append(("reset 직후 — 해제 전", *rst,
                 int(dut.io_fault_hiuPerm.value), int(dut.io_fault_hiuOwn.value)))
    want.append(("reset 직후 — 해제 전", 0, 0, 0, 0, 0))
    await mmio_write(dut, OWN_SET, FRAME_DEV)
    lat_ref = {}
    for (name, part, idx, tag, frame, (r, w, x), wr, path, (eg, e4, e19)) in N14_CASES:
        await clear_hiu_report(dut, name)
        vpn = vpn_of(tag, idx)
        if path == "hit":
            await install_entry(dut, part, idx, tag, frame, r=r, w=w, x=x)
            res = await hiu_lookup(dut, part, vpn, write=wr)
            lat = len(res["trace"])
        else:
            res = await hiu_lookup(dut, part, vpn, write=wr)
            assert_miss(dut, res, f"{name} — 채움 전 정지")
            await install_entry(dut, part, idx, tag, frame, r=r, w=w, x=x)
            res = await wait_rsp(dut)
            lat = res["wait"]
        lat_ref.setdefault(path, lat)          # 경로마다 첫 행 = 양성 대조
        b4, b19, b6 = await hiu_report(dut)
        rows.append((name, res["rsp"], res["granted"], res["phys"], res["frame"],
                     res["fromFill"], lat, b4, b19, b6))
        want.append((name, 1, eg, eg, frame if eg else 0, int(path == "fill"), lat_ref[path],
                     e4, e19, 0))

    # sticky · 0xF84 행 — 열은 ([4], [19], [6]).
    unowned = N14_CASES[3]
    denied = N14_CASES[1]
    granted = N14_CASES[0]

    async def access(case):
        _, part, idx, tag, _, _, wr, _, _ = case
        res = await hiu_lookup(dut, part, vpn_of(tag, idx), write=wr)
        assert res["rsp"] == 1, f"[{case[0]}] 재적중에 응답이 없다 ({res})"

    async def note(label, exp):
        rows.append((label, *(await hiu_report(dut))))
        want.append((label, *exp))

    await clear_hiu_report(dut, "sticky 행")
    await access(unowned)
    await note("[19] 세움 — 비소유 · 자격 허용 재적중", (0, 1, 0))
    await step(dut, 8)
    await access(granted)
    await mmio_read(dut, FAULT_STATUS)
    await note("[19] sticky — 8 사이클 · 승인된 접근 · 0xF80 재읽기 뒤에도", (0, 1, 0))
    await access(denied)
    await note("[4] 도 세운다 — 자격 거부 재적중 (둘은 원천이 다른 sticky)", (1, 1, 0))
    await mmio_write(dut, FAULT_CLEAR, (1 << B_XLATE_PERM) | (1 << FLT_RSV_LO))
    await note("0xF84 ← [4] | [20] — 예약 비0: 거절 + [6] · 한 비트도 내리지 않는다", (1, 1, 1))
    await clear_fault6(dut)
    await mmio_write(dut, FAULT_CLEAR, (1 << B_OWN_FRAME) | (1 << 31))
    await note("0xF84 ← [19] | [31] — 예약 비0: 거절 + [6] · [19] 유지", (1, 1, 1))
    await clear_fault6(dut)
    await mmio_write(dut, FAULT_CLEAR, 1 << B_XLATE_PERM)
    await note("0xF84 ← [4] — [19] = 1 인 채 [4] 만 내린다 ([19] 는 원천이 다른 sticky)", (0, 1, 0))
    await mmio_write(dut, FAULT_CLEAR, (1 << B_OWN_FRAME) - 1)
    await step(dut, 2)
    st, sm = await mmio_read(dut, FAULT_STATUS), await mmio_read(dut, FAULT_SUMMARY)
    rows.append(("0xF84 ← [18:0] — [19] 하나만 남긴 (FAULT_STATUS, FAULT_SUMMARY)", st, sm))
    want.append(("0xF84 ← [18:0] — [19] 하나만 남긴 (FAULT_STATUS, FAULT_SUMMARY)", 1 << B_OWN_FRAME, 1))
    await access(denied)
    await note("[4] 다시 세움 — 자격 거부 재적중", (1, 1, 0))
    await mmio_write(dut, FAULT_CLEAR, 1 << B_OWN_FRAME)
    await note("0xF84 ← [19] — [6] 없이 [19] 만 내린다 ([4] 는 1 을 쓰지 않았다)", (1, 0, 0))
    await mmio_write(dut, FAULT_CLEAR, 1 << B_XLATE_PERM)
    await note("0xF84 ← [4] — 정리", (0, 0, 0))

    assert rows == want, (
        "FAULT_STATUS [4]/[19] 원인별 보고 행 표가 정본과 다르다 — reset 행의 열은 ([4], [19], [6], "
        "hiuPerm, hiuOwn) · 접근 행의 열은 (응답, 승인, phys, 값, fromFill, 사이클, [4], [19], [6]) · "
        "sticky/0xF84 행의 열은 ([4], [19], [6]) · 요약 행은 (FAULT_STATUS, FAULT_SUMMARY):\n"
        + table_diff(rows, want))

    # 원천별 수출 (포트 계약 — io.fault.hiuOwn 이 [19] 원천, io.fault.hiuPerm 이 [4] 원천).
    await access(unowned)
    await step(dut, 2)
    got = (int(dut.io_fault_hiuPerm.value), int(dut.io_fault_hiuOwn.value))
    assert got == (0, 1), f"비소유 · 자격 허용 접근 뒤 (hiuPerm, hiuOwn) = {got} ≠ (0, 1)"
    await mmio_write(dut, FAULT_CLEAR, 1 << B_OWN_FRAME)
    await access(denied)
    await step(dut, 2)
    got = (int(dut.io_fault_hiuPerm.value), int(dut.io_fault_hiuOwn.value))
    assert got == (1, 0), f"자격 거부 접근 뒤 (hiuPerm, hiuOwn) = {got} ≠ (1, 0)"
    dut._log.info(f"원인별 보고: reset 1 행 + 접근 {len(N14_CASES)} 행(적중 · 채움 경로) + sticky/0xF84/"
                  f"0xF88 {len(rows) - len(N14_CASES) - 1} 행이 정본과 등가 · 원천별 수출 hiuOwn/hiuPerm 확인")


# ═══════════════════════════════════════════════════════════════════════════
# W2 — 판정 래치: 판정은 그 요청이 조회 지점을 떠날 때까지 산다 (N8 · N9)
# ═══════════════════════════════════════════════════════════════════════════
#
# 3.10 v1.0 묶음 RTL 파도의 둘째 하위 파도. 선-formal 은 rtl/formal/tla/XlateObs.tla 의 판정
# 래치 절(가드 verdict_latch · latch_clears_on_leave · latch_one_value), 후-formal 은 hiumask
# 하네스다. 여기는 그 결과가 호스트 쪽 문(0xC00 기입 · 0xE04 관측)과 HIU 요청 경로의 응답
# 값으로 나타나는지를 잰다. 정본 (같은 줄 축자):
#   03-hiu.typ:734 「처음 적중한 사이클이다」 — 판정 시점
#   03-hiu.typ:735 「요청이 조회 지점을 떠날 때까지 유지되고, 그 뒤의 커밋 · flush 는 그 요청의」
#   03-hiu.typ:737 「같은 값으로 쓰인다」 — 승인 단 소유권 조회 주소와 마스킹 입력 프레임
#   03-hiu.typ:738 「판정 래치는 경로를 가르지 않는다」
#   03-hiu.typ:741 「수락되면 풀리고, 그 커밋 항목으로 판정된다」
#   03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」
#   03-hiu.typ:754 「조회 지점 뒤의 단이 배압으로 서 있으면 풀린 요청이 조회 지점에 머물고」
#   03-hiu.typ:755 「사이에 같은 파티션의 다른 커밋이 그 칸을 덮으면 요청은」 — 반례의 몸
#   03-hiu.typ:763 「한 단이라도 저장 블록을 다시 읽으면 한 요청이 두」
#   03-hiu.typ:1323 「조회에만 효력이 있다」 — V=0 COMMIT · flush 의 효력 범위
#   03-hiu.typ:1324 「스냅샷을 들고 끝까지 간다」
#   e-defined.typ:310 「풀린 그 요청은 그 커밋 항목으로 판정되고」 — 결과 (d)
#   e-defined.typ:310 「효력은 그 커밋 에지 뒤에 판정되는 조회에만 미친다 — 그 전에 판정이 래치된 요청은 래치된 판정으로 끝까지 간다」 — 결과 (a)
#
# 기대값은 위 문장과 이 시험이 쓴 값(프레임 · 권한 · 소유)에서 유도한다 — RTL 의 래치 신호를 보지
# 않는다(포트 계약만: io_hiuHold · io_hiuReq · io_hiuRsp · io_phys · io_hostRsp · 0xE04 · FAULT_STATUS).
# 판정 = 03-hiu.typ:734 「그 판정(적중 · 프레임 · 권한)은」 — 응답 칸의 승인 · 값 · 권한(io_hiuRsp_perm —
# 승인일 때만 실린다)이 그것이다. **예외 하나 — 응답의 fromFill 칸은 정본 밖이다.** 정본 전체에 fromFill
# 은 없다 — RTL 진단 포트다. 그 기대(판정이 채움 바이패스 사이클의 것이면 1)는 RTL 진단 계약(GUARD-MAP
# verdict_latch · latch_one_value 의 「fromFill 도 같은 래치」)에서 온다. 판정 값의 칸이 아니다.
#
# **화이트박스 하나 (N8):** 같은 칸을 다투는 VPN 둘을 고르는 것은 오늘 문의 형상 지식이다 —
# 직접 사상 · 색인 = VPN[3:0] (위 `vpn_of`), 같은 (파티션, 색인)의 다른 태그가 그 칸을 덮는다
# (위 xlate_adjacent_hi_stalls_then_commits 의 「tagA 덮임」). 형상 비노출 문(W3)에서는 호스트가
# 어느 VPN 둘이 한 칸을 다투는지 모른다 — 그 판에서 고르기는 헬퍼(`entry_ops` · `install_entry`)와
# 함께 바뀐다. 시험은 축출이 실제로 일어났는지를 끝에서 전건으로 확인한다(B 적중 · A 미적중).
#
# **타이밍 (N8):** RTL 에서 가능한 반례의 꼴은 hold ≥ 2 사이클 뒤의 경쟁 커밋이다 — HI(A) 수락
# C → C+1 채움 바이패스 적중(정지 해제 · hold 로 조회 지점에 머묾 · 채움 슬롯 해제) → C+2 같은
# 칸의 다른 VPN HI(B) 수락(채움 슬롯이 비어 정지 없음) → C+3 채움 가림으로 A 가 안 보인다.
# 모델의 BFS 최단 반례(축출을 첫 적중 사이클 끝 에지에 둔다)는 RTL 에서 그 에지가 같은 파티션
# 커밋을 받지 않으므로(채움 슬롯 점유) 그대로는 재현되지 않는다 (XlateObs.tla 머리 「원자성」 2).
# `mmio_burst` 의 인접 구동과 정지 계수 [0, 0, 0, 0] 이 C · C+2 를 못박는다.


def entry_ops(part, idx, tag, frame, v=1, r=1, w=0, x=0):
    """`install_entry` 와 같은 기입 열(오늘 문 — LO 스테이징 · HI 커밋)을 `mmio_burst` 용
    (주소, 데이터) 목록으로 낸다. 문이 바뀌면(W3) `install_entry` 와 함께 바뀐다."""
    return [(xent(part, idx), frame), (xent(part, idx) + 4, hi_word(tag, v=v, r=r, w=w, x=x))]


async def set_hold(dut, v):
    """하류 배압 `io_hiuHold` — 파이프 전체가 함께 선다(advance 하강). 같은 사이클에 정착한다."""
    dut.io_hiuHold.value = v
    await settle(dut)


async def present_seq(dut, reqs, hold_at_s3=False, write=0):
    """요청 열(`write` — 전부 읽기 또는 전부 쓰기)을 **인접** 제시한다 — 첫 요청의 접수 엣지 바로
    다음 사이클에 둘째 요청.

    돌아올 때 첫 요청은 조회 지점(s3)에 막 닿은 사이클에 있다 — 접수 뒤 `MISS_LEAD` 엣지(위
    실측 상수; 파이프 깊이가 바뀌면 `assert_miss` 가 먼저 크게 깨진다). `hold_at_s3` 이면 그
    사이클의 엣지 전에 hold 를 올린다 — 첫 요청이 *첫 적중 사이클*에 떠나지 못한다(판정이
    래치되는 자리). 둘째 요청은 그때 s2 에 있고, 첫 요청이 떠나는 *그* 에지에 조회 지점에 든다.
    """
    assert 1 <= len(reqs) <= MISS_LEAD + 1, "present_seq: 첫 요청이 s3 에 닿기 전에 다 들어가야 한다"
    for i, (part, vpn) in enumerate(reqs):
        dut.io_hiuReq_part.value = part
        dut.io_hiuReq_vpn.value = vpn
        dut.io_hiuReq_write.value = write
        dut.io_hiuReq_valid.value = 1
        await settle(dut)
        assert int(dut.io_hiuReq_ready.value) == 1, (
            f"present_seq: 요청 {i} 의 접수 사이클에 ready = 0 — 파이프에 앞 요청이 남아 있다")
        await step(dut)                                      # 접수 엣지
    dut.io_hiuReq_valid.value = 0
    dut.io_hiuReq_write.value = 0
    await step(dut, MISS_LEAD - (len(reqs) - 1))             # 첫 요청이 조회 지점에 닿는다
    if hold_at_s3:
        await set_hold(dut, 1)


def rwx(r, w, x):
    """권한 칸 — `R`·`W`·`X` 가 선 자리만 글자, 나머지 `-` (행 표에서 읽히게)."""
    return ("R" if r else "-") + ("W" if w else "-") + ("X" if x else "-")


async def collect_rsp(dut, window):
    """`window` 사이클 동안 응답을 거둔다 — 응답마다 (사이클, 승인, phys, 값, fromFill, 권한).
    권한은 응답의 io_hiuRsp_perm_r/w/x 다 — 승인일 때만 실리고 거부면 `---` (값 게이트).
    사이클은 부른 사이클이 0 이다 (`wait_rsp` 의 `wait` 와 같은 셈)."""
    got = []
    for n in range(window):
        await settle(dut)
        if int(dut.io_hiuRsp_valid.value):
            got.append((n, int(dut.io_hiuRsp_granted.value), int(dut.io_phys_valid.value),
                        int(dut.io_phys_frame.value), int(dut.io_hiuRsp_fromFill.value),
                        rwx(int(dut.io_hiuRsp_perm_r.value), int(dut.io_hiuRsp_perm_w.value),
                            int(dut.io_hiuRsp_perm_x.value))))
        await step(dut)
    return got


def flat_rsp(got):
    """행 표 칸 — (응답 수, 응답마다 사이클 · 승인 · phys · 값 · fromFill · 권한 …)."""
    return (len(got),) + tuple(x for r in got for x in r)


def host_leg(dut, v, frame=0):
    """호스트 응답 leg(io_hostRsp_*)을 세우거나 내린다 — 판정 · 값 · 정지 어느 축에도 들지 않는
    의도된 미결선 입력이다(GUARD-MAP Isolation.query_no_serve · Platform.xlate_local). 세울 때는
    비0 프레임과 RWX 전부 — 새면 승인된 오값 · 권한으로 드러난다."""
    dut.io_hostRsp_valid.value = v
    dut.io_hostRsp_frame.value = frame if v else 0
    dut.io_hostRsp_perm_r.value = v
    dut.io_hostRsp_perm_w.value = v
    dut.io_hostRsp_perm_x.value = v


N8_IDX_C, N8_TAG_C, N8_FC = 9, 0x00C8C03, 0x0000_3CC3   # 대조 — 저장 적중 요청
N8_TAG_B, N8_FB = 0x00B8B02, 0x0000_3B82                 # 경쟁 커밋 — 같은 (파티션, 색인)의 다른 VPN
N8_FH = 0x0000_3E05                                      # 호스트 응답 leg 의 프레임 (장치 소유 — 새면 승인된 오값)
# (이름, 파티션, 색인, 태그, 프레임, 정지를 푸는 커밋 뒤에 잇는 기입, 그 열의 정지 계수 기대)
#   프레임은 전부 OWN_SET 한다 — 소유권 표 직접 사상 슬롯(하위 6b)이 서로 겹치지 않게 골랐다.
N8_CASES = [
    ("경쟁 커밋 — C+2 에 같은 칸의 다른 VPN B", 1, 6, 0x00A8A01, 0x0000_3A41,
     entry_ops(1, 6, N8_TAG_B, N8_FB), (0, 0, 0, 0)),
    ("flush(p) — C+1 = 풀린 첫 적중 사이클의 끝 에지", 2, 6, 0x00A8A04, 0x0000_3D04,
     [(XCTL_FLUSH, 2)], (0, 0, 0)),
]
N8_HOLD_MORE = 16


@cocotb.test()
async def xlate_released_judgment_survives_eviction(dut):
    """N8 — 풀린 판정은 축출을 건너 산다 (결과 (d) · 판정 시점과 판정 래치).

    반례 그대로: R(p, A) 미적중 정지 → 하류 hold 를 올린다 → A 의 커밋이 정지를 풀고 R 은 hold 로
    조회 지점에 머문다 → 같은 파티션의 축출이 A 를 밀어낸다 → hold 를 놓는다. 정본은 R 이 다시
    미적중하지 않고 *A 의 커밋 항목으로* 승인된다고 적는다. 축출 원인은 정본이 이름한 둘이다
    (e-defined.typ:312 「장치는 축출을 같은 파티션에 대한 호스트 COMMIT 과 flush 의 결과로만 한다」):
      · 경쟁 커밋 — RTL 에서 가장 이른 꼴. HI(A) 수락 C → C+1 채움 바이패스 적중(풀림) → C+2 같은
        칸의 다른 VPN HI(B) 수락 → C+3 채움 가림 (위 W2 절 머리 「타이밍」)
      · flush(p) — flush 는 채움 슬롯을 기다리지 않으므로 풀린 첫 적중 사이클 C+1 에 수락되고 그
        끝 에지(= 래치 포착 에지)에 A 의 진행 중 채움 줄과 유효 비트를 함께 지운다. 모델의 BFS 최단
        꼴(첫 적중 사이클 끝 에지의 철회)이 RTL 에서 서는 경로다 — 판정은 그 에지 *앞* 사이클에
        났으므로 정본상 산다(e-defined.typ:310 「효력은 그 커밋 에지 뒤에 판정되는 조회에만 미친다」).
        판정 시점이 첫 적중 사이클이라는 것(늦은 포착이 아니라는 것)을 값으로 가르는 행이다

    재는 것 (행 표 — 끝에 통째로 등가 비교):
      · 대조 — 저장 적중 요청을 첫 적중 사이클에 hold 로 잡았다 놓으면 놓은 뒤 `w_ref` 사이클에
        승인된다. `w_ref` = 래치가 끼지 않는 적중 조회의 길이 − `MISS_LEAD` (같은 실행의 실측)
      · 사례마다: 전건 — 정지 중 관측면이 R 을 말한다 (`[0]` · `[1]` · 파티션 · VPN) · 버스트가 정지
        없이 인접 수락된다(HI(A) 가 C — 계수가 C+1 · C+2 를 못박는다) · `[6]` 0 · 축출 뒤 hold 중 관측면
        `[0]` = 0 (재미적중 없음) — 정지 해제 뒤 `0xE10` 해제가 sticky `[1]` 을 내리고 다시 서지 않는다
        (sticky set 이 정지 레벨이므로 재미적중이면 남는다). 16 사이클 뒤에도 같다 · hold 를 놓으면
        R 이 놓은 뒤 `w_ref` 사이클에(대조와 같은 상태열 — 판정 래치는 경로를 가르지 않는다) A 의
        프레임 · 권한(R--)으로 승인된다 · fromFill = 1 — **정본 밖** 칸이다(W2 절 머리 「예외 하나」:
        RTL 진단 계약 — GUARD-MAP verdict_latch · latch_one_value 의 fromFill 래치. 판정이 채움 바이패스
        적중 사이클의 것) · 응답 뒤 관측면 0 · `[4]` · `[19]` · `[6]` = 0
      · 사례마다 hold 를 올린 뒤부터 응답까지 **호스트 응답 leg(io_hostRsp — 장치 소유 비0 프레임 ·
        RWX)을 세워 둔다.** 정지를 푸는 것도 판정을 짓는 것도 항목 기입뿐이다
        (e-defined.typ:889 「정지를 푸는 것은 2항의 항목 기입뿐이다」 — 정지를 풀린 요청의 판정도
        03-hiu.typ:741 「수락되면 풀리고, 그 커밋 항목으로 판정된다」) — 래치를 호스트 leg 에서 포착하는 구현은 첫 관측 행(정지가 사라진다)과 응답 행(그 프레임)에서 운다
      · 래치가 선 hold 중에 `0xF84` W1C(`[4]` · `[19]`, 둘 다 0 인 채)를 한 번 쓴다 — 판정은 요청이
        떠날 때까지 산다(03-hiu.typ:735 「요청이 조회 지점을 떠날 때까지 유지되고」) · 해제가 래치를 비우는
        구현은 「hold 더」 행(재미적중)에서 운다
      · 끝의 전건(표 대조 뒤): 경쟁 커밋 사례 — B 는 B 의 프레임으로 적중하고 A 는 미적중 · flush
        사례 — A 는 미적중(진행 중 채움 줄까지 지워졌다). 축출이 실제로 일어났다

    재지 않는 것: C+3 이후의 경쟁 커밋(가장 이른 꼴 하나만 — 래치는 그 뒤 에지마다 같은 값을 든다) ·
    호스트 leg 이 *먼저* 서 있다가 정지가 오는 순서 · IO 해제선 io_faultClear_hiuPerm(W1C 와 같은 hiu
    해제로 합류 — 합류 자체는 조립층 몫) · 권한 필드의 래치(경쟁 커밋 B 의 권한이 A 와 같다 — N9 의 권한 행) ·
    V=0 COMMIT 축출(채움 슬롯 때문에 C+2 가 가장 이르다 — N9 가 저장 적중 래치로 잰다) · flush 와 같은
    사이클의 채움 *거절* 창(어느 모델에도 없다 — model_feedback) · 동시에 정지하는 조회 지점 여럿(형상
    밖) · 호스트 ABI 층위(조회는 내부 포트 io.hiuReq) · reset 의 래치 비움(형식 단언 이월 W2-9).
    HEAD(9b6eee6) 생성물에서는 축출 뒤(C+3 의 채움 가림 · C+2 의 flush 된 칸)부터 R 이 다시 미적중해
    관측면이 R 을 다시 말하고(`0xE10` 해제도 sticky 를 못 내린다) hold 를 놓아도 응답이 없을 것으로
    예상한다.
    """
    await boot_hiu(dut)
    for f in (N8_FC, N8_FB, N8_FH, *(c[4] for c in N8_CASES)):
        await mmio_write(dut, OWN_SET, f)
    rows, want = [], []

    # 기준 — 래치가 끼지 않는 적중 조회(hold 없음)의 길이.
    pc = N8_CASES[0][1]
    vc = vpn_of(N8_TAG_C, N8_IDX_C)
    await install_entry(dut, pc, N8_IDX_C, N8_TAG_C, N8_FC)
    ref = await hiu_lookup(dut, pc, vc)
    assert_hit(ref, N8_FC, "기준 — 저장 적중")
    w_ref = len(ref["trace"]) - MISS_LEAD
    dut._log.info(f"실측: 적중 조회 접수 → 응답 {len(ref['trace'])} 사이클 · 조회 지점 도달 MISS_LEAD "
                  f"{MISS_LEAD} · 조회 지점 → 응답 {w_ref}")

    lbl = "대조 — 저장 적중을 첫 적중 사이클에 hold 로 잡았다 놓음 · 응답"
    await present_seq(dut, [(pc, vc)], hold_at_s3=True)
    await step(dut, N8_HOLD_MORE)
    await set_hold(dut, 0)
    rows.append((lbl, *flat_rsp(await collect_rsp(dut, 12))))
    want.append((lbl, 1, w_ref, 1, 1, N8_FC, 0, "R--"))

    for name, p, idx, tag, fa, evict, stall_want in N8_CASES:
        va = vpn_of(tag, idx)
        res = await hiu_lookup(dut, p, va)
        assert_miss(dut, res, f"{name} — R(p, A) 빈 칸")           # 정지 (ready 표본열 등식)
        await set_hold(dut, 1)
        host_leg(dut, 1, N8_FH)                                     # 응답까지 세워 둔다 (머리 「재는 것」)
        lbl = f"{name} · 정지한 R — hold · 호스트 leg 을 올린 뒤 관측면 (STATUS, VPN, VPN_HI)"
        rows.append((lbl, *await read_obs(dut)))
        want.append((lbl, xstatus_word(1, 1, p), va, 0))
        stalls = await mmio_burst(dut, entry_ops(p, idx, tag, fa) + evict)
        lbl = f"{name} · LO(A) · HI(A) 수락 C · 뒤 기입 인접 — 정지 계수"
        rows.append((lbl, *stalls))
        want.append((lbl, *stall_want))
        lbl = f"{name} · 버스트 뒤 [6] (적법한 기입뿐)"
        rows.append((lbl, await fault6(dut)))
        want.append((lbl, 0))
        await mmio_write(dut, XCTL_MISS_CLEAR, 1)
        lbl = f"{name} · 축출 뒤 hold 중 · 0xE10 해제 뒤 관측면 — 재미적중 없음"
        rows.append((lbl, *await read_obs(dut)))
        want.append((lbl, 0, 0, 0))
        await mmio_write(dut, FAULT_CLEAR, (1 << B_XLATE_PERM) | (1 << B_OWN_FRAME))   # 해제는 판정을 안 비운다
        await step(dut, N8_HOLD_MORE)
        lbl = f"{name} · 0xF84 [4]·[19] W1C · hold {N8_HOLD_MORE} 사이클 더 — 관측면 · io_fault_hiuMiss"
        rows.append((lbl, *await read_obs(dut), int(dut.io_fault_hiuMiss.value)))
        want.append((lbl, 0, 0, 0, 0))
        await set_hold(dut, 0)
        lbl = f"{name} · hold 해제 — R 의 응답 (수, 사이클, 승인, phys, 값, fromFill, 권한)"
        rows.append((lbl, *flat_rsp(await collect_rsp(dut, 12))))
        want.append((lbl, 1, w_ref, 1, 1, fa, 1, "R--"))
        host_leg(dut, 0)
        b4, b19, b6 = await hiu_report(dut)
        lbl = f"{name} · 응답 뒤 관측면 · [4] · [19] · [6]"
        rows.append((lbl, *await read_obs(dut), b4, b19, b6))
        want.append((lbl, 0, 0, 0, 0, 0, 0))
        if int(dut.io_hiuReq_ready.value) == 0:
            # 음성 대조의 기록을 잇기 위한 회복 — R 이 다시 미적중한 채 남았다(위 행이 이미 그것을
            # 적었다). A 를 다시 커밋해 풀어 다음 사례가 빈 파이프에서 시작하게 한다. 정본대로인
            # 생성물에서는 이 가지가 돌지 않는다(위 행이 정지 0 을 요구한다).
            await install_entry(dut, p, idx, tag, fa)
            await wait_rsp(dut)

    assert rows == want, (
        "풀린 판정이 축출을 건너 살지 못했다 (결과 (d) · 판정 래치) — 행 표가 정본과 다르다:\n"
        + table_diff(rows, want))

    # 전건 — 축출이 실제로 일어났다. 경쟁 커밋: B 가 그 칸에 있고 A 는 없다 (A 의 미적중 정지는 A 를
    # 다시 커밋해 푼다). flush: A 는 없다 (진행 중 채움 줄까지 지워졌다).
    (_, p1, i1, t1, f1, _, _), (_, p2, i2, t2, _, _, _) = N8_CASES
    assert_hit(await hiu_lookup(dut, p1, vpn_of(N8_TAG_B, i1)), N8_FB, "경쟁 커밋 B 의 VPN")
    assert_miss(dut, await hiu_lookup(dut, p1, vpn_of(t1, i1)), "B 에 밀려난 A 의 VPN (반례 전건)")
    await install_entry(dut, p1, i1, t1, f1)
    r = await wait_rsp(dut)
    assert r["rsp"] == 1 and r["frame"] == f1, f"A 재커밋이 전건 확인의 정지를 풀지 못했다 ({r})"
    assert_miss(dut, await hiu_lookup(dut, p2, vpn_of(t2, i2)), "flush 된 A 의 VPN (반례 전건)")
    dut._log.info(f"정지 → A 커밋이 풀고 hold 로 머묾 → C+2 경쟁 커밋 · C+1 flush 가 A 를 밀어냄 → 재미적중 "
                  f"없음 · 놓은 뒤 {w_ref} 사이클에 A 의 프레임으로 승인 (대조와 같은 상태열) · 축출 전건 확인")


# ── N9 — 래치된 판정과 철회(V=0 COMMIT · flush) · 대체 커밋의 효력 범위 ─────────────
#
# 행마다 같은 (파티션, VPN) 의 요청 둘 R1 · R2 를 인접 제시하고, R1 이 조회 지점에 닿은 첫 적중
# 사이클에 hold 를 올린다 — R1 의 판정은 그 사이클의 것(저장 적중 · 프레임 FA)이다. hold 중에
# 철회 · 대체를 하고 hold 를 놓는다. R2 는 그때 s2 에 있다가 R1 이 떠나는 *그* 에지에 조회 지점에
# 들므로 철회 · 대체 에지 *뒤에* 판정된다 — 정본이 가르는 두 요청이 한 줄에 선다. 철회 행에서
# R2 는 미적중으로 정지하고(정지는 파이프 전체를 세운다 — 앞선 R1 도 그동안 선다) 채움 커밋(FC)이
# 그것을 푼다. 대체 행의 새 프레임 FB 는 호스트 소유로 둔다 — 그래서 R2(FB 로 판정)는 값 차단 +
# `[19]` 이고, 어느 단이든 R1 의 판정 대신 저장 블록을 다시 읽으면 R1 의 소유권 조회가 FB 를 보아
# 승인이 무너진다 (한 요청 한 값 — 03-hiu.typ:763 「한 단이라도 저장 블록을 다시 읽으면 한 요청이 두」).
# 철회는 두 시각에 둔다 — 포착 뒤(hold 두 사이클 뒤)와 *포착 에지 자체*(R1 의 첫 적중 사이클에 기입을
# 실어 그 끝 에지에 수락 — 저장 적중의 칸은 채움 슬롯이 비어 V=0 도 기다리지 않는다). 둘째가 판정
# 시점이 첫 적중 사이클이라는 것을 값으로 가른다: 판정은 그 에지 *앞* 사이클에 났으므로 산다.
# 마지막 행은 hold 없는 대조다 — 적중 R1 은 첫 적중 에지에 떠나고 그 에지에 미적중 R2 가 든다.
# 권한 행의 대체는 *권한만* 바꾸고(같은 프레임 FA · A 의 권한 -WX → B 의 R--) R1 · R2 가 쓰기
# 요청이다 — 자격(쓰기는 W)이 래치된 권한을 보는지 새 권한을 보는지가 승인 · `[4]` 로 갈리고, 응답의
# 권한 칸이 R · W · X 각 필드의 래치를 값으로 가른다 (판정의 셋째 칸 — 03-hiu.typ:734 「그 판정(적중 · 프레임 · 권한)은」).

N9_FA = 0x0000_5104      # OWN_SET — 래치될 판정의 프레임
N9_FC = 0x0000_5245      # OWN_SET — 철회 뒤 채움 커밋의 프레임
N9_FD = 0x0000_5487      # OWN_SET — hold 없는 행의 채움 프레임
N9_FB = 0x0000_5386      # 넘기지 않는다(호스트 소유) — 대체 커밋의 새 프레임. 슬롯(하위 6b)이 위 셋과 다르다

# (이름, 파티션, 색인, 태그, 철회 종류, 포착 에지와 같은 에지인가)
N9_CASES = [
    ("대조 — hold 중 철회 없음", 0, 2, 0x0090002, None, False),
    ("V=0 COMMIT — 포착 뒤", 1, 3, 0x0090003, "v0", False),
    ("flush(p) — 포착 뒤", 2, 4, 0x0090004, "flush", False),
    ("같은 VPN 재커밋(대체) — 새 프레임은 호스트 소유", 3, 5, 0x0090005, "replace", False),
    ("같은 VPN 재커밋(대체) — 권한만 바뀜(-WX → R--) · 쓰기 요청 둘", 3, 6, 0x0090006, "perm", False),
    ("V=0 COMMIT — 포착 에지와 같은 에지", 1, 10, 0x009000A, "v0", True),
    ("flush(p) — 포착 에지와 같은 에지", 2, 11, 0x009000B, "flush", True),
]
N9_NOHOLD = ("hold 없음 — 적중 R1 은 첫 적중 에지에 떠나고 미적중 R2 가 그 에지에 든다",
             0, 7, 0x0090007, 8, 0x0090008)


async def n9_clean(dut, what):
    """행 사이 정리 — 미적중 sticky · [4] · [19] 를 내리고 파이프가 비었는지 본다."""
    if int(dut.io_fault_hiuMiss.value):
        await mmio_write(dut, XCTL_MISS_CLEAR, 1)
    f = await mmio_read(dut, FAULT_STATUS)
    for b in (B_XLATE_PERM, B_OWN_FRAME):
        if bit(f, b):
            await mmio_write(dut, FAULT_CLEAR, 1 << b)
    got = (*(await hiu_report(dut)), int(dut.io_fault_hiuMiss.value), int(dut.io_hiuReq_ready.value))
    assert got == (0, 0, 0, 0, 1), (
        f"[{what}] 앞 정리: ([4], [19], [6], hiuMiss, ready) = {got} ≠ (0, 0, 0, 0, 1) — 앞 행의 "
        f"잔재(정지 · sticky)가 남았다")


@cocotb.test()
async def xlate_latched_hit_survives_retire(dut):
    """N9 — 래치된 판정은 철회 · 대체를 건너 그 요청과 함께 끝까지 간다 (3.7.2 철회의 효력 범위 ·
    결과 (a)(b) 의 「그 에지 뒤에 판정되는」 한정 · 판정 래치의 한 값).

    재는 것 (행 표 — 끝에 통째로 등가 비교, 위 「N9」 절의 자극):
      · 대조 — 철회 없이 hold 를 놓으면 R1 · R2 가 놓은 뒤 `w_ref` · `w_ref`+1 사이클에 FA 로 승인
        (응답마다 권한 칸 — 승인이면 그 판정의 권한, 거부면 `---`)
      · V=0 COMMIT · flush(p) — 포착 뒤 · 포착 에지와 같은 에지 둘 다 — hold 중 관측면 `[0]` = 0 ·
        `[1]` = 0 (래치된 R1 은 정지가 아니다).
        놓으면 R2 가 그 에지 뒤에 판정돼 미적중 정지(관측면이 R2 의 (p, VPN))하고 응답이 없다.
        채움 커밋(FC)이 R2 를 풀면 R1 은 *래치된* FA 로(fromFill 0 — 저장 적중의 판정), R2 는 FC 로
        (fromFill 1) 승인된다 — 사이클은 정지 하나를 채움이 푸는 기준 경로(`w_fill`)와 같은 셈
      · 대체(같은 VPN · 새 프레임 FB, 호스트 소유) — R1 은 FA 로 승인 · R2 는 FB 로 판정돼 값 차단
        (승인 0 · 값 0) + `[19]`
      · 권한만 바뀌는 대체(같은 VPN · 같은 프레임 FA · 권한 -WX → R--)와 쓰기 요청 둘 — R1 은 래치된
        권한으로 승인되고(응답 권한 `-WX`) R2 는 새 권한(W = 0)으로 판정돼 자격 거부(승인 0 · 값 0 ·
        권한 `---`) + `[4]`. 자격이 래치 아닌 저장 시야의 W 를 보거나(R1 거부) W 래치가 R 을 잡거나
        (R1 거부) 어느 권한 필드가 래치를 안 타면(응답 권한 칸) 이 행이 운다
      · hold 없음 대조 — R1 이 첫 적중 에지에 떠나면 판정은 R1 과 함께 나가고 같은 에지에 든 미적중
        R2 는 자기 조회로 정지한다(물려받지 않는다). 채움(FD)이 R2 를 풀면 R1 FA · R2 FD
      · 행마다 끝 `[4]` · `[19]` · `[6]` (대체 행만 `[19]` = 1 · 권한 행만 `[4]` = 1) · 철회 · 대체 기입
        뒤 `[6]` = 0

    재지 않는 것: 대체가 포착 에지와 같은 에지인 꼴(대체는 LO · HI 두 기입이라 한 에지에 싣지
    못한다 — 같은 에지는 철회 둘이 잰다) · 다른 파티션 flush 의 무효과(flush 범위는
    xlate_flush_then_miss) · 드레인 관측면으로 「완전한 철회」를 재는 것(관측면 미배선 — 이월) ·
    권한 행 밖의 쓰기 요청 · reset 의 래치 비움(이월 W2-9). HEAD(9b6eee6) 생성물에서는 V=0 · flush
    행에서 R1 이 hold 중 다시 미적중하고(관측면 `[0]` = 1) 채움 커밋의 FC 로 판정되며, 대체 행 · 권한
    행에서 R1 이 떠나는 시점의 저장 시야(FB · R--)로 판정돼 승인이 무너질 것으로 예상한다.
    """
    await boot_hiu(dut)
    for f in (N9_FA, N9_FC, N9_FD):
        await mmio_write(dut, OWN_SET, f)
    rows, want = [], []

    # 기준 둘 — 정지 하나를 채움이 푸는 경로(`w_fill`, 채움 기입이 돌아온 사이클부터) · 래치가
    # 끼지 않는 적중 조회의 길이(`w_ref` = 조회 지점 → 응답).
    rp, ri, rt = 0, 1, 0x0090001
    assert_miss(dut, await hiu_lookup(dut, rp, vpn_of(rt, ri)), "기준 — 빈 칸")
    await install_entry(dut, rp, ri, rt, N9_FA)
    r = await wait_rsp(dut)
    assert r["rsp"] == 1 and r["granted"] == 1 and r["frame"] == N9_FA, f"기준 채움이 정지를 풀지 못했다 ({r})"
    w_fill = r["wait"]
    ref = await hiu_lookup(dut, rp, vpn_of(rt, ri))
    assert_hit(ref, N9_FA, "기준 — 저장 적중")
    w_ref = len(ref["trace"]) - MISS_LEAD
    dut._log.info(f"실측: 채움 기입 → 응답 {w_fill} 사이클 · 조회 지점 → 응답 {w_ref} 사이클")

    for name, p, idx, tag, kind, at_edge in N9_CASES:
        await n9_clean(dut, name)
        vpn = vpn_of(tag, idx)
        wr = int(kind == "perm")                             # 권한 행만 쓰기 요청 — 자격이 W 를 본다
        await install_entry(dut, p, idx, tag, N9_FA, **(dict(r=0, w=1, x=1) if wr else {}))
        await present_seq(dut, [(p, vpn), (p, vpn)], hold_at_s3=True, write=wr)
        ops = {None: [], "v0": [(xent(p, idx) + 4, hi_word(tag, v=0))], "flush": [(XCTL_FLUSH, p)],
               "replace": entry_ops(p, idx, tag, N9_FB), "perm": entry_ops(p, idx, tag, N9_FA)}[kind]
        if at_edge:
            # R1 의 첫 적중 사이클(hold 가 막 섰다)에 기입을 싣는다 — 수락 에지 = 래치 포착 에지.
            (addr, data), = ops
            dut.io_mmio_addr.value = addr
            dut.io_mmio_wdata.value = data
            dut.io_mmio_wstrobe.value = 1
            await settle(dut)
            assert int(dut.io_mmio_ready.value) == 1, (
                f"[{name}] 포착 에지에 실은 기입이 버스에서 잡혔다 — 같은 에지가 아니다")
            await step(dut)                                  # 포착 에지 = 수락 에지
            dut.io_mmio_wstrobe.value = 0
            await step(dut)
        else:
            await step(dut, 2)                               # R1 의 판정이 래치된 뒤
            for addr, data in ops:
                await mmio_write(dut, addr, data)
        await step(dut, 4)
        lbl = f"{name} · hold 중 관측면 (STATUS, VPN, VPN_HI) · [6]"
        rows.append((lbl, *await read_obs(dut), await fault6(dut)))
        want.append((lbl, 0, 0, 0, 0))
        await set_hold(dut, 0)
        got = await collect_rsp(dut, 12)
        lbl = f"{name} · hold 해제 뒤 응답 (수, 사이클, 승인, phys, 값, fromFill, 권한 …)"
        rows.append((lbl, *flat_rsp(got)))
        if kind is None:
            want.append((lbl, 2, w_ref, 1, 1, N9_FA, 0, "R--", w_ref + 1, 1, 1, N9_FA, 0, "R--"))
        elif kind in ("replace", "perm"):
            want.append((lbl, 2, w_ref, 1, 1, N9_FA, 0, "-WX" if wr else "R--",
                         w_ref + 1, 0, 0, 0, 0, "---"))
        else:
            want.append((lbl, 0))
            lbl = f"{name} · hold 해제 뒤 관측면 — R2 가 그 에지 뒤에 판정돼 미적중"
            rows.append((lbl, *await read_obs(dut)))
            want.append((lbl, xstatus_word(1, 1, p), vpn, 0))
            await install_entry(dut, p, idx, tag, N9_FC)
            lbl = f"{name} · 채움(FC) 뒤 응답 (수, 사이클, 승인, phys, 값, fromFill, 권한 …)"
            rows.append((lbl, *flat_rsp(await collect_rsp(dut, 12))))
            want.append((lbl, 2, w_fill - 1, 1, 1, N9_FA, 0, "R--", w_fill, 1, 1, N9_FC, 1, "R--"))
        lbl = f"{name} · 끝 [4] · [19] · [6]"
        rows.append((lbl, *await hiu_report(dut)))
        want.append((lbl, wr, int(kind == "replace"), 0))

    name, p, i1, t1, i2, t2 = N9_NOHOLD
    await n9_clean(dut, name)
    v1, v2 = vpn_of(t1, i1), vpn_of(t2, i2)
    await install_entry(dut, p, i1, t1, N9_FA)
    await present_seq(dut, [(p, v1), (p, v2)], hold_at_s3=False)
    lbl = f"{name} · 응답 (수 …)"
    rows.append((lbl, *flat_rsp(await collect_rsp(dut, 12))))
    want.append((lbl, 0))
    lbl = f"{name} · 관측면 — R2 자신의 정지"
    rows.append((lbl, *await read_obs(dut)))
    want.append((lbl, xstatus_word(1, 1, p), v2, 0))
    await install_entry(dut, p, i2, t2, N9_FD)
    lbl = f"{name} · 채움(FD) 뒤 응답"
    rows.append((lbl, *flat_rsp(await collect_rsp(dut, 12))))
    want.append((lbl, 2, w_fill - 1, 1, 1, N9_FA, 0, "R--", w_fill, 1, 1, N9_FD, 1, "R--"))
    lbl = f"{name} · 끝 [4] · [19] · [6]"
    rows.append((lbl, *await hiu_report(dut)))
    want.append((lbl, 0, 0, 0))

    assert rows == want, (
        "래치된 판정이 철회 · 대체를 건너 그 요청과 함께 가지 않았다 (철회의 효력 범위 · 결과 (a)(b) · "
        "판정 래치의 한 값) — 행 표가 정본과 다르다:\n" + table_diff(rows, want))
    dut._log.info(f"래치된 R1 은 V=0 · flush · 대체를 건너 FA 로 승인 · 그 에지 뒤에 판정된 R2 는 미적중"
                  f"(철회) 또는 새 프레임(대체 — 호스트 소유라 차단 + [19]) · 권한만 바뀐 대체에서 쓰기 R1 은 "
                  f"래치된 -WX 로 승인 · R2 는 R-- 로 거부 + [4] · hold 없는 대조에서 판정을 물려받지 않음 — "
                  f"{len(rows)} 행")
