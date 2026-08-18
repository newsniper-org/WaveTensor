# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Tensor_ALU 값 검증 테스트베드 (v1.9.1 §31.9 / §28.4 항 8 이행).

**이 모듈의 지위: `superseded duplicate` (spec §31.6).** 세 opcode
0x30/0x31/0x32 는 `isa/wt64v1_isa.json` 에 살아 있고 하드웨어 **정본은
`PE_Core`** 다 (`test_isa_decoder.py::test_matmul_2x2` 가 [[19,22],[43,50]]
로 값 검증 통과). `TENSOR_ALU.v` 는 어떤 `.v` 도 인스턴스화하지 않고
`synth/` read_verilog 목록에도 없다 — 즉 GATE S1 전 축에 0 기여다.

---------------------------------------------------------------------------
구 테스트가 무엇을 은폐했는가 (spec §31.9 은폐 3사례 중 O1)
---------------------------------------------------------------------------
구 `test_tensor_alu.py` 는 `alu_valid == 1` **하나만** assert 하고 결과 값을
전혀 보지 않았다. 그래서 1/1 PASS 가 "MATMUL(0x30) 완전 무동작" 을 initial
commit 이후 전 기간 덮고 있었다. 부수 결함 2건도 같이 드러났다:

* **O1b** — `alu_valid` 는 result-valid 가 아니다. `TENSOR_ALU.v:26` 이
  무조건 `alu_valid <= 1` 을 놓으므로 사실상 "reset 중 아님" 자유주행
  플래그이며, 실제 파이프라인 latency 는 **3 사이클**이다.
* **O1c** — 구 테스트는 256-bit 리터럴을 1,024-bit 포트에 주고 있었다
  (파라미터 미override). 즉 의도한 행렬을 넣은 적이 **없다**. 본 파일은
  `Makefile` 의 `-GADDR_WIDTH=16 -GDIM_SIZE=2` 와 짝을 이뤄 포트 실폭
  64 bit 에 정확히 패킹한다.

---------------------------------------------------------------------------
은폐 재발 탐지 기전 (§28.4 항 8(e))
---------------------------------------------------------------------------
MATMUL 케이스는 golden 을 assert 하면서 `expect_fail=True` 로 표기한다.
이 형식은 **양방향 래칫**이다:

  * 누군가 `TENSOR_ALU.v` 의 MATMUL 을 고치면 → unexpected pass → **FAIL**
    → spec §31.7 갱신을 강제한다.
  * 누군가 이 테스트의 assert 를 다시 약화시키면(예: `alu_valid == 1` 만
    보게 되돌리면) → 그 테스트는 통과해 버리므로 → unexpected pass →
    **FAIL**. 즉 **축퇴를 다시 은폐하는 순간 CI 가 운다.**

`expect_fail` 없이 RED 를 방치하는 것도, 축퇴 동작을 정답으로 못박는 것도
둘 다 §28.4 항 8(e) 가 금지한다. 여기서는 **정답(golden)** 을 적고
실패를 기대한다 — 결함은 기계 판독 가능하게 기록되고 CI 는 마비되지 않는다.

---------------------------------------------------------------------------
검사하지 않는 자극 축 (§28.4 항 8(c) 명시 기록)
---------------------------------------------------------------------------
warm reset(동작 중 rst), back-pressure, opcode 연속 전환 중의 파이프라인
겹침, D≠2 / W≠16 형상. 이 모듈은 superseded 이므로 자극 공간을 넓히지
않고 **공백으로 기록**한다.
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Makefile 의 -GADDR_WIDTH / -GDIM_SIZE 와 반드시 일치해야 한다 (§28.4 항 8(d)).
W = 16          # ADDR_WIDTH — 원소 폭
D = 2           # DIM_SIZE   — 행렬 차수
MASK = (1 << W) - 1

# 표준 대조 벡터 (spec §31.7 / §28.8 이 쓴 것과 동일).
A = [[1, 2], [3, 4]]
B = [[5, 6], [7, 8]]

