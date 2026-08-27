# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# Makefile — multi-module cocotb runner.
#
# Usage:
#   make                     # default: HIU
#   make MOD=ISA_Decoder
#   make MOD=ALU_Extended
#   make MOD=Top_Core / Cluster / Pod
#
# C-2 (2026-08-18, spec §33): MOD 9 → 6. Tensor_ALU / SIMD_ALU / PE 는 모듈
# 자체가 폐기됐다 (superseded duplicate — §12a 규칙 6).

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
MOD ?= HIU

# Per-module configuration. Each row defines:
#   - the Verilog source filename
#   - the cocotb top-level module name
#   - the Python test module
ifeq ($(MOD),HIU)
    VERILOG_SOURCES = $(CURDIR)/HIU.v
    COCOTB_TOPLEVEL = HIU
    COCOTB_TEST_MODULES = test_hiu
else ifeq ($(MOD),ISA_Decoder)
    VERILOG_SOURCES = $(CURDIR)/ISA_Decoder.v $(CURDIR)/EHDecode.v $(CURDIR)/PE_Core.v $(CURDIR)/FP_StepSeq.v $(CURDIR)/FP_Mul36.v $(CURDIR)/FP_AddWide.v
    COCOTB_TOPLEVEL = ISA_Decoder
    COCOTB_TEST_MODULES = test_isa_decoder
else ifeq ($(MOD),ALU_Extended)
    VERILOG_SOURCES = $(CURDIR)/ALU_Extended.v
    COCOTB_TOPLEVEL = ALU_Extended
    COCOTB_TEST_MODULES = test_alu_extended
else ifeq ($(MOD),Top_Core)
    VERILOG_SOURCES = $(CURDIR)/Top_Core.v $(CURDIR)/ISA_Decoder.v $(CURDIR)/EHDecode.v $(CURDIR)/PE_Core.v $(CURDIR)/FP_StepSeq.v $(CURDIR)/FP_Mul36.v $(CURDIR)/FP_AddWide.v $(CURDIR)/HIU.v
    COCOTB_TOPLEVEL = Top_Core
    COCOTB_TEST_MODULES = test_top_core
else ifeq ($(MOD),Cluster)
    VERILOG_SOURCES = $(CURDIR)/Cluster.v $(CURDIR)/ISA_Decoder.v $(CURDIR)/EHDecode.v $(CURDIR)/PE_Core.v $(CURDIR)/FP_StepSeq.v $(CURDIR)/FP_Mul36.v $(CURDIR)/FP_AddWide.v
    COCOTB_TOPLEVEL = Cluster
    COCOTB_TEST_MODULES = test_cluster
    # v1.6.5c §22.16 — override the fragment/cache buffer slot count for
    # multi-slot persistence tests (default 1 = v1.5.1/v1.6.5b compat).
    # e.g. `make MOD=Cluster FRAG_SLOTS=4`
    ifdef FRAG_SLOTS
        COMPILE_ARGS += -GFRAG_SLOTS=$(FRAG_SLOTS)
    endif
else ifeq ($(MOD),Pod)
    VERILOG_SOURCES = $(CURDIR)/Pod.v $(CURDIR)/Cluster.v $(CURDIR)/ISA_Decoder.v $(CURDIR)/EHDecode.v $(CURDIR)/PE_Core.v $(CURDIR)/FP_StepSeq.v $(CURDIR)/FP_Mul36.v $(CURDIR)/FP_AddWide.v
    COCOTB_TOPLEVEL = Pod
    COCOTB_TEST_MODULES = test_pod
else
    $(error Unknown MOD '$(MOD)'. Valid: HIU, ISA_Decoder, ALU_Extended, Top_Core, Cluster, Pod)
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

