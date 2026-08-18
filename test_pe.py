# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""PE.v wrapper testbench.

Confirms that the thin PE wrapper exposes the underlying ISA_Decoder
behavior unchanged: ADD, EINSUM matmul kernel, error_flag and
lower_required all propagate from the inner decoder out to the PE
boundary. This guarantees Cluster.v can instantiate PE.v without losing
any decoder semantics.
"""

import os
import random
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, 'asm'))
from wavetensor_asm import assemble_one  # noqa: E402

from test_isa_decoder import (  # noqa: E402
    eh_port, eh_imm16, eh_subscript, eh_opref, axes,
    encode_instr, make_tag, pack16, F_HAS_OPB,
)


PORT_MASK = 0x01
PORT_OUT  = 0x00


def _std_tag(dim=0):
    return make_tag(port_context_id=0, dimension_sizes=dim)


async def _reset(dut):
    dut.rst.value = 1
    dut.in_valid.value = 0
    dut.in_b_valid.value = 0
    dut.in_instruction.value = 0
    dut.in_tag.value = 0
    dut.in_payload.value = 0
    dut.in_b_payload.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _fire(dut, instr, tag, payload_a=0, payload_b=0, payload_b_valid=0):
    dut.in_instruction.value = instr
    dut.in_tag.value = tag
    dut.in_payload.value = payload_a
    dut.in_b_payload.value = payload_b
    dut.in_b_valid.value = payload_b_valid
    dut.in_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_valid.value = 0
    # Poll for completion: chain walk + dispatch + optional multi-cycle pipe.
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.out_valid.value) == 1
                or int(dut.error_flag.value) == 1
                or int(dut.lower_required.value) == 1):
            break


@cocotb.test()
async def test_pe_add_passthrough(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "ADD .imm16 5\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=10)

    assert dut.out_valid.value == 1
    assert int(dut.out_payload.value) == 15
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0


@cocotb.test()
async def test_pe_einsum_matmul(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
    )
    await _fire(dut, instr, _std_tag(dim=0x05),
                payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.out_valid.value == 1
    assert int(dut.out_payload.value) == expected


@cocotb.test()
async def test_pe_lower_required_propagates(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # An unsupported subscript (all label-d, axes(4)) raises lower_required
    instr = encode_instr(
        0x32,
        eh_port(PORT_MASK, PORT_OUT),
        eh_subscript(axes(4), axes(4), axes(4)),
        eh_opref(),
        flags=F_HAS_OPB,
    )
    await _fire(dut, instr, _std_tag(),
                payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.lower_required.value == 1
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_pe_error_flag_propagates(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "DIV .imm16 0\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=42)
    assert dut.error_flag.value == 1
    assert dut.out_valid.value == 0


# =============================================================================
# v1.9.1 §31.3 (D10) — warm reset 회귀. §28.4 항 8(c) 이행.
#
# 스위트 전체에 **동작 중 rst (warm reset) 자극이 0건**이었다는 것이 §31 조사의
# 실측이다 (`_reset(dut)` 호출 전건이 `clock.start()` 직후 = cold reset 만).
# `PE_Core.v:1794-1807` 의 RTL 주석이 "mid-op rst" 를 설계 시나리오로 명시하는데
# 그 시나리오의 자극이 없었다 — 항 7 이 잡는 "잘못된 자극" 이 아니라 **"없는
# 자극"** 이다.
#
# 검사 계약: rst 해제 후 **dispatch 가 0건**인데 `out_valid` / `error_flag` /
# `lower_required` 중 어느 하나라도 뜨면 FAIL. 세 발현형을 모두 덮는다 —
# 유령 wave 토큰만 검사하면 reject-arm 발현형(error / lower)을 놓친다.
#
# 주입 시점은 스윕한다: `cr_dispatch_valid == 1` 인 창은 정확히 1 사이클이므로
# 고정 지연으로는 재현이 불안정하다. 디코드 체인 walk 전 구간에 걸쳐 rst 를
# 넣어 보고 **한 지점이라도** 유령이 나오면 FAIL 로 잡는다.
#
# 미검사 자극 축 (§28.4 항 8(c) 명시 기록): back-pressure (out_regs_free 를
# 낮춘 상태에서의 재시도), 동시 도착/충돌, HIU 경유 메모리 응답 왕복.
# =============================================================================

_WARM_SWEEP = 24      # rst 주입 지연 스윕 폭 (사이클)
_WARM_HOLD  = 3       # rst 유지 사이클
_WARM_WATCH = 24      # 해제 후 감시 사이클


async def _warm_reset_probe(dut, instr, tag, payload_a=0,
                            payload_b=0, payload_b_valid=0):
    """명령 1건을 발사하고 delay 사이클 뒤 warm reset 을 넣는다.

    rst 해제 후 in_valid 를 0 으로 묶은 채 _WARM_WATCH 사이클 동안 어떤
    출력 스트로브도 떠서는 안 된다. 뜨면 (사이클, 종류) 를 돌려준다.
    """
    ghosts = []
    for delay in range(1, _WARM_SWEEP):
        await _reset(dut)
        dut.in_instruction.value = instr
        dut.in_tag.value = tag
        dut.in_payload.value = payload_a
        dut.in_b_payload.value = payload_b
        dut.in_b_valid.value = payload_b_valid
        dut.in_valid.value = 1
        await RisingEdge(dut.clk)
        dut.in_valid.value = 0
        for _ in range(delay):
            await RisingEdge(dut.clk)
        # ---- warm reset (동작 중) ----
        dut.rst.value = 1
        dut.in_instruction.value = 0
        dut.in_tag.value = 0
        dut.in_payload.value = 0
        dut.in_b_payload.value = 0
        dut.in_b_valid.value = 0
        for _ in range(_WARM_HOLD):
            await RisingEdge(dut.clk)
        dut.rst.value = 0
        # ---- 해제 후 감시: dispatch 0건이므로 출력도 0건이어야 한다 ----
        for cyc in range(_WARM_WATCH):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.out_valid.value) == 1:
                ghosts.append((delay, cyc, "out_valid",
                               int(dut.out_payload.value)))
            if int(dut.error_flag.value) == 1:
                ghosts.append((delay, cyc, "error_flag", 0))
            if int(dut.lower_required.value) == 1:
                ghosts.append((delay, cyc, "lower_required", 0))
    return ghosts


@cocotb.test()
async def test_pe_warm_reset_no_ghost_token(dut):
    """§31.3 D10 — warm reset 후 유령 wave 토큰이 나오면 FAIL."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "ADD .imm16 5\n"
    )
    ghosts = await _warm_reset_probe(dut, instr, _std_tag(), payload_a=10)
    assert not ghosts, (
        "§31.3 D10 회귀 — warm reset 해제 후 dispatch 0건인데 출력 스트로브 "
        f"{len(ghosts)}건 관측: {ghosts[:8]}"
    )


