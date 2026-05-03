# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock

@cocotb.test()
async def test_tensor_alu(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst.value = 1
    await Timer(10, units="ns")
    dut.rst.value = 0
    await Timer(10, units="ns")

    # Test MATMUL (opcode=0x30, 4x4 matrix)
    dut.opcode.value = 0x30
    dut.matrix_a.value = 0x000100020003000400050006000700080009000A000B000C000D000E000F0010  # Packed A [1~16]
    dut.matrix_b.value = 0x001100120013001400150016001700180019001A001B001C001D001E001F0020  # Packed B [17~32]
    await RisingEdge(dut.clk)
    await Timer(20, units="ns")
    assert dut.alu_valid.value == 1, "Tensor ALU 실행 실패"

    await Timer(10, units="ns")