# synth-clean USED TO run `rm -rf $(SYNTH_DIR)/reports/* ... vivado*.jou
# vivado*.log`, which would have deleted 92 TRACKED gate-evidence files
# (GATE V20-2 / V20-3 / S1-US reports — including sys_top_core_run.log,
# whose CRITICAL WARNING census is a BINDING gate axis, see .gitignore
# above) plus the 12 root Vivado logs that were tracked at the time (they
# were untracked on 2026-08-18 — see .gitignore). A "clean" target that destroys
# the evidence its own gates depend on is a landmine; found by the
# 2026-08-18 legacy audit before anyone tripped it.
#
# It now removes ONLY untracked byproducts, and refuses loudly if any
# target it is about to delete is tracked — the guard is the point, not
# the shorter list: a future edit that re-adds a tracked path fails here
# instead of silently deleting evidence.
synth-clean:
	@set -e; \
	targets="$(SYNTH_DIR)/checkpoints $(SYNTH_DIR)/reports/fp_ops/.sysgate_cwd .Xil"; \
	tracked=$$(git ls-files -- $$targets 2>/dev/null); \
	if [ -n "$$tracked" ]; then \
	    echo "synth-clean: REFUSING — the following targets are TRACKED:"; \
	    echo "$$tracked" | sed 's/^/    /'; \
	    echo "synth-clean: a clean target must never delete tracked evidence."; \
	    exit 1; \
	fi; \
	rm -rf $$targets; \
	echo "synth-clean: removed untracked byproducts only."; \
	echo "  Tracked gate evidence under $(SYNTH_DIR)/reports/ is PRESERVED by design."; \
	echo "  Root vivado*.{jou,log} + clockInfo.txt are gitignored (2026-08-18) and"; \
	echo "  are deliberately NOT in the target list — deleting a vendor log is not"; \
	echo "  this target's job, and synth-sys-gate no longer writes to the root."

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

# GATE V20-4 — FDOT32_CR (0x7A) 를 호스팅하는 step-sequencer unit
# (spec §27.7a.5; xcu55c 반쪽이 유일한 merge-blocker binding):
#   make synth-fp-op FP_OP=fp_stepseq PART=xcu55c-fsvh2892-2L-e
#
# 이 unit 의 xcu55c 실측은 존재한 적이 없다. §27.7a.5 가 선언한 anchor-부재
# 절차대로 **anchor 를 먼저 만든다** — OPS_FDOTCR 이 없는 base 형상을 같은
# 스크립트로 재고, 착지 후 재실측해 **delta** 로 판정한다 (binding: LUT
# delta <= 2,200 / premap $mul delta 정확히 0 / DSP48 · BRAM delta 0).
# base 형상 tag 는 `fp_stepseq_base` 이며 소스 목록은 아래와 동일하다 —
# **다른 것은 FP_StepSeq.v 의 내용 하나뿐**이어야 delta 가 OPS_FDOTCR 만
# 가리킨다 (spec §34).
FP_OP_TOP_fp_stepseq  := FP_StepSeq_gate_top
FP_OP_SRCS_fp_stepseq := FP_StepSeq.v,FP_Mul36.v,FP_AddWide.v,synth/lattice/fp_ops/FP_StepSeq_gate_top.v

FP_OP_TOP_fp_stepseq_base  := $(FP_OP_TOP_fp_stepseq)
FP_OP_SRCS_fp_stepseq_base := $(FP_OP_SRCS_fp_stepseq)

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

# -----------------------------------------------------------------------------
# premap $mul 증거 (spec §22.14b-10, 2026-08-18 적대 검수에서 추가).
#
# `fp_op_gate_check.py` 의 binding 축 하나(premap $mul)는 archived yosys stat
# 로그에서 읽힌다. 그런데 **그 로그를 만드는 단계가 어느 타깃에도 없었다** —
# Vivado 만 돌고, 로그는 사람이 손으로 친 yosys 한 줄의 산출물이었다. 그래서
# 소스가 바뀌어도 로그는 그대로 남았고, GATE S1 이 두 번 완주하는 동안 이
# 파일만 갱신되지 않은 채 축이 PASS 했다 — 측정이 아니라 동결 상수였다.
# 이제 합성 타깃이 증거를 **직접 재생성**하고, 소비 측(gate check)이 로그
# 선두의 BLAKE2b-512 provenance 를 현행 소스와 대조한다. 어느 한쪽만으로는 부족
# 하다: 생성만 편입하면 옛 로그가 계속 통과하고, 검증만 넣으면 flow 가 증거를
# 못 만들어 gate 가 영영 FAIL 한다.
#
# 코어 top / 코어 소스 목록은 **파생**한다 (손으로 두 벌 유지하지 않는다 —
# 두 벌이 어긋난 것이 바로 이 결함이었다):
#   * 코어 top   = gate_top 래퍼 이름에서 `_gate_top` 접미를 뗀 것
#   * 코어 소스  = FP_OP_SRCS_<tag> 에서 `synth/` 밑의 래퍼를 뺀 것
#     (gen_premap_mul.py 의 premap_sources() 가 같은 규칙을 집행한다)
PREMAP_CORE_TOP = $(patsubst %_gate_top,%,$(FP_OP_TOP_$(1)))

