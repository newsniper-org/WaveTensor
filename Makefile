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
    VERILOG_SOURCES = $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/FP_StepSeq.v $(PWD)/FP_Mul36.v $(PWD)/FP_AddWide.v
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
    VERILOG_SOURCES = $(PWD)/Top_Core.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/FP_StepSeq.v $(PWD)/FP_Mul36.v $(PWD)/FP_AddWide.v $(PWD)/HIU.v
    COCOTB_TOPLEVEL = Top_Core
    COCOTB_TEST_MODULES = test_top_core
else ifeq ($(MOD),PE)
    VERILOG_SOURCES = $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/FP_StepSeq.v $(PWD)/FP_Mul36.v $(PWD)/FP_AddWide.v
    COCOTB_TOPLEVEL = PE
    COCOTB_TEST_MODULES = test_pe
else ifeq ($(MOD),Cluster)
    VERILOG_SOURCES = $(PWD)/Cluster.v $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/FP_StepSeq.v $(PWD)/FP_Mul36.v $(PWD)/FP_AddWide.v
    COCOTB_TOPLEVEL = Cluster
    COCOTB_TEST_MODULES = test_cluster
    # v1.6.5c §22.16 — override the fragment/cache buffer slot count for
    # multi-slot persistence tests (default 1 = v1.5.1/v1.6.5b compat).
    # e.g. `make MOD=Cluster FRAG_SLOTS=4`
    ifdef FRAG_SLOTS
        COMPILE_ARGS += -GFRAG_SLOTS=$(FRAG_SLOTS)
    endif
else ifeq ($(MOD),Pod)
    VERILOG_SOURCES = $(PWD)/Pod.v $(PWD)/Cluster.v $(PWD)/PE.v $(PWD)/ISA_Decoder.v $(PWD)/EHDecode.v $(PWD)/PE_Core.v $(PWD)/FP_StepSeq.v $(PWD)/FP_Mul36.v $(PWD)/FP_AddWide.v
    COCOTB_TOPLEVEL = Pod
    COCOTB_TEST_MODULES = test_pod
else
    $(error Unknown MOD '$(MOD)'. Valid: HIU, ISA_Decoder, Tensor_ALU, SIMD_ALU, ALU_Extended, Top_Core, PE, Cluster, Pod)
endif

# Add include path so `include/attributes.vh` (vendor-agnostic attribute macros)
# is discoverable by whichever simulator cocotb chooses (verilator / iverilog).
# See include/attributes.vh for the macro semantics and per-vendor mapping.
COMPILE_ARGS += -I$(CURDIR)/include

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
SYNTH_DIR := $(CURDIR)/synth

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

# -----------------------------------------------------------------------------
# Per-operator UltraScale+ gates (v2.0) — the Vivado counterpart of
# `sh synth/lattice/scripts/synth_fp_ops.sh`. Out-of-context synth + place +
# route of ONE operator core through its shared *_gate_top wrapper, so the
# ECP5 and UltraScale+ numbers measure an identical netlist boundary.
#
#   make synth-fp-op FP_OP=fp_fmalane_bf16 PART=xcu55c-fsvh2892-2L-e
#   make synth-fp-op FP_OP=fp_fmalane_bf16 PART=xcu50-fsvh2104-2-e \
#                    FP_OP_TAG=fp_fmalane_bf16_xcu50
#   make fp-op-report
#
# PART MUST be passed explicitly — the common.tcl default is a small Zynq
# part. xcu55c-fsvh2892-2L-e (= EC2 F2 silicon, conservative -2L) and
# xcu50-fsvh2104-2-e synthesize under the license-free Vivado 2025.2;
# xcvu47p does not. Do NOT upgrade Vivado past 2025.2.
# -----------------------------------------------------------------------------

FP_OP        ?= fp_fmalane_bf16
FP_OP_TAG    ?= $(FP_OP)
FP_OP_PERIOD ?= 10.000

FP_OP_TOP_fp_fmalane_bf16  := FP_FmaLaneBf16_gate_top
FP_OP_SRCS_fp_fmalane_bf16 := FP_FmaLaneBf16.v,FP_AddWide.v,synth/lattice/fp_ops/FP_FmaLaneBf16_gate_top.v

# GATE V20-2 — 528-bit exact-integer lattice unit (spec §27.6; xcu55c 반쪽이
# 유일한 merge-blocker binding):
#   make synth-fp-op FP_OP=fp_acclattice PART=xcu55c-fsvh2892-2L-e
FP_OP_TOP_fp_acclattice  := FP_AccLattice_gate_top
FP_OP_SRCS_fp_acclattice := FP_AccLattice.v,synth/lattice/fp_ops/FP_AccLattice_gate_top.v

