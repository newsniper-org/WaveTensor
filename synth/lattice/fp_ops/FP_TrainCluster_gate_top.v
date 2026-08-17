// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_TrainCluster_gate_top.v — GATE V20-3 wrapper (spec §27.6 "④ GATE
// V20-3 기준 선공표" — v2.0 TRAIN full-cluster datapath gate, dual-fabric;
// merge-blocker binding 은 xcu55c 반쪽에만 있고 ECP5 반쪽은 MEASUREMENT).
//
// FP_AccLattice_gate_top.v / FP_FmaLaneBf16_gate_top.v 와 동일한 규약:
// 전 입력/출력을 정확히 1회 등록해, out-of-context run 이 재는 모든
// timing path 가 통합체의 실제 FF-to-FF path 가 되게 한다. wrapper 는
// flop 만 더한다 — LUT 기여 ~0 이므로 리포트의 LUT 수는 정직한 (보수적)
// core 수치다.
//
// Wrapper I/O flop = 432: 입력 140 (srst 1 + ld 38 + wave 12 + cmd 83 +
// dbg_slot 6) + 출력 292 (bank 응답/관측 103 + clu_reject 1 + lattice 관측
// 97 + fault 집약 22 + dbg 69). FF 는 GATE V20-3 에서 추적만 한다 (V9-4
// 관례) — binding 은 LUT ceiling / DSP·premap $mul / BRAM / DRC 만.
//
// 같은 wrapper 를 ECP5 MEASUREMENT 반쪽과 xcu55c 반쪽이 공유해 두 fabric
// 이 동일한 netlist boundary 를 재는 fp_ops 관례를 따른다.

