# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""HIU 테스트 — spec §29.13 / §30.10 test_plan (D4 / D6 / D7 / D8 착지).

§30 (D8-A/B) 에서 추가된 것 — 아래 7절
--------------------------------------
§29 의 이 파일은 마스크를 **golden 정확값**과 비교하게 만들었고, 그것이
D8-0 (`initial_state` 경유) 을 잡았다. 그러나 정확값 비교 하나로는
**부분 수리**를 잡지 못한다: 마스크 2워드만 보면 라운드 수가 절반이거나
nonce 워드 배치가 어긋난 상태에서도 "어떤 정확값" 은 나온다 (그 정확값이
계약과 다를 뿐이고, 계약을 잘못 갱신하면 조용히 통과한다).

7절은 그 구멍을 셋으로 닫는다:

  * **벡터 전량 소비** — `include/generated/xchacha_vectors.hex` 80 라인의
    `SUBKEY` 256b · `BLOCK` 16워드 · `MASK` 64b 를 전부 대조한다. 1단
    (HChaCha20) 과 2단 (ChaCha20) 중 어디가 틀렸는지가 분리 진단된다.
  * **가족별 회귀 검출기** — `nonce_tail` 8쌍 (D8-A), `key_word` 8쌍
    (D8-B 궤도 분해).
  * **확산 실증** — 폐기 RTL 의 4그룹 궤도 분해가 **사라졌음**을 TB 에서
    기계로 판정한다 (`test_no_orbit_decomposition` / `test_avalanche_*`).
    산문이 아니라 실측이며, 궤도 4개를 상수로 적어 두고 "변한 워드 집합이
    어떤 궤도에도 포함되지 않음" 을 assert 한다.

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
import random
import re
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, "scripts"))

