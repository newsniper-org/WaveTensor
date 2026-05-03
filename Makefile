# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# Makefile — multi-module cocotb runner.
#
# Usage:
#   make                     # default: HIU
#   make MOD=ISA_Decoder
#   make MOD=Tensor_ALU
#   make MOD=SIMD_ALU
#   make MOD=ALU_Extended

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
MOD ?= HIU

# Per-module configuration. Each row defines:
#   - the Verilog source filename
#   - the cocotb top-level module name
#   - the Python test module
ifeq ($(MOD),HIU)
    VERILOG_SOURCES = $(PWD)/HIU.v
    COCOTB_TOPLEVEL = HIU
    COCOTB_TEST_MODULES = test_hiu
else ifeq ($(MOD),ISA_Decoder)
    VERILOG_SOURCES = $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v
    COCOTB_TOPLEVEL = ISA_Decoder
    COCOTB_TEST_MODULES = test_isa_decoder
else ifeq ($(MOD),Tensor_ALU)
    VERILOG_SOURCES = $(PWD)/TENSOR_ALU.v
    COCOTB_TOPLEVEL = Tensor_ALU
    COCOTB_TEST_MODULES = test_tensor_alu
else ifeq ($(MOD),SIMD_ALU)
    VERILOG_SOURCES = $(PWD)/SIMD_ALU.v
    COCOTB_TOPLEVEL = SIMD_ALU
    COCOTB_TEST_MODULES = test_simd_alu
else ifeq ($(MOD),ALU_Extended)
    VERILOG_SOURCES = $(PWD)/ALU_Extended.v
    COCOTB_TOPLEVEL = ALU_Extended
    COCOTB_TEST_MODULES = test_alu_extended
else ifeq ($(MOD),Top_Core)
    VERILOG_SOURCES = $(PWD)/Top_Core.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/HIU.v
    COCOTB_TOPLEVEL = Top_Core
    COCOTB_TEST_MODULES = test_top_core
else ifeq ($(MOD),PE)
    VERILOG_SOURCES = $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v
    COCOTB_TOPLEVEL = PE
    COCOTB_TEST_MODULES = test_pe
else ifeq ($(MOD),Cluster)
    VERILOG_SOURCES = $(PWD)/Cluster.v $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v
    COCOTB_TOPLEVEL = Cluster
    COCOTB_TEST_MODULES = test_cluster
else ifeq ($(MOD),Pod)
    VERILOG_SOURCES = $(PWD)/Pod.v $(PWD)/Cluster.v $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v
    COCOTB_TOPLEVEL = Pod
    COCOTB_TEST_MODULES = test_pod
else
    $(error Unknown MOD '$(MOD)'. Valid: HIU, ISA_Decoder, Tensor_ALU, SIMD_ALU, ALU_Extended, Top_Core, PE, Cluster, Pod)
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

# =============================================================================
# Vivado synthesis targets — separate from the cocotb flow above. Invoked
# directly (no MOD= override needed). They use their own Makefile-fragment
# style so the cocotb include block above remains the default behavior of
# `make`.
# =============================================================================

VIVADO_VERSION ?= 2025.2.1
VIVADO ?= /opt/Xilinx/$(VIVADO_VERSION)/Vivado/bin/vivado
VIVADO_FLAGS := -mode batch -nolog -nojournal
SYNTH_DIR := $(PWD)/synth

# Geometry knobs (override on the command line, e.g. `make synth-pod PE_ROWS=4 PE_COLS=4`)
PE_ROWS      ?= 2
PE_COLS      ?= 2
CLUSTER_ROWS ?= 2
CLUSTER_COLS ?= 2
PART         ?= xczu3eg-sfvc784-1-i

GEOM_TAG := $(PE_ROWS)x$(PE_COLS)_$(CLUSTER_ROWS)x$(CLUSTER_COLS)

VIVADO_TCLARGS := \
    PART=$(PART) \
    PE_ROWS=$(PE_ROWS) PE_COLS=$(PE_COLS) \
    CLUSTER_ROWS=$(CLUSTER_ROWS) CLUSTER_COLS=$(CLUSTER_COLS)

.PHONY: synth-pod impl-pod synth-report synth-clean

synth-pod:
	$(VIVADO) $(VIVADO_FLAGS) -source $(SYNTH_DIR)/scripts/synth_pod.tcl \
	          -tclargs $(VIVADO_TCLARGS)

impl-pod:
	$(VIVADO) $(VIVADO_FLAGS) -source $(SYNTH_DIR)/scripts/impl_pod.tcl \
	          -tclargs $(VIVADO_TCLARGS)

synth-report:
	@python3 $(SYNTH_DIR)/parse_reports.py $(GEOM_TAG)

synth-clean:
	rm -rf $(SYNTH_DIR)/reports/* $(SYNTH_DIR)/checkpoints/* \
	       vivado*.jou vivado*.log .Xil