# GATE V20-3 — v2.0 TRAIN full-cluster datapath (spec §27.6 ④ 선공표 블록;
# xcu55c 반쪽이 유일한 merge-blocker binding, ECP5 반쪽은 MEASUREMENT):
#   make synth-fp-op FP_OP=fp_traincluster PART=xcu55c-fsvh2892-2L-e
FP_OP_TOP_fp_traincluster  := FP_TrainCluster_gate_top
FP_OP_SRCS_fp_traincluster := FP_TrainCluster.v,FP_AccLattice.v,FP_AccBank.v,synth/lattice/fp_ops/FP_TrainCluster_gate_top.v

# -----------------------------------------------------------------------------
# GATE S1-US — system-integration SYNTHESIZABILITY gate (spec §28).
#
# WHY THIS GATE EXISTS. `HIU.v` and `Top_Core.v` were never synthesized by
# anything in this repo (`grep -rn 'HIU.v|Top_Core.v' synth/` matched
# nothing before this gate), yet both passed cocotb continuously. The first
# synthesis attempt was REFUSED by Vivado — `ERROR [Synth 8-685]` on a
# Verilog-2001 violation in HIU.v (defect D1). "Simulator PASS" had been
# standing in for "synthesizable" for the entire system-integration branch
# of the tree. This gate converts that into a standing check.
#
#   make synth-sys-gate SYS_GATE=sys_top_core PART=xcu55c-fsvh2892-2L-e
#   make fp-op-report
#
# Two things differ from the fp-ops rows above and BOTH are per-gate opts
# of synth/scripts/synth_fp_op.tcl (no fork of the harness):
#   RSTFP   = 1 — these tops are async-reset designs; the fp-ops cores are
#                 reset-free. The gate_top wrapper does not register rst,
#                 so rst is a top-level input to every FF and needs a
#                 false path (same position as synth/constraints/pod.xdc).
#   POSTXDC = synth/constraints/hiu_trng_ro.xdc — defect D2. The HIU TRNG
#                 ring oscillators are an INTENDED combinational feedback
#                 (they are the entropy source). The constraint matches
#                 netlist objects `g_ro[*]` and therefore must be sourced
#                 after synth_design, which is what the tcl's POST_XDC
#                 hook does. Without it: DRC LUTLP-1 Critical Warning x8.
# -----------------------------------------------------------------------------

FP_OP_TOP_sys_top_core     := Top_Core_gate_top
FP_OP_SRCS_sys_top_core    := Top_Core.v,ISA_Decoder.v,EHDecode.v,PE_Core.v,FP_StepSeq.v,FP_Mul36.v,FP_AddWide.v,HIU.v,synth/gate/Top_Core_gate_top.v
FP_OP_RSTFP_sys_top_core   := 1
FP_OP_POSTXDC_sys_top_core := synth/constraints/hiu_trng_ro.xdc

# DISCRIMINATOR SELF-TEST (tautology prevention — the §27.6 ③ PHASE C
# convention applied to a synthesis gate). Identical to sys_top_core except
# POST_XDC is NOT passed, i.e. the defect-D2 constraint is withheld. If the
# gate's DRC axis is real, this run must FAIL it (LUTLP-1 Critical Warnings
# on the 8 ring oscillators); if it passed too, the axis would be
# vacuous. Reports land under the `_diag_` naming precedent of
# synth/reports/fp_ops/fp_acclattice_diag_* and are archived as evidence —
# they are NOT a gate row and never affect `make fp-op-report`.
#
#   make synth-sys-gate SYS_GATE=sys_top_core_diag_nod2 \
#        PART=xcu55c-fsvh2892-2L-e
FP_OP_TOP_sys_top_core_diag_nod2   := Top_Core_gate_top
FP_OP_SRCS_sys_top_core_diag_nod2  := $(FP_OP_SRCS_sys_top_core)
FP_OP_RSTFP_sys_top_core_diag_nod2 := 1

SYS_GATE     ?= sys_top_core
SYS_GATE_TAG ?= $(SYS_GATE)

.PHONY: synth-fp-op synth-sys-gate fp-op-report

synth-fp-op:
	$(VIVADO) $(VIVADO_FLAGS) -source $(CURDIR)/synth/scripts/synth_fp_op.tcl \
	          -tclargs TAG=$(FP_OP_TAG) \
	                   TOP=$(FP_OP_TOP_$(FP_OP)) \
	                   SRCS=$(FP_OP_SRCS_$(FP_OP)) \
	                   PART=$(PART) PERIOD=$(FP_OP_PERIOD)

# Same tcl harness as synth-fp-op, plus: the per-gate RST_FALSE_PATH /
# POST_XDC options, and an ARCHIVED Vivado log. The log is archived because
# the CRITICAL WARNING census is a binding gate axis (spec §28) and a count
# with no listing is not evidence — the log is where "the 8 timing loops
# are the 8 ring oscillators and nothing else" is checkable.
# Vivado writes clockInfo.txt / .Xil/ into its CWD. clockInfo.txt is a
# tracked file with no consumers, so a repo-root run dirties the tree on
# every gate invocation (adversarial audit 2026-08-18). Run from a scratch
# CWD instead — every path handed to Vivado below is already absolute.
SYS_GATE_SCRATCH := $(CURDIR)/synth/reports/fp_ops/.sysgate_cwd

