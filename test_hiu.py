# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""HIU 테스트 — spec §29.13 test_plan (D4 / D6 / D7 / D8 착지 단계 S2-C3).

이 파일이 **재작성**된 이유 (사고가 아니라 요구된 결과다 — §29.14)
--------------------------------------------------------------------
폐기된 형태의 이 파일은 3.5개월 동안 두 가지를 했다:

  1. `dut.partitioned_tlb_{virt,phys,valid}[0][0].value = ...` 로 **RTL 이
     구동하지 않는 상태를 스스로 만들어** 그 위에서 "파티셔닝 TLB 히트"
     를 검증했다. 실리콘에는 그 저장소가 아예 없었다 (넷리스트 셀 0개,
     `Synth 8-3848` × 128). 즉 그 검증은 실물에 대해 아무것도 말하지
     않았다 — §28.4 항 7 (c) 의 정확한 형태다.
  2. 마스킹을 `masked_phys_addr != phys_addr` 로만 검사했다. 마스크가
     **무엇이든** 0 이 아니면 통과한다. 그 뒤에 결함 D8 (XChaCha20 의
     영구적 1단계 어긋남) 이 숨어 있었다 (§29.8).

두 은폐 경로를 모두 닫는다. 모든 TLB 상태는 **`tlb_write_*` 포트로만**
만들고, 마스크는 `scripts/golden_xchacha.py` 의 **정확값**과 비교한다.

계층 접근 정책 (§28.4 항 7)
---------------------------
  * (a) **관측**은 무제한 허용 — `dut.<internal>.value` 읽기는 이 규범의
        대상이 아니다. 아래 테스트는 `tlb_valid` / `tlb_mem` / `state` 를
        적극적으로 **읽는다**. 그것이 "RTL 이 실제로 구동했다" 의 증거다.
  * (c) **구동원 없는 기입은 금지** — 이 파일에는 TLB 내부 상태에 대한
        계층 강제 기입이 **한 건도 없다.** `test_no_hierarchical_tlb_writes`
        가 그 사실을 **소스 스캔으로 기계 검사**한다 (은폐 재발 탐지).