# golden-before-RTL (§29.8 / §30.6) — 마스크·subkey·블록의 정확값은 전부
# 여기서 온다. RTL 을 보고 기대값을 쓰는 일은 없다.
from golden_xchacha import (  # noqa: E402
    FIXED_KEY, FIXED_NONCE, hiu_block_words, hiu_mask64, hiu_masked_phys,
    hiu_subkey_words,
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
S_CHACHA_H_INIT, S_CHACHA_H_MASK, S_CHACHA_INIT = 9, 10, 11
S_CHACHA_MASK, S_CHACHA_FINAL = 12, 13
S_TLB_UPDATE, S_TLB_READ = 14, 15

# tlb_fault_code 인코딩 (spec §29.6 표)
F_NONE, F_INDEX_MISMATCH, F_PHYS_MISALIGNED = 0, 1, 2
F_BUSY, F_PARTITION_RANGE = 3, 4

MASK32 = 0xFFFF_FFFF
MASK64 = hiu_mask64(FIXED_KEY, FIXED_NONCE)

# XChaCha20 라운드 수 (HIU.v 파라미터와 같은 값). 형태 (A) 에서 이 값은
# **cycle 수이자 라운드 수**다 — 1 cycle = 1 라운드 (§30.7).
CHACHA_ROUNDS = 20

# 폐기 RTL 의 4그룹 궤도 (§30.4 (a) 실측). `test_no_orbit_decomposition`
# 이 "변한 워드 집합이 이 중 어느 하나에도 포함되지 않음" 을 assert 하는
# 데 쓴다 — 방어 대상을 이름으로 적어 둔다.
LEGACY_ORBITS = ([0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14])

_SETTLE_NS = 1  # NBA 정착용 (clk 주기 10 ns)


# ---------------------------------------------------------------------------
# golden 벡터 파일 (§30.6 / xchacha_vec_contract.md §1)
# ---------------------------------------------------------------------------
VEC_PATH = os.path.join(_REPO, "include", "generated", "xchacha_vectors.hex")
VEC_FIELDS = (("META", 32), ("KEY", 256), ("NONCE", 192), ("PHYS", 64),
              ("SUBKEY", 256), ("BLOCK", 512), ("MASK", 64), ("MASKED", 64))
VEC_BITS = sum(w for _, w in VEC_FIELDS)      # 1440
VEC_HEX = VEC_BITS // 4                        # 360

FAM_PINNED, FAM_RAND, FAM_EDGE, FAM_NONCE_TAIL, FAM_KEY_WORD = 0, 1, 2, 3, 4
FAM_NAME = {FAM_PINNED: "pinned", FAM_RAND: "rand", FAM_EDGE: "edge",
            FAM_NONCE_TAIL: "nonce_tail", FAM_KEY_WORD: "key_word"}


def load_vectors():
    """`xchacha_vectors.hex` 를 필드로 분해한다 (RTL 에는 벡터를 넣지 않는다).

    §30.10 "벡터 소비 형태": `$readmemh` 형식이지만 여기서는 **cocotb 가
    파일을 파싱해 포트를 구동**한다. RTL 에 벡터를 읽는 구조물을 넣으면
    테스트 전용 데이터가 실리콘에 들어간다 (§28.4 항 7 금지).
    """
    vecs = []
    with open(VEC_PATH, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh):
            ln = raw.strip()
            if not ln or ln.startswith("//"):
                continue
            assert len(ln) == VEC_HEX, (
                f"{VEC_PATH}:{lineno + 1} 라인 길이 {len(ln)} != {VEC_HEX} — "
                "벡터 계약이 어긋났다 (golden 재생성 필요)")
            v = int(ln, 16)
            f = {}
            for name, width in reversed(VEC_FIELDS):
                f[name] = v & ((1 << width) - 1)
                v >>= width
            f["index"] = len(vecs)
            f["family"] = (f["META"] >> 24) & 0xFF
            f["serial"] = (f["META"] >> 8) & 0xFFFF
            f["flags"] = f["META"] & 0xFF
            f["BLOCK_W"] = [(f["BLOCK"] >> (32 * j)) & MASK32
                            for j in range(16)]
            vecs.append(f)
    assert len(vecs) == 80, \
        f"벡터 라인 수 {len(vecs)} != 80 — 벡터 계약이 어긋났다"
    return vecs


VECTORS = load_vectors()


def vectors_of(family):
    return [v for v in VECTORS if v["family"] == family]


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
# XChaCha20 관측 하네스 (§30.10 test_plan 2-6)
# ---------------------------------------------------------------------------

# **의도적으로 아무도 채우지 않는 주소.** `reset_dut` 직후 `tlb_valid` /
# `shadow_valid` 가 전부 0 이므로 이 주소는 반드시 miss 하고, miss 경로는
# `phys_addr = 0` 으로 **구동**되므로 (§29.6 부수 규범)
# `masked_phys_addr == mask ^ 0 == mask` 다. 즉 마스크 64비트를 **가공 없이
# 그대로** 관측할 수 있다 — TLB 를 채워 phys 를 XOR 로 벗겨내는 것보다
# 오차 경로가 적다.
PROBE_VIRT = 0x0000_0000_ABCD_E000


async def chacha_probe(dut, key, nonce, virt=PROBE_VIRT):
    """key/nonce 를 구동해 변환 1회를 돌리고 XChaCha20 내부를 관측한다.

    반환 dict:
      * `mask`   — `masked_phys_addr` (miss 경로이므로 마스크 그 자체)
      * `subkey` — `CHACHA_INIT` 시점의 `subkey` 256비트 (1단 산출물)
      * `block`  — `CHACHA_FINAL` 시점 `chacha_state[i]+initial_state[i]`
                   16워드 (2단 산출물 전량)
      * `cycles` — dma_req 샘플 edge 이후 `GRANT_ACCESS` 까지의 edge 수
      * `hist`   — FSM 상태별 cycle 수 (latency 분해 기록용)

    전부 **읽기**다 (§28.4 항 7 (a) — 관측은 무제한 허용). 계층 강제 기입은
    없다.
    """
    dut.chacha_key.value = key
    dut.chacha_nonce.value = nonce
    dut.partition_id.value = 0
    dut.virt_addr.value = virt
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0

    out = {"subkey": None, "block": None, "hist": {}}
    for n in range(1, 400):
        await RisingEdge(dut.clk)
        await _settle(dut)
        st = int(dut.state.value)
        out["hist"][st] = out["hist"].get(st, 0) + 1
        if st == S_CHACHA_INIT:
            # 이 edge 에서 `subkey <= chacha_state[...]` 가 이미 반영됐다.
            out["subkey"] = int(dut.subkey.value)
        elif st == S_CHACHA_FINAL:
            out["block"] = [
                (int(dut.chacha_state[i].value)
                 + int(dut.initial_state[i].value)) & MASK32
                for i in range(16)]
        elif st == S_GRANT_ACCESS:
            out["granted"] = int(dut.access_granted.value)
            out["phys"] = int(dut.phys_addr.value)
            out["mask"] = int(dut.masked_phys_addr.value)
            out["cycles"] = n
            await RisingEdge(dut.clk)     # GRANT_ACCESS 소비 → IDLE
            await _settle(dut)
            assert out["phys"] == 0, (
                "probe 주소가 miss 하지 않았다 — 마스크 관측 전제가 깨졌다 "
                f"(phys=0x{out['phys']:016x})")
            assert out["subkey"] is not None and out["block"] is not None, \
                "CHACHA_INIT / CHACHA_FINAL 을 관측하지 못했다"
            return out
    raise AssertionError("변환 시퀀스가 GRANT_ACCESS 에 도달하지 못했다")


def _diff_words(a, b):
    """두 16워드 블록에서 **다른** 워드의 인덱스 집합."""
    return {i for i in range(16) if a[i] != b[i]}


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


# ---------------------------------------------------------------------------
# 7. §30 — 표준 XChaCha20 준거 (D8-A nonce 배치 / D8-B 라운드 구조)
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_xchacha_vectors_bit_exact(dut):
    """§30.10 test_plan 2-5 — 벡터 80 라인 전량 bit-exact.

    **마스크 2워드만 보는 것으로는 부분 수리를 잡을 수 없다.** 그래서 세
    관측면을 전부 건다:

      * `SUBKEY` 256b — 1단 (HChaCha20) 이 규범대로 유도됐는가.
      * `BLOCK` 16워드 — 2단 (ChaCha20) 이 규범대로 돌았는가. **라운드 수가
        절반인 오류 (§30.7 부분 편집 함정 1) 를 잡는 유일한 축**이다.
        마스크는 워드 0/1 만 쓰므로 나머지 14워드는 여기서만 보인다.
      * `MASK` 64b — 소비되는 값 그 자체.

    셋을 분리해 assert 하므로 실패 시 **어느 단이 틀렸는지가 즉시 나온다.**
    """
    await reset_dut(dut)

    bad = []
    for v in VECTORS:
        got = await chacha_probe(dut, v["KEY"], v["NONCE"])
        sk_want = 0
        for j, w in enumerate(hiu_subkey_words(v["KEY"], v["NONCE"])):
            sk_want |= w << (32 * j)
        # golden 모듈과 벡터 파일이 어긋나면 그것부터 잡는다 (둘 다 golden
        # 산출물이므로 어긋날 수 없어야 한다).
        assert sk_want == v["SUBKEY"], \
            f"line {v['index']}: 벡터 SUBKEY 가 golden 모듈과 다르다"
        assert hiu_block_words(v["KEY"], v["NONCE"]) == v["BLOCK_W"], \
            f"line {v['index']}: 벡터 BLOCK 이 golden 모듈과 다르다"
        assert hiu_mask64(v["KEY"], v["NONCE"]) == v["MASK"], \
            f"line {v['index']}: 벡터 MASK 가 golden 모듈과 다르다"

        if got["subkey"] != v["SUBKEY"]:
            bad.append(
                f"line {v['index']} ({FAM_NAME[v['family']]}): SUBKEY "
                f"0x{got['subkey']:064x} != 0x{v['SUBKEY']:064x} "
                "— 1단 HChaCha20 이 규범과 다르다")
        if got["block"] != v["BLOCK_W"]:
            diff = [i for i in range(16) if got["block"][i] != v["BLOCK_W"][i]]
            bad.append(
                f"line {v['index']} ({FAM_NAME[v['family']]}): BLOCK 워드 "
                f"{diff} 불일치 — 2단 ChaCha20 이 규범과 다르다 "
                f"(got[{diff[0]}]=0x{got['block'][diff[0]]:08x} "
                f"want=0x{v['BLOCK_W'][diff[0]]:08x})")
        if got["mask"] != v["MASK"]:
            bad.append(
                f"line {v['index']} ({FAM_NAME[v['family']]}): MASK "
                f"0x{got['mask']:016x} != 0x{v['MASK']:016x}")

    assert not bad, (
        f"XChaCha20 값 계약 (§30.6) 불이행 {len(bad)}건:\n  "
        + "\n  ".join(bad[:12]))
    dut._log.info("xchacha 벡터 %d 라인 bit-exact (SUBKEY+BLOCK16+MASK)",
                  len(VECTORS))


@cocotb.test()
async def test_vector_nonce_tail_pairs(dut):
    """§30.10 test_plan 2 — `nonce_tail` 8쌍: D8-A 회귀의 직접 검출기.

    폐기 RTL 은 `[13]=nonce[16:20], [14]=nonce[20:24], [15]=0` 배치와 궤도
    분해가 겹쳐 **nonce 바이트 16-23 = 64비트가 완전히 죽어 있었다** —
    이 쌍의 두 마스크가 **같았다.** 표준에서는 반드시 다르다.

    `D8-A 만 수리` 라는 부분 수리도 여기서 죽는다: 라운드 구조를 그대로
    두면 nonce tail 64비트 중 32비트가 여전히 마스크에 닿지 않는다
    (§30.3 통제 실험).
    """
    await reset_dut(dut)

    vs = vectors_of(FAM_NONCE_TAIL)
    assert len(vs) == 16, f"nonce_tail 가족 라인 수 {len(vs)} != 16"

    for k in range(0, 16, 2):
        a, b = vs[k], vs[k + 1]
        assert a["flags"] == 0x01 and b["flags"] == 0x02, \
            "쌍 flag 가 계약과 다르다 (앞=0x01, 뒤=0x02)"
        assert a["KEY"] == b["KEY"], "nonce_tail 쌍의 key 가 다르다"
        delta = a["NONCE"] ^ b["NONCE"]
        assert delta != 0 and (delta >> 128) != 0 and (delta & ((1 << 128) - 1)) == 0, \
            ("nonce_tail 쌍의 차이가 바이트 16-23 밖에 있다 — 이 가족의 "
             "검출력 근거가 무너졌다")

        ma = (await chacha_probe(dut, a["KEY"], a["NONCE"]))["mask"]
        mb = (await chacha_probe(dut, b["KEY"], b["NONCE"]))["mask"]
        assert ma == a["MASK"] and mb == b["MASK"], \
            f"nonce_tail 쌍 {k // 2}: 마스크가 벡터와 다르다"
        assert ma != mb, (
            f"nonce_tail 쌍 {k // 2}: nonce 바이트 16-23 만 다른 두 입력이 "
            f"**같은 마스크** 0x{ma:016x} 를 냈다 — 그 64비트가 죽어 있다 "
            "(D8-A 회귀, §30.6 회귀 검출기 표)")


@cocotb.test()
async def test_vector_key_word_pairs(dut):
    """§30.10 test_plan 3 — `key_word` 8쌍: D8-B 궤도 분해의 직접 검출기.

    폐기 RTL 은 상태가 4그룹으로 분해돼 마스크 하위 32b 가 key 워드
    {0,2,5,7} 만, 상위 32b 가 {1,3,4,6} 만 보았다 — **서로소인 128비트
    반쪽 2개**였다. 그래서 key 워드 하나의 1비트를 뒤집으면 마스크의
    **한쪽 32비트만** 움직였다. 표준에서는 양쪽이 모두 움직인다.
    """
    await reset_dut(dut)

    vs = vectors_of(FAM_KEY_WORD)
    assert len(vs) == 16, f"key_word 가족 라인 수 {len(vs)} != 16"

    for k in range(0, 16, 2):
        a, b = vs[k], vs[k + 1]
        assert a["NONCE"] == b["NONCE"], "key_word 쌍의 nonce 가 다르다"
        delta = a["KEY"] ^ b["KEY"]
        assert bin(delta).count("1") == 1, \
            "key_word 쌍의 차이가 1비트가 아니다 — 검출력 근거가 무너졌다"
        word = (delta.bit_length() - 1) // 32

        ma = (await chacha_probe(dut, a["KEY"], a["NONCE"]))["mask"]
        mb = (await chacha_probe(dut, b["KEY"], b["NONCE"]))["mask"]
        assert ma == a["MASK"] and mb == b["MASK"], \
            f"key_word 쌍 w={word}: 마스크가 벡터와 다르다"
        lo_moved = (ma & MASK32) != (mb & MASK32)
        hi_moved = (ma >> 32) != (mb >> 32)
        assert lo_moved and hi_moved, (
            f"key_word 쌍 w={word}: key 1비트 변화에 마스크의 "
            f"{'상위' if lo_moved else '하위'} 32비트가 움직이지 않았다 "
            f"(0x{ma:016x} → 0x{mb:016x}) — 궤도 분해 회귀 (D8-B, §30.4 (b))")


@cocotb.test()
async def test_no_orbit_decomposition(dut):
    """**task 4 / §30.4 (a) — 4그룹 궤도 분해가 사라졌음의 기계 판정.**

    폐기 RTL 에서 상태 16워드는 `LEGACY_ORBITS` 4개로 영구 분해됐고 10
    라운드 내내 그룹 간 혼합이 0 이었다. 따라서 **입력 워드 하나를 건드리면
    출력에서 변하는 워드는 그 워드가 속한 궤도 4개뿐**이었다.

    여기서는 2단 초기상태의 워드 **하나만** 건드리는 자극을 쓴다: nonce
    바이트 16-19 는 `c_init_w[14]` 로만, 20-23 은 `c_init_w[15]` 로만
    들어가므로 (D8-A 수리 후 배치) 그 안의 1비트 flip 은 2단 입력 16워드
    중 정확히 1워드만 바꾼다. 그 상태에서 `BLOCK` 16워드를 관측해

      (i) **16워드 전부가 변하고**,
      (ii) 변한 집합이 `LEGACY_ORBITS` 어느 것에도 포함되지 않음

    을 assert 한다. (ii) 가 궤도 분해의 부재를 이름으로 지목하는 축이다.
    """
    await reset_dut(dut)

    base = await chacha_probe(dut, FIXED_KEY, FIXED_NONCE)
    assert base["mask"] == MASK64, "기준 마스크가 golden 과 다르다"

    rnd = random.Random(0x30_0001)
    checked = 0
    for bit in [128, 159, 160, 191] + [rnd.randrange(128, 192) for _ in range(4)]:
        nonce = FIXED_NONCE ^ (1 << bit)
        got = await chacha_probe(dut, FIXED_KEY, nonce)
        assert got["block"] == hiu_block_words(FIXED_KEY, nonce), \
            f"nonce bit {bit}: BLOCK 이 golden 과 다르다"

        moved = _diff_words(base["block"], got["block"])
        assert len(moved) == 16, (
            f"nonce bit {bit} (2단 입력 워드 1개) 를 뒤집었는데 BLOCK 16워드 중 "
            f"{len(moved)}개만 변했다: {sorted(moved)} — 확산이 전 상태에 "
            "미치지 않는다")
        for orbit in LEGACY_ORBITS:
            assert not moved.issubset(set(orbit)), (
                f"nonce bit {bit}: 변한 워드 집합 {sorted(moved)} 이 폐기 "
                f"궤도 {orbit} 안에 갇혔다 — 4그룹 분해 회귀 (D8-B)")
        assert (base["mask"] & MASK32) != (got["mask"] & MASK32) and \
               (base["mask"] >> 32) != (got["mask"] >> 32), \
            f"nonce bit {bit}: 마스크 32비트 반쪽 하나가 움직이지 않았다"
        checked += 1

    assert checked == 8
    dut._log.info(
        "궤도 분해 부재 확인: 2단 입력 1워드 flip %d회 전부 BLOCK 16/16 워드 "
        "변화 (폐기 RTL 은 4/16)", checked)


@cocotb.test()
async def test_avalanche_key_and_nonce(dut):
    """**task 4 — avalanche 실측.** 1비트 입력 변화 → 마스크 64비트 확산.

    §30.4 (c) 의 폐기 실측: key flip 16.04/64 (25.1%) · nonce flip
    10.42/64 (16.3%) · **변화 0비트인 nonce flip 34.7%**. 표준은 양쪽 모두
    ≈ 31.95/64 (49.9%) 이고 zero-change 는 0 이다.

    여기서는 절대 임계를 넉넉히 잡되 (표본 24+24 의 통계 요동 고려)
    **zero-change 는 단 1건도 허용하지 않는다** — 그것이 폐기 형태와
    표준을 가르는 정성적 축이다.
    """
    await reset_dut(dut)

    base = (await chacha_probe(dut, FIXED_KEY, FIXED_NONCE))["mask"]
    rnd = random.Random(0x30_0002)

    results = {}
    for label, nbits, trials in (("key", 256, 24), ("nonce", 192, 24)):
        dist = []
        for _ in range(trials):
            bit = rnd.randrange(nbits)
            if label == "key":
                key, nonce = FIXED_KEY ^ (1 << bit), FIXED_NONCE
            else:
                key, nonce = FIXED_KEY, FIXED_NONCE ^ (1 << bit)
            got = await chacha_probe(dut, key, nonce)
            assert got["mask"] == hiu_mask64(key, nonce), \
                f"{label} bit {bit}: 마스크가 golden 과 다르다"
            hd = bin(got["mask"] ^ base).count("1")
            assert hd > 0, (
                f"{label} 비트 {bit} 를 뒤집었는데 마스크가 **전혀** 변하지 "
                "않았다 — 그 입력 비트가 죽어 있다 (§30.4 (c) 폐기 형태의 "
                "nonce zero-change 34.7% 가 정확히 이 증상이다)")
            assert 12 <= hd <= 52, (
                f"{label} 비트 {bit}: 마스크 변화 {hd}/64 비트 — 확산이 "
                "표준 범위를 크게 벗어난다")
            dist.append(hd)
        mean = sum(dist) / len(dist)
        results[label] = mean
        assert 25.0 <= mean <= 39.0, (
            f"{label} avalanche 평균 {mean:.2f}/64 ({100 * mean / 64:.1f}%) "
            "— 표준은 ≈ 31.95/64 (49.9%), 폐기 형태는 16.04 / 10.42 였다 "
            "(§30.4 (c))")

    dut._log.info(
        "avalanche: key %.2f/64 (%.1f%%), nonce %.2f/64 (%.1f%%) "
        "— 폐기 형태 실측은 16.04 / 10.42 였다",
        results["key"], 100 * results["key"] / 64,
        results["nonce"], 100 * results["nonce"] / 64)


@cocotb.test()
async def test_chacha_round_count_is_twenty(dut):
    """§30.7 부분 편집 함정 1 — 라운드 수가 실제로 20 인가를 **cycle 로** 센다.

    값 축은 `BLOCK` 16워드가 이미 잡는다. 여기서는 **구조 축**을 따로
    건다: `CHACHA_H_MASK` / `CHACHA_MASK` 에 머무는 cycle 수가 각각
    `CHACHA_ROUNDS + 1` (20 라운드 + 판정 1) 이어야 한다.

    형태 (A) 는 **1 cycle = 1 라운드** 이므로 이 수가 곧 라운드 수다.
    `< CHACHA_ROUNDS / 2` 를 되돌리면 여기서 11 이 나와 즉시 FAIL 한다.
    """
    await reset_dut(dut)

    got = await chacha_probe(dut, FIXED_KEY, FIXED_NONCE)
    hist = got["hist"]

    assert hist.get(S_CHACHA_H_MASK) == CHACHA_ROUNDS + 1, (
        f"HChaCha20 라운드 cycle {hist.get(S_CHACHA_H_MASK)} != "
        f"{CHACHA_ROUNDS + 1} — 1 cycle = 1 라운드 계약 (§30.7) 위반. "
        "11 이면 `< CHACHA_ROUNDS / 2` 가 남아 double round 5회다")
    assert hist.get(S_CHACHA_MASK) == CHACHA_ROUNDS + 1, (
        f"ChaCha20 라운드 cycle {hist.get(S_CHACHA_MASK)} != "
        f"{CHACHA_ROUNDS + 1} — §30.7 위반")
    assert hist.get(S_CHACHA_H_INIT) == 1 and hist.get(S_CHACHA_INIT) == 1
    assert hist.get(S_CHACHA_FINAL) == 1
    assert hist.get(S_DUMMY_DELAY) == 8, "상수시간 dummy 구간이 바뀌었다"


@cocotb.test()
async def test_translate_latency_record(dut):
    """§30.10 test_plan 6 — 변환 latency **절대치 실측 기록**.

    **절대치를 assert 하지 않는다** (§29.5 / §29.13 항 4 — 계약은 경로 간
    동일성이다). 이 로그가 S2B-D 의 Y4 `docs/hiu_abi.md` §2.1 개정 입력이며,
    그 문서는 오늘 `1 + 8 + 10 + 10 + 1 + 1 + 1 ≈ 32 cycle` 로 **ChaCha
    라운드 cycle 수 두 개를 직접 pin** 하고 있다 (§30.8 소비자 표).
    산술 재계산이 아니라 여기 찍히는 실측값을 옮겨 적어야 한다.
    """
    await reset_dut(dut)

    got = await chacha_probe(dut, FIXED_KEY, FIXED_NONCE)
    names = {S_TRANSLATE: "TRANSLATE", S_TLB_READ: "TLB_READ",
             S_DUMMY_DELAY: "DUMMY_DELAY", S_CHACHA_H_INIT: "CHACHA_H_INIT",
             S_CHACHA_H_MASK: "CHACHA_H_MASK", S_CHACHA_INIT: "CHACHA_INIT",
             S_CHACHA_MASK: "CHACHA_MASK", S_CHACHA_FINAL: "CHACHA_FINAL",
             S_DMA_EXEC: "DMA_EXEC", S_GRANT_ACCESS: "GRANT_ACCESS"}
    parts = " + ".join(
        f"{names.get(st, st)}:{n}" for st, n in sorted(got["hist"].items()))
    dut._log.info("변환 latency 실측: %d cycle  (%s)", got["cycles"], parts)