# 파이프라인 latency 계약: matrix_a/b -> a/b reg -> res -> result_matrix.
LATENCY = 3


def pack(m):
    """행렬을 `matrix_a[(i*D + j)*W +: W]` 레이아웃으로 패킹한다."""
    v = 0
    for i in range(D):
        for j in range(D):
            v |= (m[i][j] & MASK) << ((i * D + j) * W)
    return v


def unpack(v):
    return [[(v >> ((i * D + j) * W)) & MASK for j in range(D)]
            for i in range(D)]


def ref_matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(D)) & MASK
             for j in range(D)] for i in range(D)]


def ref_add(a, b):
    return [[(a[i][j] + b[i][j]) & MASK for j in range(D)] for i in range(D)]


def ref_mul(a, b):
    return [[(a[i][j] * b[i][j]) & MASK for j in range(D)] for i in range(D)]


def resolved(sig):
    """4-state X 를 만나도 `ValueError` 대신 명확한 AssertionError 가 나게 한다.

    §31.11 추가 규범: expect_fail 케이스는 **깨끗한 AssertionError** 로
    실패해야 한다. `int()` 를 바로 걸면 X 에서 ValueError 가 나 실패 사유가
    흐려진다.
    """
    binstr = sig.value.binstr
    assert set(binstr) <= set("01"), (
        f"신호가 4-state 미정의 값을 가진다 (binstr={binstr}) — "
        "정의된 결과가 아니다"
    )
    return int(binstr, 2)


ZERO = [[0, 0], [0, 0]]


async def _flush(dut):
    """파이프라인을 결정적 0 상태로 비운다.

    **왜 필요한가 (그 자체가 결함의 증상이다):** 이 모듈은 `rst` 로
    `alu_valid` **하나만** 리셋한다 — `a`/`b`/`res`/`result_matrix` 는
    reset-free 다 (spec §28.8 O2 / §31.8 이 센 49건이 바로 이 군이다).
    cocotb 는 한 시뮬레이션 안에서 테스트를 연달아 돌리므로, 앞 테스트의
    행렬이 뒤 테스트로 새어 들어와 값·latency 측정을 오염시킨다. 실제로
    본 파일을 쓰는 동안 그 오염이 latency 측정을 3 → 2 로 보이게 만들었다.
    따라서 모든 케이스는 **명시적 flush 로 시작한다.**
    """
    dut.rst.value = 0
    dut.opcode.value = 0x31
    dut.matrix_a.value = pack(ZERO)
    dut.matrix_b.value = pack(ZERO)
    for _ in range(LATENCY + 2):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert unpack(resolved(dut.result_matrix)) == ZERO, "flush 실패"