@cocotb.test()
async def test_pe_warm_reset_no_ghost_reject(dut):
    """§31.3 D10 — reject arm 발현형(error_flag)까지 덮는다.

    MATMUL(0x30) 에 dim_sizes != 0x05 를 주면 `cr_hard_error` arm 을 탄다
    (`PE_Core.v` 0x30 케이스). 이 arm 은 자신의 자격 비트가 아니라
    `cr_dispatch_valid` 로만 게이트되므로 D10 의 error 발현형을 정확히
    재현한다 — div-by-zero 는 `div_b_zero_p2`(rst 분기에서 대입됨)를 타므로
    이 발현형을 **재현하지 못한다**.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr = encode_instr(
        0x30,
        eh_port(PORT_MASK, PORT_OUT),
        eh_opref(),
        flags=F_HAS_OPB,
    )
    ghosts = await _warm_reset_probe(dut, instr, _std_tag(dim=0x03),
                                     payload_a=0x1111, payload_b=0x2222,
                                     payload_b_valid=1)
    assert not ghosts, (
        "§31.3 D10 회귀 — warm reset 해제 후 유령 error_flag/토큰 "
        f"{len(ghosts)}건 관측: {ghosts[:8]}"
    )


@cocotb.test()
async def test_pe_warm_reset_no_ghost_lower(dut):
    """§31.3 D10 — lower_required 발현형까지 덮는다."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr = encode_instr(
        0x32,
        eh_port(PORT_MASK, PORT_OUT),
        eh_subscript(axes(4), axes(4), axes(4)),
        eh_opref(),
        flags=F_HAS_OPB,
    )
    ghosts = await _warm_reset_probe(dut, instr, _std_tag(),
                                     payload_a=0, payload_b=0,
                                     payload_b_valid=1)
    assert not ghosts, (
        "§31.3 D10 회귀 — warm reset 해제 후 유령 lower_required/토큰 "
        f"{len(ghosts)}건 관측: {ghosts[:8]}"
    )


# =============================================================================
# v1.9.1 §31.14 — 자격자-홀드 불변식 H1/H2 의 **런타임 감시**.
#
# 왜 이 테스트가 있는가 (적대 검증이 무엇을 뒤집었는가)
# ------------------------------------------------------
# §31.13.3 은 D6/D11 착지본과 기준본의 `output_payload` 차이를 "자격자가 양쪽
# 0 인 masked 사이클(SOFT)" 로 분류했다. **그 분류는 거짓이다.** `Cluster` 의
# NoC bank (OPREF.src_kind=1) 는 L-PE 슬롯의 저장소로 `PE_Core.output_payload`
# 를 그대로 재사용하고 `pe_out_valid` 게이트 없이 조합적으로 읽는다 —
# MU/DU 가 `mu_bank_reg`/`du_bank_reg` 라는 valid-게이트 레지스터를 따로 두는
# 것과 다르다. 따라서 `output_valid == 0` 인 사이클의 payload 변화는 masked 가
# 아니라 **다음 소비자의 B 피연산자를 바꾸는 관측 가능한 사건**이다
# (Cluster 경계 실증: spec §31.14.2).
#
# 계약을 주석으로만 두는 것이 §31.4 가 지적한 실패 양식 그 자체이므로,
# 여기서 기계적으로 감시한다:
#
#     H1 — `out_payload` 는 `out_valid` 가 1 인 사이클에만 바뀐다.
#     H2 — `mem_addr` 는 `memory_req` 가 1 인 사이클에만 바뀐다.
#
# (`PE.out_payload` / `PE.mem_addr` 는 `PE_Core` 의 동명 포트 직결이고,
#  `Cluster` 의 `pe_out_payload[k]` 도 같은 포트다 — 즉 여기서 보는 것이
#  뱅크가 보는 것과 같은 신호다.)
#
# rst 가 걸린 에지는 제외한다: reset arm 이 결정적 0 으로 초기화하는 것은
# 계약 위반이 아니다 (자격자도 같은 에지에 0 이 된다).
#
# 정적 짝: `scripts/lint_output_payload_hold.py` (make lint). 정적 lint 는
# "쓰기 site 의 형식" 을, 이 테스트는 "실제 파형" 을 본다 — 둘 다 필요하다.
# =============================================================================