define regen-premap-mul
@python3 $(CURDIR)/synth/scripts/gen_premap_mul.py \
	--tag $(2) \
	--top $(call PREMAP_CORE_TOP,$(1)) \
	--sources '$(FP_OP_SRCS_$(1))'
endef

.PHONY: synth-fp-op synth-sys-gate fp-op-report premap-mul-evidence

# 운영자 gate 도 run log 를 아카이브한다 (2026-08-18). 이전에는 -nolog 라
# 로그가 남지 않았고, 그래서 `parse_run_expect` 가 이 gate 들에 대해서만
# (None, None) 을 돌려줘 premap provenance 가 **해시 대조까지만** 이었다 —
# 소스가 하나 추가되면 남은 항목 해시는 전부 맞으므로 조용히 PASS 하는
# 구멍이다. 검증 강도를 gate 마다 다르게 두면 그 예외가 다음 번 구멍이 된다
# (§22.14b-10 이 세 증거를 전부 재생성한 것과 같은 이유). 로그가 쌓이는
# **다음 재합성부터** sys_top_core 와 같은 강도(소스 목록 + top 대조)가 된다.
synth-fp-op:
	$(VIVADO) -mode batch \
	          -log     $(CURDIR)/synth/reports/fp_ops/$(FP_OP_TAG)_run.log \
	          -journal $(CURDIR)/synth/reports/fp_ops/$(FP_OP_TAG)_run.jou \
	          -source $(CURDIR)/synth/scripts/synth_fp_op.tcl \
	          -tclargs TAG=$(FP_OP_TAG) \
	                   TOP=$(FP_OP_TOP_$(FP_OP)) \
	                   SRCS=$(FP_OP_SRCS_$(FP_OP)) \
	                   PART=$(PART) PERIOD=$(FP_OP_PERIOD)
	$(call regen-premap-mul,$(FP_OP),$(FP_OP_TAG))

