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

호스트 명령 링(E.5 투입 방향)은 **미배선**이다: `Wt64Top.scala:1139` 의
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

**재지 못한다 (이름을 적는다 — 여기 없는 것은 미측정이지 통과가 아니다)**
  1. **형상 B/C 와의 실제 대조** — `Wt64Config(nPoints=2)` 로 두 번째 SV 를
     내는 생성기가 없다 (`rtl/spinal/.../gen/` 에 `GenWt64TopShape.scala`
     부재 — 실측). 선례는 있다 (`GenSharedUnit.scala:22-28` 이 같은 패턴으로
     `SharedUnitDepth0.sv` 를 낸다). 그 20줄이 착지하기 전까지 ISA-1 의
     **형상 축은 미측정**이다. 이 파일은 비교기를 세우고 그것이 살아 있음을
     `isa1_comparator_selfcheck` 로 매 실행 증명하되, **형상 축을 잰 척하지
     않는다.**
  2. **ISA-2 자리 축** — LNID 엔트리의 소유 지점 `[23:16]` 순열과 LBID
     엔트리의 슬롯 구간 `[15:0]` 순열은 **관측면이 없다.** RouteJudge 는
     지점별 소유를 구조적으로 모르고(`RouteJudge.scala:145` — missLnid 는
     `!viewHit` 뿐), 구간값의 소비자인 `Reassembly.wr → ResultBank.write` 가
     미배선이다(`Wt64Top.scala:81-83` — 「잠정 배선 (TODO)」 1항). MMIO 되읽기는 *저장* 확인이지
     *사상 경유* 확인이 아니다. ⇒ **ISA-2 는 「존재 축」만 닫히고 「자리 축」은
     열린 채 남는다.** 부록 D 에 ISA-2 를 「증명됨」으로 올리면 안 되고
     「부분 — 존재 축만」이 정직한 지위다.
  3. **OPREF B 참조의 LBID 축** — 제시 자체가 없다 (`Wt64Top.scala:84` TODO 2항 · `:925-927`,
     tokIn 은 사이클당 하나). ISA-2 α 는 **OPREF A 축만** 덮는다.
  4. **끝-끝 수치 등가** — 데이터패스 소비자 다수가 미착지 IO 수출이다
     (`Wt64Top.scala:95-97` — 같은 TODO 5항). 지금 대조 가능한 「결과」는 판정·fault·디코드
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
#   True** 이고 (`Wt64Top.scala:1512`) 구성 구역에서만 `cfgBlk.io.ready` 로
#   덮인다 (:1515). ⇒ 예약 오프셋(예: addr=0)에서 ready 를 폴링하면 **reset
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
EXPECT_OUTPUTS = 117
EXPECT_COMPARE_FACE = 115


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
# 내려간다 (`Wt64Top.scala:1154`·:1164·:1165·:1443). 궤적 대조 전에 IO 만
# 흔들면 이 축들은 sticky 로 남고, 그 잔재가 다음 궤적의 시작 상태를 바꾼다.
# 이 하네스의 자극은 이 넷을 세우지 않으므로 지금은 무해하지만, 세우는 자극이
# 추가되면 여기가 먼저 깨져야 한다 — 그래서 이름으로 적어 둔다.
NO_IO_CLEAR = ["io_fault_ownBadWrite", "io_fault_cqOverflow",
               "io_fault_cqBadWrite", "io_fault_fpCapAbsent"]
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
# `asm/wavetensor_asm.py:2059` `encode_pass` 가 명령마다 416비트 정수를 낸다.
# top 의 명령 포트는 13워드 × 32b = 416b (`Wt64Top.scala:615-619`) — 정확히
# 맞는다. 워드 0 이 최하위다.
#
# ⚠ **「같은 바이너리」의 단위는 (명령 워드열, 태그) 쌍이다.** 라우팅되는
#   LNID 는 **태그**의 것이지 명령 인코딩의 것이 아니다 (`Wt64Top.scala:927`
#   — `rj.io.tokIn.payload.tag := tagQ`, `tagQ = RegNext(io.instr.tag)`).
#   정본 §1.1 이 태그를 「명령어 인코딩의 일부가 아니라」고 못박았으므로
#   어셈블러는 태그를 방출하지 않는다. 「어셈블러가 다 준다」고 적으면 거짓이다.
#   ⇒ 태그는 이 하네스가 벡터로 든다. 그리고 **80b 로 팩하지 않는다** — 팩킹
#   순서는 미확정이고(`Common.scala:117-130`), top 이 필드별 포트로 받으므로
#   팩킹을 알 필요가 없다. 팩하는 순간 미확정 값이 시험 코드로 굳는다.
INSTR_WORDS = 13
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
    for n in ("wave", "thread", "lnid", "precision", "dim"):
        getattr(dut, f"io_instr_tag_{n}").value = 0
    for n in ("io_mmio_addr", "io_mmio_wdata", "io_mmio_wstrobe", "io_mmio_rstrobe",
              "io_hiuReq_valid", "io_hiuReq_part", "io_hiuReq_vpn", "io_hiuReq_write",
              "io_hiuHold", "io_install_valid", "io_flush_valid", "io_hostRsp_valid",
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

async def present(dut, words, lnid, thread=0, wave=0):
    """명령 디스크립터 하나를 제시하고 **그 엣지**의 관측면 전체를 뜬다.

    ⚠ **표본 엣지 = 방출 엣지다 (실측).** 디코드 사슬은 레지스터 한 단이고
      (`DecodeWalk` 방출단 + `tagQ = RegNext(io.instr.tag)` 정렬,
      `Wt64Top.scala:876-892`), `OperandDecode` 는 그 위의 조합이다. 값을
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
    dut.io_instr_tag_thread.value = thread
    dut.io_instr_tag_wave.value = wave
    dut.io_instr_valid.value = 1
    await step(dut)                     # ← 표본 엣지이자 방출 엣지
    snap = snapshot(dut)
    dut.io_instr_valid.value = 0
    for i in range(INSTR_WORDS):
        getattr(dut, f"io_instr_words_{i}").value = 0
    dut.io_instr_tag_lnid.value = 0
    dut.io_instr_tag_thread.value = 0
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
    (`Wt64Top.scala:918` — OPREF 직접 참조는 게이트 산출 0)."""
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