synth-sys-gate:
	@mkdir -p $(SYS_GATE_SCRATCH)
	cd $(SYS_GATE_SCRATCH) && $(VIVADO) -mode batch \
	          -log     $(CURDIR)/synth/reports/fp_ops/$(SYS_GATE_TAG)_run.log \
	          -journal $(CURDIR)/synth/reports/fp_ops/$(SYS_GATE_TAG)_run.jou \
	          -source $(CURDIR)/synth/scripts/synth_fp_op.tcl \
	          -tclargs TAG=$(SYS_GATE_TAG) \
	                   TOP=$(FP_OP_TOP_$(SYS_GATE)) \
	                   SRCS=$(FP_OP_SRCS_$(SYS_GATE)) \
	                   PART=$(PART) PERIOD=$(FP_OP_PERIOD) \
	                   RST_FALSE_PATH=$(or $(FP_OP_RSTFP_$(SYS_GATE)),0) \
	                   POST_XDC=$(FP_OP_POSTXDC_$(SYS_GATE))

fp-op-report:
	@python3 $(CURDIR)/synth/scripts/fp_op_gate_check.py

# =============================================================================
# Lattice ECP5 synthesis flow — Stage 1 target (ULX3S / LFE5U-85F).
#
# Fully FOSS: yosys (frontend + techmap) → nextpnr-ecp5 (place+route) → ecppack
# (bitstream). No vendor Radiant install required. Vendor-neutral attribute
# macros are defined in include/attributes.vh and enabled by the yosys script
# via +define+WT_VENDOR_LATTICE_YOSYS.
#
# Usage:
#   make synth-pod-ecp5    # yosys synthesis → JSON netlist
#   make impl-pod-ecp5     # nextpnr place+route + ecppack bitstream
#
# Prerequisites (install before first invocation):
#   * yosys (>= 0.36)                # arch: yosys yosys-abc
#   * nextpnr-ecp5                   # arch: nextpnr-ecp5
#   * prjtrellis (via ecppack)       # arch: prjtrellis
#   * openFPGALoader                 # arch: openfpgaloader
# =============================================================================

YOSYS         ?= yosys
NEXTPNR_ECP5  ?= nextpnr-ecp5
ECPPACK       ?= ecppack

LATTICE_DIR   := $(CURDIR)/synth/lattice
LATTICE_TAG   := $(PE_ROWS)x$(PE_COLS)_$(CLUSTER_ROWS)x$(CLUSTER_COLS)

.PHONY: synth-pod-ecp5 impl-pod-ecp5 lattice-clean

synth-pod-ecp5:
	$(YOSYS) -q -l $(LATTICE_DIR)/reports/pod_$(LATTICE_TAG)_synth.log \
	    -s $(LATTICE_DIR)/scripts/synth_pod.ys

impl-pod-ecp5: synth-pod-ecp5
	GEOM=$(LATTICE_TAG) sh $(LATTICE_DIR)/scripts/pnr_pod.sh

lattice-clean:
	rm -rf $(LATTICE_DIR)/reports/pod_*.json \
	       $(LATTICE_DIR)/reports/pod_*.rpt \
	       $(LATTICE_DIR)/reports/pod_*.log \
	       $(LATTICE_DIR)/reports/pod_*.config \
	       $(LATTICE_DIR)/reports/pod_*.bit

# =============================================================================
# Lint targets — v1.8.0a §23.9. `make lint` is the future CI entrypoint.
#   * lint_isa_tables_fresh   — generated ISA artifacts match isa/wt64v1_isa.json
#   * lint_frag_total_m1_held — frag-drain FSM invariant (v1.7 §22.18)
#   * lint_synth_coverage     — every cocotb-verified module has a DECLARED
#                               synthesis position (spec §28). This is the
#                               standing form of "simulator PASS is not
#                               synthesizable": HIU.v/Top_Core.v passed
#                               cocotb for the repo's whole 3.5-month
#                               history while no synthesis
#                               script in the repo could even elaborate
#                               them. Adding a module to the cocotb MOD
#                               list without declaring where it gets
#                               synthesized now breaks the build.
# All three are stdlib-only Python; runnable directly without cocotb:
#   python3 scripts/lint_isa_tables_fresh.py
# =============================================================================

.PHONY: lint

lint:
	python3 $(CURDIR)/scripts/lint_isa_tables_fresh.py
	python3 $(CURDIR)/scripts/lint_frag_total_m1_held.py
	python3 $(CURDIR)/scripts/lint_synth_coverage.py

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
CC_MEMORY_DST := $(CURDIR)/.claude-memories

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

CC_RECENT_SID := $(CURDIR)/.claude-recent-session-id

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