module FP_TrainCluster_gate_top (
    input             clk,

    input             srst_i,

    input             ld_v_i,
    input      [4:0]  ld_idx_i,
    input      [15:0] ld_a_i,
    input      [15:0] ld_b_i,

    input             wave_v_i,
    input             wave_dtype_bf16_i,
    input      [3:0]  wave_stream_i,
    input      [5:0]  wave_slot_i,

    input             cmd_v_i,
    input      [2:0]  cmd_op_i,
    input      [3:0]  cmd_stream_i,
    input      [5:0]  cmd_slot_i,
    input      [63:0] cmd_word_i,
    input             cmd_tag_v_i,
    input      [3:0]  cmd_tag_i,

    input      [5:0]  dbg_slot_i,

    output reg        resp_v_o,
    output reg        resp_refused_o,
    output reg        resp_vfault_o,
    output reg        acq_v_o,
    output reg        acq_reject_o,
    output reg        drain_v_o,
    output reg [31:0] drain_o,
    output reg        spill_v_o,
    output reg [63:0] spill_o,

    output reg        clu_reject_o,

    output reg        lat_done_o,
    output reg [63:0] lat_wide_o,
    output reg [31:0] lat_fp32_o,

    output reg [6:0]  clu_fault_causes_o,
    output reg [13:0] bank_fault_causes_o,
    output reg        fault_o,

    output reg [63:0] dbg_word_o,
    output reg        dbg_owner_v_o,
    output reg [3:0]  dbg_owner_o
);

    // ---- 입력 등록 (140 flops) ----
    reg        srst_q;
    reg        ld_v_q;
    reg [4:0]  ld_idx_q;
    reg [15:0] ld_a_q, ld_b_q;
    reg        wave_v_q, wave_dt_q;
    reg [3:0]  wave_stream_q;
    reg [5:0]  wave_slot_q;
    reg        cmd_v_q;
    reg [2:0]  cmd_op_q;
    reg [3:0]  cmd_stream_q;
    reg [5:0]  cmd_slot_q;
    reg [63:0] cmd_word_q;
    reg        cmd_tag_v_q;
    reg [3:0]  cmd_tag_q;
    reg [5:0]  dbg_slot_q;

    wire        resp_v_w, resp_refused_w, resp_vfault_w;
    wire        acq_v_w, acq_reject_w;
    wire        drain_v_w;
    wire [31:0] drain_w;
    wire        spill_v_w;
    wire [63:0] spill_w;
    wire        clu_reject_w;
    wire        lat_done_w;
    wire [63:0] lat_wide_w;
    wire [31:0] lat_fp32_w;
    wire [6:0]  clu_causes_w;
    wire [13:0] bank_causes_w;
    wire        fault_w;
    wire [63:0] dbg_word_w;
    wire        dbg_owner_v_w;
    wire [3:0]  dbg_owner_w;

    always @(posedge clk) begin
        srst_q        <= srst_i;
        ld_v_q        <= ld_v_i;
        ld_idx_q      <= ld_idx_i;
        ld_a_q        <= ld_a_i;
        ld_b_q        <= ld_b_i;
        wave_v_q      <= wave_v_i;
        wave_dt_q     <= wave_dtype_bf16_i;
        wave_stream_q <= wave_stream_i;
        wave_slot_q   <= wave_slot_i;
        cmd_v_q       <= cmd_v_i;
        cmd_op_q      <= cmd_op_i;
        cmd_stream_q  <= cmd_stream_i;
        cmd_slot_q    <= cmd_slot_i;
        cmd_word_q    <= cmd_word_i;
        cmd_tag_v_q   <= cmd_tag_v_i;
        cmd_tag_q     <= cmd_tag_i;
        dbg_slot_q    <= dbg_slot_i;

        // ---- 출력 등록 (292 flops) ----
        resp_v_o            <= resp_v_w;
        resp_refused_o      <= resp_refused_w;
        resp_vfault_o       <= resp_vfault_w;
        acq_v_o             <= acq_v_w;
        acq_reject_o        <= acq_reject_w;
        drain_v_o           <= drain_v_w;
        drain_o             <= drain_w;
        spill_v_o           <= spill_v_w;
        spill_o             <= spill_w;
        clu_reject_o        <= clu_reject_w;
        lat_done_o          <= lat_done_w;
        lat_wide_o          <= lat_wide_w;
        lat_fp32_o          <= lat_fp32_w;
        clu_fault_causes_o  <= clu_causes_w;
        bank_fault_causes_o <= bank_causes_w;
        fault_o             <= fault_w;
        dbg_word_o          <= dbg_word_w;
        dbg_owner_v_o       <= dbg_owner_v_w;
        dbg_owner_o         <= dbg_owner_w;
    end

    FP_TrainCluster u_core (
        .clk                 (clk),
        .srst_i              (srst_q),
        .ld_v_i              (ld_v_q),
        .ld_idx_i            (ld_idx_q),
        .ld_a_i              (ld_a_q),
        .ld_b_i              (ld_b_q),
        .wave_v_i            (wave_v_q),
        .wave_dtype_bf16_i   (wave_dt_q),
        .wave_stream_i       (wave_stream_q),
        .wave_slot_i         (wave_slot_q),
        .cmd_v_i             (cmd_v_q),
        .cmd_op_i            (cmd_op_q),
        .cmd_stream_i        (cmd_stream_q),
        .cmd_slot_i          (cmd_slot_q),
        .cmd_word_i          (cmd_word_q),
        .cmd_tag_v_i         (cmd_tag_v_q),
        .cmd_tag_i           (cmd_tag_q),
        .resp_v_o            (resp_v_w),
        .resp_refused_o      (resp_refused_w),
        .resp_vfault_o       (resp_vfault_w),
        .acq_v_o             (acq_v_w),
        .acq_reject_o        (acq_reject_w),
        .drain_v_o           (drain_v_w),
        .drain_o             (drain_w),
        .spill_v_o           (spill_v_w),
        .spill_o             (spill_w),
        .clu_reject_q        (clu_reject_w),
        .lat_done_o          (lat_done_w),
        .lat_wide_o          (lat_wide_w),
        .lat_fp32_o          (lat_fp32_w),
        .clu_fault_causes_o  (clu_causes_w),
        .bank_fault_causes_o (bank_causes_w),
        .fault_o             (fault_w),
        .dbg_slot_i          (dbg_slot_q),
        .dbg_word_o          (dbg_word_w),
        .dbg_owner_v_o       (dbg_owner_v_w),
        .dbg_owner_o         (dbg_owner_w)
    );

endmodule
