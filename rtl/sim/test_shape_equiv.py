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
    정본이 상주를 요구하는 시험(03-hiu.typ:700 「항목 설치 → 컨텍스트 전환 → *같은 주소*의 변환이 미적중하는지 확인한다」)의
    기입 쪽이 처음으로 MMIO 로 표현 가능해졌다 — 설치 → flush → 같은 주소 미적중.
    같은 항목 HI 두 워드를 쉬는 사이클 없이 잇는 원시 구동(`mmio_burst`)으로
    하류 거부의 처분(D-2 버스 정지 — 정확히 한 사이클 · `[6]` 무발화 · 풀린
    기입의 커밋)도 값 수준에서 잰다.
    조회 쪽은 여전히 내부 포트이므로 이것도 **끝-끝 호스트 ABI 등가는 아니다**
    (호스트 쪽 문 · 디코드 진입 층위의 요청).

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
EXPECT_OUTPUTS = 121
EXPECT_COMPARE_FACE = 119


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


OUT_PORTS = parse_output_ports()
CLEAR_PORTS = parse_clear_ports()
COMPARE_FACE = [n for n in OUT_PORTS if n not in SHAPE_DEPENDENT]

# 해제선이 없는 sticky — 여기 있는 것은 IO 해제선이 아니라 **MMIO 로만**
# 내려간다 (Wt64Top: `own.io.faultClearBadWrite`·`cq.io.faultClearOverflow`·
# `cq.io.faultClearBadWrite` 는 `fclr(…)` 만 받고, `fpCapAbsent`·`ehCapAbsent`
# 는 `capWord.io.word` 라 해제가 `capWord.io.clrAcc` 뿐). 궤적 대조 전에 IO 만
# 흔들면 이 축들은 sticky 로 남고, 그 잔재가 다음 궤적의 시작 상태를 바꾼다.
# `fpCfgBadWrite` 는 0xF84[6] 로만 내려간다 (D1 (b) — IO 해제선을 새로 만들지 않았다). 궤적 대조
# 시험의 자극은 이 여섯을 세우지 않으므로 지금은 무해하지만, 세우는 자극이
# 추가되면 여기가 먼저 깨져야 한다 — 그래서 이름으로 적어 둔다.
NO_IO_CLEAR = ["io_fault_ownBadWrite", "io_fault_cqOverflow",
               "io_fault_cqBadWrite", "io_fault_fpCapAbsent",
               "io_fault_ehCapAbsent", "io_fault_fpCfgBadWrite"]
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


def zero_inputs(dut):
    dut.io_instr_valid.value = 0
    for i in range(INSTR_WORDS):
        getattr(dut, f"io_instr_words_{i}").value = 0
    for n in ("wave", "epoch", "poison", "trace", "lnid", "precision", "dim"):
        getattr(dut, f"io_instr_tag_{n}").value = 0
    for n in ("io_mmio_addr", "io_mmio_wdata", "io_mmio_wstrobe", "io_mmio_rstrobe",
              "io_hiuReq_valid", "io_hiuReq_part", "io_hiuReq_vpn", "io_hiuReq_write",
              "io_hiuHold", "io_hostRsp_valid",
              "io_sharedReq_valid", "io_bank_acqValid", "io_bank_wrValid",
              "io_fp_reqValid", "io_mem_epochClear", "io_mem_complete",
              "io_mem_slotSel"):
        getattr(dut, n).value = 0
    for i in range(3):
        getattr(dut, f"io_push_{i}_strb").value = 0
    for i in range(4):
        getattr(dut, f"io_mem_cfgPreds_{i}").value = 0
        getattr(dut, f"io_mem_down_{i}_ready").value = 0
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
    """e-defined.typ:297 「항목 기저 주소는 `0xC00` + (파티션 ≪ 7) + (색인 ≪ 3) 이다」"""
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


async def install_entry(dut, part, idx, tag, frame, v=1):
    await mmio_write(dut, xent(part, idx), frame)            # LO — 스테이징
    await mmio_write(dut, xent(part, idx) + 4, hi_word(tag, v=v))  # HI — 커밋 발화


async def hiu_lookup(dut, part, vpn, window=LOOKUP_WINDOW):
    """읽기 요청 하나를 제시하고 결과를 돌려준다.

    반환: dict(rsp, granted, frame, stalled, trace). `rsp=0` 이면 창 안에 응답이
    없었고 `stalled` 는 그동안 `io.hiuReq.ready` 가 0 이던 사이클 수다 — 미적중
    정지다. `trace` 는 접수 뒤 사이클마다의 ready 표본이다 (`assert_miss` 가
    정지의 *모양*을 등식으로 잰다).
    """
    dut.io_hiuReq_part.value = part
    dut.io_hiuReq_vpn.value = vpn
    dut.io_hiuReq_write.value = 0
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
    stalled = 0
    trace = []
    for _ in range(window):
        await settle(dut)
        if int(dut.io_hiuRsp_valid.value):
            return dict(rsp=1, granted=int(dut.io_hiuRsp_granted.value),
                        frame=int(dut.io_phys_frame.value),
                        phys=int(dut.io_phys_valid.value), stalled=stalled,
                        trace=trace)
        rdy = int(dut.io_hiuReq_ready.value)
        trace.append(rdy)
        if rdy == 0:
            stalled += 1
        await step(dut)
    return dict(rsp=0, granted=0, frame=0, phys=0, stalled=stalled, trace=trace)


async def wait_rsp(dut, window=20):
    """정지가 풀린 뒤 그 요청의 응답을 기다린다."""
    for _ in range(window):
        await settle(dut)
        if int(dut.io_hiuRsp_valid.value):
            return dict(rsp=1, granted=int(dut.io_hiuRsp_granted.value),
                        frame=int(dut.io_phys_frame.value))
        await step(dut)
    return dict(rsp=0, granted=0, frame=0)


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
#   03-hiu.typ:1337 「이 장치는 거기 워드를 두지 않는다. 쓰기는」 — 물려받은 0x000–0x11F
#   e-defined.typ:743 「*소비 회로가 없는 RW 워드 — 쓰기는 거절, 읽기는 0.*」
#   03-hiu.typ:754 「비정렬 *읽기*는 0 · fault 없음이다」
#   03-hiu.typ:990 「읽기도 같다 — 수락(ready ∧ 스트로브)되지 않은 접근은 효과도 응답도 없다」

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