# premap 증거만 따로 재생성 (Vivado 없이 yosys 만으로 돌아간다).
#
# ⚠️ 이 타깃은 **gate 를 다시 판정하기 위한 것이 아니다.** 정반대다 — 잊는
# 쪽이 안전하고 쓰는 쪽이 위험하다:
#   * 잊으면  → provenance 해시가 어긋나 `fp_op_gate_check` 가 STALE FAIL.
#              **시끄럽게** 실패한다. 이것이 원하는 동작이다.
#   * 단독 사용 → premap 축만 현행 소스로 갱신되고, LUT / DSP48 / RAMB18 /
#              WHS / DRC / CRIT WARN 6축은 **옛 소스로 측정된 Vivado 리포트
#              그대로** PASS 한다. 즉 저장소에 남은 **유일한 stale 신호를
#              끄는 경로**다. 소스 목록 대조도 파일 이름만 보므로 못 잡는다.
# 그러므로 이 타깃 단독 실행 후의 `fp_op_gate_check` PASS 는 **gate 판정이
# 아니다.** RTL 을 고쳤으면 `make synth-sys-gate` / `make synth-fp-op` 로
# Vivado 를 다시 돌려라 — 그 타깃들이 증거 재생성을 이미 포함한다.
# 정당한 용도는 하나뿐이다: 증거 생성 자체를 손보거나(이 스크립트 개발),
# Vivado 없는 환경에서 premap 계수만 따로 확인할 때.
#   make premap-mul-evidence                      # 기본 = sys_top_core
#   make premap-mul-evidence PREMAP_GATE=fp_acclattice
#   make premap-mul-evidence PREMAP_GATE=fp_traincluster
PREMAP_GATE ?= $(SYS_GATE)
premap-mul-evidence:
	$(call regen-premap-mul,$(PREMAP_GATE),$(PREMAP_GATE))

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
	$(call regen-premap-mul,$(SYS_GATE),$(SYS_GATE_TAG))

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
#   * lint_output_payload_hold  — v1.9.1 §31.14. `PE_Core.output_payload` /
#                               `mem_addr` must change ONLY on cycles where
#                               their qualifier (`output_valid` /
#                               `memory_req`) is asserted. The Cluster's NoC
#                               bank (OPREF.src_kind=1) reuses PE_Core's
#                               output register as the L-PE slot's STORAGE
#                               and reads it combinationally, so a payload
#                               that moves on a token-less cycle silently
#                               corrupts the next consumer's B operand.
#                               The v1.9 baseline violated this.
#   * lint_frag_slots_dual_run  — P0-2. `test_cluster.py` 의 FRAG_SLOTS>1
#                               전용 6건은 기본 빌드(FRAG_SLOTS=1)에서
#                               값 검사를 0건 하고도 PASS 로 집계됐고,
#                               두 빌드를 모두 돌리도록 강제하는 장치가
#                               어디에도 없었다. 이 lint 은 (a) 조용한
#                               self-skip(`_slots()` → bare return)을
#                               금지하고, (b) loud 게이트를 쓰는 테스트
#                               집합이 선언표와 일치하는지, (c) 이중 빌드
#                               진입점(`make test-cluster-both`)이 살아
#                               있는지를 기계적으로 대조한다.
#   * lint_known_defect_tests   — v1.9.1 §31.14. §28.4 item 8(e)'s
#                               `expect_fail` ratchet, mechanically enforced
#                               in BOTH directions. Weakening an assert
#                               while ALSO dropping the `expect_fail=True`
#                               marker used to restore full concealment with
#                               a green CI; that path is now closed, and
#                               undeclared `expect_fail` markers (silencing
#                               a regression) fail too.
#   * lint_estimate_index      — spec §39.2. 추정치 색인의 기계 집행. 이
#                               저장소는 자기 추정치를 성실하게 적어 왔지만
#                               ("hand-count 추정이고 합성 실측이 아니다",
#                               "gate 판정 근거로 인용하지 마라") 그 성실함을
#                               지키는 것이 아무것도 없었다: 실측이 추정
#                               대역을 전부 하회했는데 원 추정 줄에 supersede
#                               배너가 없고, "졸업" 배너가 붙었는데 정작
#                               졸업한 것은 문장의 절반뿐이었다. 이 lint 은
#                               색인의 anchor 실재(정확히 1회) / spec §39.2.3
#                               본표와의 ID 양방향 정합 / 졸업 근거의 실재 /
#                               인용 금지 / 4축 래칫을 강제한다. **산문
#                               스캐너는 의도적으로 advisory 다** — 고정밀
#                               검출기의 오탐률을 실측했더니 HEAD 증분 31줄
#                               중 진성이 약 3건이었고, 그런 검사를
#                               merge-blocker 로 걸면 사람이 lint 를 끈다.
# All eight are stdlib-only Python; runnable directly without cocotb:
#   python3 scripts/lint_isa_tables_fresh.py
# =============================================================================

.PHONY: lint

lint:
	python3 $(CURDIR)/scripts/lint_isa_tables_fresh.py
	python3 $(CURDIR)/scripts/lint_frag_total_m1_held.py
	python3 $(CURDIR)/scripts/lint_synth_coverage.py
	python3 $(CURDIR)/scripts/lint_output_payload_hold.py
	python3 $(CURDIR)/scripts/lint_frag_slots_dual_run.py
	python3 $(CURDIR)/scripts/lint_known_defect_tests.py
	python3 $(CURDIR)/scripts/lint_estimate_index.py
	python3 $(CURDIR)/scripts/lint_gate_thresholds.py
	python3 $(CURDIR)/scripts/lint_guide_derived_tables.py
	python3 $(CURDIR)/scripts/lint_guard_map.py
	python3 $(CURDIR)/scripts/lint_postformal.py
	python3 $(CURDIR)/scripts/lint_generated_names.py
	python3 $(CURDIR)/scripts/lint_tautology.py --audit
	python3 $(CURDIR)/scripts/lint_witness_map.py
	python3 $(CURDIR)/scripts/lint_witness_map.py --self-test
	python3 $(CURDIR)/scripts/lint_section_refs.py

# =============================================================================
# P0-2 — Cluster 이중 빌드(FRAG_SLOTS=1 / FRAG_SLOTS=4) 단일 진입점.
#
# `make MOD=Cluster` 하나만 돌린 녹색은 다중 슬롯 경로(persistence / LRU /
# cold-fill / FRAG_INVAL)가 검증됐다는 뜻이 **아니다** — 그 6건은 기본
# 빌드에서 값 검사를 0건 수행하고 self-skip 한다. 이 타깃은 두 빌드를
# 모두 돌리고, FRAG_SLOTS=1 에서 self-skip 이 정확히 7건 / FRAG_SLOTS=4
# 에서 정확히 0건인지까지 대조한다. 한쪽만 돌리면 통과할 수 없다.
# =============================================================================