"""

import os
import re
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, "scripts"))

# golden-before-RTL (§29.8) — 마스크의 정확값은 여기서 온다.
from golden_xchacha import (  # noqa: E402
    FIXED_KEY, FIXED_NONCE, hiu_mask64, hiu_masked_phys,
)

# ---------------------------------------------------------------------------
# RTL 형상 상수 (HIU.v 의 파라미터/localparam 과 같은 값)
# ---------------------------------------------------------------------------
ADDR_WIDTH     = 64
PAGE_SHIFT     = 12
TLB_ENTRIES    = 16
NUM_PARTITIONS = 4
TLB_IDX_W      = 4
TLB_TAG_W      = ADDR_WIDTH - PAGE_SHIFT - TLB_IDX_W   # 48
TLB_PPN_W      = ADDR_WIDTH - PAGE_SHIFT               # 52
TLB_DEPTH      = NUM_PARTITIONS * TLB_ENTRIES          # 64

# FSM 상태 인코딩 (HIU.v localparam)
S_IDLE, S_TRANSLATE, S_DMA_EXEC, S_ATS_QUERY = 0, 1, 2, 3
S_PRI_REQUEST, S_GRANT_ACCESS, S_SHADOW_UPDATE, S_DUMMY_DELAY = 4, 5, 6, 7
S_FLUSH_TLB = 8
S_TLB_UPDATE, S_TLB_READ = 14, 15

# tlb_fault_code 인코딩 (spec §29.6 표)
F_NONE, F_INDEX_MISMATCH, F_PHYS_MISALIGNED = 0, 1, 2
F_BUSY, F_PARTITION_RANGE = 3, 4

MASK64 = hiu_mask64(FIXED_KEY, FIXED_NONCE)

_SETTLE_NS = 1  # NBA 정착용 (clk 주기 10 ns)


# ---------------------------------------------------------------------------
# 하네스
# ---------------------------------------------------------------------------

def _entry_addr(partition, virt):
    """엔트리 주소 = {partition, index} 연접 (§29.5). 곱셈 없음."""
    return (partition << TLB_IDX_W) | ((virt >> PAGE_SHIFT) & (TLB_ENTRIES - 1))


def _entry_word(virt, phys):
    """`tlb_mem` 워드 = {tag[47:0], ppn[51:0]}."""
    tag = virt >> (PAGE_SHIFT + TLB_IDX_W)
    ppn = phys >> PAGE_SHIFT
    return (tag << TLB_PPN_W) | ppn


async def _settle(dut):
    await Timer(_SETTLE_NS, unit="ns")


async def reset_dut(dut):
    """전 입력을 정의된 값으로 구동한 뒤 reset 한다.

    클럭은 테스트마다 새로 띄운다 — cocotb 는 테스트가 끝날 때 그
    테스트가 `start_soon` 한 태스크를 취소하므로, 동시에 존재하는 클럭
    구동자는 항상 하나다 (모듈 전역으로 한 번만 띄우면 두 번째 테스트에
    클럭이 없다).

    **`tlb_mem` 은 reset 으로 지워지지 않는다** — reset-free RAM 이기
    때문이며, 그것이 §29.6 의 전제다. 따라서 앞선 테스트가 남긴 tag/ppn
    데이터가 그대로 살아 있다. 이 사실에 의존하는 테스트는 아래
    `test_zero_tag_probe` 처럼 **아무도 쓰지 않은 엔트리 주소**를 골라
    순서 의존을 피한다.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst.value = 1
    dut.virt_addr.value = 0
    dut.dma_req.value = 0
    dut.dma_data_in.value = 0
    # D7 (§29.10 항 1): RESERVED 포트 — 호스트는 2'b00 으로 구동해야 한다.
    dut.interface_type.value = 0
    dut.ats_req.value = 0
    dut.pri_req.value = 0
    dut.shadow_write_start.value = 0
    dut.shadow_write_end.value = 0
    dut.shadow_write_en.value = 0
    dut.shadow_index.value = 0
    dut.context_switch.value = 0
    dut.partition_id.value = 0
    dut.chacha_nonce.value = FIXED_NONCE
    dut.chacha_key.value = FIXED_KEY
    dut.tlb_write_en.value = 0
    dut.tlb_write_partition.value = 0
    dut.tlb_write_index.value = 0
    dut.tlb_write_virt.value = 0
    dut.tlb_write_phys.value = 0

    await Timer(20, unit="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await _settle(dut)


async def tlb_fill(dut, partition, virt, phys, index=None):
    """`tlb_write_*` **포트**로 엔트리를 설치한다 (§29.4 프로토콜).

    반환: (fault, code) — 설치 직후 cycle 의 `tlb_fault` 펄스와 코드.
    계층 강제 기입은 쓰지 않는다. 이것이 이 파일 재작성의 본체다.
    """
    if index is None:
        index = (virt >> PAGE_SHIFT) & (TLB_ENTRIES - 1)

    dut.tlb_write_partition.value = partition
    dut.tlb_write_index.value = index
    dut.tlb_write_virt.value = virt
    dut.tlb_write_phys.value = phys
    dut.tlb_write_en.value = 1
    await RisingEdge(dut.clk)          # IDLE edge: payload 샘플 + → TLB_UPDATE
    dut.tlb_write_en.value = 0
    await RisingEdge(dut.clk)          # TLB_UPDATE edge: 설치 (정확히 1 cycle)
    await _settle(dut)
    fault = int(dut.tlb_fault.value)
    code = int(dut.tlb_fault_code.value)
    await RisingEdge(dut.clk)          # fault 펄스 소멸 확인용 여유
    await _settle(dut)
    assert int(dut.tlb_fault.value) == 0, \
        "tlb_fault 는 1-cycle 펄스여야 한다 (§29.4 출력 표)"
    return fault, code


async def install_shadow(dut, index, start, end):
    """`shadow_write_*` 포트로 shadow region 을 설치한다."""
    dut.shadow_write_start.value = start
    dut.shadow_write_end.value = end
    dut.shadow_index.value = index
    dut.shadow_write_en.value = 1
    await RisingEdge(dut.clk)          # IDLE → SHADOW_UPDATE
    dut.shadow_write_en.value = 0
    await RisingEdge(dut.clk)          # SHADOW_UPDATE 실행 (라이브 입력 유지)
    await _settle(dut)


async def run_translate(dut, virt, partition=0):
    """DMA 변환 1회. 반환: (cycles, granted, phys, masked).

    `cycles` 는 dma_req 샘플 edge 이후 `GRANT_ACCESS` 도달까지의 edge 수다.
    **절대치를 assert 하지 않는다** — 계약은 경로 간 동일성이지 절대치가
    아니다 (§29.5 상수시간 계약).
    """
    dut.partition_id.value = partition
    dut.virt_addr.value = virt
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0

    for n in range(1, 400):
        await RisingEdge(dut.clk)
        await _settle(dut)
        if int(dut.state.value) == S_GRANT_ACCESS:
            granted = int(dut.access_granted.value)
            phys = int(dut.phys_addr.value)
            masked = int(dut.masked_phys_addr.value)
            await RisingEdge(dut.clk)   # GRANT_ACCESS 소비 → IDLE
            await _settle(dut)
            return n, granted, phys, masked
    raise AssertionError("변환 시퀀스가 GRANT_ACCESS 에 도달하지 못했다")


def tlb_valid_bit(dut, addr):
    return (int(dut.tlb_valid.value) >> addr) & 1


# ---------------------------------------------------------------------------
# 1. 은폐 재발 탐지 — 이 파일 자신에 대한 기계 검사
# ---------------------------------------------------------------------------

# 금지 대상: TLB **내부 저장소**에 대한 계층 강제 기입 (§28.4 항 7 (c)).
# 허용: 포트 (`tlb_write_*`) 구동, 그리고 모든 읽기.
_FORBIDDEN_WRITE = re.compile(
    r"dut\."                                   # cocotb 계층 루트
    r"(?!tlb_write_|tlb_fault)"                # 포트는 대상이 아니다
    r"(?:partitioned_)?(?:tlb_|xlat_)"         # TLB 내부 상태 이름
    r"[A-Za-z0-9_]*"
    r"(?:\s*\[[^\]]*\])*"                      # 배열 첨자 0개 이상
    r"\s*\.\s*value\s*=(?!=)"                  # .value = (== 는 아님)
)


@cocotb.test()
async def test_no_hierarchical_tlb_writes(dut):
    """§28.4 항 7 (c) — TLB 내부 상태에 대한 계층 강제 기입 0건.

    **은폐 재발 탐지기다.** D4 는 `test_hiu.py:24-26` 의 강제 기입 3건이
    RTL 이 만들지 않는 상태를 만들어 3.5개월 동안 검증을 통과시킨
    결함이었다. 이 검사는 그 형태가 다시 들어오면 즉시 FAIL 한다.

    정직한 한계: 소스 스캔은 **이 파일**만 본다. 넷리스트 측 방어는
    별개이며 `Synth 8-3848` exact 0 축이 담당한다 (§29.11 별항 3) —
    그리고 그 축도 D4 의 절반만 본다 (clear 구동원이 있는 `valid` 는
    잡히지 않는다). 두 검사 어느 쪽도 규범의 대체물이 아니다.
    """
    with open(os.path.join(_REPO, "test_hiu.py"), encoding="utf-8") as fh:
        src = fh.read()
    hits = [m.group(0) for m in _FORBIDDEN_WRITE.finditer(src)]
    assert not hits, (
        "TLB 내부 상태에 대한 계층 강제 기입이 발견됐다 — §28.4 항 7 (c) "
        f"위반. 처분은 테스트 수정이 아니라 RTL 과 테스트 중 어느 쪽이 "
        f"진실인지의 판정이다. 발견: {hits}")

    # 도달 가능성 자체 확인 — 정규식이 아무것도 못 잡는 죽은 검사가
    # 아님을 같은 실행에서 실증한다 (tautology 방지). probe 문자열은
    # **조각으로 조립**한다 — 통째로 적으면 위 스캔이 자기 자신을 잡는다.
    for name in ("tlb_valid", "tlb_mem", "partitioned_tlb_valid", "xlat_virt"):
        probe = "dut." + name + "[0]" + ".value" + " = 1"
        assert _FORBIDDEN_WRITE.search(probe), \
            f"탐지 정규식이 알려진 위반 형태를 잡지 못한다 ({name}) — 검사가 죽었다"
    for ok in ("dut." + "tlb_write_en" + ".value = 1",
               "dut." + "shadow_write_en" + ".value = 1"):
        assert not _FORBIDDEN_WRITE.search(ok), \
            f"탐지 정규식이 정규 포트 구동을 오탐한다: {ok}"


# ---------------------------------------------------------------------------
# 2. D4 — fill 경로가 실재하고 RTL 이 저장소를 구동한다
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_tlb_storage_is_rtl_driven(dut):
    """§29.13 항 1 — TLB 저장소를 **RTL 이** 구동한다는 직접 증거.

    reset 직후 전부 0 → 포트 기입 1회 → `tlb_valid` 비트가 서고
    `tlb_mem` 워드가 {tag, ppn} 으로 채워진다. 이 검사는 fill 경로가
    사라지거나 (D4 재발) 저장소가 다시 구동원을 잃으면 FAIL 한다.
    """
    await reset_dut(dut)

    assert int(dut.tlb_valid.value) == 0, "reset 후 tlb_valid 는 전부 0 이어야 한다"

    virt, phys, part = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000, 0
    addr = _entry_addr(part, virt)

    fault, _ = await tlb_fill(dut, part, virt, phys)
    assert fault == 0, "정상 기입에 fault 가 떴다"

    assert tlb_valid_bit(dut, addr) == 1, \
        "포트 기입 후에도 tlb_valid 가 서지 않았다 — fill 경로가 없다 (D4 재발)"
    got = int(dut.tlb_mem[addr].value)
    want = _entry_word(virt, phys)
    assert got == want, \
        f"tlb_mem[{addr}] = 0x{got:025x}, 기대 0x{want:025x} — RTL 이 저장소를 " \
        "구동하지 않는다"

    # 다른 엔트리는 건드리지 않았다 (설치의 부작용 범위 = 해당 엔트리뿐).
    assert int(dut.tlb_valid.value) == (1 << addr), \
        "설치가 다른 엔트리의 valid 까지 건드렸다"


@cocotb.test()
async def test_tlb_hit_translates_and_masks(dut):
    """§29.13 항 1/8 — TLB 히트 변환 + XChaCha20 **정확값**.

    폐기된 `masked != phys` 검사는 마스크가 무엇이든 통과했다 (§29.8 은폐
    경로). 여기서는 golden 산출값과 정확 비교한다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    await tlb_fill(dut, 0, virt, phys)

    _, granted, got_phys, masked = await run_translate(dut, virt, partition=0)
    assert granted == 1, "포트로 채운 TLB 엔트리가 히트하지 않았다"
    assert got_phys == phys, f"phys_addr = 0x{got_phys:016x}, 기대 0x{phys:016x}"
    assert masked == hiu_masked_phys(phys, FIXED_KEY, FIXED_NONCE), \
        (f"masked_phys_addr = 0x{masked:016x}, golden "
         f"0x{hiu_masked_phys(phys, FIXED_KEY, FIXED_NONCE):016x} — "
         "XChaCha20 계약 불이행 (§29.8 D8)")

    # 페이지 오프셋이 살아 있는지 — {ppn, offset} 재조립의 직접 검사.
    voff = virt | 0x0ABC
    _, granted, got_phys, _ = await run_translate(dut, voff, partition=0)
    assert granted == 1
    assert got_phys == (phys | 0x0ABC), \
        f"페이지 오프셋이 전달되지 않았다: 0x{got_phys:016x}"


# ---------------------------------------------------------------------------
# 3. §29.6 — 미초기화 TLB 를 히트로 오인하지 않는다
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_zero_tag_probe(dut):
    """§29.13 항 2 / §29.6 항 3 — zero-tag probe.

    **discriminator 가 실재하는 테스트다.** `SIM ?= verilator` 는 2-state
    zero-init 이라 미기입 `tlb_mem` 이 0 으로 읽힌다. tag 가 0 이 되는
    주소로 변환을 걸면 `valid` 게이팅이 빠진 순간 tag 0 == RAM 0 으로
    **반드시 히트한다** — 즉 이 테스트는 tautology 가 아니다.

    엔트리 주소는 **이 파일의 어떤 테스트도 쓰지 않는** {partition 3,
    index 15} 를 고른다. `tlb_mem` 은 reset-free 이므로 "reset 했으니
    비어 있다" 를 가정할 수 없기 때문이다 — 이 회피 자체가 §29.6 항 2
    ("flush 는 데이터를 남긴다") 를 테스트 설계에서 이행한 형태다.
    """
    await reset_dut(dut)

    virt = 0x0000_0000_0000_F000        # tag = 0, index = 15
    part = NUM_PARTITIONS - 1           # partition 3
    addr = _entry_addr(part, virt)
    assert addr == TLB_DEPTH - 1

    # discriminator 가 살아 있음을 같은 실행에서 실증한다: RAM 이 정말 0 이고,
    # 따라서 tag 비교 단독으로는 **반드시 히트한다**.
    ram = int(dut.tlb_mem[addr].value)
    assert ram == 0, \
        "verilator zero-init 가정이 깨졌다 — 이 테스트의 discriminator 가 죽었다"
    assert (ram >> TLB_PPN_W) == (virt >> (PAGE_SHIFT + TLB_IDX_W)), \
        "tag 가 우연히 일치하지 않는다 — discriminator 가 죽었다"
    assert tlb_valid_bit(dut, addr) == 0

    _, granted, phys, masked = await run_translate(dut, virt, partition=part)
    assert granted == 0, \
        "미기입 TLB 를 히트로 오인했다 — valid 게이팅이 빠졌다 (§29.6 항 1)"
    assert phys == 0, "§29.6 부수 규범 — miss 시 phys_addr 는 0 으로 구동한다"
    assert masked == (0 ^ MASK64), "miss 경로의 마스크가 golden 과 다르다"


@cocotb.test()
async def test_flush_leaves_data_valid_is_the_barrier(dut):
    """§29.13 항 7 / §29.5 flush 규범.

    `FLUSH_TLB` 는 `tlb_valid` 만 지우고 `tlb_mem` 의 tag/ppn 은
    **남긴다** (reset-free RAM 이라 지울 수단이 없다). 그래도 같은 주소가
    miss 해야 한다 — `valid` 가 유일한 방벽이기 때문이다. 구현자는
    "flush 했으니 깨끗하다" 를 가정할 수 없다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    addr = _entry_addr(0, virt)
    await tlb_fill(dut, 0, virt, phys)
    _, granted, _, _ = await run_translate(dut, virt)
    assert granted == 1

    await install_shadow(dut, 0, 0x0000_0000_3000_0000, 0x0000_0000_3FFF_FFFF)

    dut.context_switch.value = 1
    await RisingEdge(dut.clk)
    dut.context_switch.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await _settle(dut)

    assert int(dut.tlb_valid.value) == 0, "FLUSH_TLB 가 tlb_valid 를 지우지 않았다"
    assert int(dut.shadow_valid[0].value) == 0, "shadow_valid 플러시 실패"
    # **데이터는 남아 있다** — 이것이 §29.6 의 존재 이유다.
    assert int(dut.tlb_mem[addr].value) == _entry_word(virt, phys), \
        "flush 가 tlb_mem 데이터를 지웠다 — spec §29.5 flush 규범과 다르다"

    _, granted, got_phys, _ = await run_translate(dut, virt)
    assert granted == 0, "flush 후에도 stale 데이터로 히트했다 — 격리 위반"
    assert got_phys == 0


# ---------------------------------------------------------------------------
# 4. §29.5 — 우선순위 / 격리 / 상수시간
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_tlb_beats_overlapping_shadow(dut):
    """§29.13 항 3 — TLB 히트가 이기고 shadow 는 fallback 전용이다.

    조사가 실증한 `SHADOW_OVERRIDES` 회귀의 직접 방어다. 폐기된 형태의
    `if (!access_granted)` 가드는 죽은 코드였고, 같은 always 블록의
    **나중 대입인 shadow 가 TLB 를 덮어** 겹치는 엔트리를 조용히
    identity-map 으로 강등시켰다 = tenant 격리 구멍.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    # TLB 항목을 **포함하는** shadow region 을 먼저 깐다.
    await install_shadow(dut, 0, 0x0000_0000_0000_0000, 0x0000_0000_FFFF_FFFF)
    await tlb_fill(dut, 0, virt, phys)

    _, granted, got_phys, _ = await run_translate(dut, virt)
    assert granted == 1
    assert got_phys == phys, (
        f"phys_addr = 0x{got_phys:016x} — shadow 가 TLB 를 덮었다 "
        "(SHADOW_OVERRIDES 회귀, §29.5 우선순위 규범 위반)")

    # 반대편: TLB 가 miss 하는 주소는 shadow 로 fallback 한다.
    other = 0x0000_0000_5000_0000
    _, granted, got_phys, _ = await run_translate(dut, other)
    assert granted == 1 and got_phys == other, \
        "shadow fallback 이 동작하지 않는다"


@cocotb.test()
async def test_partition_isolation(dut):
    """§29.13 항 6 — 파티션 = tenant lease 격리 경계.

    엔트리 주소 상위 2비트가 partition_id 이므로 파티션 간 충돌은
    **구조적으로** 불가능하다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    await tlb_fill(dut, 0, virt, phys)

    _, granted, _, _ = await run_translate(dut, virt, partition=1)
    assert granted == 0, "파티션 0 의 엔트리가 파티션 1 에서 히트했다 — 격리 위반"

    # 같은 index 를 파티션 1 에 따로 설치하면 서로 간섭하지 않는다.
    phys1 = 0x0000_0000_7000_0000
    await tlb_fill(dut, 1, virt, phys1)
    _, g0, p0, _ = await run_translate(dut, virt, partition=0)
    _, g1, p1, _ = await run_translate(dut, virt, partition=1)
    assert (g0, p0) == (1, phys), "파티션 1 기입이 파티션 0 을 덮었다"
    assert (g1, p1) == (1, phys1), "파티션 1 엔트리가 설치되지 않았다"


@cocotb.test()
async def test_constant_time_paths(dut):
    """§29.13 항 4 — hit / shadow-fallback / miss 의 cycle 수가 **서로 같다**.

    **절대치를 assert 하지 않는다.** 계약은 경로 간 동일성이지 절대치가
    아니다 (§29.5). `TLB_READ` 추가로 절대치는 1 cycle 늘어났고, 그것은
    계약 위반이 아니라 계약의 갱신이다.
    """
    await reset_dut(dut)

    await install_shadow(dut, 0, 0x0000_0000_3000_0000, 0x0000_0000_3FFF_FFFF)
    await tlb_fill(dut, 0, 0x0000_0000_1000_0000, 0x0000_0000_2000_0000)

    n_hit, g_hit, _, _ = await run_translate(dut, 0x0000_0000_1000_0000)
    n_shadow, g_shadow, _, _ = await run_translate(dut, 0x0000_0000_3500_0000)
    n_miss, g_miss, _, _ = await run_translate(dut, 0x0000_0000_FFFF_F000)

    assert (g_hit, g_shadow, g_miss) == (1, 1, 0), \
        f"경로 판정이 틀렸다: {(g_hit, g_shadow, g_miss)}"
    assert n_hit == n_shadow == n_miss, (
        "상수시간 계약 위반 — hit/shadow/miss 의 cycle 수가 다르다: "
        f"{n_hit} / {n_shadow} / {n_miss}")
    dut._log.info(
        "constant-time: hit=shadow=miss=%d cycles (절대치는 기록만 한다)", n_hit)


# ---------------------------------------------------------------------------
# 5. §29.6 항 5 — loud fault 4종
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_fault_index_mismatch(dut):
    """code 1 — index 가 tag 와 어긋난 엔트리는 어떤 주소로도 조회될 수 없다.

    조용히 설치하면 호스트는 매핑했다고 믿고 하드웨어는 영원히 miss 한다
    — D4 와 같은 종류의 "선언과 실물의 괴리" 다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000   # index = 0
    fault, code = await tlb_fill(dut, 0, virt, phys, index=3)    # 어긋난 index
    assert fault == 1 and code == F_INDEX_MISMATCH, \
        f"INDEX_MISMATCH 가 조용히 통과했다 (fault={fault}, code={code})"
    assert int(dut.tlb_valid.value) == 0, "fault 인데 엔트리가 설치됐다"

    _, granted, _, _ = await run_translate(dut, virt)
    assert granted == 0


@cocotb.test()
async def test_fault_phys_misaligned(dut):
    """code 2 — 하위 PAGE_SHIFT 비트가 비영이면 기입하지 않는다.

    비영을 조용히 버리면 호스트가 요청한 물리 주소와 실제 변환 결과가
    말없이 달라진다.
    """
    await reset_dut(dut)

    virt = 0x0000_0000_1000_0000
    fault, code = await tlb_fill(dut, 0, virt, 0x0000_0000_2000_0001)
    assert fault == 1 and code == F_PHYS_MISALIGNED, \
        f"PHYS_MISALIGNED 가 조용히 통과했다 (fault={fault}, code={code})"
    assert int(dut.tlb_valid.value) == 0, "fault 인데 엔트리가 설치됐다"


@cocotb.test()
async def test_fault_busy(dut):
    """code 3 — `state != IDLE` 에서의 기입 요청은 **거절되고 소리를 낸다**.

    조용한 드롭도 조용한 큐잉도 없다 (§29.4 프로토콜 3). 재시도는 호스트
    책임이다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000

    # 변환 시퀀스를 띄워 IDLE 이 아닌 상태를 만든다.
    dut.virt_addr.value = virt
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    await _settle(dut)
    assert int(dut.state.value) != S_IDLE, "BUSY 조건을 만들지 못했다"

    dut.tlb_write_partition.value = 0
    dut.tlb_write_index.value = 0
    dut.tlb_write_virt.value = virt
    dut.tlb_write_phys.value = phys
    dut.tlb_write_en.value = 1
    await RisingEdge(dut.clk)
    dut.tlb_write_en.value = 0
    await _settle(dut)
    assert int(dut.tlb_fault.value) == 1, "BUSY 기입이 조용히 드롭됐다"
    assert int(dut.tlb_fault_code.value) == F_BUSY

    # 시퀀스를 끝까지 흘려보내고, 기입이 **수행되지 않았음**을 확인한다.
    for _ in range(120):
        await RisingEdge(dut.clk)
        await _settle(dut)
        if int(dut.state.value) == S_IDLE:
            break
    assert int(dut.tlb_valid.value) == 0, "BUSY 인데 엔트리가 설치됐다"

    # 호스트가 재시도하면 정상 설치된다 (거절이 영구 손상이 아님).
    fault, _ = await tlb_fill(dut, 0, virt, phys)
    assert fault == 0
    assert tlb_valid_bit(dut, _entry_addr(0, virt)) == 1


@cocotb.test()
async def test_fault_partition_range_unreachable(dut):
    """code 4 — 현 형상에서 **도달 불가**임을 기록한다 (§29.13 항 5).

    `NUM_PARTITIONS = 4` 이고 `tlb_write_partition` 이 2비트이므로
    `partition >= NUM_PARTITIONS` 는 구조적으로 성립할 수 없다. RTL 은
    조건을 그대로 들고 있고 (재형상 시의 조용한 실패를 막기 위해),
    합성기는 그것을 상수 0 으로 접는다. 여기서는 **도달 가능한 최대
    파티션이 정상 동작한다**는 것만 확인한다 — 존재하지 않는 자극을
    발명하지 않는다.
    """
    await reset_dut(dut)

    assert NUM_PARTITIONS == 4, "형상이 바뀌면 이 주석의 도달 불가 논거를 재유도하라"
    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    fault, code = await tlb_fill(dut, NUM_PARTITIONS - 1, virt, phys)
    assert fault == 0 and code == F_NONE, \
        f"최대 파티션 기입이 거절됐다 (fault={fault}, code={code})"
    _, granted, got_phys, _ = await run_translate(
        dut, virt, partition=NUM_PARTITIONS - 1)
    assert granted == 1 and got_phys == phys


@cocotb.test()
async def test_tlb_write_beats_shadow_write(dut):
    """§29.4 프로토콜 4 — 동시 어서트 시 TLB 기입이 이긴다 (fault 아님).

    조회 우선순위 (TLB > shadow) 와 **같은 방향**인 것 자체가 규범이다.
    """
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    dut.tlb_write_partition.value = 0
    dut.tlb_write_index.value = 0
    dut.tlb_write_virt.value = virt
    dut.tlb_write_phys.value = phys
    dut.tlb_write_en.value = 1
    dut.shadow_write_start.value = 0x0000_0000_3000_0000
    dut.shadow_write_end.value = 0x0000_0000_3FFF_FFFF
    dut.shadow_index.value = 0
    dut.shadow_write_en.value = 1
    await RisingEdge(dut.clk)
    dut.tlb_write_en.value = 0
    dut.shadow_write_en.value = 0
    await RisingEdge(dut.clk)
    await _settle(dut)
    assert int(dut.tlb_fault.value) == 0, \
        "우선순위 규정인데 fault 가 떴다 (호스트 오류가 아니다)"
    await RisingEdge(dut.clk)
    await _settle(dut)

    assert tlb_valid_bit(dut, _entry_addr(0, virt)) == 1, "TLB 기입이 지지 않아야 한다"
    assert int(dut.shadow_valid[0].value) == 0, \
        "shadow 기입이 수행됐다 — TLB 기입이 이겨야 한다"


# ---------------------------------------------------------------------------
# 6. 기존 커버리지 승계 (shadow / ATS / PRI) — D7 주석 정정 포함
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_shadow_hit_and_ats_pri(dut):
    """shadow 히트 + ATS/PRI 응답.

    **D7 주석 정정 (§29.10 항 4 — 의무).** 폐기된 형태의 이 파일은
    Test 1 에 "PCIe", Test 2 에 "USB" 라고 적고 `interface_type` 을 0/1 로
    바꿨다. 그 주석은 두 transport 를 검증하는 것처럼 읽히게 하는 **D4 와
    동종의 거짓 진술**이었다 — RTL 은 `interface_type` 을 **한 번도 읽지
    않으므로** 그 구분을 전혀 하지 않는다. 포트를 남기든 없애든 무조건
    정정 대상이다. 여기서는 §29.10 항 1 대로 RESERVED = `2'b00` 으로만
    구동하고, transport 구분을 주장하지 않는다.
    """
    await reset_dut(dut)
    assert int(dut.interface_type.value) == 0, \
        "RESERVED 포트는 2'b00 으로 구동한다 (§29.10 항 1)"

    await install_shadow(dut, 0, 0x0000_0000_3000_0000, 0x0000_0000_3FFF_FFFF)

    virt = 0x0000_0000_3500_0000
    _, granted, phys, masked = await run_translate(dut, virt)
    assert granted == 1, "Shadow 히트 실패"
    assert phys == virt, "shadow 는 identity map 이다"
    assert masked == hiu_masked_phys(virt, FIXED_KEY, FIXED_NONCE), \
        "shadow 경로의 마스크가 golden 과 다르다"

    dut.ats_req.value = 1
    await RisingEdge(dut.clk)
    dut.ats_req.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await _settle(dut)
    assert int(dut.ats_resp.value) == 1, "ATS 응답 실패"

    dut.pri_req.value = 1
    await RisingEdge(dut.clk)
    dut.pri_req.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await _settle(dut)
    assert int(dut.pri_resp.value) == 1, "PRI 응답 실패"


@cocotb.test()
async def test_dma_completes_on_hit(dut):
    """DMA 왕복 — `dma_ack` 와 `dma_data_out` 이 마스킹된 주소로 계산된다."""
    await reset_dut(dut)

    virt, phys = 0x0000_0000_1000_0000, 0x0000_0000_2000_0000
    await tlb_fill(dut, 0, virt, phys)

    dut.dma_data_in.value = 0xDEADBEEF
    dut.virt_addr.value = virt
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0

    for _ in range(200):
        await RisingEdge(dut.clk)
        await _settle(dut)
        if int(dut.dma_ack.value) == 1:
            break
    else:
        raise AssertionError("dma_ack 가 뜨지 않았다")

    assert int(dut.access_granted.value) == 1
    expect_mask = hiu_masked_phys(phys, FIXED_KEY, FIXED_NONCE)
    assert int(dut.masked_phys_addr.value) == expect_mask, \
        "DMA 시점의 마스크가 golden 과 다르다"
