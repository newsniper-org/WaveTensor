// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// attributes.vh — vendor-agnostic wrappers for synthesis attributes
//
// Some RTL nets and registers carry vendor-specific attributes that control
// optimizer behavior:
//
//   (* keep = "true" *)         — keep this net through synthesis / opt
//   (* dont_touch = "true" *)   — same, stronger form (survives opt-through-hierarchy)
//   (* use_dsp = "yes" *)       — hint to infer a DSP block for this mul/mac
//
// The keep / dont_touch pair is CRITICAL for the HIU TRNG ring oscillators:
// without them the optimizer prunes the ROs as combinational loops with no
// meaningful output, breaking entropy. `use_dsp` is a soft hint that maps
// multiplications to DSP blocks; on Lattice / yosys / Radiant the mapper
// usually chooses correctly on its own.
//
// This header defines vendor-neutral names. Pass one of these on the
// command line at synthesis invocation:
//
//   Vivado (Xilinx / AMD):    +define+WT_VENDOR_VIVADO
//   yosys + nextpnr-ecp5:     -DWT_VENDOR_LATTICE_YOSYS
//   Lattice Radiant (Nexus/CertusPro-NX/Avant): -define WT_VENDOR_LATTICE_RADIANT
//
// If no vendor is defined, expansions are empty (safe default — some tools
// silently ignore unknown attributes; use of the macros makes the intent
// explicit and the vendor mapping traceable).

`ifndef WT_ATTRIBUTES_VH
`define WT_ATTRIBUTES_VH

`ifdef WT_VENDOR_VIVADO
    // Xilinx / Vivado — native syntax
    `define WT_KEEP        (* keep = "true" *)
    `define WT_DONT_TOUCH  (* dont_touch = "true" *)
    `define WT_USE_DSP     (* use_dsp = "yes" *)

`elsif WT_VENDOR_LATTICE_YOSYS
    // yosys understands `(* keep = "true" *)` and `(* keep *)` natively as the
    // opt-preserve marker. There is no dont_touch — keep alone is sufficient
    // through the yosys pipeline. use_dsp is a no-op (yosys' techmap infers
    // DSPs automatically per target device library).
    `define WT_KEEP        (* keep = "true" *)
    `define WT_DONT_TOUCH  (* keep = "true" *)
    `define WT_USE_DSP     // no-op

`elsif WT_VENDOR_LATTICE_RADIANT
    // Lattice Radiant Synplify Pro syntax (per Lattice AN synth attributes).
    `define WT_KEEP        (* syn_keep = 1 *)
    `define WT_DONT_TOUCH  (* syn_noprune = 1 *)
    `define WT_USE_DSP     (* syn_multstyle = "dsp" *)

`else
    // Unknown / undefined vendor — no attribute expansion.
    // NOTE: this default is UNSAFE for the TRNG oscillator rings — they will
    //       likely be pruned. Always define one of the vendor macros above at
    //       synthesis invocation. Simulation flows (verilator / iverilog) can
    //       leave the vendor undefined since they do not optimize combinational
    //       loops the way synthesis does.
    `define WT_KEEP
    `define WT_DONT_TOUCH
    `define WT_USE_DSP
`endif

`endif // WT_ATTRIBUTES_VH