.PHONY: test-cluster-both

test-cluster-both:
	python3 $(CURDIR)/scripts/run_cluster_dual.py

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

# =============================================================================
# WT64v1 RTL 전면 재구현 (SpinalHDL + SystemVerilog) — `rtl-*` 타깃군.
#
# 정본은 `docs/wt64v1-architecture-guide/main.pdf` 하나이며, 이 트리의 규약은
# `rtl/README.md` 가 선언한다.
#
# ⚠️ 여기에 **MOD 표 항목을 추가하지 않는다.** 위쪽 cocotb 흐름의
#    `ifeq ($(MOD),...)` 표는 `scripts/lint_synth_coverage.py` 의 COVERAGE
#    딕셔너리·지위 래칫과 이중으로 잠겨 있어서, 새 top 을 거기 끼우면 lint 가
#    즉시 FAIL 한다. 재구현 트리는 `synth/lattice/fp_ops/run_fp_ops_tests.py`
#    선례(자립형 cocotb python runner)를 따라 **독립 진입점**으로 돈다.
#    기존 게이트 계보를 건드리지 않는 것이 목적이다.
# =============================================================================

RTL_DIR     := $(CURDIR)/rtl
# 후-formal 산출물의 호스트 쪽 자리. 저장소 밖에 두어 트리를 더럽히지 않되,
# 컨테이너와 *공유*되어야 한다 — 공허 게이트가 셀을 세려면 산출물과 세는
# 주체가 같은 파일시스템에 있어야 하기 때문이다 (rtl-postformal 주석 참조).
SBY_OUT     := /tmp/wt-sby-out
RTL_SPINAL  := $(RTL_DIR)/spinal
RTL_GEN     := $(RTL_DIR)/generated

.PHONY: rtl-pins rtl-gen rtl-lint rtl-formal rtl-postformal rtl-impact rtl-sim rtl-clean

# 툴체인 핀 대조 — devcontainer 의 ARG 와 rtl/spinal 의 빌드 파일이 같은 값을
# 말하는지. 어긋나면 컨테이너가 구워 둔 캐시와 빌드가 원하는 버전이 달라지고,
# 그러면 오프라인에서 죽거나(운이 좋을 때) 조용히 다른 버전을 받는다(나쁠 때).
rtl-pins:
	python3 $(CURDIR)/scripts/lint_toolchain_pins.py

# SpinalHDL → SystemVerilog 생성. 생성물은 커밋 대상이며 손편집 금지다.
rtl-gen: rtl-pins
	@mkdir -p $(RTL_GEN)
	cd $(RTL_SPINAL) && sbt -batch \
	  "runMain wt64.gen.GenRouteJudge $(RTL_GEN)" \
	  "runMain wt64.gen.GenMmioConfig $(RTL_GEN)" \
	  "runMain wt64.gen.GenSharedUnit $(RTL_GEN)" \
	  "runMain wt64.gen.GenResultBank $(RTL_GEN)" \
	  "runMain wt64.gen.GenFabricMerge $(RTL_GEN)" \
	  "runMain wt64.gen.GenXlateStore $(RTL_GEN)" \
	  "runMain wt64.gen.GenDecodeWalk $(RTL_GEN)" \
	  "runMain wt64.gen.GenHiuPipeline $(RTL_GEN)" \
	  "runMain wt64.gen.GenReassembly $(RTL_GEN)" \
	  "runMain wt64.gen.GenMemOrderGate $(RTL_GEN)" \
	  "runMain wt64.gen.GenOperandDecode $(RTL_GEN)" \
	  "runMain wt64.gen.GenOwnershipTable $(RTL_GEN)" \
	  "runMain wt64.gen.GenMaskUnit $(RTL_GEN)" \
	  "runMain wt64.gen.GenCompletionUnit $(RTL_GEN)" \
	  "runMain wt64.gen.GenStepSequencer $(RTL_GEN)" \
	  "runMain wt64.gen.GenWt64Top $(RTL_GEN)"
	@echo "rtl-gen: 생성물 → $(RTL_GEN)"

# 정적 검사. ISA-7(형상 파라미터 노출 0)과 금지 용어를 포함한다.
rtl-lint: rtl-pins
	python3 $(CURDIR)/scripts/lint_forbidden_terms.py
	python3 $(CURDIR)/scripts/lint_isa7_topology.py