_HOLD_OPCODES = (
    0x10, 0x11, 0x12, 0x13, 0x1C, 0x1D, 0x1F,   # 스칼라 ALU / MUL / DIV 계열
    0x04, 0x05,                                  # 메모리 (LD / ST — ST 는 D11')
    0x30, 0x31,                                  # 텐서
    0x6A,                                        # FRAG_INVAL ack (D11')
    0x63,                                        # 2-fragment emit (frag drain)
    0xFE,                                        # 미정의 (reject arm)
)


async def _hold_monitor(dut, cycles, rng):
    """랜덤 자극을 주며 H1/H2 를 매 사이클 검사한다. 위반을 모아 돌려준다."""
    violations = []
    prev_payload = None
    prev_addr = None
    for _ in range(cycles):
        # 자극: 매 사이클 새 명령을 던지거나 idle
        if rng.random() < 0.45:
            opc = rng.choice(_HOLD_OPCODES)
            if opc == 0x63:
                instr = encode_instr(opc, eh_port(PORT_MASK, PORT_OUT),
                                     eh_opref(), flags=F_HAS_OPB)
            elif opc in (0x04, 0x05):
                instr = encode_instr(opc, eh_port(PORT_MASK, PORT_OUT),
                                     eh_imm16(rng.randrange(1 << 12)))
            else:
                instr = encode_instr(opc, eh_port(PORT_MASK, PORT_OUT),
                                     eh_opref(), flags=F_HAS_OPB)
            dut.in_instruction.value = instr
            dut.in_tag.value = _std_tag(dim=rng.choice((0, 0x05)))
            dut.in_payload.value = rng.randrange(1 << 64)
            dut.in_b_payload.value = rng.randrange(1 << 64)
            dut.in_b_valid.value = 1
            dut.in_valid.value = 1
        else:
            dut.in_valid.value = 0
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        # 4-state 를 그대로 보존해 비교한다 (X→0 전환도 "값이 바뀐 것"이다).
        pay = str(dut.out_payload.value)
        adr = str(dut.mem_addr.value)
        val = int(dut.out_valid.value)
        req = int(dut.memory_req.value)
        if prev_payload is not None and pay != prev_payload and val != 1:
            violations.append(("H1", prev_payload, pay))
        if prev_addr is not None and adr != prev_addr and req != 1:
            violations.append(("H2", prev_addr, adr))
        prev_payload, prev_addr = pay, adr
    return violations


@cocotb.test()
async def test_pe_output_payload_hold_invariant(dut):
    """§31.14 H1/H2 — 자격자가 0 인 사이클에 값 레지스터가 움직이면 FAIL.

    이 불변식이 깨지면 `Cluster` NoC bank 가 토큰을 내지 않은 명령의 값으로
    오염된다. v1.9 baseline 은 실제로 이것을 위반했고, 그 위반이 Cluster
    경계에서 관측 가능한 값 변화를 만들었다 (spec §31.14.2 — 소비자가 읽은
    B 피연산자가 `0x7777...` 에서 `0x3333...` 로 바뀐다).

    미검사 자극 축 (§28.4 항 8(c)): back-pressure 하의 재시도, HIU 왕복
    메모리 응답, 다중 PE 동시 발행 (그것들은 Cluster 레벨 몫이다).
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    all_violations = []
    for seed in (20260818, 991, 4242):
        await _reset(dut)
        rng = random.Random(seed)
        v = await _hold_monitor(dut, 900, rng)
        all_violations.extend((seed, *x) for x in v)

    assert not all_violations, (
        f"§31.14 자격자-홀드 불변식 위반 {len(all_violations)}건 — 자격자가 "
        "0 인 사이클에 값 레지스터가 움직였다. Cluster NoC bank "
        "(OPREF.src_kind=1) 가 L-PE 슬롯의 저장소로 이 레지스터를 그대로 "
        f"재사용하므로 이는 masked 가 아니다: {all_violations[:6]}"
    )
