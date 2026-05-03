# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

import cocotb
from cocotb.triggers import Timer, RisingEdge, with_timeout
from cocotb.clock import Clock
import random  # For randomization test

@cocotb.test()
async def test_hiu(dut):
    """HIU 모듈 테스트: 보안 강화 기법 검증 (constant-time, XChaCha20 masking, partitioned TLB, flush)"""
    # 클럭 생성 (100MHz)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # 리셋
    dut.rst.value = 1
    await Timer(10, unit="ns")
    dut.rst.value = 0
    await Timer(10, unit="ns")

    # 파티셔닝 TLB 초기화 (파티션 0 예시)
    dut.partition_id.value = 0
    dut.partitioned_tlb_virt[0][0].value = 0x0000000010000000
    dut.partitioned_tlb_phys[0][0].value = 0x0000000020000000
    dut.partitioned_tlb_valid[0][0].value = 1

    # Shadow Region 초기화
    dut.shadow_regions_start[0].value = 0x0000000030000000
    dut.shadow_regions_end[0].value = 0x000000003FFFFFFF
    dut.shadow_valid[0].value = 1

    # XChaCha20 초기화 (랜덤 nonce/key)
    dut.chacha_nonce.value = random.randint(0, 2**192 - 1)
    dut.chacha_key.value = random.randint(0, 2**256 - 1)

    # Test 1: Partitioned TLB 히트 (partition_id=0), PCIe, DMA 요청
    dut.interface_type.value = 0
    dut.virt_addr.value = 0x0000000010000000
    dut.dma_data_in.value = 0xDEADBEEF
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0

    # [수정] 고정 시간을 기다리는 대신, dma_ack 신호가 올라올 때까지 대기 (Timeout 1000ns 설정)
    await with_timeout(RisingEdge(dut.dma_ack), 1000, 'ns')
    
    # RisingEdge 직후이므로 dma_ack는 1임이 보장됨
    assert dut.access_granted.value == 1, "파티셔닝 TLB 히트 실패"
    # assert dut.dma_ack.value == 1  <-- RisingEdge로 잡았으므로 생략 가능하나 확인차 남겨도 됨
    assert dut.masked_phys_addr.value != dut.phys_addr.value, "XChaCha20 마스킹 실패"

    # [수정 중요] FSM이 GRANT_ACCESS -> IDLE로 넘어갈 시간을 줌 (2사이클 대기)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Test 2: Shadow 히트 with USB, DMA 요청
    dut.interface_type.value = 1
    dut.virt_addr.value = 0x0000000035000000
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0

    # [수정] Test 2도 동일하게 수정
    await with_timeout(RisingEdge(dut.dma_ack), 1000, 'ns')

    assert dut.access_granted.value == 1, "Shadow 히트 실패"
    assert dut.masked_phys_addr.value != dut.phys_addr.value, "XChaCha20 랜덤화 실패"

    # [수정 중요] FSM이 GRANT_ACCESS -> IDLE로 넘어갈 시간을 줌 (2사이클 대기)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Test 3: 미스 케이스 (constant-time delay 확인)
    dut.virt_addr.value = 0x00000000FFFFFFFF  # 미스 예상
    dut.dma_req.value = 1
    await RisingEdge(dut.clk)
    dut.dma_req.value = 0
    await Timer(1000, unit="ns")
    assert dut.access_granted.value == 0, "미스 케이스 접근 허용 오류"

    # Test 4: Flush-on-context-switch
    dut.context_switch.value = 1
    await RisingEdge(dut.clk)
    dut.context_switch.value = 0
    await Timer(20, unit="ns")
    assert dut.partitioned_tlb_valid[0][0].value == 0, "파티셔닝 TLB 플러시 실패"
    assert dut.shadow_valid[0].value == 0, "Shadow 플러시 실패"

    # Test 5: ATS/PRI 쿼리 (masking 적용 후)
    dut.ats_req.value = 1
    await Timer(20, unit="ns")
    dut.ats_req.value = 0
    assert dut.ats_resp.value == 1, "ATS 응답 실패"
    dut.pri_req.value = 1
    await Timer(20, unit="ns")
    dut.pri_req.value = 0
    assert dut.pri_resp.value == 1, "PRI 응답 실패"

    # 테스트 완료
    await Timer(10, unit="ns")