# 선-formal 게이트 — 재구현 모델 전용. 기존 AccBank 게이트와 분리해 둔다.
rtl-formal:
	@if [ -x $(RTL_DIR)/formal/tla/run.sh ]; then \
	    sh $(RTL_DIR)/formal/tla/run.sh; \
	else \
	    echo "rtl-formal: 선-formal 모델이 아직 없다 (단계 1 미착수)."; \
	    echo "  ⇒ 이것은 통과가 아니라 **미측정**이다 (정본 §6.7 원칙 5)."; \
	    exit 1; \
	fi

# 후-formal 게이트 — sby 전 태스크 실행 (§6.3 셋째 단).
#
# GUARD-MAP 의 CHECK 는 주장이고, lint_guard_map 은 전수성만 잰다. 이 타깃이
# 그 주장의 *참*을 잰다 — 각 .sby 를 컨테이너에서 실행해 하나라도 FAIL 이면
# 크게 실패한다. 산출물은 /tmp (저장소에 쌓지 않는다). 솔버는 z3 단독
# (.sby 안에 명시 — 기본값 의존 금지). 호스트 sby 사용 금지 — 컨테이너로만
# (호스트 tlc 2.19 함정과 동류).
#
# ## 공허 게이트 — PASS 가 아무것도 보증하지 않는 경우
#
# yosys 0.66 은 SystemVerilog `bind` 를 오류 없이 파싱하고 *조용히 무시*한다.
# 하네스 모듈이 「Removing unused module」로 제거되면 단언이 하나도 없는 채
# 전 태스크가 PASS 한다. 2026-08-25 실측: XlateStore 가 PROVES 앵커 7건을
# 달고도 assert 0 으로 통과하고 있었고, lint_postformal 의 커버리지 래칫이
# 그 일곱을 「덮임」으로 세고 있었다 — 주장만 있고 측정이 없었다.
#
# 그래서 PASS 만으로는 부족하다. 각 태스크의 합성 모델에서 assert/cover 셀을
# 세어 0 이면 HOLLOW 로 판정하고 실패시킨다. 「돌았고 통과했다」는 관측이
# 무엇을 보증하는지는 셀 수가 답한다.
#
# 이 게이트가 사람의 적발을 대신하는 이유: 1차 파도에서 세 팀이 독립적으로
# 이 함정을 밟고 각자 적발했는데도 둘이 그물을 빠져나갔다. 지문을 「prep -top
# 이 DUT 자신인 것」으로 잡은 것이 원인이다 — HiuMask 는 래퍼를 가져서 그
# 검사를 통과했고, 다만 그 래퍼가 DUT 둘을 배선만 하고 단언은 별도 props 에
# bind 로 붙었다. **래퍼 top 은 부착의 증거가 아니다. 셀 수만이 증거다.**
#
# lint_postformal 은 이것을 잡을 수 없다 — 정적 검사라 셀을 셀 수 없고,
# PROVES 앵커의 실재성만 재면서 그것을 「덮임」으로 계수한다. 두 층의 분업이
# 그래서 이렇다: lint 은 *선언*의 정합을, 이 타깃은 *측정*의 실재를 잰다.
#
# 산출물을 SBY_OUT 볼륨으로 빼는 이유: sby 는 컨테이너 안에서 돌므로 --prefix
# 를 컨테이너 /tmp 로 두면 --rm 과 함께 사라진다. 셀 수를 세는 쪽은 호스트라
# 전부 0 으로 읽히고, 게이트가 멀쩡한 태스크를 공허로 오판한다 (2026-08-25
# 첫 실행에서 14/16 오탐). 세는 주체와 산출물이 같은 파일시스템에 있어야 한다.
#
# ## 증거 층 — 이 타깃이 남기고 lint 가 검사한다 (2026-08-26)
#
# 스윕은 이제 태스크마다 `rtl/formal/sby/<Dir>/<name>.evidence.json` 을 쓴다.
# 산출물(/tmp)은 여전히 버려지지만 **증거는 저장소에 남는다** — 그 둘은 다른
# 것이다. 산출물은 수십 MB 의 재생성 가능한 중간물이고, 증거는 태스크당 20줄
# 남짓의 「무엇을 언제 무슨 소스로 쟀는가」다.
#
# 커밋 대상인 이유는 이 저장소의 기존 처분과 같다 (.gitignore 의 synth 절):
# **부피 큰 재생성 가능 산출물은 ignore, 컴팩트한 측정 증거는 tracked.**
# `synth/reports/fp_ops/*_run.log` 가 「reviewer 가 grep 할 수 있어야 한다」는
# 이유로 tracked 인 것과 같은 자리다. 증거를 커밋하지 않으면 갓 clone 한
# 사람의 `make lint` 는 증거 0 건 = 전부 미측정이 되고, 그 검사는 방금 스윕을
# 돌린 사람 말고 아무에게도 아무것도 재지 못한다.
#
# 스윕 직후의 `--require-fresh` 는 **게이트 자신에 대한 검사**다. 방금 잰
# 증거가 stale 하거나 비어 있다면 그것은 대상의 결함이 아니라 스윕의 결함이다
# — 2026-08-25 의 두 오탐(경로·인용)이 정확히 그 형태였고, 그때는 그것을
# 알아차릴 검사가 없었다. `make lint` 쪽은 이 강도를 걸지 않는다: RTL 을
# 편집하는 중에는 증거가 stale 한 것이 정상이고, 거기서 실패시키면 50분짜리
# 스윕 없이는 아무 작업도 못 한다. 대신 stale·미측정을 **낱말을 갈라** 인쇄하고
# 게이트는 래칫(줄지 않는다)으로만 건다.
#
# ## 상수 접힘 게이트 — 공허 3형 (2026-08-27)
#
# 단언이 `connect \A 1'1` 로 접히면 **어떤 설계에서도 통과한다.** 셀 수는
# 정직하게 1 을 세고 sby 는 PASS 를 낸다 — 앞의 두 게이트(HOLLOW·증인)가
# 통째로 눈감는 자리다. 음성 시험 실측(격리 사본): 항진 4건을 심은 하네스에서
# `sby … prove` 가 **PASS (rc=0)** 를 냈고 `lint_tautology` 만 잡았다.
#
# 왜 `lint_postformal` 이 아니라 별도 스크립트인가 — 셀 수 세기와 달리
# **간접 결속을 따라가야 하므로 grep 두 줄로 끝나지 않는다.** 실측으로 이
# 저장소의 모델에는 모듈 수준 상수 결속이 434건 있고, 직접 `\A 1'1` 만
# 보면 그 뒤에 숨은 항진을 통째로 놓친다. 파서는 한 벌뿐이고(`--count` 를
# 스윕이, `--audit` 를 여기가 부른다) 그것이 정규식 사본이 두 층에 생기는
# 것 — 2026-08-25 두 오탐의 뿌리 — 을 막는다.
#
# **두 강도가 다른 이유**는 `--require-fresh` 의 비대칭과 정확히 같다.
# 모델은 /tmp 에 있고 커밋되지 않으므로 갓 clone 한 사람에게는 없다. 거기서
# 하드 실패시키면 50분 스윕 없이는 아무 작업도 못 하고, 다음 사람이 할 일은
# 정해져 있다 — 게이트를 「임시로」 끄는 것. 그래서:
#
#   · `make lint`          모델 없음 = **미계수로 인쇄**하고 통과.
#                          상수 0 을 인쇄하지 않는다 — 「없다」와 「없는 곳을
#                          봤다」를 가르는 것이 이 게이트의 알맹이다.
#   · `make rtl-postformal` 방금 스윕을 돌렸는데 모델이 없다 = **게이트의
#                          결함**이다. 하드 실패.
#
# 그리고 `--audit` 는 매번 **양성 대조를 먼저** 돌린다 (일부러 심은 상수
# 접힘을 잡는지). 그것이 없으면 계수 0 은 「접힘이 없다」와 「검사가 죽었다」를
# 구별하지 못하고, 그 둘이 같은 결과를 내는 것이 이 저장소가 세 번 밟은
# 형태다. 양성 대조는 모델 없이 도므로 **갓 clone 한 사람에게도 뜻이 있다.**
rtl-postformal:
	@test -d $(RTL_DIR)/formal/sby || { echo "rtl-postformal: sby 스크립트가 없다 — 미측정은 통과가 아니다"; exit 1; }
	@rm -rf $(SBY_OUT); mkdir -p $(SBY_OUT)
	@podman run --rm --userns=keep-id -v "$(CURDIR):/workspace" -v "$(SBY_OUT):/sbyout" \
	   wavetensor-dev:scala sh -lc "cd /workspace && sh scripts/sby_sweep.sh"
	@python3 $(CURDIR)/scripts/lint_postformal.py --require-fresh
	@SBY_OUT=$(SBY_OUT) python3 $(CURDIR)/scripts/lint_tautology.py \
	   --audit --require-models