async def _boot(dut, opcode, a=None, b=None):
    """flush → rst → 자극 인가 → LATENCY 사이클."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.opcode.value = 0x31
    dut.matrix_a.value = pack(ZERO)
    dut.matrix_b.value = pack(ZERO)
    await Timer(25, units="ns")
    await _flush(dut)
    dut.opcode.value = opcode
    dut.matrix_a.value = pack(a if a is not None else A)
    dut.matrix_b.value = pack(b if b is not None else B)
    for _ in range(LATENCY):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


# ---------------------------------------------------------------------------
# 케이스 1 — MATMUL(0x30) golden. 알려진 결함이므로 expect_fail.
# ---------------------------------------------------------------------------
@cocotb.test(expect_fail=True)
async def test_matmul_golden_known_broken(dut):
    """§31.7 O1 — MATMUL(0x30) 무동작. **수리 기각** 상태의 loud 기록.

    `TENSOR_ALU.v:38-40` 의 inner k-loop 이 한 시간스텝 안에서 같은
    `res[i][j]` 에 비차단 대입을 D회 하므로 마지막 k 만 살아남고, 그 RHS 가
    `res[i][j]` **구값**을 읽어 `res += a[i][D-1]*b[D-1][j]` 무한 누산기로
    축퇴한다. `res[i][j] <= 0` 초기화도 같은 규칙으로 덮여 영구 무효다.
    4-state 시뮬/실리콘에서는 `res` 가 미리셋이므로 **영구 X** 다 (§31.7 정정).

    수리를 기각한 사유는 spec §31.7 — 정답 구현은 D²=16 mul 축퇴를
    D³=64 mul 로 되돌려 `$mul` 31→76 (2.45×), DSP48 310→~760 이 되며,
    이는 `claude.md:383` 이 진단하고 프로젝트가 **이미 기각한** 자원
    폭증이다. 정본(`PE_Core.matmul_func`)이 이미 옳으므로 수리해도
    기능이 늘지 않는다.

    **이 테스트가 PASS 하면 그것은 결함이 고쳐졌다는 뜻이고, spec §31.7 의
    "수리 기각" 판정이 낡았다는 뜻이다 — 그때 spec 을 갱신하라.**
    """
    await _boot(dut, 0x30)
    got = unpack(resolved(dut.result_matrix))
    assert got == ref_matmul(A, B), (
        f"MATMUL golden 불일치: got={got} expected={ref_matmul(A, B)}"
    )


# ---------------------------------------------------------------------------
# 케이스 2 — TADD(0x31) golden.
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tadd_golden(dut):
    """0x31 element-wise add — golden [[6,8],[10,12]] 전 원소 assert."""
    await _boot(dut, 0x31)
    got = unpack(resolved(dut.result_matrix))
    exp = ref_add(A, B)
    assert exp == [[6, 8], [10, 12]], "참조 구현 자체가 틀렸다"
    assert got == exp, f"TADD 불일치: got={got} expected={exp}"


# ---------------------------------------------------------------------------
# 케이스 3 — 0x32 golden. **현행 ISA 의 0x32 가 아니다.**
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_opcode_0x32_superseded_tensor_mul_golden(dut):
    """0x32 element-wise multiply — golden [[5,12],[21,32]].

    **의미론 경고 (spec §31.6):** 이 모듈의 0x32 는 `TENSOR_ALU.v:53` 주석
    그대로 **superseded TENSOR_MUL** 이며, **현행 ISA 의 0x32 = `EINSUM`
    (SUBSCRIPT-dispatched) 이 아니다.** 현행 ISA 에서 Hadamard 곱은 EINSUM
    의 서브시그니처(`einsum_hadamard`)로 흡수돼 opcode 직행 진입점이 없다.
    즉 이 테스트가 검증하는 것은 **현행 ISA 에 존재하지 않는 의미론**이고,
    그 사실이 이 모듈이 superseded 인 근거 중 하나다.
    """
    await _boot(dut, 0x32)
    got = unpack(resolved(dut.result_matrix))
    exp = ref_mul(A, B)
    assert exp == [[5, 12], [21, 32]], "참조 구현 자체가 틀렸다"
    assert got == exp, f"0x32 불일치: got={got} expected={exp}"


# ---------------------------------------------------------------------------
# 케이스 4 — default arm.
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_default_opcode_zeroes(dut):
    """미정의 opcode 는 `result_matrix <= 0` (default arm)."""
    await _boot(dut, 0x33)
    got = unpack(resolved(dut.result_matrix))
    assert got == [[0, 0], [0, 0]], f"default arm 불일치: got={got}"


# ---------------------------------------------------------------------------
# 케이스 5 — latency 계약.
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_latency_contract_three_cycles(dut):
    """rst 해제 후 **정확히 3 사이클** 뒤에 값이 안정한다 (§28.4 항 8(b)).

    3 사이클은 `matrix_a/b` → `a`/`b` reg → `res` → `result_matrix` 의 2단
    구조에서 나온다. 2 사이클 시점에는 아직 정답이 아니어야 하고, 3·4·5
    사이클에서는 같은 값이어야 한다 — 두 방향을 다 본다.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    await Timer(25, units="ns")
    await _flush(dut)
    dut.matrix_a.value = pack(A)
    dut.matrix_b.value = pack(B)

    exp = ref_add(A, B)
    seen = []
    for _ in range(5):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        seen.append(unpack(resolved(dut.result_matrix)))

    assert seen[1] != exp, (
        f"2 사이클에 이미 정답이 나왔다 — latency 계약이 3 이 아니다: {seen}"
    )
    assert seen[2] == exp, f"3 사이클에 정답이 아니다: {seen}"
    assert seen[3] == exp and seen[4] == exp, f"3 사이클 이후 불안정: {seen}"


