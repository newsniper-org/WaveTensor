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

# =============================================================================
# Claude Code memory mirror — copies the per-project memory directory
#   ~/.claude/projects/-home-ybi-WaveTensor/memory/
# into the repo's `.claude-memories/` so the memory state can be backed up,
# diffed, and (optionally) committed.
#
# Usage:
#   make mirror-memory           # one-shot: copy memory/ → .claude-memories/
#   make mirror-memory-dry       # rsync --dry-run preview, no changes
#   make mirror-memory-clean     # remove the mirror copy
#
# Wire-up (optional):
#   * Pre-commit hook: `.git/hooks/pre-commit` may invoke `make mirror-memory`
#     so every commit captures the latest memory state.
#   * Session-end hook: see `.claude/settings.local.json` Stop hook to call
#     `make mirror-memory` automatically when the CC session ends.
# =============================================================================

CC_MEMORY_SRC := $(HOME)/.claude/projects/-home-ybi-WaveTensor/memory
CC_MEMORY_DST := $(PWD)/.claude-memories

.PHONY: mirror-memory mirror-memory-dry mirror-memory-clean

mirror-memory:
	@if [ ! -d "$(CC_MEMORY_SRC)" ]; then \
	    echo "mirror-memory: source $(CC_MEMORY_SRC) not found — skipping."; \
	    exit 0; \
	fi
	@mkdir -p "$(CC_MEMORY_DST)"
	@rsync -a --delete \
	    --exclude='.git/' \
	    "$(CC_MEMORY_SRC)/" "$(CC_MEMORY_DST)/"
	@echo "mirror-memory: $(CC_MEMORY_SRC) → $(CC_MEMORY_DST)"
	@ls -1 "$(CC_MEMORY_DST)" | sed 's/^/  /'

mirror-memory-dry:
	@if [ ! -d "$(CC_MEMORY_SRC)" ]; then \
	    echo "mirror-memory-dry: source $(CC_MEMORY_SRC) not found."; \
	    exit 0; \
	fi
	@rsync -a --delete --dry-run --itemize-changes \
	    --exclude='.git/' \
	    "$(CC_MEMORY_SRC)/" "$(CC_MEMORY_DST)/"

mirror-memory-clean:
	rm -rf "$(CC_MEMORY_DST)"

# =============================================================================
# Claude Code session resume — reads the session ID stamped by the CC
# SessionEnd hook (`.claude/session-end-hook.sh`) into the file
# `.claude-recent-session-id` and re-attaches with `claude --resume`.
#
# Usage:
#   make claude-resume          # resume the most recently ended session
#
# The recent-session-id file is machine-local and gitignored — it is
# overwritten every time a CC session ends in this repo.
# =============================================================================

CC_RECENT_SID := $(PWD)/.claude-recent-session-id

.PHONY: claude-resume claude-recent-id

claude-resume:
	@if [ ! -f "$(CC_RECENT_SID)" ]; then \
	    echo "claude-resume: $(CC_RECENT_SID) not found."; \
	    echo "  → start a CC session in this repo first; the SessionEnd hook"; \
	    echo "    will stamp the file when the session ends."; \
	    exit 1; \
	fi
	@sid=$$(cat "$(CC_RECENT_SID)" | tr -d '[:space:]'); \
	if [ -z "$$sid" ]; then \
	    echo "claude-resume: $(CC_RECENT_SID) is empty."; \
	    exit 1; \
	fi; \
	echo "claude-resume: resuming session $$sid"; \
	exec claude --resume "$$sid"

claude-recent-id:
	@if [ -f "$(CC_RECENT_SID)" ]; then \
	    cat "$(CC_RECENT_SID)"; \
	else \
	    echo "(no recent session id stamped yet)"; \
	    exit 1; \
	fi
