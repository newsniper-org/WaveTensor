# FROZEN — 수정 금지. 진단 전용 하네스 (GATE 미등재).
#
# 2026-08-15 GATE V20-2 FAIL 원인 진단 (R3) 의 재현 스크립트다: 출하
# FP_AccLattice_gate_top 을 재-synth 해 전 LUT cell 이름을 dump 하고,
# `classify_luts.py` 가 이름-cone 으로 스테이지에 귀속시킨다. 산출물은
# spec `.claude-memos/wt64v1_spec.md` §27.6 이 인용하는 규범적 증적
# (`synth/reports/fp_ops/fp_acclattice_diag_flat_attribution.txt`).
#
# 입력은 **저장소 루트의 살아 있는 RTL 이 아니라** frozen/ 의 고정본을
# 읽는다. 2026-08-16 커밋 cddb4d1 이 FP_AccLattice 를 beat-serial 로
# 재작성하면서 `classify_luts.py` 의 이름 규칙이 현행 RTL 에 0건이 됐고,
# 살아 있는 RTL 을 가리킨 채로 두면 하네스는 돌아가되 **조용히 틀린 답**
# (전부 OTHER)을 낸다. 고정 리비전과 기준 수치는 frozen/PROVENANCE.txt 참조.
#
# 현행 RTL 분류가 필요하면 이 파일을 고치지 말고 별도 하네스를 만들어라.

set REPO /home/ybi/WaveTensor
set FROZEN $REPO/synth/scripts/diag/frozen

create_project -in_memory -part xcu55c-fsvh2892-2L-e
read_verilog $FROZEN/FP_AccLattice.v
read_verilog $FROZEN/FP_AccLattice_gate_top.v
read_xdc     $FROZEN/fp_acclattice_gate.xdc

synth_design -top FP_AccLattice_gate_top \
             -part xcu55c-fsvh2892-2L-e \
             -mode out_of_context \
             -include_dirs $REPO/include \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -flatten_hierarchy none

file mkdir /tmp/wt_diag
set fh [open /tmp/wt_diag/lutcells.txt w]
foreach c [get_cells -hierarchical -filter {REF_NAME =~ LUT?}] {
    puts $fh "[get_property REF_NAME $c] $c"
}
close $fh
set fh [open /tmp/wt_diag/carrycells.txt w]
foreach c [get_cells -hierarchical -filter {REF_NAME =~ CARRY*}] {
    puts $fh "[get_property REF_NAME $c] $c"
}
close $fh
exit 0
