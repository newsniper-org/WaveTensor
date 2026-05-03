# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# common.tcl — shared procedures and source-file lists for WaveTensor
# synthesis flows.

# ---- Project layout -----------------------------------------------------
set REPO_ROOT [file normalize [file join [file dirname [info script]] ../..]]
set SYNTH_DIR [file join $REPO_ROOT synth]
set REPORT_DIR [file join $SYNTH_DIR reports]
set CKPT_DIR  [file join $SYNTH_DIR checkpoints]
set XDC_FILE  [file join $SYNTH_DIR constraints pod.xdc]

file mkdir $REPORT_DIR
file mkdir $CKPT_DIR

# ---- Target part --------------------------------------------------------
# Default target: ALINX AXU3EGB V2.1 (Zynq UltraScale+ XCZU3EG, package
# SFVC784, speed -1, industrial -I). Override at invocation time with
# `vivado -tclargs PART=<other>` for smoke-tests on different devices.
if {![info exists ::PART]} {
    set ::PART "xczu3eg-sfvc784-1-i"
}

# ---- Default geometry --------------------------------------------------
# 2x2 PE/Cluster x 2x2 Cluster/Pod = 16 PE/Pod (debug-scale default).
foreach {var def} {PE_ROWS 2 PE_COLS 2 CLUSTER_ROWS 2 CLUSTER_COLS 2} {
    if {[info exists ::env($var)]} {
        set ::$var $::env($var)
    } else {
        set ::$var $def
    }
}

# ---- Verilog source list (Pod top) -------------------------------------
set ::POD_SOURCES [list \
    [file join $REPO_ROOT Pod.v] \
    [file join $REPO_ROOT Cluster.v] \
    [file join $REPO_ROOT PE.v] \
    [file join $REPO_ROOT ISA_Decoder.v] \
    [file join $REPO_ROOT EHDecode.v] \
    [file join $REPO_ROOT PE_Core.v] \
]

# ---- Helpers ------------------------------------------------------------
proc print_banner {msg} {
    puts ""
    puts "================================================================"
    puts "  $msg"
    puts "================================================================"
}

proc dump_summary {tag} {
    print_banner "Geometry summary ($tag)"
    puts "  Target part         : $::PART"
    puts "  PE_ROWS x PE_COLS   : $::PE_ROWS x $::PE_COLS"
    puts "  CLUSTER_ROWS x COLS : $::CLUSTER_ROWS x $::CLUSTER_COLS"
    puts "  Total PE count      : [expr {$::PE_ROWS * $::PE_COLS \
                                       * $::CLUSTER_ROWS * $::CLUSTER_COLS}]"
    puts ""
}