# 후-formal 영향 역색인 — 「이 변경으로 어느 태스크가 흔들리는가」.
#
# 2026-08-25 에 실제로 놓친 회귀가 근거다. MmioConfig 를 고친 담당자가 그
# 모듈의 두 태스크만 돌리고, 그것을 *인스턴스하는* 합성 증명 RouteMmio 를
# 돌리지 않아 하네스가 옛 「성공」 정의를 든 채 커밋됐다. basecase 는 통과하고
# induction 만 깨져서 얕은 확인으로는 보이지 않았다. 뒤이은 검증자도 「이번
# 파도가 바꾼 파일」만 대조해 그것을 선재 결함으로 오분류했다.
#
# 둘 다 성실했고 둘 다 놓쳤다 — 역색인을 매번 사람이 머리로 짜야 했기 때문이다.
# rtl-postformal 전수 실행이 최종 그물이지만 50분+ 걸리므로, 작업 중에는
# 이 타깃으로 좁혀 돌리고 커밋 전에 전수를 돌린다.
rtl-impact:
	@python3 $(CURDIR)/scripts/sby_impact.py

# 재구현 하네스 — 자립형 cocotb 러너.
rtl-sim:
	@if [ -f $(RTL_DIR)/sim/run_wt64.py ]; then \
	    python3 $(RTL_DIR)/sim/run_wt64.py; \
	else \
	    echo "rtl-sim: 하네스가 아직 없다 (단계 2 미착수) — 미측정."; \
	    exit 1; \
	fi