# ---------------------------------------------------------------------------
# 케이스 6 — `alu_valid` 는 result-valid 가 아니다.
# ---------------------------------------------------------------------------
@cocotb.test(expect_fail=True)
async def test_alu_valid_is_not_result_valid(dut):
    """§31.7 O1b — `alu_valid == 1` 인 첫 사이클에 결과가 정의돼 있지 않다.

    `TENSOR_ALU.v:26` 이 else 분기 최상단에서 무조건 `alu_valid <= 1` 을
    놓으므로 이 비트는 "reset 중이 아님" 자유주행 플래그다. 자격 비트를
    result-valid 로 쓰는 테스트는 **그 비트가 실제로 result-valid 임**을
    별도 케이스로 실증해야 한다 (§28.4 항 8(b)) — 실증하면 이렇게 실패한다.

    **이 테스트가 PASS 하면 `alu_valid` 의 의미론이 바뀐 것이고, 그것은
    인터페이스 계약 변경이므로 spec 갱신 대상이다.**
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    await Timer(25, units="ns")
    await _flush(dut)
    # rst 를 다시 넣어 alu_valid 만 0 으로 내린다 — a/b/res 는 reset-free
    # 이므로 flush 가 남긴 0 상태를 그대로 유지한다.
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.alu_valid.value) == 0, "rst 가 alu_valid 를 내리지 못했다"
    dut.matrix_a.value = pack(A)
    dut.matrix_b.value = pack(B)
    dut.rst.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.alu_valid.value) == 1:
            break
    assert int(dut.alu_valid.value) == 1, "alu_valid 가 뜨지 않았다"
    got = unpack(resolved(dut.result_matrix))
    assert got == ref_add(A, B), (
        f"alu_valid=1 인 첫 사이클의 결과가 정답이 아니다: got={got} "
        f"expected={ref_add(A, B)} — alu_valid 는 result-valid 가 아니다"
    )


# ---------------------------------------------------------------------------
# 케이스 7/8 — 파이썬 참조와 bit-exact 랜덤 대조 (동작하는 두 opcode).
# ---------------------------------------------------------------------------
async def _random_cross_check(dut, opcode, ref):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    rng = random.Random(int(os.environ.get("WT_TALU_SEED", "20260818")))
    dut.opcode.value = opcode
    for _ in range(24):
        a = [[rng.randrange(1 << W) for _ in range(D)] for _ in range(D)]
        b = [[rng.randrange(1 << W) for _ in range(D)] for _ in range(D)]
        dut.rst.value = 1
        dut.matrix_a.value = pack(a)
        dut.matrix_b.value = pack(b)
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        dut.rst.value = 0
        for _ in range(LATENCY):
            await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = unpack(resolved(dut.result_matrix))
        exp = ref(a, b)
        assert got == exp, (
            f"opcode 0x{opcode:02x} 랜덤 대조 불일치: A={a} B={b} "
            f"got={got} expected={exp}"
        )


@cocotb.test()
async def test_tadd_random_bit_exact(dut):
    """0x31 — 파이썬 참조와 24 벡터 bit-exact 대조."""
    await _random_cross_check(dut, 0x31, ref_add)


@cocotb.test()
async def test_0x32_random_bit_exact(dut):
    """0x32 (superseded TENSOR_MUL) — 파이썬 참조와 24 벡터 bit-exact 대조."""
    await _random_cross_check(dut, 0x32, ref_mul)
