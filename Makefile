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
# 선두의 sha256 provenance 를 현행 소스와 대조한다. 어느 한쪽만으로는 부족
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
#   * 잊으면  → provenance sha256 이 어긋나 `fp_op_gate_check` 가 STALE FAIL.
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
# All six are stdlib-only Python; runnable directly without cocotb:
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
