# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# pod.xdc — constraints for OOC synthesis of Pod.v
#
# Out-of-context mode means there are no physical pin assignments — the
# Pod's ports are kept as boundary I/O. We still need a clock definition
# so timing reports are meaningful.
#
# Initial target: 100 MHz (10 ns period). The single-cycle decoder's
# critical path is the EH chain walk inside ISA_Decoder.v; if synthesis
# fails timing at 100 MHz we'll either pipeline that walk or relax to a
# slower clock for the first bring-up.

create_clock -name clk -period 10.000 [get_ports clk]

# Treat reset as asynchronous to the clock domain it deasserts into; the
# decoder uses posedge rst as an async reset, so this matches the RTL
# semantics.
set_false_path -from [get_ports rst]

# The wide instruction bus (416 bits) and 80-bit tag are I/O for OOC; we
# leave them unconstrained for input/output delay (Vivado will warn about
# unconstrained I/O — expected and ignored at this OOC stage).
