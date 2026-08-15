# DIAGNOSTIC ONLY — GATE V20-2 LUT 귀속: 스테이지 hierarchy synth (OOC, synth-only)
set RPT_DIR /home/ybi/WaveTensor/synth/reports/fp_ops
create_project -in_memory -part xcu55c-fsvh2892-2L-e
read_verilog /tmp/wt_diag/fp_acclattice_diag_stages.v

set xdc_file /tmp/wt_diag/diag_stages.xdc
set fh [open $xdc_file w]
puts $fh "create_clock -name clk -period 10.000 \[get_ports clk\]"
close $fh
read_xdc $xdc_file

synth_design -top fp_acclattice_diag_stages_top \
             -part xcu55c-fsvh2892-2L-e \
             -mode out_of_context \
             -flatten_hierarchy none

report_utilization -file $RPT_DIR/fp_acclattice_diag_stages_util.rpt -hierarchical
report_timing_summary -file $RPT_DIR/fp_acclattice_diag_stages_timing.rpt

# CARRY8 per-module 집계 (ternary 실험 판단용)
set fh [open $RPT_DIR/fp_acclattice_diag_stages_carry.txt w]
foreach m {u_tree u_resolve u_extract u_encode u_ncnt u_x_ternary} {
    set n [llength [get_cells -quiet -hierarchical -filter "REF_NAME =~ {CARRY*} && NAME =~ {$m/*}"]]
    puts $fh "$m CARRY=$n"
}
set np 0
for {set i 0} {$i < 33} {incr i} {
    incr np [llength [get_cells -quiet -hierarchical -filter "REF_NAME =~ {CARRY*} && NAME =~ {g_place\[$i\].u_place/*}"]]
}
puts $fh "place_all CARRY=$np"
puts $fh "total CARRY=[llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ CARRY*}]]"
close $fh
exit 0
