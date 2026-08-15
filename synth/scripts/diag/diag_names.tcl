# DIAGNOSTIC ONLY — 출하 FP_AccLattice_gate_top 재-synth 후 LUT cell 이름 dump
# (스테이지 귀속의 flat-netlist 교차검증용; GATE 실측 run 과 동일 플래그)
set REPO /home/ybi/WaveTensor
create_project -in_memory -part xcu55c-fsvh2892-2L-e
read_verilog $REPO/FP_AccLattice.v
read_verilog $REPO/synth/lattice/fp_ops/FP_AccLattice_gate_top.v
read_xdc $REPO/synth/reports/fp_ops/fp_acclattice_gate.xdc

synth_design -top FP_AccLattice_gate_top \
             -part xcu55c-fsvh2892-2L-e \
             -mode out_of_context \
             -include_dirs $REPO/include \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -flatten_hierarchy none

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