# 생성물이 아니라 **빌드 산출물**만 지운다. rtl/generated/ 는 tracked 이므로
# 건드리지 않는다 (`synth-clean` 이 tracked 증적을 지우던 사고의 재발 방지).
rtl-clean:
	rm -rf $(RTL_SPINAL)/target $(RTL_SPINAL)/project/target $(RTL_SPINAL)/project/project

# =============================================================================
# Git 훅 설치 — `.git/hooks/` 는 추적되지 않으므로 훅을 거기에만 두면
# "내 머신에서만 돈다" 가 된다. 정본은 `scripts/hooks/` 이고 설치는 절차다.
#
# 정본 부록 B.3 이 "커밋 훅은 무조건 성공을 반환하고 CI 는 없다" 를
# **재구현이 반드시 고쳐야 할 것**으로 분류했다.
# =============================================================================

.PHONY: hooks-install hooks-check

# =============================================================================
# 정본 컴파일 + 렌더 검사 — 정본을 컴파일하는 정규 진입점.
#
# raw `typst compile` 을 직접 부르면 렌더 검사가 빠진다. 부록 B.5 표가 73쪽으로
# 부풀어 있는 동안 「컴파일 OK · N쪽」 만 반복 보고된 사고의 재발 방지다 —
# 컴파일 성공과 렌더링 정상은 다른 명제다.
guide:
	cd $(CURDIR)/docs/wt64v1-architecture-guide && typst compile main.typ
	python3 $(CURDIR)/scripts/check_guide_render.py

hooks-install:
	@install -m 0755 $(CURDIR)/scripts/hooks/pre-commit $(CURDIR)/.git/hooks/pre-commit
	@echo "hooks-install: .git/hooks/pre-commit ← scripts/hooks/pre-commit"
	@$(MAKE) --no-print-directory hooks-check

# 설치된 훅이 정본과 같은지 — 그리고 **실제로 막는 훅인지**.
# 무조건 exit 0 하는 훅이 설치돼 있으면 그 사실을 크게 알린다.
hooks-check:
	@if [ ! -x $(CURDIR)/.git/hooks/pre-commit ]; then \
	    echo "hooks-check: ⛔ pre-commit 훅이 설치돼 있지 않다 → make hooks-install"; exit 1; \
	fi
	@if ! cmp -s $(CURDIR)/scripts/hooks/pre-commit $(CURDIR)/.git/hooks/pre-commit; then \
	    echo "hooks-check: ⛔ 설치된 훅이 scripts/hooks/pre-commit 과 다르다 → make hooks-install"; exit 1; \
	fi
	@echo "hooks-check: OK — 설치된 훅이 정본과 일치한다"
