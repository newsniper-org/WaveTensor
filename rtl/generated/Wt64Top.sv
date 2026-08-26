// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : Wt64Top
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module Wt64Top (
  input  wire          io_instr_valid,
  input  wire [31:0]   io_instr_words_0,
  input  wire [31:0]   io_instr_words_1,
  input  wire [31:0]   io_instr_words_2,
  input  wire [31:0]   io_instr_words_3,
  input  wire [31:0]   io_instr_words_4,
  input  wire [31:0]   io_instr_words_5,
  input  wire [31:0]   io_instr_words_6,
  input  wire [31:0]   io_instr_words_7,
  input  wire [31:0]   io_instr_words_8,
  input  wire [31:0]   io_instr_words_9,
  input  wire [31:0]   io_instr_words_10,
  input  wire [31:0]   io_instr_words_11,
  input  wire [31:0]   io_instr_words_12,
  input  wire [31:0]   io_instr_tag_wave,
  input  wire [15:0]   io_instr_tag_thread,
  input  wire [15:0]   io_instr_tag_lnid,
  input  wire [7:0]    io_instr_tag_precision,
  input  wire [7:0]    io_instr_tag_dim,
  output wire          io_dec_valid,
  output wire          io_dec_malformed,
  output wire          io_dec_capAbsent,
  output wire          io_dec_execValid,
  output wire          io_dec_portPresent,
  output wire [15:0]   io_dec_portDest,
  output wire          io_dec_imm16Present,
  output wire [15:0]   io_dec_imm16,
  output wire          io_dec_imm32Present,
  output wire [31:0]   io_dec_imm32,
  output wire          io_dec_imm64Present,
  output wire [63:0]   io_dec_imm64,
  output wire          io_dec_memPresent,
  output wire          io_dec_subValid_0,
  output wire          io_dec_subValid_1,
  output wire          io_dec_subValid_2,
  output wire          io_dec_subValid_3,
  output wire [15:0]   io_dec_subO_0,
  output wire [15:0]   io_dec_subO_1,
  output wire [15:0]   io_dec_subO_2,
  output wire [15:0]   io_dec_subO_3,
  output wire [15:0]   io_dec_subA_0,
  output wire [15:0]   io_dec_subA_1,
  output wire [15:0]   io_dec_subA_2,
  output wire [15:0]   io_dec_subA_3,
  output wire [15:0]   io_dec_subB_0,
  output wire [15:0]   io_dec_subB_1,
  output wire [15:0]   io_dec_subB_2,
  output wire [15:0]   io_dec_subB_3,
  output wire [2:0]    io_dec_subCount,
  output wire          io_dec_oprefAValid,
  output wire          io_dec_oprefBValid,
  output wire [7:0]    io_dec_oprefBLbid,
  output wire [3:0]    io_dec_oprefBSrcKind,
  output wire          io_dec_precPresent,
  output wire [7:0]    io_dec_precMode,
  output wire [7:0]    io_dec_precDim,
  output wire          io_route_tokOut_valid,
  output wire [31:0]   io_route_tokOut_payload_tag_wave,
  output wire [15:0]   io_route_tokOut_payload_tag_thread,
  output wire [15:0]   io_route_tokOut_payload_tag_lnid,
  output wire [7:0]    io_route_tokOut_payload_tag_precision,
  output wire [7:0]    io_route_tokOut_payload_tag_dim,
  output wire [7:0]    io_route_tokOut_payload_lbid,
  output wire [3:0]    io_route_tokOut_payload_srcKind,
  output wire          io_route_faultFire,
  output wire          io_reasmOpenGranted,
  output wire          io_reasmWr_valid,
  output wire [7:0]    io_reasmWr_base,
  output wire [3:0]    io_reasmWr_off,
  output wire [63:0]   io_reasmWr_body,
  output wire          io_reasmClr_valid,
  output wire [7:0]    io_reasmClr_base,
  input  wire [2:0]    io_mem_cfgPreds_0,
  input  wire [2:0]    io_mem_cfgPreds_1,
  input  wire [2:0]    io_mem_cfgPreds_2,
  input  wire [2:0]    io_mem_cfgPreds_3,
  input  wire          io_mem_epochClear,
  input  wire [3:0]    io_mem_complete,
  input  wire [1:0]    io_mem_slotSel,
  output reg  [3:0]    io_mem_upReady,
  output wire          io_mem_down_0_valid,
  input  wire          io_mem_down_0_ready,
  output wire [127:0]  io_mem_down_0_payload,
  output wire          io_mem_down_1_valid,
  input  wire          io_mem_down_1_ready,
  output wire [127:0]  io_mem_down_1_payload,
  output wire          io_mem_down_2_valid,
  input  wire          io_mem_down_2_ready,
  output wire [127:0]  io_mem_down_2_payload,
  output wire          io_mem_down_3_valid,
  input  wire          io_mem_down_3_ready,
  output wire [127:0]  io_mem_down_3_payload,
  output wire [3:0]    io_mem_token,
  output wire [3:0]    io_mem_gateOpen,
  input  wire          io_hiuReq_valid,
  output wire          io_hiuReq_ready,
  input  wire [1:0]    io_hiuReq_part,
  input  wire [31:0]   io_hiuReq_vpn,
  input  wire          io_hiuReq_write,
  input  wire          io_hiuHold,
  input  wire          io_install_valid,
  output wire          io_install_ready,
  input  wire [1:0]    io_install_part,
  input  wire [3:0]    io_install_idx,
  input  wire [27:0]   io_install_tag,
  input  wire [31:0]   io_install_frame,
  input  wire          io_install_perm_r,
  input  wire          io_install_perm_w,
  input  wire          io_install_perm_x,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  input  wire          io_hostRsp_valid,
  input  wire [31:0]   io_hostRsp_frame,
  input  wire          io_hostRsp_perm_r,
  input  wire          io_hostRsp_perm_w,
  input  wire          io_hostRsp_perm_x,
  output wire          io_hiuRsp_valid,
  output wire          io_hiuRsp_granted,
  output wire [1:0]    io_hiuRsp_part,
  output wire          io_hiuRsp_write,
  output wire          io_hiuRsp_fromFill,
  output wire          io_hiuRsp_perm_r,
  output wire          io_hiuRsp_perm_w,
  output wire          io_hiuRsp_perm_x,
  output wire          io_phys_valid,
  output wire [31:0]   io_phys_frame,
  input  wire          io_push_0_strb,
  input  wire [31:0]   io_push_0_result_head_tag_wave,
  input  wire [15:0]   io_push_0_result_head_tag_thread,
  input  wire [15:0]   io_push_0_result_head_tag_lnid,
  input  wire [7:0]    io_push_0_result_head_tag_precision,
  input  wire [7:0]    io_push_0_result_head_tag_dim,
  input  wire [7:0]    io_push_0_result_head_seq,
  input  wire [7:0]    io_push_0_result_head_total,
  input  wire          io_push_0_result_head_last,
  input  wire [63:0]   io_push_0_result_body,
  output wire          io_push_0_stall,
  input  wire          io_push_1_strb,
  input  wire [31:0]   io_push_1_result_head_tag_wave,
  input  wire [15:0]   io_push_1_result_head_tag_thread,
  input  wire [15:0]   io_push_1_result_head_tag_lnid,
  input  wire [7:0]    io_push_1_result_head_tag_precision,
  input  wire [7:0]    io_push_1_result_head_tag_dim,
  input  wire [7:0]    io_push_1_result_head_seq,
  input  wire [7:0]    io_push_1_result_head_total,
  input  wire          io_push_1_result_head_last,
  input  wire [63:0]   io_push_1_result_body,
  output wire          io_push_1_stall,
  input  wire          io_push_2_strb,
  input  wire [31:0]   io_push_2_result_head_tag_wave,
  input  wire [15:0]   io_push_2_result_head_tag_thread,
  input  wire [15:0]   io_push_2_result_head_tag_lnid,
  input  wire [7:0]    io_push_2_result_head_tag_precision,
  input  wire [7:0]    io_push_2_result_head_tag_dim,
  input  wire [7:0]    io_push_2_result_head_seq,
  input  wire [7:0]    io_push_2_result_head_total,
  input  wire          io_push_2_result_head_last,
  input  wire [63:0]   io_push_2_result_body,
  output wire          io_push_2_stall,
  input  wire          io_sharedReq_valid,
  input  wire [160:0]  io_sharedReq_payload,
  output wire          io_sharedReq_ready,
  output wire          io_sharedPushStall,
  input  wire          io_bank_acqValid,
  input  wire [3:0]    io_bank_acqSlot,
  input  wire [3:0]    io_bank_acqProd,
  output wire          io_bank_acqGranted,
  input  wire          io_bank_wrValid,
  input  wire [3:0]    io_bank_wrSlot,
  input  wire [3:0]    io_bank_wrProd,
  input  wire [63:0]   io_bank_wrData,
  input  wire [3:0]    io_bank_rdSlot,
  output wire [63:0]   io_bank_rdData,
  output wire          io_bank_rdOwned,
  input  wire          io_fp_reqValid,
  input  wire [7:0]    io_fp_opKind,
  input  wire [7:0]    io_fp_precision,
  input  wire [31:0]   io_fp_a,
  input  wire [31:0]   io_fp_b,
  input  wire [31:0]   io_fp_c,
  output wire          io_fp_reqReady,
  output wire          io_fp_done,
  output wire          io_fp_execValid,
  output wire          io_fp_capAbsent,
  output wire          io_fp_progMal,
  output wire [31:0]   io_fp_result,
  input  wire [11:0]   io_mmio_addr,
  input  wire          io_mmio_wstrobe,
  input  wire [31:0]   io_mmio_wdata,
  input  wire          io_mmio_rstrobe,
  output reg  [31:0]   io_mmio_rdata,
  output wire          io_mmio_rvalid,
  output reg           io_mmio_ready,
  output wire          io_irq,
  output wire          io_fault_decodeWalk,
  output wire          io_fault_operandDecode,
  output wire          io_fault_route,
  output wire          io_fault_reasm,
  output wire          io_fault_reasmCap,
  output wire          io_fault_hiuPerm,
  output wire          io_fault_hiuMiss,
  output wire          io_fault_cfgDupOwner,
  output wire          io_fault_cfgBadWrite,
  output wire          io_fault_cfgSurfBadWrite,
  output wire          io_fault_ownCollide,
  output wire          io_fault_ownBadWrite,
  output wire          io_fault_fabricBp,
  output wire          io_fault_sharedBp,
  output wire          io_fault_bankWrite,
  output wire          io_fault_maskNoMask,
  output wire          io_fault_maskNonceDup,
  output wire          io_fault_maskWrRekey,
  output wire          io_fault_fpBp,
  output wire          io_fault_fpBadProg,
  output wire          io_fault_fpCapAbsent,
  output wire          io_fault_cqOverflow,
  output wire          io_fault_cqBadWrite,
  input  wire          io_faultClear_decodeWalk,
  input  wire          io_faultClear_operandDecode,
  input  wire          io_faultClear_route,
  input  wire          io_faultClear_reasm,
  input  wire          io_faultClear_reasmCap,
  input  wire          io_faultClear_hiuPerm,
  input  wire          io_faultClear_hiuMiss,
  input  wire          io_faultClear_cfgDupOwner,
  input  wire          io_faultClear_cfgBadWrite,
  input  wire          io_faultClear_cfgSurfBadWrite,
  input  wire          io_faultClear_ownCollide,
  input  wire          io_faultClear_fabricBp,
  input  wire          io_faultClear_sharedBp,
  input  wire          io_faultClear_bankWrite,
  input  wire          io_faultClear_maskNoMask,
  input  wire          io_faultClear_maskNonceDup,
  input  wire          io_faultClear_maskWrRekey,
  input  wire          io_faultClear_fpBp,
  input  wire          io_faultClear_fpBadProg,
  input  wire          clk,
  input  wire          reset
);

  wire                walk_io_iFaultClear;
  wire                od_io_iFaultClear;
  wire                rj_io_faultClear;
  wire                reasm_io_faultClear;
  wire                reasm_io_capAbsentClear;
  wire                mog_io_up_0_valid;
  wire       [127:0]  mog_io_up_0_payload;
  wire                mog_io_up_1_valid;
  wire       [127:0]  mog_io_up_1_payload;
  wire                mog_io_up_2_valid;
  wire       [127:0]  mog_io_up_2_payload;
  wire                mog_io_up_3_valid;
  wire       [127:0]  mog_io_up_3_payload;
  wire                hiu_io_faultClear;
  wire                own_io_wstrobe;
  wire                own_io_rstrobe;
  wire                own_io_faultClearCollide;
  wire                own_io_faultClearBadWrite;
  wire                cfgBlk_io_wstrobe;
  wire                cfgBlk_io_rstrobe;
  wire                cfgBlk_io_faultClearDup;
  wire                cfgBlk_io_faultClearBad;
  wire                merge_io_faultClear;
  wire       [31:0]   merge_io_push_0_result_head_tag_wave;
  wire       [15:0]   merge_io_push_0_result_head_tag_thread;
  wire       [15:0]   merge_io_push_0_result_head_tag_lnid;
  wire       [7:0]    merge_io_push_0_result_head_tag_precision;
  wire       [7:0]    merge_io_push_0_result_head_tag_dim;
  wire       [7:0]    merge_io_push_0_result_head_seq;
  wire       [7:0]    merge_io_push_0_result_head_total;
  wire                merge_io_push_0_result_head_last;
  wire       [63:0]   merge_io_push_0_result_body;
  wire                shared_1_io_faultClear;
  wire                bank_io_faultClear;
  wire                mask_io_keyWr_valid;
  wire       [2:0]    mask_io_keyWr_idx;
  wire                mask_io_nonceWr_valid;
  wire       [2:0]    mask_io_nonceWr_idx;
  wire                mask_io_rekey_valid;
  wire       [1:0]    mask_io_rekey_part;
  wire                mask_io_faultClearNoMask;
  wire                mask_io_faultClearNonceDup;
  wire                mask_io_faultClearWrRekey;
  wire                fps_io_progWr_valid;
  wire       [7:0]    fps_io_progWr_slot;
  wire       [7:0]    fps_io_progWr_idx;
  wire       [15:0]   fps_io_progWr_step;
  wire                fps_io_bindWr_valid;
  wire       [15:0]   fps_io_bindWr_key;
  wire                fps_io_bindWr_en;
  wire       [7:0]    fps_io_bindWr_slot;
  wire                fps_io_faultClearBp;
  wire                fps_io_faultClearBadProg;
  wire       [7:0]    cq_io_addr;
  wire                cq_io_wstrobe;
  wire                cq_io_rstrobe;
  wire       [15:0]   cq_io_drain_pipe;
  wire       [15:0]   cq_io_drain_pending;
  wire       [15:0]   cq_io_drain_output;
  wire       [15:0]   cq_io_drain_ownSlots;
  wire       [15:0]   cq_io_drain_contexts;
  wire       [15:0]   cq_io_drain_tokens;
  wire                cq_io_faultClearOverflow;
  wire                cq_io_faultClearBadWrite;
  wire                walk_io_oValid;
  wire                walk_io_oMalformed;
  wire                walk_io_oCapAbsent;
  wire                walk_io_oExecValid;
  wire       [31:0]   walk_io_oInstr_0;
  wire       [31:0]   walk_io_oInstr_1;
  wire       [31:0]   walk_io_oInstr_2;
  wire       [31:0]   walk_io_oInstr_3;
  wire       [31:0]   walk_io_oInstr_4;
  wire       [31:0]   walk_io_oInstr_5;
  wire       [31:0]   walk_io_oInstr_6;
  wire       [31:0]   walk_io_oInstr_7;
  wire       [31:0]   walk_io_oInstr_8;
  wire       [31:0]   walk_io_oInstr_9;
  wire       [31:0]   walk_io_oInstr_10;
  wire       [31:0]   walk_io_oInstr_11;
  wire       [31:0]   walk_io_oInstr_12;
  wire                walk_io_oSlotPresent_0;
  wire                walk_io_oSlotPresent_1;
  wire                walk_io_oSlotPresent_2;
  wire                walk_io_oSlotPresent_3;
  wire       [3:0]    walk_io_oSlotCode_0;
  wire       [3:0]    walk_io_oSlotCode_1;
  wire       [3:0]    walk_io_oSlotCode_2;
  wire       [3:0]    walk_io_oSlotCode_3;
  wire       [7:0]    walk_io_oSlotOff_0;
  wire       [7:0]    walk_io_oSlotOff_1;
  wire       [7:0]    walk_io_oSlotOff_2;
  wire       [7:0]    walk_io_oSlotOff_3;
  wire                walk_io_oFault;
  wire                od_io_oValid;
  wire                od_io_oMalformed;
  wire                od_io_oCapAbsent;
  wire                od_io_oExecValid;
  wire                od_io_oPortPresent;
  wire       [15:0]   od_io_oPortDest;
  wire                od_io_oImm16Present;
  wire       [15:0]   od_io_oImm16;
  wire                od_io_oImm32Present;
  wire       [31:0]   od_io_oImm32;
  wire                od_io_oImm64Present;
  wire       [63:0]   od_io_oImm64;
  wire                od_io_oMemPresent;
  wire       [3:0]    od_io_oMemAddrMode;
  wire       [11:0]   od_io_oMemStride;
  wire       [31:0]   od_io_oMemOffset;
  wire                od_io_oSubValid_0;
  wire                od_io_oSubValid_1;
  wire                od_io_oSubValid_2;
  wire                od_io_oSubValid_3;
  wire       [15:0]   od_io_oSubO_0;
  wire       [15:0]   od_io_oSubO_1;
  wire       [15:0]   od_io_oSubO_2;
  wire       [15:0]   od_io_oSubO_3;
  wire       [15:0]   od_io_oSubA_0;
  wire       [15:0]   od_io_oSubA_1;
  wire       [15:0]   od_io_oSubA_2;
  wire       [15:0]   od_io_oSubA_3;
  wire       [15:0]   od_io_oSubB_0;
  wire       [15:0]   od_io_oSubB_1;
  wire       [15:0]   od_io_oSubB_2;
  wire       [15:0]   od_io_oSubB_3;
  wire       [2:0]    od_io_oSubCount;
  wire                od_io_oOprefAValid;
  wire       [7:0]    od_io_oOprefALbid;
  wire       [3:0]    od_io_oOprefASrcKind;
  wire                od_io_oOprefBValid;
  wire       [7:0]    od_io_oOprefBLbid;
  wire       [3:0]    od_io_oOprefBSrcKind;
  wire                od_io_oPrecPresent;
  wire       [7:0]    od_io_oPrecMode;
  wire       [7:0]    od_io_oPrecDim;
  wire                od_io_oReasmBind_valid;
  wire       [7:0]    od_io_oReasmBind_payload;
  wire                od_io_oFault;
  wire                rj_io_tokOut_valid;
  wire       [31:0]   rj_io_tokOut_payload_tag_wave;
  wire       [15:0]   rj_io_tokOut_payload_tag_thread;
  wire       [15:0]   rj_io_tokOut_payload_tag_lnid;
  wire       [7:0]    rj_io_tokOut_payload_tag_precision;
  wire       [7:0]    rj_io_tokOut_payload_tag_dim;
  wire       [7:0]    rj_io_tokOut_payload_lbid;
  wire       [3:0]    rj_io_tokOut_payload_srcKind;
  wire                rj_io_fault;
  wire                rj_io_faultFire;
  wire                reasm_io_open_granted;
  wire                reasm_io_wr_valid;
  wire       [7:0]    reasm_io_wr_base;
  wire       [3:0]    reasm_io_wr_off;
  wire       [63:0]   reasm_io_wr_body;
  wire                reasm_io_deliver_valid;
  wire       [31:0]   reasm_io_deliver_payload_tag_wave;
  wire       [15:0]   reasm_io_deliver_payload_tag_thread;
  wire       [15:0]   reasm_io_deliver_payload_tag_lnid;
  wire       [7:0]    reasm_io_deliver_payload_tag_precision;
  wire       [7:0]    reasm_io_deliver_payload_tag_dim;
  wire       [7:0]    reasm_io_deliver_payload_base;
  wire       [7:0]    reasm_io_deliver_payload_total;
  wire       [2:0]    reasm_io_incomplete;
  wire       [2:0]    reasm_io_occupancy;
  wire                reasm_io_clr_valid;
  wire       [7:0]    reasm_io_clr_base;
  wire       [7:0]    reasm_io_abortCount;
  wire                reasm_io_fault;
  wire                reasm_io_capAbsent;
  wire                mog_io_up_0_ready;
  wire                mog_io_up_1_ready;
  wire                mog_io_up_2_ready;
  wire                mog_io_up_3_ready;
  wire                mog_io_down_0_valid;
  wire       [127:0]  mog_io_down_0_payload;
  wire                mog_io_down_1_valid;
  wire       [127:0]  mog_io_down_1_payload;
  wire                mog_io_down_2_valid;
  wire       [127:0]  mog_io_down_2_payload;
  wire                mog_io_down_3_valid;
  wire       [127:0]  mog_io_down_3_payload;
  wire       [3:0]    mog_io_token;
  wire       [3:0]    mog_io_gateOpen;
  wire       [2:0]    mog_io_occupancy;
  wire                hiu_io_req_ready;
  wire       [31:0]   hiu_io_owner_frame;
  wire                hiu_io_mask_req_valid;
  wire       [1:0]    hiu_io_mask_req_part;
  wire       [31:0]   hiu_io_mask_req_frame;
  wire                hiu_io_install_ready;
  wire                hiu_io_rsp_valid;
  wire                hiu_io_rsp_granted;
  wire       [1:0]    hiu_io_rsp_part;
  wire                hiu_io_rsp_write;
  wire                hiu_io_rsp_fromFill;
  wire       [31:0]   hiu_io_rsp_frame;
  wire                hiu_io_rsp_perm_r;
  wire                hiu_io_rsp_perm_w;
  wire                hiu_io_rsp_perm_x;
  wire       [2:0]    hiu_io_occupancy;
  wire                hiu_io_faultPerm;
  wire                hiu_io_missNotice;
  wire       [31:0]   own_io_rdata;
  wire                own_io_rvalid;
  wire                own_io_ready;
  wire                own_io_query_devOwned;
  wire                own_io_faultCollide;
  wire                own_io_faultBadWrite;
  wire       [31:0]   cfgBlk_io_rdata;
  wire                cfgBlk_io_rvalid;
  wire                cfgBlk_io_ready;
  wire                cfgBlk_io_viewWr_valid;
  wire       [3:0]    cfgBlk_io_viewWr_idx;
  wire                cfgBlk_io_viewWr_en;
  wire       [15:0]   cfgBlk_io_viewWr_lnid;
  wire                cfgBlk_io_bankWr_valid;
  wire       [7:0]    cfgBlk_io_bankWr_lbid;
  wire                cfgBlk_io_bankWr_mapped;
  wire                cfgBlk_io_faultDupOwner;
  wire                cfgBlk_io_faultBadWrite;
  wire                merge_io_fault;
  wire                merge_io_push_0_stall;
  wire                merge_io_push_1_stall;
  wire                merge_io_push_2_stall;
  wire                merge_io_push_3_stall;
  wire                merge_io_consumer_valid;
  wire       [31:0]   merge_io_consumer_payload_head_tag_wave;
  wire       [15:0]   merge_io_consumer_payload_head_tag_thread;
  wire       [15:0]   merge_io_consumer_payload_head_tag_lnid;
  wire       [7:0]    merge_io_consumer_payload_head_tag_precision;
  wire       [7:0]    merge_io_consumer_payload_head_tag_dim;
  wire       [7:0]    merge_io_consumer_payload_head_seq;
  wire       [7:0]    merge_io_consumer_payload_head_total;
  wire                merge_io_consumer_payload_head_last;
  wire       [63:0]   merge_io_consumer_payload_body;
  wire       [2:0]    merge_io_occupancy;
  wire                shared_1_io_req_ready;
  wire                shared_1_io_rsp_valid;
  wire       [160:0]  shared_1_io_rsp_payload;
  wire                shared_1_io_faultBpViolation;
  wire       [2:0]    shared_1_io_occupancy;
  wire                bank_io_acquire_granted;
  wire       [63:0]   bank_io_read_data;
  wire                bank_io_read_owned;
  wire                bank_io_fault;
  wire       [4:0]    bank_io_occupancy;
  wire                mask_io_rekey_ready;
  wire       [3:0]    mask_io_maskReady;
  wire                mask_io_busy;
  wire                mask_io_rsp_valid;
  wire       [31:0]   mask_io_rsp_frame;
  wire                mask_io_faultNoMask;
  wire                mask_io_faultNonceDup;
  wire                mask_io_faultWrDuringRekey;
  wire                fps_io_req_ready;
  wire                fps_io_oDone;
  wire                fps_io_oExecValid;
  wire                fps_io_oCapAbsent;
  wire                fps_io_oProgMal;
  wire       [31:0]   fps_io_oResult;
  wire                fps_io_oBusy;
  wire                fps_io_loadReady;
  wire                fps_io_faultBpViolation;
  wire                fps_io_faultBadProg;
  wire       [31:0]   cq_io_rdata;
  wire                cq_io_rvalid;
  wire                cq_io_ready;
  wire                cq_io_comp_ready;
  wire                cq_io_irq;
  wire                cq_io_faultOverflow;
  wire                cq_io_faultBadWrite;
  wire                stg_io_badWrite;
  wire       [2:0]    stg_io_armed;
  wire                stg_io_fire;
  wire       [31:0]   stg_io_tag_wave;
  wire       [15:0]   stg_io_tag_thread;
  wire       [15:0]   stg_io_tag_lnid;
  wire       [7:0]    stg_io_tag_precision;
  wire       [7:0]    stg_io_tag_dim;
  wire       [1:0]    _zz_maskArea_readValue;
  wire       [7:0]    _zz_abortArea_readValue;
  wire       [2:0]    _zz_abortArea_readValue_1;
  wire                fltClrAccept;
  wire                capClrAccept;
  reg        [31:0]   tagQ_wave;
  reg        [15:0]   tagQ_thread;
  reg        [15:0]   tagQ_lnid;
  reg        [7:0]    tagQ_precision;
  reg        [7:0]    tagQ_dim;
  wire       [96:0]   _zz_io_push_0_result_head_seq;
  wire       [79:0]   _zz_io_push_0_result_head_tag_wave;
  wire                mmioAligned;
  wire                selOwn;
  wire                selCq;
  wire                selCfg;
  wire                selMask;
  wire                selFp;
  wire                selAbort;
  wire                selFault;
  wire                selSq;
  wire                selXent;
  wire                selXctl;
  wire                selIdent;
  wire                selUnwired;
  reg                 surfBadWr;
  wire       [4:0]    maskArea_wordOff;
  wire                maskArea_wr;
  wire                maskArea_rd;
  wire                maskArea_isKey;
  wire                maskArea_isNoncePart;
  wire                maskArea_isNonce;
  wire                maskArea_isRekey;
  wire                maskArea_isStatus;
  wire       [7:0]    maskArea_partField;
  wire                maskArea_partBad;
  reg        [1:0]    maskArea_noncePart;
  wire                maskArea_npWr;
  wire                maskArea_npRsvBad;
  wire                maskArea_npReject;
  wire                when_Wt64Top_l1236;
  wire                maskArea_rkWr;
  wire                maskArea_rkRsvBad;
  wire                maskArea_rkReject;
  reg        [31:0]   maskArea_maskStat;
  wire                when_Wt64Top_l1263;
  reg        [31:0]   maskArea_readValue;
  wire       [3:0]    fpArea_wordOff;
  wire                fpArea_wr;
  wire                fpArea_rd;
  wire                fpArea_isProg;
  wire                fpArea_isBind;
  wire                fpArea_isStatus;
  wire                fpArea_bindRsvBad;
  wire                when_Wt64Top_l1304;
  reg        [31:0]   fpArea_fpStat;
  reg        [31:0]   fpArea_readValue;
  wire       [3:0]    abortArea_wordOff;
  wire                abortArea_wr;
  wire                abortArea_rd;
  wire                abortArea_isTag0;
  wire                abortArea_isTag1;
  wire                abortArea_isTag2;
  wire                abortArea_isFire;
  wire                abortArea_isCnt;
  wire                abortArea_isInc;
  wire                abortArea_isArm;
  wire                when_Wt64Top_l1356;
  reg        [31:0]   abortArea_readValue;
  wire       [3:0]    faultArea_wordOff;
  wire                faultArea_wr;
  wire                faultArea_rd;
  wire                faultArea_isStatus;
  wire                faultArea_isClear;
  wire                faultArea_isSummary;
  wire                faultArea_isCapSt;
  wire                faultArea_isCapClr;
  wire                faultArea_clrRsvBad;
  wire                faultArea_capRsvBad;
  wire                faultArea_doClr;
  wire                faultArea_doCapClr;
  wire                when_Wt64Top_l1406;
  wire                when_Common_l258;
  reg                 _zz_io_fault_cfgSurfBadWrite;
  wire                when_Common_l258_1;
  reg                 _zz_io_fault_fpCapAbsent;
  reg        [31:0]   faultWords_status;
  reg        [31:0]   faultWords_summary;
  reg        [31:0]   faultWords_capStatus;
  reg        [31:0]   faultWords_readValue;
  wire                when_Wt64Top_l1517;
  wire                mapRd;
  reg        [31:0]   mapRdReg;
  reg                 mapRv;
  wire                resvOffset;
  wire                resvRd;
  reg                 resvRv;

  assign _zz_maskArea_readValue = maskArea_noncePart;
  assign _zz_abortArea_readValue = reasm_io_abortCount;
  assign _zz_abortArea_readValue_1 = reasm_io_incomplete;
  DecodeWalk walk (
    .io_iValid         (io_instr_valid          ), //i
    .io_iInstr_0       (io_instr_words_0[31:0]  ), //i
    .io_iInstr_1       (io_instr_words_1[31:0]  ), //i
    .io_iInstr_2       (io_instr_words_2[31:0]  ), //i
    .io_iInstr_3       (io_instr_words_3[31:0]  ), //i
    .io_iInstr_4       (io_instr_words_4[31:0]  ), //i
    .io_iInstr_5       (io_instr_words_5[31:0]  ), //i
    .io_iInstr_6       (io_instr_words_6[31:0]  ), //i
    .io_iInstr_7       (io_instr_words_7[31:0]  ), //i
    .io_iInstr_8       (io_instr_words_8[31:0]  ), //i
    .io_iInstr_9       (io_instr_words_9[31:0]  ), //i
    .io_iInstr_10      (io_instr_words_10[31:0] ), //i
    .io_iInstr_11      (io_instr_words_11[31:0] ), //i
    .io_iInstr_12      (io_instr_words_12[31:0] ), //i
    .io_iFaultClear    (walk_io_iFaultClear     ), //i
    .io_oValid         (walk_io_oValid          ), //o
    .io_oMalformed     (walk_io_oMalformed      ), //o
    .io_oCapAbsent     (walk_io_oCapAbsent      ), //o
    .io_oExecValid     (walk_io_oExecValid      ), //o
    .io_oInstr_0       (walk_io_oInstr_0[31:0]  ), //o
    .io_oInstr_1       (walk_io_oInstr_1[31:0]  ), //o
    .io_oInstr_2       (walk_io_oInstr_2[31:0]  ), //o
    .io_oInstr_3       (walk_io_oInstr_3[31:0]  ), //o
    .io_oInstr_4       (walk_io_oInstr_4[31:0]  ), //o
    .io_oInstr_5       (walk_io_oInstr_5[31:0]  ), //o
    .io_oInstr_6       (walk_io_oInstr_6[31:0]  ), //o
    .io_oInstr_7       (walk_io_oInstr_7[31:0]  ), //o
    .io_oInstr_8       (walk_io_oInstr_8[31:0]  ), //o
    .io_oInstr_9       (walk_io_oInstr_9[31:0]  ), //o
    .io_oInstr_10      (walk_io_oInstr_10[31:0] ), //o
    .io_oInstr_11      (walk_io_oInstr_11[31:0] ), //o
    .io_oInstr_12      (walk_io_oInstr_12[31:0] ), //o
    .io_oSlotPresent_0 (walk_io_oSlotPresent_0  ), //o
    .io_oSlotPresent_1 (walk_io_oSlotPresent_1  ), //o
    .io_oSlotPresent_2 (walk_io_oSlotPresent_2  ), //o
    .io_oSlotPresent_3 (walk_io_oSlotPresent_3  ), //o
    .io_oSlotCode_0    (walk_io_oSlotCode_0[3:0]), //o
    .io_oSlotCode_1    (walk_io_oSlotCode_1[3:0]), //o
    .io_oSlotCode_2    (walk_io_oSlotCode_2[3:0]), //o
    .io_oSlotCode_3    (walk_io_oSlotCode_3[3:0]), //o
    .io_oSlotOff_0     (walk_io_oSlotOff_0[7:0] ), //o
    .io_oSlotOff_1     (walk_io_oSlotOff_1[7:0] ), //o
    .io_oSlotOff_2     (walk_io_oSlotOff_2[7:0] ), //o
    .io_oSlotOff_3     (walk_io_oSlotOff_3[7:0] ), //o
    .io_oFault         (walk_io_oFault          ), //o
    .clk               (clk                     ), //i
    .reset             (reset                   )  //i
  );
  OperandDecode od (
    .io_iValid             (walk_io_oValid               ), //i
    .io_iMalformed         (walk_io_oMalformed           ), //i
    .io_iCapAbsent         (walk_io_oCapAbsent           ), //i
    .io_iExecValid         (walk_io_oExecValid           ), //i
    .io_iInstr_0           (walk_io_oInstr_0[31:0]       ), //i
    .io_iInstr_1           (walk_io_oInstr_1[31:0]       ), //i
    .io_iInstr_2           (walk_io_oInstr_2[31:0]       ), //i
    .io_iInstr_3           (walk_io_oInstr_3[31:0]       ), //i
    .io_iInstr_4           (walk_io_oInstr_4[31:0]       ), //i
    .io_iInstr_5           (walk_io_oInstr_5[31:0]       ), //i
    .io_iInstr_6           (walk_io_oInstr_6[31:0]       ), //i
    .io_iInstr_7           (walk_io_oInstr_7[31:0]       ), //i
    .io_iInstr_8           (walk_io_oInstr_8[31:0]       ), //i
    .io_iInstr_9           (walk_io_oInstr_9[31:0]       ), //i
    .io_iInstr_10          (walk_io_oInstr_10[31:0]      ), //i
    .io_iInstr_11          (walk_io_oInstr_11[31:0]      ), //i
    .io_iInstr_12          (walk_io_oInstr_12[31:0]      ), //i
    .io_iSlotPresent_0     (walk_io_oSlotPresent_0       ), //i
    .io_iSlotPresent_1     (walk_io_oSlotPresent_1       ), //i
    .io_iSlotPresent_2     (walk_io_oSlotPresent_2       ), //i
    .io_iSlotPresent_3     (walk_io_oSlotPresent_3       ), //i
    .io_iSlotCode_0        (walk_io_oSlotCode_0[3:0]     ), //i
    .io_iSlotCode_1        (walk_io_oSlotCode_1[3:0]     ), //i
    .io_iSlotCode_2        (walk_io_oSlotCode_2[3:0]     ), //i
    .io_iSlotCode_3        (walk_io_oSlotCode_3[3:0]     ), //i
    .io_iSlotOff_0         (walk_io_oSlotOff_0[7:0]      ), //i
    .io_iSlotOff_1         (walk_io_oSlotOff_1[7:0]      ), //i
    .io_iSlotOff_2         (walk_io_oSlotOff_2[7:0]      ), //i
    .io_iSlotOff_3         (walk_io_oSlotOff_3[7:0]      ), //i
    .io_iFaultClear        (od_io_iFaultClear            ), //i
    .io_oValid             (od_io_oValid                 ), //o
    .io_oMalformed         (od_io_oMalformed             ), //o
    .io_oCapAbsent         (od_io_oCapAbsent             ), //o
    .io_oExecValid         (od_io_oExecValid             ), //o
    .io_oPortPresent       (od_io_oPortPresent           ), //o
    .io_oPortDest          (od_io_oPortDest[15:0]        ), //o
    .io_oImm16Present      (od_io_oImm16Present          ), //o
    .io_oImm16             (od_io_oImm16[15:0]           ), //o
    .io_oImm32Present      (od_io_oImm32Present          ), //o
    .io_oImm32             (od_io_oImm32[31:0]           ), //o
    .io_oImm64Present      (od_io_oImm64Present          ), //o
    .io_oImm64             (od_io_oImm64[63:0]           ), //o
    .io_oMemPresent        (od_io_oMemPresent            ), //o
    .io_oMemAddrMode       (od_io_oMemAddrMode[3:0]      ), //o
    .io_oMemStride         (od_io_oMemStride[11:0]       ), //o
    .io_oMemOffset         (od_io_oMemOffset[31:0]       ), //o
    .io_oSubValid_0        (od_io_oSubValid_0            ), //o
    .io_oSubValid_1        (od_io_oSubValid_1            ), //o
    .io_oSubValid_2        (od_io_oSubValid_2            ), //o
    .io_oSubValid_3        (od_io_oSubValid_3            ), //o
    .io_oSubO_0            (od_io_oSubO_0[15:0]          ), //o
    .io_oSubO_1            (od_io_oSubO_1[15:0]          ), //o
    .io_oSubO_2            (od_io_oSubO_2[15:0]          ), //o
    .io_oSubO_3            (od_io_oSubO_3[15:0]          ), //o
    .io_oSubA_0            (od_io_oSubA_0[15:0]          ), //o
    .io_oSubA_1            (od_io_oSubA_1[15:0]          ), //o
    .io_oSubA_2            (od_io_oSubA_2[15:0]          ), //o
    .io_oSubA_3            (od_io_oSubA_3[15:0]          ), //o
    .io_oSubB_0            (od_io_oSubB_0[15:0]          ), //o
    .io_oSubB_1            (od_io_oSubB_1[15:0]          ), //o
    .io_oSubB_2            (od_io_oSubB_2[15:0]          ), //o
    .io_oSubB_3            (od_io_oSubB_3[15:0]          ), //o
    .io_oSubCount          (od_io_oSubCount[2:0]         ), //o
    .io_oOprefAValid       (od_io_oOprefAValid           ), //o
    .io_oOprefALbid        (od_io_oOprefALbid[7:0]       ), //o
    .io_oOprefASrcKind     (od_io_oOprefASrcKind[3:0]    ), //o
    .io_oOprefBValid       (od_io_oOprefBValid           ), //o
    .io_oOprefBLbid        (od_io_oOprefBLbid[7:0]       ), //o
    .io_oOprefBSrcKind     (od_io_oOprefBSrcKind[3:0]    ), //o
    .io_oPrecPresent       (od_io_oPrecPresent           ), //o
    .io_oPrecMode          (od_io_oPrecMode[7:0]         ), //o
    .io_oPrecDim           (od_io_oPrecDim[7:0]          ), //o
    .io_oReasmBind_valid   (od_io_oReasmBind_valid       ), //o
    .io_oReasmBind_payload (od_io_oReasmBind_payload[7:0]), //o
    .io_oFault             (od_io_oFault                 ), //o
    .clk                   (clk                          ), //i
    .reset                 (reset                        )  //i
  );
  RouteJudge rj (
    .io_tokIn_valid                  (od_io_oExecValid                       ), //i
    .io_tokIn_payload_tag_wave       (tagQ_wave[31:0]                        ), //i
    .io_tokIn_payload_tag_thread     (tagQ_thread[15:0]                      ), //i
    .io_tokIn_payload_tag_lnid       (tagQ_lnid[15:0]                        ), //i
    .io_tokIn_payload_tag_precision  (tagQ_precision[7:0]                    ), //i
    .io_tokIn_payload_tag_dim        (tagQ_dim[7:0]                          ), //i
    .io_tokIn_payload_lbid           (od_io_oOprefALbid[7:0]                 ), //i
    .io_tokIn_payload_srcKind        (od_io_oOprefASrcKind[3:0]              ), //i
    .io_tokOut_valid                 (rj_io_tokOut_valid                     ), //o
    .io_tokOut_payload_tag_wave      (rj_io_tokOut_payload_tag_wave[31:0]    ), //o
    .io_tokOut_payload_tag_thread    (rj_io_tokOut_payload_tag_thread[15:0]  ), //o
    .io_tokOut_payload_tag_lnid      (rj_io_tokOut_payload_tag_lnid[15:0]    ), //o
    .io_tokOut_payload_tag_precision (rj_io_tokOut_payload_tag_precision[7:0]), //o
    .io_tokOut_payload_tag_dim       (rj_io_tokOut_payload_tag_dim[7:0]      ), //o
    .io_tokOut_payload_lbid          (rj_io_tokOut_payload_lbid[7:0]         ), //o
    .io_tokOut_payload_srcKind       (rj_io_tokOut_payload_srcKind[3:0]      ), //o
    .io_viewWr_valid                 (cfgBlk_io_viewWr_valid                 ), //i
    .io_viewWr_idx                   (cfgBlk_io_viewWr_idx[3:0]              ), //i
    .io_viewWr_en                    (cfgBlk_io_viewWr_en                    ), //i
    .io_viewWr_lnid                  (cfgBlk_io_viewWr_lnid[15:0]            ), //i
    .io_bankWr_valid                 (cfgBlk_io_bankWr_valid                 ), //i
    .io_bankWr_lbid                  (cfgBlk_io_bankWr_lbid[7:0]             ), //i
    .io_bankWr_mapped                (cfgBlk_io_bankWr_mapped                ), //i
    .io_fault                        (rj_io_fault                            ), //o
    .io_faultClear                   (rj_io_faultClear                       ), //i
    .io_faultFire                    (rj_io_faultFire                        ), //o
    .clk                             (clk                                    ), //i
    .reset                           (reset                                  )  //i
  );
  Reassembly reasm (
    .io_open_valid                    (od_io_oReasmBind_valid                           ), //i
    .io_open_tag_wave                 (tagQ_wave[31:0]                                  ), //i
    .io_open_tag_thread               (tagQ_thread[15:0]                                ), //i
    .io_open_tag_lnid                 (tagQ_lnid[15:0]                                  ), //i
    .io_open_tag_precision            (tagQ_precision[7:0]                              ), //i
    .io_open_tag_dim                  (tagQ_dim[7:0]                                    ), //i
    .io_open_base                     (od_io_oReasmBind_payload[7:0]                    ), //i
    .io_open_granted                  (reasm_io_open_granted                            ), //o
    .io_frag_valid                    (merge_io_consumer_valid                          ), //i
    .io_frag_head_tag_wave            (merge_io_consumer_payload_head_tag_wave[31:0]    ), //i
    .io_frag_head_tag_thread          (merge_io_consumer_payload_head_tag_thread[15:0]  ), //i
    .io_frag_head_tag_lnid            (merge_io_consumer_payload_head_tag_lnid[15:0]    ), //i
    .io_frag_head_tag_precision       (merge_io_consumer_payload_head_tag_precision[7:0]), //i
    .io_frag_head_tag_dim             (merge_io_consumer_payload_head_tag_dim[7:0]      ), //i
    .io_frag_head_seq                 (merge_io_consumer_payload_head_seq[7:0]          ), //i
    .io_frag_head_total               (merge_io_consumer_payload_head_total[7:0]        ), //i
    .io_frag_head_last                (merge_io_consumer_payload_head_last              ), //i
    .io_frag_body                     (merge_io_consumer_payload_body[63:0]             ), //i
    .io_wr_valid                      (reasm_io_wr_valid                                ), //o
    .io_wr_base                       (reasm_io_wr_base[7:0]                            ), //o
    .io_wr_off                        (reasm_io_wr_off[3:0]                             ), //o
    .io_wr_body                       (reasm_io_wr_body[63:0]                           ), //o
    .io_deliver_valid                 (reasm_io_deliver_valid                           ), //o
    .io_deliver_ready                 (cq_io_comp_ready                                 ), //i
    .io_deliver_payload_tag_wave      (reasm_io_deliver_payload_tag_wave[31:0]          ), //o
    .io_deliver_payload_tag_thread    (reasm_io_deliver_payload_tag_thread[15:0]        ), //o
    .io_deliver_payload_tag_lnid      (reasm_io_deliver_payload_tag_lnid[15:0]          ), //o
    .io_deliver_payload_tag_precision (reasm_io_deliver_payload_tag_precision[7:0]      ), //o
    .io_deliver_payload_tag_dim       (reasm_io_deliver_payload_tag_dim[7:0]            ), //o
    .io_deliver_payload_base          (reasm_io_deliver_payload_base[7:0]               ), //o
    .io_deliver_payload_total         (reasm_io_deliver_payload_total[7:0]              ), //o
    .io_incomplete                    (reasm_io_incomplete[2:0]                         ), //o
    .io_occupancy                     (reasm_io_occupancy[2:0]                          ), //o
    .io_abort_valid                   (stg_io_fire                                      ), //i
    .io_abort_tag_wave                (stg_io_tag_wave[31:0]                            ), //i
    .io_abort_tag_thread              (stg_io_tag_thread[15:0]                          ), //i
    .io_abort_tag_lnid                (stg_io_tag_lnid[15:0]                            ), //i
    .io_abort_tag_precision           (stg_io_tag_precision[7:0]                        ), //i
    .io_abort_tag_dim                 (stg_io_tag_dim[7:0]                              ), //i
    .io_clr_valid                     (reasm_io_clr_valid                               ), //o
    .io_clr_base                      (reasm_io_clr_base[7:0]                           ), //o
    .io_abortCount                    (reasm_io_abortCount[7:0]                         ), //o
    .io_fault                         (reasm_io_fault                                   ), //o
    .io_faultClear                    (reasm_io_faultClear                              ), //i
    .io_capAbsent                     (reasm_io_capAbsent                               ), //o
    .io_capAbsentClear                (reasm_io_capAbsentClear                          ), //i
    .clk                              (clk                                              ), //i
    .reset                            (reset                                            )  //i
  );
  MemOrderGate mog (
    .io_cfgPreds_0     (io_mem_cfgPreds_0[2:0]      ), //i
    .io_cfgPreds_1     (io_mem_cfgPreds_1[2:0]      ), //i
    .io_cfgPreds_2     (io_mem_cfgPreds_2[2:0]      ), //i
    .io_cfgPreds_3     (io_mem_cfgPreds_3[2:0]      ), //i
    .io_epochClear     (io_mem_epochClear           ), //i
    .io_up_0_valid     (mog_io_up_0_valid           ), //i
    .io_up_0_ready     (mog_io_up_0_ready           ), //o
    .io_up_0_payload   (mog_io_up_0_payload[127:0]  ), //i
    .io_up_1_valid     (mog_io_up_1_valid           ), //i
    .io_up_1_ready     (mog_io_up_1_ready           ), //o
    .io_up_1_payload   (mog_io_up_1_payload[127:0]  ), //i
    .io_up_2_valid     (mog_io_up_2_valid           ), //i
    .io_up_2_ready     (mog_io_up_2_ready           ), //o
    .io_up_2_payload   (mog_io_up_2_payload[127:0]  ), //i
    .io_up_3_valid     (mog_io_up_3_valid           ), //i
    .io_up_3_ready     (mog_io_up_3_ready           ), //o
    .io_up_3_payload   (mog_io_up_3_payload[127:0]  ), //i
    .io_down_0_valid   (mog_io_down_0_valid         ), //o
    .io_down_0_ready   (io_mem_down_0_ready         ), //i
    .io_down_0_payload (mog_io_down_0_payload[127:0]), //o
    .io_down_1_valid   (mog_io_down_1_valid         ), //o
    .io_down_1_ready   (io_mem_down_1_ready         ), //i
    .io_down_1_payload (mog_io_down_1_payload[127:0]), //o
    .io_down_2_valid   (mog_io_down_2_valid         ), //o
    .io_down_2_ready   (io_mem_down_2_ready         ), //i
    .io_down_2_payload (mog_io_down_2_payload[127:0]), //o
    .io_down_3_valid   (mog_io_down_3_valid         ), //o
    .io_down_3_ready   (io_mem_down_3_ready         ), //i
    .io_down_3_payload (mog_io_down_3_payload[127:0]), //o
    .io_complete       (io_mem_complete[3:0]        ), //i
    .io_token          (mog_io_token[3:0]           ), //o
    .io_gateOpen       (mog_io_gateOpen[3:0]        ), //o
    .io_occupancy      (mog_io_occupancy[2:0]       ), //o
    .clk               (clk                         ), //i
    .reset             (reset                       )  //i
  );
  HiuPipeline hiu (
    .io_req_valid      (io_hiuReq_valid            ), //i
    .io_req_ready      (hiu_io_req_ready           ), //o
    .io_req_part       (io_hiuReq_part[1:0]        ), //i
    .io_req_vpn        (io_hiuReq_vpn[31:0]        ), //i
    .io_req_write      (io_hiuReq_write            ), //i
    .io_hold           (io_hiuHold                 ), //i
    .io_owner_frame    (hiu_io_owner_frame[31:0]   ), //o
    .io_owner_devOwned (own_io_query_devOwned      ), //i
    .io_mask_req_valid (hiu_io_mask_req_valid      ), //o
    .io_mask_req_part  (hiu_io_mask_req_part[1:0]  ), //o
    .io_mask_req_frame (hiu_io_mask_req_frame[31:0]), //o
    .io_mask_rsp_valid (mask_io_rsp_valid          ), //i
    .io_mask_rsp_frame (mask_io_rsp_frame[31:0]    ), //i
    .io_install_valid  (io_install_valid           ), //i
    .io_install_ready  (hiu_io_install_ready       ), //o
    .io_install_part   (io_install_part[1:0]       ), //i
    .io_install_idx    (io_install_idx[3:0]        ), //i
    .io_install_tag    (io_install_tag[27:0]       ), //i
    .io_install_frame  (io_install_frame[31:0]     ), //i
    .io_install_perm_r (io_install_perm_r          ), //i
    .io_install_perm_w (io_install_perm_w          ), //i
    .io_install_perm_x (io_install_perm_x          ), //i
    .io_flush_valid    (io_flush_valid             ), //i
    .io_flush_part     (io_flush_part[1:0]         ), //i
    .io_hostRsp_valid  (io_hostRsp_valid           ), //i
    .io_hostRsp_frame  (io_hostRsp_frame[31:0]     ), //i
    .io_hostRsp_perm_r (io_hostRsp_perm_r          ), //i
    .io_hostRsp_perm_w (io_hostRsp_perm_w          ), //i
    .io_hostRsp_perm_x (io_hostRsp_perm_x          ), //i
    .io_rsp_valid      (hiu_io_rsp_valid           ), //o
    .io_rsp_granted    (hiu_io_rsp_granted         ), //o
    .io_rsp_part       (hiu_io_rsp_part[1:0]       ), //o
    .io_rsp_write      (hiu_io_rsp_write           ), //o
    .io_rsp_fromFill   (hiu_io_rsp_fromFill        ), //o
    .io_rsp_frame      (hiu_io_rsp_frame[31:0]     ), //o
    .io_rsp_perm_r     (hiu_io_rsp_perm_r          ), //o
    .io_rsp_perm_w     (hiu_io_rsp_perm_w          ), //o
    .io_rsp_perm_x     (hiu_io_rsp_perm_x          ), //o
    .io_occupancy      (hiu_io_occupancy[2:0]      ), //o
    .io_faultPerm      (hiu_io_faultPerm           ), //o
    .io_faultClear     (hiu_io_faultClear          ), //i
    .io_missNotice     (hiu_io_missNotice          ), //o
    .io_missClear      (io_faultClear_hiuMiss      ), //i
    .clk               (clk                        ), //i
    .reset             (reset                      )  //i
  );
  OwnershipTable own (
    .io_addr               (io_mmio_addr[11:0]       ), //i
    .io_wstrobe            (own_io_wstrobe           ), //i
    .io_wdata              (io_mmio_wdata[31:0]      ), //i
    .io_rstrobe            (own_io_rstrobe           ), //i
    .io_rdata              (own_io_rdata[31:0]       ), //o
    .io_rvalid             (own_io_rvalid            ), //o
    .io_ready              (own_io_ready             ), //o
    .io_query_frame        (hiu_io_owner_frame[31:0] ), //i
    .io_query_devOwned     (own_io_query_devOwned    ), //o
    .io_faultCollide       (own_io_faultCollide      ), //o
    .io_faultClearCollide  (own_io_faultClearCollide ), //i
    .io_faultBadWrite      (own_io_faultBadWrite     ), //o
    .io_faultClearBadWrite (own_io_faultClearBadWrite), //i
    .clk                   (clk                      ), //i
    .reset                 (reset                    )  //i
  );
  MmioConfig cfgBlk (
    .io_addr          (io_mmio_addr[11:0]         ), //i
    .io_wstrobe       (cfgBlk_io_wstrobe          ), //i
    .io_wdata         (io_mmio_wdata[31:0]        ), //i
    .io_rstrobe       (cfgBlk_io_rstrobe          ), //i
    .io_rdata         (cfgBlk_io_rdata[31:0]      ), //o
    .io_rvalid        (cfgBlk_io_rvalid           ), //o
    .io_ready         (cfgBlk_io_ready            ), //o
    .io_viewWr_valid  (cfgBlk_io_viewWr_valid     ), //o
    .io_viewWr_idx    (cfgBlk_io_viewWr_idx[3:0]  ), //o
    .io_viewWr_en     (cfgBlk_io_viewWr_en        ), //o
    .io_viewWr_lnid   (cfgBlk_io_viewWr_lnid[15:0]), //o
    .io_bankWr_valid  (cfgBlk_io_bankWr_valid     ), //o
    .io_bankWr_lbid   (cfgBlk_io_bankWr_lbid[7:0] ), //o
    .io_bankWr_mapped (cfgBlk_io_bankWr_mapped    ), //o
    .io_faultDupOwner (cfgBlk_io_faultDupOwner    ), //o
    .io_faultBadWrite (cfgBlk_io_faultBadWrite    ), //o
    .io_faultClearDup (cfgBlk_io_faultClearDup    ), //i
    .io_faultClearBad (cfgBlk_io_faultClearBad    ), //i
    .clk              (clk                        ), //i
    .reset            (reset                      )  //i
  );
  FabricMerge merge (
    .io_fault                               (merge_io_fault                                   ), //o
    .io_faultClear                          (merge_io_faultClear                              ), //i
    .io_push_0_strb                         (shared_1_io_rsp_valid                            ), //i
    .io_push_0_result_head_tag_wave         (merge_io_push_0_result_head_tag_wave[31:0]       ), //i
    .io_push_0_result_head_tag_thread       (merge_io_push_0_result_head_tag_thread[15:0]     ), //i
    .io_push_0_result_head_tag_lnid         (merge_io_push_0_result_head_tag_lnid[15:0]       ), //i
    .io_push_0_result_head_tag_precision    (merge_io_push_0_result_head_tag_precision[7:0]   ), //i
    .io_push_0_result_head_tag_dim          (merge_io_push_0_result_head_tag_dim[7:0]         ), //i
    .io_push_0_result_head_seq              (merge_io_push_0_result_head_seq[7:0]             ), //i
    .io_push_0_result_head_total            (merge_io_push_0_result_head_total[7:0]           ), //i
    .io_push_0_result_head_last             (merge_io_push_0_result_head_last                 ), //i
    .io_push_0_result_body                  (merge_io_push_0_result_body[63:0]                ), //i
    .io_push_0_stall                        (merge_io_push_0_stall                            ), //o
    .io_push_1_strb                         (io_push_0_strb                                   ), //i
    .io_push_1_result_head_tag_wave         (io_push_0_result_head_tag_wave[31:0]             ), //i
    .io_push_1_result_head_tag_thread       (io_push_0_result_head_tag_thread[15:0]           ), //i
    .io_push_1_result_head_tag_lnid         (io_push_0_result_head_tag_lnid[15:0]             ), //i
    .io_push_1_result_head_tag_precision    (io_push_0_result_head_tag_precision[7:0]         ), //i
    .io_push_1_result_head_tag_dim          (io_push_0_result_head_tag_dim[7:0]               ), //i
    .io_push_1_result_head_seq              (io_push_0_result_head_seq[7:0]                   ), //i
    .io_push_1_result_head_total            (io_push_0_result_head_total[7:0]                 ), //i
    .io_push_1_result_head_last             (io_push_0_result_head_last                       ), //i
    .io_push_1_result_body                  (io_push_0_result_body[63:0]                      ), //i
    .io_push_1_stall                        (merge_io_push_1_stall                            ), //o
    .io_push_2_strb                         (io_push_1_strb                                   ), //i
    .io_push_2_result_head_tag_wave         (io_push_1_result_head_tag_wave[31:0]             ), //i
    .io_push_2_result_head_tag_thread       (io_push_1_result_head_tag_thread[15:0]           ), //i
    .io_push_2_result_head_tag_lnid         (io_push_1_result_head_tag_lnid[15:0]             ), //i
    .io_push_2_result_head_tag_precision    (io_push_1_result_head_tag_precision[7:0]         ), //i
    .io_push_2_result_head_tag_dim          (io_push_1_result_head_tag_dim[7:0]               ), //i
    .io_push_2_result_head_seq              (io_push_1_result_head_seq[7:0]                   ), //i
    .io_push_2_result_head_total            (io_push_1_result_head_total[7:0]                 ), //i
    .io_push_2_result_head_last             (io_push_1_result_head_last                       ), //i
    .io_push_2_result_body                  (io_push_1_result_body[63:0]                      ), //i
    .io_push_2_stall                        (merge_io_push_2_stall                            ), //o
    .io_push_3_strb                         (io_push_2_strb                                   ), //i
    .io_push_3_result_head_tag_wave         (io_push_2_result_head_tag_wave[31:0]             ), //i
    .io_push_3_result_head_tag_thread       (io_push_2_result_head_tag_thread[15:0]           ), //i
    .io_push_3_result_head_tag_lnid         (io_push_2_result_head_tag_lnid[15:0]             ), //i
    .io_push_3_result_head_tag_precision    (io_push_2_result_head_tag_precision[7:0]         ), //i
    .io_push_3_result_head_tag_dim          (io_push_2_result_head_tag_dim[7:0]               ), //i
    .io_push_3_result_head_seq              (io_push_2_result_head_seq[7:0]                   ), //i
    .io_push_3_result_head_total            (io_push_2_result_head_total[7:0]                 ), //i
    .io_push_3_result_head_last             (io_push_2_result_head_last                       ), //i
    .io_push_3_result_body                  (io_push_2_result_body[63:0]                      ), //i
    .io_push_3_stall                        (merge_io_push_3_stall                            ), //o
    .io_consumer_valid                      (merge_io_consumer_valid                          ), //o
    .io_consumer_ready                      (1'b1                                             ), //i
    .io_consumer_payload_head_tag_wave      (merge_io_consumer_payload_head_tag_wave[31:0]    ), //o
    .io_consumer_payload_head_tag_thread    (merge_io_consumer_payload_head_tag_thread[15:0]  ), //o
    .io_consumer_payload_head_tag_lnid      (merge_io_consumer_payload_head_tag_lnid[15:0]    ), //o
    .io_consumer_payload_head_tag_precision (merge_io_consumer_payload_head_tag_precision[7:0]), //o
    .io_consumer_payload_head_tag_dim       (merge_io_consumer_payload_head_tag_dim[7:0]      ), //o
    .io_consumer_payload_head_seq           (merge_io_consumer_payload_head_seq[7:0]          ), //o
    .io_consumer_payload_head_total         (merge_io_consumer_payload_head_total[7:0]        ), //o
    .io_consumer_payload_head_last          (merge_io_consumer_payload_head_last              ), //o
    .io_consumer_payload_body               (merge_io_consumer_payload_body[63:0]             ), //o
    .io_occupancy                           (merge_io_occupancy[2:0]                          ), //o
    .clk                                    (clk                                              ), //i
    .reset                                  (reset                                            )  //i
  );
  SharedUnit shared_1 (
    .io_req_valid        (io_sharedReq_valid            ), //i
    .io_req_payload      (io_sharedReq_payload[160:0]   ), //i
    .io_req_ready        (shared_1_io_req_ready         ), //o
    .io_rsp_valid        (shared_1_io_rsp_valid         ), //o
    .io_rsp_payload      (shared_1_io_rsp_payload[160:0]), //o
    .io_faultBpViolation (shared_1_io_faultBpViolation  ), //o
    .io_faultClear       (shared_1_io_faultClear        ), //i
    .io_occupancy        (shared_1_io_occupancy[2:0]    ), //o
    .clk                 (clk                           ), //i
    .reset               (reset                         )  //i
  );
  ResultBank bank (
    .io_acquire_valid   (io_bank_acqValid       ), //i
    .io_acquire_slot    (io_bank_acqSlot[3:0]   ), //i
    .io_acquire_prod    (io_bank_acqProd[3:0]   ), //i
    .io_acquire_granted (bank_io_acquire_granted), //o
    .io_write_valid     (io_bank_wrValid        ), //i
    .io_write_slot      (io_bank_wrSlot[3:0]    ), //i
    .io_write_prod      (io_bank_wrProd[3:0]    ), //i
    .io_write_data      (io_bank_wrData[63:0]   ), //i
    .io_read_slot       (io_bank_rdSlot[3:0]    ), //i
    .io_read_data       (bank_io_read_data[63:0]), //o
    .io_read_owned      (bank_io_read_owned     ), //o
    .io_fault           (bank_io_fault          ), //o
    .io_faultClear      (bank_io_faultClear     ), //i
    .io_occupancy       (bank_io_occupancy[4:0] ), //o
    .clk                (clk                    ), //i
    .reset              (reset                  )  //i
  );
  MaskUnit mask (
    .io_keyWr_valid        (mask_io_keyWr_valid        ), //i
    .io_keyWr_idx          (mask_io_keyWr_idx[2:0]     ), //i
    .io_keyWr_data         (io_mmio_wdata[31:0]        ), //i
    .io_nonceWr_valid      (mask_io_nonceWr_valid      ), //i
    .io_nonceWr_part       (maskArea_noncePart[1:0]    ), //i
    .io_nonceWr_idx        (mask_io_nonceWr_idx[2:0]   ), //i
    .io_nonceWr_data       (io_mmio_wdata[31:0]        ), //i
    .io_rekey_valid        (mask_io_rekey_valid        ), //i
    .io_rekey_ready        (mask_io_rekey_ready        ), //o
    .io_rekey_part         (mask_io_rekey_part[1:0]    ), //i
    .io_maskReady          (mask_io_maskReady[3:0]     ), //o
    .io_busy               (mask_io_busy               ), //o
    .io_en                 (hiu_io_req_ready           ), //i
    .io_req_valid          (hiu_io_mask_req_valid      ), //i
    .io_req_part           (hiu_io_mask_req_part[1:0]  ), //i
    .io_req_frame          (hiu_io_mask_req_frame[31:0]), //i
    .io_rsp_valid          (mask_io_rsp_valid          ), //o
    .io_rsp_frame          (mask_io_rsp_frame[31:0]    ), //o
    .io_faultNoMask        (mask_io_faultNoMask        ), //o
    .io_faultNonceDup      (mask_io_faultNonceDup      ), //o
    .io_faultWrDuringRekey (mask_io_faultWrDuringRekey ), //o
    .io_faultClearNoMask   (mask_io_faultClearNoMask   ), //i
    .io_faultClearNonceDup (mask_io_faultClearNonceDup ), //i
    .io_faultClearWrRekey  (mask_io_faultClearWrRekey  ), //i
    .clk                   (clk                        ), //i
    .reset                 (reset                      )  //i
  );
  StepSequencer fps (
    .io_req_valid         (io_fp_reqValid          ), //i
    .io_req_opKind        (io_fp_opKind[7:0]       ), //i
    .io_req_precision     (io_fp_precision[7:0]    ), //i
    .io_req_a             (io_fp_a[31:0]           ), //i
    .io_req_b             (io_fp_b[31:0]           ), //i
    .io_req_c             (io_fp_c[31:0]           ), //i
    .io_req_ready         (fps_io_req_ready        ), //o
    .io_oDone             (fps_io_oDone            ), //o
    .io_oExecValid        (fps_io_oExecValid       ), //o
    .io_oCapAbsent        (fps_io_oCapAbsent       ), //o
    .io_oProgMal          (fps_io_oProgMal         ), //o
    .io_oResult           (fps_io_oResult[31:0]    ), //o
    .io_oBusy             (fps_io_oBusy            ), //o
    .io_progWr_valid      (fps_io_progWr_valid     ), //i
    .io_progWr_slot       (fps_io_progWr_slot[7:0] ), //i
    .io_progWr_idx        (fps_io_progWr_idx[7:0]  ), //i
    .io_progWr_step       (fps_io_progWr_step[15:0]), //i
    .io_bindWr_valid      (fps_io_bindWr_valid     ), //i
    .io_bindWr_key        (fps_io_bindWr_key[15:0] ), //i
    .io_bindWr_en         (fps_io_bindWr_en        ), //i
    .io_bindWr_slot       (fps_io_bindWr_slot[7:0] ), //i
    .io_loadReady         (fps_io_loadReady        ), //o
    .io_faultBpViolation  (fps_io_faultBpViolation ), //o
    .io_faultBadProg      (fps_io_faultBadProg     ), //o
    .io_faultClearBp      (fps_io_faultClearBp     ), //i
    .io_faultClearBadProg (fps_io_faultClearBadProg), //i
    .clk                  (clk                     ), //i
    .reset                (reset                   )  //i
  );
  CompletionUnit cq (
    .io_addr               (cq_io_addr[7:0]                            ), //i
    .io_wstrobe            (cq_io_wstrobe                              ), //i
    .io_wdata              (io_mmio_wdata[31:0]                        ), //i
    .io_rstrobe            (cq_io_rstrobe                              ), //i
    .io_rdata              (cq_io_rdata[31:0]                          ), //o
    .io_rvalid             (cq_io_rvalid                               ), //o
    .io_ready              (cq_io_ready                                ), //o
    .io_comp_valid         (reasm_io_deliver_valid                     ), //i
    .io_comp_tag_wave      (reasm_io_deliver_payload_tag_wave[31:0]    ), //i
    .io_comp_tag_thread    (reasm_io_deliver_payload_tag_thread[15:0]  ), //i
    .io_comp_tag_lnid      (reasm_io_deliver_payload_tag_lnid[15:0]    ), //i
    .io_comp_tag_precision (reasm_io_deliver_payload_tag_precision[7:0]), //i
    .io_comp_tag_dim       (reasm_io_deliver_payload_tag_dim[7:0]      ), //i
    .io_comp_base          (reasm_io_deliver_payload_base[7:0]         ), //i
    .io_comp_total         (reasm_io_deliver_payload_total[7:0]        ), //i
    .io_comp_ready         (cq_io_comp_ready                           ), //o
    .io_irq                (cq_io_irq                                  ), //o
    .io_drain_pipe         (cq_io_drain_pipe[15:0]                     ), //i
    .io_drain_pending      (cq_io_drain_pending[15:0]                  ), //i
    .io_drain_output       (cq_io_drain_output[15:0]                   ), //i
    .io_drain_ownSlots     (cq_io_drain_ownSlots[15:0]                 ), //i
    .io_drain_contexts     (cq_io_drain_contexts[15:0]                 ), //i
    .io_drain_tokens       (cq_io_drain_tokens[15:0]                   ), //i
    .io_faultOverflow      (cq_io_faultOverflow                        ), //o
    .io_faultClearOverflow (cq_io_faultClearOverflow                   ), //i
    .io_faultBadWrite      (cq_io_faultBadWrite                        ), //o
    .io_faultClearBadWrite (cq_io_faultClearBadWrite                   ), //i
    .clk                   (clk                                        ), //i
    .reset                 (reset                                      )  //i
  );
  AbortStaging stg (
    .io_wr            (abortArea_wr             ), //i
    .io_selTag0       (abortArea_isTag0         ), //i
    .io_selTag1       (abortArea_isTag1         ), //i
    .io_selTag2       (abortArea_isTag2         ), //i
    .io_selFire       (abortArea_isFire         ), //i
    .io_wdata         (io_mmio_wdata[31:0]      ), //i
    .io_badWrite      (stg_io_badWrite          ), //o
    .io_armed         (stg_io_armed[2:0]        ), //o
    .io_fire          (stg_io_fire              ), //o
    .io_tag_wave      (stg_io_tag_wave[31:0]    ), //o
    .io_tag_thread    (stg_io_tag_thread[15:0]  ), //o
    .io_tag_lnid      (stg_io_tag_lnid[15:0]    ), //o
    .io_tag_precision (stg_io_tag_precision[7:0]), //o
    .io_tag_dim       (stg_io_tag_dim[7:0]      ), //o
    .clk              (clk                      ), //i
    .reset            (reset                    )  //i
  );
  assign walk_io_iFaultClear = (io_faultClear_decodeWalk || (fltClrAccept && io_mmio_wdata[0]));
  assign od_io_iFaultClear = (io_faultClear_operandDecode || (fltClrAccept && io_mmio_wdata[1]));
  assign io_dec_valid = od_io_oValid;
  assign io_dec_malformed = od_io_oMalformed;
  assign io_dec_capAbsent = od_io_oCapAbsent;
  assign io_dec_execValid = od_io_oExecValid;
  assign io_dec_portPresent = od_io_oPortPresent;
  assign io_dec_portDest = od_io_oPortDest;
  assign io_dec_imm16Present = od_io_oImm16Present;
  assign io_dec_imm16 = od_io_oImm16;
  assign io_dec_imm32Present = od_io_oImm32Present;
  assign io_dec_imm32 = od_io_oImm32;
  assign io_dec_imm64Present = od_io_oImm64Present;
  assign io_dec_imm64 = od_io_oImm64;
  assign io_dec_memPresent = od_io_oMemPresent;
  assign io_dec_subValid_0 = od_io_oSubValid_0;
  assign io_dec_subValid_1 = od_io_oSubValid_1;
  assign io_dec_subValid_2 = od_io_oSubValid_2;
  assign io_dec_subValid_3 = od_io_oSubValid_3;
  assign io_dec_subO_0 = od_io_oSubO_0;
  assign io_dec_subO_1 = od_io_oSubO_1;
  assign io_dec_subO_2 = od_io_oSubO_2;
  assign io_dec_subO_3 = od_io_oSubO_3;
  assign io_dec_subA_0 = od_io_oSubA_0;
  assign io_dec_subA_1 = od_io_oSubA_1;
  assign io_dec_subA_2 = od_io_oSubA_2;
  assign io_dec_subA_3 = od_io_oSubA_3;
  assign io_dec_subB_0 = od_io_oSubB_0;
  assign io_dec_subB_1 = od_io_oSubB_1;
  assign io_dec_subB_2 = od_io_oSubB_2;
  assign io_dec_subB_3 = od_io_oSubB_3;
  assign io_dec_subCount = od_io_oSubCount;
  assign io_dec_oprefAValid = od_io_oOprefAValid;
  assign io_dec_oprefBValid = od_io_oOprefBValid;
  assign io_dec_oprefBLbid = od_io_oOprefBLbid;
  assign io_dec_oprefBSrcKind = od_io_oOprefBSrcKind;
  assign io_dec_precPresent = od_io_oPrecPresent;
  assign io_dec_precMode = od_io_oPrecMode;
  assign io_dec_precDim = od_io_oPrecDim;
  assign rj_io_faultClear = (io_faultClear_route || (fltClrAccept && io_mmio_wdata[2]));
  assign io_route_tokOut_valid = rj_io_tokOut_valid;
  assign io_route_tokOut_payload_tag_wave = rj_io_tokOut_payload_tag_wave;
  assign io_route_tokOut_payload_tag_thread = rj_io_tokOut_payload_tag_thread;
  assign io_route_tokOut_payload_tag_lnid = rj_io_tokOut_payload_tag_lnid;
  assign io_route_tokOut_payload_tag_precision = rj_io_tokOut_payload_tag_precision;
  assign io_route_tokOut_payload_tag_dim = rj_io_tokOut_payload_tag_dim;
  assign io_route_tokOut_payload_lbid = rj_io_tokOut_payload_lbid;
  assign io_route_tokOut_payload_srcKind = rj_io_tokOut_payload_srcKind;
  assign io_route_faultFire = rj_io_faultFire;
  assign io_reasmOpenGranted = reasm_io_open_granted;
  assign io_reasmWr_valid = reasm_io_wr_valid;
  assign io_reasmWr_base = reasm_io_wr_base;
  assign io_reasmWr_off = reasm_io_wr_off;
  assign io_reasmWr_body = reasm_io_wr_body;
  assign io_reasmClr_valid = reasm_io_clr_valid;
  assign io_reasmClr_base = reasm_io_clr_base;
  assign reasm_io_faultClear = (io_faultClear_reasm || (fltClrAccept && io_mmio_wdata[3]));
  assign reasm_io_capAbsentClear = (io_faultClear_reasmCap || (capClrAccept && io_mmio_wdata[0]));
  assign mog_io_up_0_valid = (od_io_oMemPresent && (io_mem_slotSel == 2'b00));
  assign mog_io_up_0_payload = {{{{tagQ_dim,{tagQ_precision,{tagQ_lnid,{tagQ_thread,tagQ_wave}}}},od_io_oMemAddrMode},od_io_oMemStride},od_io_oMemOffset};
  always @(*) begin
    io_mem_upReady[0] = mog_io_up_0_ready;
    io_mem_upReady[1] = mog_io_up_1_ready;
    io_mem_upReady[2] = mog_io_up_2_ready;
    io_mem_upReady[3] = mog_io_up_3_ready;
  end

  assign io_mem_down_0_valid = mog_io_down_0_valid;
  assign io_mem_down_0_payload = mog_io_down_0_payload;
  assign mog_io_up_1_valid = (od_io_oMemPresent && (io_mem_slotSel == 2'b01));
  assign mog_io_up_1_payload = {{{{tagQ_dim,{tagQ_precision,{tagQ_lnid,{tagQ_thread,tagQ_wave}}}},od_io_oMemAddrMode},od_io_oMemStride},od_io_oMemOffset};
  assign io_mem_down_1_valid = mog_io_down_1_valid;
  assign io_mem_down_1_payload = mog_io_down_1_payload;
  assign mog_io_up_2_valid = (od_io_oMemPresent && (io_mem_slotSel == 2'b10));
  assign mog_io_up_2_payload = {{{{tagQ_dim,{tagQ_precision,{tagQ_lnid,{tagQ_thread,tagQ_wave}}}},od_io_oMemAddrMode},od_io_oMemStride},od_io_oMemOffset};
  assign io_mem_down_2_valid = mog_io_down_2_valid;
  assign io_mem_down_2_payload = mog_io_down_2_payload;
  assign mog_io_up_3_valid = (od_io_oMemPresent && (io_mem_slotSel == 2'b11));
  assign mog_io_up_3_payload = {{{{tagQ_dim,{tagQ_precision,{tagQ_lnid,{tagQ_thread,tagQ_wave}}}},od_io_oMemAddrMode},od_io_oMemStride},od_io_oMemOffset};
  assign io_mem_down_3_valid = mog_io_down_3_valid;
  assign io_mem_down_3_payload = mog_io_down_3_payload;
  assign io_mem_token = mog_io_token;
  assign io_mem_gateOpen = mog_io_gateOpen;
  assign io_hiuReq_ready = hiu_io_req_ready;
  assign io_install_ready = hiu_io_install_ready;
  assign hiu_io_faultClear = (io_faultClear_hiuPerm || (fltClrAccept && io_mmio_wdata[4]));
  assign io_phys_valid = (hiu_io_rsp_valid && hiu_io_rsp_granted);
  assign io_phys_frame = hiu_io_rsp_frame;
  assign io_hiuRsp_valid = hiu_io_rsp_valid;
  assign io_hiuRsp_granted = hiu_io_rsp_granted;
  assign io_hiuRsp_part = hiu_io_rsp_part;
  assign io_hiuRsp_write = hiu_io_rsp_write;
  assign io_hiuRsp_fromFill = hiu_io_rsp_fromFill;
  assign io_hiuRsp_perm_r = hiu_io_rsp_perm_r;
  assign io_hiuRsp_perm_w = hiu_io_rsp_perm_w;
  assign io_hiuRsp_perm_x = hiu_io_rsp_perm_x;
  assign io_sharedReq_ready = shared_1_io_req_ready;
  assign shared_1_io_faultClear = (io_faultClear_sharedBp || (fltClrAccept && io_mmio_wdata[9]));
  assign _zz_io_push_0_result_head_seq = shared_1_io_rsp_payload[96 : 0];
  assign _zz_io_push_0_result_head_tag_wave = _zz_io_push_0_result_head_seq[79 : 0];
  assign merge_io_push_0_result_head_tag_wave = _zz_io_push_0_result_head_tag_wave[31 : 0];
  assign merge_io_push_0_result_head_tag_thread = _zz_io_push_0_result_head_tag_wave[47 : 32];
  assign merge_io_push_0_result_head_tag_lnid = _zz_io_push_0_result_head_tag_wave[63 : 48];
  assign merge_io_push_0_result_head_tag_precision = _zz_io_push_0_result_head_tag_wave[71 : 64];
  assign merge_io_push_0_result_head_tag_dim = _zz_io_push_0_result_head_tag_wave[79 : 72];
  assign merge_io_push_0_result_head_seq = _zz_io_push_0_result_head_seq[87 : 80];
  assign merge_io_push_0_result_head_total = _zz_io_push_0_result_head_seq[95 : 88];
  assign merge_io_push_0_result_head_last = _zz_io_push_0_result_head_seq[96];
  assign merge_io_push_0_result_body = shared_1_io_rsp_payload[160 : 97];
  assign io_sharedPushStall = merge_io_push_0_stall;
  assign io_push_0_stall = merge_io_push_1_stall;
  assign io_push_1_stall = merge_io_push_2_stall;
  assign io_push_2_stall = merge_io_push_3_stall;
  assign merge_io_faultClear = (io_faultClear_fabricBp || (fltClrAccept && io_mmio_wdata[8]));
  assign io_bank_acqGranted = bank_io_acquire_granted;
  assign io_bank_rdData = bank_io_read_data;
  assign io_bank_rdOwned = bank_io_read_owned;
  assign bank_io_faultClear = (io_faultClear_bankWrite || (fltClrAccept && io_mmio_wdata[10]));
  assign io_fp_reqReady = fps_io_req_ready;
  assign io_fp_done = fps_io_oDone;
  assign io_fp_execValid = fps_io_oExecValid;
  assign io_fp_capAbsent = fps_io_oCapAbsent;
  assign io_fp_progMal = fps_io_oProgMal;
  assign io_fp_result = fps_io_oResult;
  assign fps_io_faultClearBp = (io_faultClear_fpBp || (fltClrAccept && io_mmio_wdata[14]));
  assign fps_io_faultClearBadProg = (io_faultClear_fpBadProg || (fltClrAccept && io_mmio_wdata[15]));
  assign cq_io_drain_pipe = {13'd0, hiu_io_occupancy};
  assign cq_io_drain_pending = {13'd0, shared_1_io_occupancy};
  assign cq_io_drain_output = {13'd0, merge_io_occupancy};
  assign cq_io_drain_ownSlots = {11'd0, bank_io_occupancy};
  assign cq_io_drain_contexts = {13'd0, reasm_io_occupancy};
  assign cq_io_drain_tokens = {13'd0, mog_io_occupancy};
  assign io_irq = cq_io_irq;
  assign mmioAligned = (io_mmio_addr[1 : 0] == 2'b00);
  assign selOwn = (io_mmio_addr[11 : 8] == 4'b0010);
  assign selCq = (io_mmio_addr[11 : 7] == 5'h06);
  assign selCfg = ((io_mmio_addr[11 : 10] == 2'b01) || (io_mmio_addr[11 : 10] == 2'b10));
  assign selMask = (io_mmio_addr[11 : 7] == 5'h1d);
  assign selFp = (io_mmio_addr[11 : 6] == 6'h3c);
  assign selAbort = (io_mmio_addr[11 : 6] == 6'h3d);
  assign selFault = (io_mmio_addr[11 : 6] == 6'h3e);
  assign selSq = (io_mmio_addr[11 : 7] == 5'h07);
  assign selXent = (io_mmio_addr[11 : 9] == 3'b110);
  assign selXctl = (io_mmio_addr[11 : 7] == 5'h1c);
  assign selIdent = (io_mmio_addr[11 : 6] == 6'h3f);
  assign selUnwired = (((selSq || selXent) || selXctl) || selIdent);
  assign own_io_wstrobe = (io_mmio_wstrobe && selOwn);
  assign own_io_rstrobe = (io_mmio_rstrobe && selOwn);
  assign own_io_faultClearCollide = (io_faultClear_ownCollide || (fltClrAccept && io_mmio_wdata[7]));
  assign own_io_faultClearBadWrite = (fltClrAccept && io_mmio_wdata[6]);
  assign cq_io_addr = io_mmio_addr[7 : 0];
  assign cq_io_wstrobe = (io_mmio_wstrobe && selCq);
  assign cq_io_rstrobe = (io_mmio_rstrobe && selCq);
  assign cq_io_faultClearOverflow = (fltClrAccept && io_mmio_wdata[16]);
  assign cq_io_faultClearBadWrite = (fltClrAccept && io_mmio_wdata[6]);
  assign cfgBlk_io_wstrobe = (io_mmio_wstrobe && selCfg);
  assign cfgBlk_io_rstrobe = (io_mmio_rstrobe && selCfg);
  assign cfgBlk_io_faultClearDup = (io_faultClear_cfgDupOwner || (fltClrAccept && io_mmio_wdata[5]));
  assign cfgBlk_io_faultClearBad = (io_faultClear_cfgBadWrite || (fltClrAccept && io_mmio_wdata[6]));
  always @(*) begin
    surfBadWr = 1'b0;
    if(when_Wt64Top_l1263) begin
      surfBadWr = 1'b1;
    end
    if(when_Wt64Top_l1304) begin
      surfBadWr = 1'b1;
    end
    if(when_Wt64Top_l1356) begin
      surfBadWr = 1'b1;
    end
    if(when_Wt64Top_l1406) begin
      surfBadWr = 1'b1;
    end
  end

  assign maskArea_wordOff = io_mmio_addr[6 : 2];
  assign maskArea_wr = ((io_mmio_wstrobe && selMask) && mmioAligned);
  assign maskArea_rd = (((io_mmio_rstrobe && (! io_mmio_wstrobe)) && selMask) && mmioAligned);
  assign maskArea_isKey = (maskArea_wordOff < 5'h08);
  assign maskArea_isNoncePart = (maskArea_wordOff == 5'h08);
  assign maskArea_isNonce = ((5'h09 <= maskArea_wordOff) && (maskArea_wordOff <= 5'h0e));
  assign maskArea_isRekey = (maskArea_wordOff == 5'h0f);
  assign maskArea_isStatus = (maskArea_wordOff == 5'h10);
  assign maskArea_partField = io_mmio_wdata[7 : 0];
  assign maskArea_partBad = (8'h04 <= maskArea_partField);
  assign mask_io_keyWr_valid = (maskArea_wr && maskArea_isKey);
  assign mask_io_keyWr_idx = maskArea_wordOff[2 : 0];
  assign maskArea_npWr = (maskArea_wr && maskArea_isNoncePart);
  assign maskArea_npRsvBad = ((io_mmio_wdata & 32'hffffff00) != 32'h0);
  assign maskArea_npReject = (maskArea_npWr && (maskArea_npRsvBad || maskArea_partBad));
  assign when_Wt64Top_l1236 = ((maskArea_npWr && (! maskArea_npRsvBad)) && (! maskArea_partBad));
  assign mask_io_nonceWr_valid = (maskArea_wr && maskArea_isNonce);
  assign mask_io_nonceWr_idx = (maskArea_wordOff[2 : 0] - 3'b001);
  assign maskArea_rkWr = (maskArea_wr && maskArea_isRekey);
  assign maskArea_rkRsvBad = ((io_mmio_wdata & 32'hffffff00) != 32'h0);
  assign maskArea_rkReject = (maskArea_rkWr && (maskArea_rkRsvBad || maskArea_partBad));
  assign mask_io_rekey_valid = ((maskArea_rkWr && (! maskArea_rkRsvBad)) && (! maskArea_partBad));
  assign mask_io_rekey_part = maskArea_partField[1:0];
  always @(*) begin
    maskArea_maskStat = 32'h0;
    maskArea_maskStat[3 : 0] = mask_io_maskReady;
    maskArea_maskStat[8] = mask_io_busy;
    maskArea_maskStat[9] = mask_io_rekey_ready;
  end

  assign when_Wt64Top_l1263 = ((maskArea_npReject || maskArea_rkReject) || (maskArea_wr && maskArea_isStatus));
  always @(*) begin
    maskArea_readValue = 32'h0;
    if(maskArea_isNoncePart) begin
      maskArea_readValue = {30'd0, _zz_maskArea_readValue};
    end
    if(maskArea_isStatus) begin
      maskArea_readValue = maskArea_maskStat;
    end
  end

  assign fpArea_wordOff = io_mmio_addr[5 : 2];
  assign fpArea_wr = ((io_mmio_wstrobe && selFp) && mmioAligned);
  assign fpArea_rd = (((io_mmio_rstrobe && (! io_mmio_wstrobe)) && selFp) && mmioAligned);
  assign fpArea_isProg = (fpArea_wordOff == 4'b0000);
  assign fpArea_isBind = (fpArea_wordOff == 4'b0001);
  assign fpArea_isStatus = (fpArea_wordOff == 4'b0010);
  assign fps_io_progWr_valid = (fpArea_wr && fpArea_isProg);
  assign fps_io_progWr_slot = io_mmio_wdata[31 : 24];
  assign fps_io_progWr_idx = io_mmio_wdata[23 : 16];
  assign fps_io_progWr_step = io_mmio_wdata[15 : 0];
  assign fpArea_bindRsvBad = ((io_mmio_wdata & 32'h7f000000) != 32'h0);
  assign fps_io_bindWr_valid = ((fpArea_wr && fpArea_isBind) && (! fpArea_bindRsvBad));
  assign fps_io_bindWr_key = io_mmio_wdata[15 : 0];
  assign fps_io_bindWr_en = io_mmio_wdata[31];
  assign fps_io_bindWr_slot = io_mmio_wdata[23 : 16];
  assign when_Wt64Top_l1304 = (((fpArea_wr && fpArea_isBind) && fpArea_bindRsvBad) || (fpArea_wr && fpArea_isStatus));
  always @(*) begin
    fpArea_fpStat = 32'h0;
    fpArea_fpStat[0] = fps_io_loadReady;
    fpArea_fpStat[1] = fps_io_oBusy;
  end

  always @(*) begin
    fpArea_readValue = 32'h0;
    if(fpArea_isStatus) begin
      fpArea_readValue = fpArea_fpStat;
    end
  end

  assign abortArea_wordOff = io_mmio_addr[5 : 2];
  assign abortArea_wr = ((io_mmio_wstrobe && selAbort) && mmioAligned);
  assign abortArea_rd = (((io_mmio_rstrobe && (! io_mmio_wstrobe)) && selAbort) && mmioAligned);
  assign abortArea_isTag0 = (abortArea_wordOff == 4'b0000);
  assign abortArea_isTag1 = (abortArea_wordOff == 4'b0001);
  assign abortArea_isTag2 = (abortArea_wordOff == 4'b0010);
  assign abortArea_isFire = (abortArea_wordOff == 4'b0011);
  assign abortArea_isCnt = (abortArea_wordOff == 4'b0100);
  assign abortArea_isInc = (abortArea_wordOff == 4'b0101);
  assign abortArea_isArm = (abortArea_wordOff == 4'b0110);
  assign when_Wt64Top_l1356 = (stg_io_badWrite || (abortArea_wr && ((abortArea_isCnt || abortArea_isInc) || abortArea_isArm)));
  always @(*) begin
    abortArea_readValue = 32'h0;
    if(abortArea_isCnt) begin
      abortArea_readValue = {24'd0, _zz_abortArea_readValue};
    end
    if(abortArea_isInc) begin
      abortArea_readValue = {29'd0, _zz_abortArea_readValue_1};
    end
    if(abortArea_isArm) begin
      abortArea_readValue = {29'd0, stg_io_armed};
    end
  end

  assign faultArea_wordOff = io_mmio_addr[5 : 2];
  assign faultArea_wr = ((io_mmio_wstrobe && selFault) && mmioAligned);
  assign faultArea_rd = (((io_mmio_rstrobe && (! io_mmio_wstrobe)) && selFault) && mmioAligned);
  assign faultArea_isStatus = (faultArea_wordOff == 4'b0000);
  assign faultArea_isClear = (faultArea_wordOff == 4'b0001);
  assign faultArea_isSummary = (faultArea_wordOff == 4'b0010);
  assign faultArea_isCapSt = (faultArea_wordOff == 4'b0011);
  assign faultArea_isCapClr = (faultArea_wordOff == 4'b0100);
  assign faultArea_clrRsvBad = ((io_mmio_wdata & 32'hfff80000) != 32'h0);
  assign faultArea_capRsvBad = ((io_mmio_wdata & 32'hfffffffc) != 32'h0);
  assign faultArea_doClr = ((faultArea_wr && faultArea_isClear) && (! faultArea_clrRsvBad));
  assign faultArea_doCapClr = ((faultArea_wr && faultArea_isCapClr) && (! faultArea_capRsvBad));
  assign fltClrAccept = faultArea_doClr;
  assign capClrAccept = faultArea_doCapClr;
  assign when_Wt64Top_l1406 = (((faultArea_wr && ((faultArea_isStatus || faultArea_isSummary) || faultArea_isCapSt)) || ((faultArea_wr && faultArea_isClear) && faultArea_clrRsvBad)) || ((faultArea_wr && faultArea_isCapClr) && faultArea_capRsvBad));
  assign io_fault_decodeWalk = walk_io_oFault;
  assign io_fault_operandDecode = od_io_oFault;
  assign io_fault_route = rj_io_fault;
  assign io_fault_reasm = reasm_io_fault;
  assign io_fault_reasmCap = reasm_io_capAbsent;
  assign io_fault_hiuPerm = hiu_io_faultPerm;
  assign io_fault_hiuMiss = hiu_io_missNotice;
  assign io_fault_cfgDupOwner = cfgBlk_io_faultDupOwner;
  assign io_fault_cfgBadWrite = cfgBlk_io_faultBadWrite;
  assign when_Common_l258 = (io_faultClear_cfgSurfBadWrite || (fltClrAccept && io_mmio_wdata[6]));
  assign io_fault_cfgSurfBadWrite = _zz_io_fault_cfgSurfBadWrite;
  assign io_fault_ownCollide = own_io_faultCollide;
  assign io_fault_ownBadWrite = own_io_faultBadWrite;
  assign io_fault_fabricBp = merge_io_fault;
  assign io_fault_sharedBp = shared_1_io_faultBpViolation;
  assign io_fault_bankWrite = bank_io_fault;
  assign io_fault_maskNoMask = mask_io_faultNoMask;
  assign io_fault_maskNonceDup = mask_io_faultNonceDup;
  assign io_fault_maskWrRekey = mask_io_faultWrDuringRekey;
  assign io_fault_fpBp = fps_io_faultBpViolation;
  assign io_fault_fpBadProg = fps_io_faultBadProg;
  assign io_fault_cqOverflow = cq_io_faultOverflow;
  assign io_fault_cqBadWrite = cq_io_faultBadWrite;
  assign when_Common_l258_1 = (capClrAccept && io_mmio_wdata[1]);
  assign io_fault_fpCapAbsent = _zz_io_fault_fpCapAbsent;
  always @(*) begin
    faultWords_status = 32'h0;
    faultWords_status[0] = io_fault_decodeWalk;
    faultWords_status[1] = io_fault_operandDecode;
    faultWords_status[2] = io_fault_route;
    faultWords_status[3] = io_fault_reasm;
    faultWords_status[4] = io_fault_hiuPerm;
    faultWords_status[5] = io_fault_cfgDupOwner;
    faultWords_status[6] = (((io_fault_cfgBadWrite || io_fault_cfgSurfBadWrite) || io_fault_cqBadWrite) || io_fault_ownBadWrite);
    faultWords_status[7] = io_fault_ownCollide;
    faultWords_status[8] = io_fault_fabricBp;
    faultWords_status[9] = io_fault_sharedBp;
    faultWords_status[10] = io_fault_bankWrite;
    faultWords_status[11] = io_fault_maskNoMask;
    faultWords_status[12] = io_fault_maskNonceDup;
    faultWords_status[13] = io_fault_maskWrRekey;
    faultWords_status[14] = io_fault_fpBp;
    faultWords_status[15] = io_fault_fpBadProg;
    faultWords_status[16] = io_fault_cqOverflow;
    faultWords_status[17] = 1'b0;
    faultWords_status[18] = 1'b0;
  end

  always @(*) begin
    faultWords_summary = 32'h0;
    faultWords_summary[0] = (|faultWords_status);
  end

  always @(*) begin
    faultWords_capStatus = 32'h0;
    faultWords_capStatus[0] = io_fault_reasmCap;
    faultWords_capStatus[1] = io_fault_fpCapAbsent;
  end

  always @(*) begin
    faultWords_readValue = 32'h0;
    if(faultArea_isStatus) begin
      faultWords_readValue = faultWords_status;
    end
    if(faultArea_isSummary) begin
      faultWords_readValue = faultWords_summary;
    end
    if(faultArea_isCapSt) begin
      faultWords_readValue = faultWords_capStatus;
    end
  end

  always @(*) begin
    io_mmio_ready = 1'b1;
    if(selOwn) begin
      io_mmio_ready = own_io_ready;
    end
    if(selCq) begin
      io_mmio_ready = cq_io_ready;
    end
    if(selCfg) begin
      io_mmio_ready = cfgBlk_io_ready;
    end
    if(when_Wt64Top_l1517) begin
      io_mmio_ready = fps_io_loadReady;
    end
  end

  assign when_Wt64Top_l1517 = (selFp && (fpArea_isProg || fpArea_isBind));
  assign mapRd = (((maskArea_rd || fpArea_rd) || abortArea_rd) || faultArea_rd);
  assign resvOffset = (! (((((((selOwn || selCq) || selCfg) || selMask) || selFp) || selAbort) || selFault) || selUnwired));
  assign resvRd = ((io_mmio_rstrobe && (! io_mmio_wstrobe)) && ((resvOffset || selUnwired) || ((((selMask || selFp) || selAbort) || selFault) && (! mmioAligned))));
  assign io_mmio_rvalid = ((((own_io_rvalid || cq_io_rvalid) || cfgBlk_io_rvalid) || mapRv) || resvRv);
  always @(*) begin
    io_mmio_rdata = 32'h0;
    if(own_io_rvalid) begin
      io_mmio_rdata = own_io_rdata;
    end
    if(cq_io_rvalid) begin
      io_mmio_rdata = cq_io_rdata;
    end
    if(cfgBlk_io_rvalid) begin
      io_mmio_rdata = cfgBlk_io_rdata;
    end
    if(mapRv) begin
      io_mmio_rdata = mapRdReg;
    end
  end

  assign mask_io_faultClearNoMask = (io_faultClear_maskNoMask || (fltClrAccept && io_mmio_wdata[11]));
  assign mask_io_faultClearNonceDup = (io_faultClear_maskNonceDup || (fltClrAccept && io_mmio_wdata[12]));
  assign mask_io_faultClearWrRekey = (io_faultClear_maskWrRekey || (fltClrAccept && io_mmio_wdata[13]));
  always @(posedge clk) begin
    tagQ_wave <= io_instr_tag_wave;
    tagQ_thread <= io_instr_tag_thread;
    tagQ_lnid <= io_instr_tag_lnid;
    tagQ_precision <= io_instr_tag_precision;
    tagQ_dim <= io_instr_tag_dim;
  end

  always @(posedge clk or posedge reset) begin
    if(reset) begin
      maskArea_noncePart <= 2'b00;
      _zz_io_fault_cfgSurfBadWrite <= 1'b0;
      _zz_io_fault_fpCapAbsent <= 1'b0;
      mapRdReg <= 32'h0;
      mapRv <= 1'b0;
      resvRv <= 1'b0;
    end else begin
      if(when_Wt64Top_l1236) begin
        maskArea_noncePart <= maskArea_partField[1:0];
      end
      if(when_Common_l258) begin
        _zz_io_fault_cfgSurfBadWrite <= 1'b0;
      end
      if(surfBadWr) begin
        _zz_io_fault_cfgSurfBadWrite <= 1'b1;
      end
      if(when_Common_l258_1) begin
        _zz_io_fault_fpCapAbsent <= 1'b0;
      end
      if(fps_io_oCapAbsent) begin
        _zz_io_fault_fpCapAbsent <= 1'b1;
      end
      mapRv <= mapRd;
      if(mapRd) begin
        mapRdReg <= 32'h0;
        if(selMask) begin
          mapRdReg <= maskArea_readValue;
        end
        if(selFp) begin
          mapRdReg <= fpArea_readValue;
        end
        if(selAbort) begin
          mapRdReg <= abortArea_readValue;
        end
        if(selFault) begin
          mapRdReg <= faultWords_readValue;
        end
      end
      resvRv <= resvRd;
    end
  end


endmodule

module AbortStaging (
  input  wire          io_wr,
  input  wire          io_selTag0,
  input  wire          io_selTag1,
  input  wire          io_selTag2,
  input  wire          io_selFire,
  input  wire [31:0]   io_wdata,
  output wire          io_badWrite,
  output wire [2:0]    io_armed,
  output wire          io_fire,
  output wire [31:0]   io_tag_wave,
  output wire [15:0]   io_tag_thread,
  output wire [15:0]   io_tag_lnid,
  output wire [7:0]    io_tag_precision,
  output wire [7:0]    io_tag_dim,
  input  wire          clk,
  input  wire          reset
);

  wire                tag2RsvBad;
  wire                fireRsvBad;
  wire                okTag0;
  wire                okTag1;
  wire                okTag2;
  wire                okFire;
  reg        [31:0]   tag0;
  reg        [31:0]   tag1;
  reg        [15:0]   tag2;
  reg        [2:0]    armed;
  wire       [31:0]   abWords_2;
  wire                stagedRsvBad;

  assign tag2RsvBad = ((io_wdata & 32'hffff0000) != 32'h0);
  assign fireRsvBad = ((io_wdata & 32'hfffffffe) != 32'h0);
  assign okTag0 = (io_wr && io_selTag0);
  assign okTag1 = (io_wr && io_selTag1);
  assign okTag2 = ((io_wr && io_selTag2) && (! tag2RsvBad));
  assign okFire = ((io_wr && io_selFire) && (! fireRsvBad));
  assign abWords_2 = {16'h0,tag2};
  assign stagedRsvBad = (abWords_2[31 : 16] != 16'h0);
  assign io_fire = (((okFire && io_wdata[0]) && (&armed)) && (! stagedRsvBad));
  assign io_tag_wave = tag0;
  assign io_tag_thread = tag1[31 : 16];
  assign io_tag_lnid = tag1[15 : 0];
  assign io_tag_precision = abWords_2[15 : 8];
  assign io_tag_dim = abWords_2[7 : 0];
  assign io_armed = armed;
  assign io_badWrite = (((io_wr && io_selTag2) && tag2RsvBad) || ((io_wr && io_selFire) && fireRsvBad));
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      tag0 <= 32'h0;
      tag1 <= 32'h0;
      tag2 <= 16'h0;
      armed <= 3'b000;
    end else begin
      if(okTag0) begin
        tag0 <= io_wdata;
        armed[0] <= 1'b1;
      end
      if(okTag1) begin
        tag1 <= io_wdata;
        armed[1] <= 1'b1;
      end
      if(okTag2) begin
        tag2 <= io_wdata[15 : 0];
        armed[2] <= 1'b1;
      end
      if(okFire) begin
        armed <= 3'b000;
      end
    end
  end


endmodule

module CompletionUnit (
  input  wire [7:0]    io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output wire [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  input  wire          io_comp_valid,
  input  wire [31:0]   io_comp_tag_wave,
  input  wire [15:0]   io_comp_tag_thread,
  input  wire [15:0]   io_comp_tag_lnid,
  input  wire [7:0]    io_comp_tag_precision,
  input  wire [7:0]    io_comp_tag_dim,
  input  wire [7:0]    io_comp_base,
  input  wire [7:0]    io_comp_total,
  output wire          io_comp_ready,
  output wire          io_irq,
  input  wire [15:0]   io_drain_pipe,
  input  wire [15:0]   io_drain_pending,
  input  wire [15:0]   io_drain_output,
  input  wire [15:0]   io_drain_ownSlots,
  input  wire [15:0]   io_drain_contexts,
  input  wire [15:0]   io_drain_tokens,
  output wire          io_faultOverflow,
  input  wire          io_faultClearOverflow,
  output wire          io_faultBadWrite,
  input  wire          io_faultClearBadWrite,
  input  wire          clk,
  input  wire          reset
);

  reg        [255:0]  ring_spinal_port1;
  wire       [2:0]    _zz_full;
  wire       [7:0]    _zz_descWords_4;
  wire       [7:0]    _zz_descWords_5;
  wire       [31:0]   _zz_readValue;
  wire       [0:0]    _zz_readValue_1;
  wire       [31:0]   _zz_readValue_2;
  wire       [0:0]    _zz_readValue_3;
  wire       [31:0]   _zz_readValue_4;
  wire       [31:0]   _zz_readValue_5;
  wire       [31:0]   _zz_readValue_6;
  wire       [31:0]   _zz_readValue_7;
  wire       [31:0]   _zz_readValue_8;
  wire       [31:0]   _zz_readValue_9;
  reg        [31:0]   _zz_io_rdata;
  reg        [31:0]   headReg;
  wire       [2:0]    head;
  reg        [2:0]    tail;
  wire                empty;
  wire                full;
  wire       [2:0]    occ;
  wire       [31:0]   descWords_0;
  wire       [31:0]   descWords_4;
  wire       [31:0]   descWords_5;
  wire       [31:0]   descWords_6;
  wire       [31:0]   descWords_7;
  wire       [255:0]  desc;
  wire                doPush;
  wire                shove;
  wire                aligned;
  wire                acceptR;
  wire                isSize;
  wire                isHead;
  wire                isTail;
  wire                isIrqSt;
  wire                isIrqMk;
  wire                isIrqClr;
  wire                isWindow;
  wire                isDrain;
  wire                isOcc;
  wire                isAllZ;
  wire                isRoOff;
  wire                doWr;
  wire                sizeRsvBad;
  wire                mkRsvBad;
  wire                clrRsvBad;
  wire                sizeValBad;
  wire                irqClrPulse;
  reg        [31:0]   irqMaskReg;
  wire                irqMask;
  wire                when_CompletionUnit_l572;
  wire                when_CompletionUnit_l573;
  wire                badWrite;
  reg                 irqSticky;
  reg                 faultOv;
  reg                 _zz_io_faultBadWrite;
  wire                allZero;
  reg        [31:0]   readValue;
  wire       [255:0]  ringRd;
  reg        [31:0]   rdataReg;
  reg                 winSel;
  reg        [2:0]    winWord;
  reg                 acceptR_regNext;
  reg [255:0] ring [0:7];

  assign _zz_full = (tail + 3'b001);
  assign _zz_descWords_4 = io_comp_base;
  assign _zz_descWords_5 = io_comp_total;
  assign _zz_readValue = {29'd0, tail};
  assign _zz_readValue_1 = irqSticky;
  assign _zz_readValue_2 = {29'd0, occ};
  assign _zz_readValue_3 = allZero;
  assign _zz_readValue_4 = {16'd0, io_drain_pipe};
  assign _zz_readValue_5 = {16'd0, io_drain_pending};
  assign _zz_readValue_6 = {16'd0, io_drain_output};
  assign _zz_readValue_7 = {16'd0, io_drain_ownSlots};
  assign _zz_readValue_8 = {16'd0, io_drain_contexts};
  assign _zz_readValue_9 = {16'd0, io_drain_tokens};
  always @(posedge clk) begin
    if(doPush) begin
      ring[tail] <= desc;
    end
  end

  always @(posedge clk) begin
    if(acceptR) begin
      ring_spinal_port1 <= ring[head];
    end
  end

  always @(*) begin
    case(winWord)
      3'b000 : _zz_io_rdata = ringRd[31 : 0];
      3'b001 : _zz_io_rdata = ringRd[63 : 32];
      3'b010 : _zz_io_rdata = ringRd[95 : 64];
      3'b011 : _zz_io_rdata = ringRd[127 : 96];
      3'b100 : _zz_io_rdata = ringRd[159 : 128];
      3'b101 : _zz_io_rdata = ringRd[191 : 160];
      3'b110 : _zz_io_rdata = ringRd[223 : 192];
      default : _zz_io_rdata = ringRd[255 : 224];
    endcase
  end

  assign io_ready = 1'b1;
  assign head = headReg[2 : 0];
  assign empty = (head == tail);
  assign full = (_zz_full == head);
  assign occ = (tail - head);
  assign io_comp_ready = (! full);
  assign descWords_0 = 32'h00000001;
  assign descWords_4 = {24'd0, _zz_descWords_4};
  assign descWords_5 = {24'd0, _zz_descWords_5};
  assign descWords_6 = 32'h0;
  assign descWords_7 = 32'h0;
  assign desc = {{{{{{{descWords_7,descWords_6},descWords_5},descWords_4},{{16'h0,io_comp_tag_precision},io_comp_tag_dim}},{io_comp_tag_thread,io_comp_tag_lnid}},io_comp_tag_wave},descWords_0};
  assign doPush = (io_comp_valid && (! full));
  assign shove = (io_comp_valid && full);
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign acceptR = ((! io_wstrobe) && io_rstrobe);
  assign isSize = (io_addr == 8'h08);
  assign isHead = (io_addr == 8'h0c);
  assign isTail = (io_addr == 8'h10);
  assign isIrqSt = (io_addr == 8'h20);
  assign isIrqMk = (io_addr == 8'h24);
  assign isIrqClr = (io_addr == 8'h28);
  assign isWindow = (io_addr[7 : 5] == 3'b010);
  assign isDrain = ((((((io_addr == 8'h60) || (io_addr == 8'h64)) || (io_addr == 8'h68)) || (io_addr == 8'h6c)) || (io_addr == 8'h70)) || (io_addr == 8'h74));
  assign isOcc = (io_addr == 8'h78);
  assign isAllZ = (io_addr == 8'h7c);
  assign isRoOff = (((((isTail || isIrqSt) || isWindow) || isDrain) || isOcc) || isAllZ);
  assign doWr = (io_wstrobe && aligned);
  assign sizeRsvBad = ((io_wdata & 32'hffffffe0) != 32'h0);
  assign mkRsvBad = ((io_wdata & 32'hfffffffe) != 32'h0);
  assign clrRsvBad = ((io_wdata & 32'hfffffffe) != 32'h0);
  assign sizeValBad = (io_wdata[4 : 0] != 5'h03);
  assign irqClrPulse = (((doWr && isIrqClr) && (! clrRsvBad)) && io_wdata[0]);
  assign irqMask = irqMaskReg[0];
  assign when_CompletionUnit_l572 = (doWr && isHead);
  assign when_CompletionUnit_l573 = ((doWr && isIrqMk) && (! mkRsvBad));
  assign badWrite = (doWr && (((isRoOff || (isSize && (sizeRsvBad || sizeValBad))) || (isIrqMk && mkRsvBad)) || (isIrqClr && clrRsvBad)));
  assign io_irq = (irqSticky && (! irqMask));
  assign io_faultOverflow = faultOv;
  assign io_faultBadWrite = _zz_io_faultBadWrite;
  assign allZero = (((((((io_drain_pipe == 16'h0) && (io_drain_pending == 16'h0)) && (io_drain_output == 16'h0)) && (io_drain_ownSlots == 16'h0)) && (io_drain_contexts == 16'h0)) && (io_drain_tokens == 16'h0)) && (occ == 3'b000));
  always @(*) begin
    readValue = 32'h0;
    if(aligned) begin
      case(io_addr)
        8'h08 : begin
          readValue = 32'h00000003;
        end
        8'h0c : begin
          readValue = headReg;
        end
        8'h10 : begin
          readValue = _zz_readValue;
        end
        8'h20 : begin
          readValue = {31'd0, _zz_readValue_1};
        end
        8'h24 : begin
          readValue = irqMaskReg;
        end
        8'h78 : begin
          readValue = _zz_readValue_2;
        end
        8'h7c : begin
          readValue = {31'd0, _zz_readValue_3};
        end
        8'h60 : begin
          readValue = _zz_readValue_4;
        end
        8'h64 : begin
          readValue = _zz_readValue_5;
        end
        8'h68 : begin
          readValue = _zz_readValue_6;
        end
        8'h6c : begin
          readValue = _zz_readValue_7;
        end
        8'h70 : begin
          readValue = _zz_readValue_8;
        end
        8'h74 : begin
          readValue = _zz_readValue_9;
        end
        default : begin
        end
      endcase
    end
  end

  assign ringRd = ring_spinal_port1;
  assign io_rvalid = acceptR_regNext;
  assign io_rdata = (winSel ? _zz_io_rdata : rdataReg);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      headReg <= 32'h0;
      tail <= 3'b000;
      irqMaskReg <= 32'h00000001;
      irqSticky <= 1'b0;
      faultOv <= 1'b0;
      _zz_io_faultBadWrite <= 1'b0;
      rdataReg <= 32'h0;
      winSel <= 1'b0;
      winWord <= 3'b000;
      acceptR_regNext <= 1'b0;
    end else begin
      if(doPush) begin
        tail <= (tail + 3'b001);
      end
      if(when_CompletionUnit_l572) begin
        headReg <= (io_wdata & 32'h00000007);
      end
      if(when_CompletionUnit_l573) begin
        irqMaskReg <= io_wdata;
      end
      if(irqClrPulse) begin
        irqSticky <= 1'b0;
      end
      if(doPush) begin
        irqSticky <= 1'b1;
      end
      if(io_faultClearOverflow) begin
        faultOv <= 1'b0;
      end
      if(shove) begin
        faultOv <= 1'b1;
      end
      if(io_faultClearBadWrite) begin
        _zz_io_faultBadWrite <= 1'b0;
      end
      if(badWrite) begin
        _zz_io_faultBadWrite <= 1'b1;
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdataReg <= readValue;
        winSel <= ((aligned && isWindow) && (! empty));
        winWord <= io_addr[4 : 2];
      end
    end
  end


endmodule

module StepSequencer (
  input  wire          io_req_valid,
  input  wire [7:0]    io_req_opKind,
  input  wire [7:0]    io_req_precision,
  input  wire [31:0]   io_req_a,
  input  wire [31:0]   io_req_b,
  input  wire [31:0]   io_req_c,
  output wire          io_req_ready,
  output wire          io_oDone,
  output wire          io_oExecValid,
  output wire          io_oCapAbsent,
  output wire          io_oProgMal,
  output wire [31:0]   io_oResult,
  output wire          io_oBusy,
  input  wire          io_progWr_valid,
  input  wire [7:0]    io_progWr_slot,
  input  wire [7:0]    io_progWr_idx,
  input  wire [15:0]   io_progWr_step,
  input  wire          io_bindWr_valid,
  input  wire [15:0]   io_bindWr_key,
  input  wire          io_bindWr_en,
  input  wire [7:0]    io_bindWr_slot,
  output wire          io_loadReady,
  output wire          io_faultBpViolation,
  output wire          io_faultBadProg,
  input  wire          io_faultClearBp,
  input  wire          io_faultClearBadProg,
  input  wire          clk,
  input  wire          reset
);

  reg        [13:0]   progMem_spinal_port1;
  reg        [4:0]    selMem_spinal_port1;
  wire       [8:0]    _zz_progMem_port;
  wire       [13:0]   _zz_progMem_port_1;
  reg        [31:0]   _zz_opA;
  reg        [31:0]   _zz_opB;
  reg        [15:0]   initCnt;
  reg                 initDone;
  wire                when_StepSequencer_l280;
  wire                when_StepSequencer_l282;
  wire                stepResvBad;
  wire                progWrBad;
  wire                progWrOk;
  wire                bindWrBad;
  reg                 selWrEn;
  reg        [15:0]   selWrAddr;
  reg        [4:0]    selWrData;
  wire                when_StepSequencer_l317;
  wire                when_StepSequencer_l320;
  reg        [1:0]    state;
  wire                bpViolation;
  reg                 _zz_io_faultBpViolation;
  wire                accept;
  reg        [31:0]   scratch_0;
  reg        [31:0]   scratch_1;
  reg        [31:0]   scratch_2;
  reg        [31:0]   scratch_3;
  reg        [31:0]   scratch_4;
  reg        [31:0]   scratch_5;
  reg        [31:0]   scratch_6;
  reg        [31:0]   scratch_7;
  reg        [31:0]   scratch_8;
  reg        [31:0]   scratch_9;
  reg        [31:0]   scratch_10;
  reg        [31:0]   scratch_11;
  reg        [31:0]   scratch_12;
  reg        [31:0]   scratch_13;
  reg        [31:0]   scratch_14;
  reg        [31:0]   scratch_15;
  wire       [15:0]   key;
  wire       [15:0]   _zz_selRd;
  wire       [4:0]    selRd;
  wire                selV;
  wire       [3:0]    selSlot;
  reg        [3:0]    slotReg;
  reg        [4:0]    fetchPc;
  reg        [4:0]    execCnt;
  reg                 fetchEn;
  reg        [8:0]    fetchAddr;
  wire       [13:0]   stepWord;
  reg                 rDone;
  reg                 rCapa;
  reg                 rMal;
  reg        [31:0]   rResult;
  wire                when_StepSequencer_l387;
  wire                stLast;
  wire                stUnit;
  wire       [3:0]    stSrcA;
  wire       [3:0]    stSrcB;
  wire       [3:0]    stDst;
  wire       [31:0]   opA;
  wire       [31:0]   opB;
  wire       [63:0]   mulProd;
  wire       [31:0]   addSum;
  wire       [31:0]   wb;
  wire                when_StepSequencer_l433;
  wire       [15:0]   _zz_5;
  wire                when_StepSequencer_l444;
  wire                runaway;
  wire                when_Common_l259;
  reg                 _zz_io_faultBadProg;
  reg [13:0] progMem [0:511];
  reg [4:0] selMem [0:65535];

  assign _zz_progMem_port = {io_progWr_slot[3 : 0],io_progWr_idx[4 : 0]};
  assign _zz_progMem_port_1 = io_progWr_step[13 : 0];
  always @(posedge clk) begin
    if(progWrOk) begin
      progMem[_zz_progMem_port] <= _zz_progMem_port_1;
    end
  end

  always @(posedge clk) begin
    if(fetchEn) begin
      progMem_spinal_port1 <= progMem[fetchAddr];
    end
  end

  always @(posedge clk) begin
    if(selWrEn) begin
      selMem[selWrAddr] <= selWrData;
    end
  end

  always @(posedge clk) begin
    if(accept) begin
      selMem_spinal_port1 <= selMem[_zz_selRd];
    end
  end

  always @(*) begin
    case(stSrcA)
      4'b0000 : _zz_opA = scratch_0;
      4'b0001 : _zz_opA = scratch_1;
      4'b0010 : _zz_opA = scratch_2;
      4'b0011 : _zz_opA = scratch_3;
      4'b0100 : _zz_opA = scratch_4;
      4'b0101 : _zz_opA = scratch_5;
      4'b0110 : _zz_opA = scratch_6;
      4'b0111 : _zz_opA = scratch_7;
      4'b1000 : _zz_opA = scratch_8;
      4'b1001 : _zz_opA = scratch_9;
      4'b1010 : _zz_opA = scratch_10;
      4'b1011 : _zz_opA = scratch_11;
      4'b1100 : _zz_opA = scratch_12;
      4'b1101 : _zz_opA = scratch_13;
      4'b1110 : _zz_opA = scratch_14;
      default : _zz_opA = scratch_15;
    endcase
  end

  always @(*) begin
    case(stSrcB)
      4'b0000 : _zz_opB = scratch_0;
      4'b0001 : _zz_opB = scratch_1;
      4'b0010 : _zz_opB = scratch_2;
      4'b0011 : _zz_opB = scratch_3;
      4'b0100 : _zz_opB = scratch_4;
      4'b0101 : _zz_opB = scratch_5;
      4'b0110 : _zz_opB = scratch_6;
      4'b0111 : _zz_opB = scratch_7;
      4'b1000 : _zz_opB = scratch_8;
      4'b1001 : _zz_opB = scratch_9;
      4'b1010 : _zz_opB = scratch_10;
      4'b1011 : _zz_opB = scratch_11;
      4'b1100 : _zz_opB = scratch_12;
      4'b1101 : _zz_opB = scratch_13;
      4'b1110 : _zz_opB = scratch_14;
      default : _zz_opB = scratch_15;
    endcase
  end

  assign when_StepSequencer_l280 = (! initDone);
  assign when_StepSequencer_l282 = (initCnt == 16'hffff);
  assign io_loadReady = initDone;
  assign stepResvBad = (io_progWr_step[15 : 14] != 2'b00);
  assign progWrBad = ((io_progWr_valid && io_loadReady) && (((8'h0a <= io_progWr_slot) || (8'h20 <= io_progWr_idx)) || stepResvBad));
  assign progWrOk = ((io_progWr_valid && io_loadReady) && (! progWrBad));
  assign bindWrBad = (((io_bindWr_valid && io_loadReady) && io_bindWr_en) && (8'h0a <= io_bindWr_slot));
  always @(*) begin
    selWrEn = 1'b0;
    if(when_StepSequencer_l317) begin
      selWrEn = 1'b1;
    end else begin
      if(when_StepSequencer_l320) begin
        selWrEn = 1'b1;
      end
    end
  end

  always @(*) begin
    selWrAddr = 16'h0;
    if(when_StepSequencer_l317) begin
      selWrAddr = initCnt;
    end else begin
      if(when_StepSequencer_l320) begin
        selWrAddr = io_bindWr_key;
      end
    end
  end

  always @(*) begin
    selWrData = 5'h0;
    if(!when_StepSequencer_l317) begin
      if(when_StepSequencer_l320) begin
        if(io_bindWr_en) begin
          selWrData = {1'b1,io_bindWr_slot[3 : 0]};
        end
      end
    end
  end

  assign when_StepSequencer_l317 = (! initDone);
  assign when_StepSequencer_l320 = (io_bindWr_valid && (! bindWrBad));
  assign io_req_ready = (initDone && (state == 2'b00));
  assign io_oBusy = (state != 2'b00);
  assign bpViolation = (io_req_valid && (! io_req_ready));
  assign io_faultBpViolation = _zz_io_faultBpViolation;
  assign accept = (io_req_valid && io_req_ready);
  assign key = {io_req_opKind,io_req_precision};
  assign _zz_selRd = key;
  assign selRd = selMem_spinal_port1;
  assign selV = selRd[4];
  assign selSlot = selRd[3 : 0];
  always @(*) begin
    fetchEn = 1'b0;
    if(when_StepSequencer_l387) begin
      if(selV) begin
        fetchEn = 1'b1;
      end
    end
    if(when_StepSequencer_l433) begin
      if(!stLast) begin
        if(!when_StepSequencer_l444) begin
          fetchEn = 1'b1;
        end
      end
    end
  end

  always @(*) begin
    fetchAddr = {slotReg,fetchPc};
    if(when_StepSequencer_l387) begin
      if(selV) begin
        fetchAddr = {selSlot,5'h0};
      end
    end
  end

  assign stepWord = progMem_spinal_port1;
  assign when_StepSequencer_l387 = (state == 2'b01);
  assign stLast = stepWord[0];
  assign stUnit = stepWord[1];
  assign stSrcA = stepWord[5 : 2];
  assign stSrcB = stepWord[9 : 6];
  assign stDst = stepWord[13 : 10];
  assign opA = _zz_opA;
  assign opB = _zz_opB;
  assign mulProd = (opA * opB);
  assign addSum = (opA + opB);
  assign wb = (stUnit ? mulProd[31 : 0] : addSum);
  assign when_StepSequencer_l433 = (state == 2'b10);
  assign _zz_5 = ({15'd0,1'b1} <<< stDst);
  assign when_StepSequencer_l444 = (execCnt == 5'h1f);
  assign runaway = (((state == 2'b10) && (! stLast)) && (execCnt == 5'h1f));
  assign when_Common_l259 = ((progWrBad || bindWrBad) || runaway);
  assign io_faultBadProg = _zz_io_faultBadProg;
  assign io_oDone = rDone;
  assign io_oCapAbsent = (rDone && rCapa);
  assign io_oProgMal = (rDone && rMal);
  assign io_oExecValid = ((rDone && (! rCapa)) && (! rMal));
  assign io_oResult = rResult;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      initCnt <= 16'h0;
      initDone <= 1'b0;
      state <= 2'b00;
      _zz_io_faultBpViolation <= 1'b0;
      scratch_0 <= 32'h0;
      scratch_1 <= 32'h0;
      scratch_2 <= 32'h0;
      scratch_3 <= 32'h0;
      scratch_4 <= 32'h0;
      scratch_5 <= 32'h0;
      scratch_6 <= 32'h0;
      scratch_7 <= 32'h0;
      scratch_8 <= 32'h0;
      scratch_9 <= 32'h0;
      scratch_10 <= 32'h0;
      scratch_11 <= 32'h0;
      scratch_12 <= 32'h0;
      scratch_13 <= 32'h0;
      scratch_14 <= 32'h0;
      scratch_15 <= 32'h0;
      slotReg <= 4'b0000;
      fetchPc <= 5'h0;
      execCnt <= 5'h0;
      rDone <= 1'b0;
      rCapa <= 1'b0;
      rMal <= 1'b0;
      rResult <= 32'h0;
      _zz_io_faultBadProg <= 1'b0;
    end else begin
      if(when_StepSequencer_l280) begin
        initCnt <= (initCnt + 16'h0001);
        if(when_StepSequencer_l282) begin
          initDone <= 1'b1;
        end
      end
      if(io_faultClearBp) begin
        _zz_io_faultBpViolation <= 1'b0;
      end
      if(bpViolation) begin
        _zz_io_faultBpViolation <= 1'b1;
      end
      if(accept) begin
        scratch_0 <= io_req_a;
        scratch_1 <= io_req_b;
        scratch_2 <= io_req_c;
        state <= 2'b01;
      end
      rDone <= 1'b0;
      rCapa <= 1'b0;
      rMal <= 1'b0;
      if(when_StepSequencer_l387) begin
        if(selV) begin
          slotReg <= selSlot;
          fetchPc <= 5'h01;
          execCnt <= 5'h0;
          state <= 2'b10;
        end else begin
          rDone <= 1'b1;
          rCapa <= 1'b1;
          state <= 2'b00;
        end
      end
      if(when_StepSequencer_l433) begin
        if(_zz_5[0]) begin
          scratch_0 <= wb;
        end
        if(_zz_5[1]) begin
          scratch_1 <= wb;
        end
        if(_zz_5[2]) begin
          scratch_2 <= wb;
        end
        if(_zz_5[3]) begin
          scratch_3 <= wb;
        end
        if(_zz_5[4]) begin
          scratch_4 <= wb;
        end
        if(_zz_5[5]) begin
          scratch_5 <= wb;
        end
        if(_zz_5[6]) begin
          scratch_6 <= wb;
        end
        if(_zz_5[7]) begin
          scratch_7 <= wb;
        end
        if(_zz_5[8]) begin
          scratch_8 <= wb;
        end
        if(_zz_5[9]) begin
          scratch_9 <= wb;
        end
        if(_zz_5[10]) begin
          scratch_10 <= wb;
        end
        if(_zz_5[11]) begin
          scratch_11 <= wb;
        end
        if(_zz_5[12]) begin
          scratch_12 <= wb;
        end
        if(_zz_5[13]) begin
          scratch_13 <= wb;
        end
        if(_zz_5[14]) begin
          scratch_14 <= wb;
        end
        if(_zz_5[15]) begin
          scratch_15 <= wb;
        end
        if(stUnit) begin
          scratch_15 <= mulProd[63 : 32];
        end
        if(stLast) begin
          rResult <= wb;
          rDone <= 1'b1;
          state <= 2'b00;
        end else begin
          if(when_StepSequencer_l444) begin
            rDone <= 1'b1;
            rMal <= 1'b1;
            state <= 2'b00;
          end else begin
            execCnt <= (execCnt + 5'h01);
            fetchPc <= (fetchPc + 5'h01);
          end
        end
      end
      if(io_faultClearBadProg) begin
        _zz_io_faultBadProg <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_faultBadProg <= 1'b1;
      end
    end
  end


endmodule

module MaskUnit (
  input  wire          io_keyWr_valid,
  input  wire [2:0]    io_keyWr_idx,
  input  wire [31:0]   io_keyWr_data,
  input  wire          io_nonceWr_valid,
  input  wire [1:0]    io_nonceWr_part,
  input  wire [2:0]    io_nonceWr_idx,
  input  wire [31:0]   io_nonceWr_data,
  input  wire          io_rekey_valid,
  output wire          io_rekey_ready,
  input  wire [1:0]    io_rekey_part,
  output wire [3:0]    io_maskReady,
  output wire          io_busy,
  input  wire          io_en,
  input  wire          io_req_valid,
  input  wire [1:0]    io_req_part,
  input  wire [31:0]   io_req_frame,
  output wire          io_rsp_valid,
  output wire [31:0]   io_rsp_frame,
  output wire          io_faultNoMask,
  output wire          io_faultNonceDup,
  output wire          io_faultWrDuringRekey,
  input  wire          io_faultClearNoMask,
  input  wire          io_faultClearNonceDup,
  input  wire          io_faultClearWrRekey,
  input  wire          clk,
  input  wire          reset
);

  reg        [191:0]  _zz_reqNonce;
  wire                _zz_nonceDup;
  wire                _zz_nonceDup_1;
  wire       [1:0]    _zz_nonceDup_2;
  reg        [31:0]   _zz_st_12;
  reg        [31:0]   _zz_st_13;
  reg        [31:0]   _zz_st_14;
  reg        [31:0]   _zz_st_15;
  reg        [31:0]   _zz_st_14_1;
  reg        [31:0]   _zz_st_15_1;
  wire       [11:0]   _zz__zz_maskFrame_0;
  wire       [19:0]   _zz__zz_maskFrame_0_1;
  wire       [19:0]   _zz__zz_maskFrame_0_2;
  wire       [19:0]   _zz__zz_maskFrame_0_3;
  wire       [0:0]    _zz__zz_maskFrame_0_4;
  reg        [31:0]   _zz_rFrame;
  reg                 _zz_noMaskFire;
  reg        [31:0]   key_0;
  reg        [31:0]   key_1;
  reg        [31:0]   key_2;
  reg        [31:0]   key_3;
  reg        [31:0]   key_4;
  reg        [31:0]   key_5;
  reg        [31:0]   key_6;
  reg        [31:0]   key_7;
  reg        [31:0]   nonce_0_0;
  reg        [31:0]   nonce_0_1;
  reg        [31:0]   nonce_0_2;
  reg        [31:0]   nonce_0_3;
  reg        [31:0]   nonce_0_4;
  reg        [31:0]   nonce_0_5;
  reg        [31:0]   nonce_1_0;
  reg        [31:0]   nonce_1_1;
  reg        [31:0]   nonce_1_2;
  reg        [31:0]   nonce_1_3;
  reg        [31:0]   nonce_1_4;
  reg        [31:0]   nonce_1_5;
  reg        [31:0]   nonce_2_0;
  reg        [31:0]   nonce_2_1;
  reg        [31:0]   nonce_2_2;
  reg        [31:0]   nonce_2_3;
  reg        [31:0]   nonce_2_4;
  reg        [31:0]   nonce_2_5;
  reg        [31:0]   nonce_3_0;
  reg        [31:0]   nonce_3_1;
  reg        [31:0]   nonce_3_2;
  reg        [31:0]   nonce_3_3;
  reg        [31:0]   nonce_3_4;
  reg        [31:0]   nonce_3_5;
  reg        [31:0]   maskFrame_0;
  reg        [31:0]   maskFrame_1;
  reg        [31:0]   maskFrame_2;
  reg        [31:0]   maskFrame_3;
  reg                 maskValid_0;
  reg                 maskValid_1;
  reg                 maskValid_2;
  reg                 maskValid_3;
  reg        [2:0]    phase;
  reg        [31:0]   st_0;
  reg        [31:0]   st_1;
  reg        [31:0]   st_2;
  reg        [31:0]   st_3;
  reg        [31:0]   st_4;
  reg        [31:0]   st_5;
  reg        [31:0]   st_6;
  reg        [31:0]   st_7;
  reg        [31:0]   st_8;
  reg        [31:0]   st_9;
  reg        [31:0]   st_10;
  reg        [31:0]   st_11;
  reg        [31:0]   st_12;
  reg        [31:0]   st_13;
  reg        [31:0]   st_14;
  reg        [31:0]   st_15;
  reg        [4:0]    cnt;
  reg        [1:0]    actPart;
  reg                 compDirty;
  wire                engineBusy;
  wire                rekeyFire;
  wire                _zz_roundNext_0;
  wire       [31:0]   _zz_roundNext_0_1;
  wire       [31:0]   _zz_roundNext_10;
  wire       [31:0]   _zz_roundNext_10_1;
  wire       [31:0]   _zz_roundNext_10_2;
  wire       [31:0]   _zz_roundNext_0_2;
  wire       [31:0]   _zz_roundNext_0_3;
  wire       [31:0]   _zz_roundNext_0_4;
  wire       [31:0]   _zz_roundNext_15;
  wire       [31:0]   _zz_roundNext_15_1;
  wire       [31:0]   _zz_roundNext_10_3;
  wire       [31:0]   _zz_roundNext_5;
  wire       [31:0]   _zz_roundNext_1;
  wire       [31:0]   _zz_roundNext_11;
  wire       [31:0]   _zz_roundNext_11_1;
  wire       [31:0]   _zz_roundNext_11_2;
  wire       [31:0]   _zz_roundNext_1_1;
  wire       [31:0]   _zz_roundNext_1_2;
  wire       [31:0]   _zz_roundNext_1_3;
  wire       [31:0]   _zz_roundNext_12;
  wire       [31:0]   _zz_roundNext_12_1;
  wire       [31:0]   _zz_roundNext_11_3;
  wire       [31:0]   _zz_roundNext_6;
  wire       [31:0]   _zz_roundNext_2;
  wire       [31:0]   _zz_roundNext_8;
  wire       [31:0]   _zz_roundNext_8_1;
  wire       [31:0]   _zz_roundNext_8_2;
  wire       [31:0]   _zz_roundNext_2_1;
  wire       [31:0]   _zz_roundNext_2_2;
  wire       [31:0]   _zz_roundNext_2_3;
  wire       [31:0]   _zz_roundNext_13;
  wire       [31:0]   _zz_roundNext_13_1;
  wire       [31:0]   _zz_roundNext_8_3;
  wire       [31:0]   _zz_roundNext_7;
  wire       [31:0]   _zz_roundNext_3;
  wire       [31:0]   _zz_roundNext_9;
  wire       [31:0]   _zz_roundNext_9_1;
  wire       [31:0]   _zz_roundNext_9_2;
  wire       [31:0]   _zz_roundNext_3_1;
  wire       [31:0]   _zz_roundNext_3_2;
  wire       [31:0]   _zz_roundNext_3_3;
  wire       [31:0]   _zz_roundNext_14;
  wire       [31:0]   _zz_roundNext_14_1;
  wire       [31:0]   _zz_roundNext_9_3;
  wire       [31:0]   _zz_roundNext_4;
  wire       [31:0]   _zz_roundNext_0_5;
  wire       [31:0]   _zz_roundNext_8_4;
  wire       [31:0]   _zz_roundNext_8_5;
  wire       [31:0]   _zz_roundNext_8_6;
  wire       [31:0]   _zz_roundNext_0_6;
  wire       [31:0]   _zz_roundNext_0_7;
  wire       [31:0]   _zz_roundNext_0_8;
  wire       [31:0]   _zz_roundNext_12_2;
  wire       [31:0]   _zz_roundNext_12_3;
  wire       [31:0]   _zz_roundNext_8_7;
  wire       [31:0]   _zz_roundNext_4_1;
  wire       [31:0]   _zz_roundNext_1_4;
  wire       [31:0]   _zz_roundNext_9_4;
  wire       [31:0]   _zz_roundNext_9_5;
  wire       [31:0]   _zz_roundNext_9_6;
  wire       [31:0]   _zz_roundNext_1_5;
  wire       [31:0]   _zz_roundNext_1_6;
  wire       [31:0]   _zz_roundNext_1_7;
  wire       [31:0]   _zz_roundNext_13_2;
  wire       [31:0]   _zz_roundNext_13_3;
  wire       [31:0]   _zz_roundNext_9_7;
  wire       [31:0]   _zz_roundNext_5_1;
  wire       [31:0]   _zz_roundNext_2_4;
  wire       [31:0]   _zz_roundNext_10_4;
  wire       [31:0]   _zz_roundNext_10_5;
  wire       [31:0]   _zz_roundNext_10_6;
  wire       [31:0]   _zz_roundNext_2_5;
  wire       [31:0]   _zz_roundNext_2_6;
  wire       [31:0]   _zz_roundNext_2_7;
  wire       [31:0]   _zz_roundNext_14_2;
  wire       [31:0]   _zz_roundNext_14_3;
  wire       [31:0]   _zz_roundNext_10_7;
  wire       [31:0]   _zz_roundNext_6_1;
  wire       [31:0]   _zz_roundNext_3_4;
  wire       [31:0]   _zz_roundNext_11_4;
  wire       [31:0]   _zz_roundNext_11_5;
  wire       [31:0]   _zz_roundNext_11_6;
  wire       [31:0]   _zz_roundNext_3_5;
  wire       [31:0]   _zz_roundNext_3_6;
  wire       [31:0]   _zz_roundNext_3_7;
  wire       [31:0]   _zz_roundNext_15_2;
  wire       [31:0]   _zz_roundNext_15_3;
  wire       [31:0]   _zz_roundNext_11_7;
  wire       [31:0]   _zz_roundNext_7_1;
  wire       [31:0]   roundNext_0;
  wire       [31:0]   roundNext_1;
  wire       [31:0]   roundNext_2;
  wire       [31:0]   roundNext_3;
  wire       [31:0]   roundNext_4;
  wire       [31:0]   roundNext_5;
  wire       [31:0]   roundNext_6;
  wire       [31:0]   roundNext_7;
  wire       [31:0]   roundNext_8;
  wire       [31:0]   roundNext_9;
  wire       [31:0]   roundNext_10;
  wire       [31:0]   roundNext_11;
  wire       [31:0]   roundNext_12;
  wire       [31:0]   roundNext_13;
  wire       [31:0]   roundNext_14;
  wire       [31:0]   roundNext_15;
  wire       [191:0]  nonceFlat_0;
  wire       [191:0]  nonceFlat_1;
  wire       [191:0]  nonceFlat_2;
  wire       [191:0]  nonceFlat_3;
  wire       [191:0]  reqNonce;
  wire                nonceDup;
  wire                nonceDupFire;
  reg                 dirtyAtFinal;
  wire       [3:0]    _zz_1;
  wire                when_MaskUnit_l313;
  wire                when_MaskUnit_l346;
  wire       [3:0]    _zz_2;
  wire       [31:0]   _zz_maskFrame_0;
  wire       [3:0]    _zz_3;
  wire                _zz_maskValid_0;
  wire       [7:0]    _zz_4;
  wire                when_MaskUnit_l392;
  wire                nonceWrHit;
  wire                when_MaskUnit_l400;
  wire       [3:0]    _zz_5;
  wire                _zz_6;
  wire                _zz_7;
  wire                _zz_8;
  wire                _zz_9;
  wire                when_MaskUnit_l400_1;
  wire                when_MaskUnit_l400_2;
  wire                when_MaskUnit_l400_3;
  wire                when_MaskUnit_l400_4;
  wire                when_MaskUnit_l400_5;
  wire       [3:0]    _zz_10;
  wire                when_MaskUnit_l407;
  reg                 rValid;
  reg        [31:0]   rFrame;
  wire                noMaskFire;
  reg                 _zz_io_faultNoMask;
  reg                 _zz_io_faultNonceDup;
  reg                 _zz_io_faultWrDuringRekey;

  assign _zz__zz_maskFrame_0 = (st_1[11 : 0] + 12'h46e);
  assign _zz__zz_maskFrame_0_1 = (_zz__zz_maskFrame_0_2 + _zz__zz_maskFrame_0_3);
  assign _zz__zz_maskFrame_0_2 = (st_0[31 : 12] + 20'h61707);
  assign _zz__zz_maskFrame_0_4 = (12'h79b <= st_0[11 : 0]);
  assign _zz__zz_maskFrame_0_3 = {19'd0, _zz__zz_maskFrame_0_4};
  assign _zz_nonceDup = (2'b00 != io_rekey_part);
  assign _zz_nonceDup_1 = (2'b01 != io_rekey_part);
  assign _zz_nonceDup_2 = 2'b10;
  always @(*) begin
    case(io_rekey_part)
      2'b00 : begin
        _zz_reqNonce = nonceFlat_0;
        _zz_st_12 = nonce_0_0;
        _zz_st_13 = nonce_0_1;
        _zz_st_14 = nonce_0_2;
        _zz_st_15 = nonce_0_3;
      end
      2'b01 : begin
        _zz_reqNonce = nonceFlat_1;
        _zz_st_12 = nonce_1_0;
        _zz_st_13 = nonce_1_1;
        _zz_st_14 = nonce_1_2;
        _zz_st_15 = nonce_1_3;
      end
      2'b10 : begin
        _zz_reqNonce = nonceFlat_2;
        _zz_st_12 = nonce_2_0;
        _zz_st_13 = nonce_2_1;
        _zz_st_14 = nonce_2_2;
        _zz_st_15 = nonce_2_3;
      end
      default : begin
        _zz_reqNonce = nonceFlat_3;
        _zz_st_12 = nonce_3_0;
        _zz_st_13 = nonce_3_1;
        _zz_st_14 = nonce_3_2;
        _zz_st_15 = nonce_3_3;
      end
    endcase
  end

  always @(*) begin
    case(actPart)
      2'b00 : begin
        _zz_st_14_1 = nonce_0_4;
        _zz_st_15_1 = nonce_0_5;
      end
      2'b01 : begin
        _zz_st_14_1 = nonce_1_4;
        _zz_st_15_1 = nonce_1_5;
      end
      2'b10 : begin
        _zz_st_14_1 = nonce_2_4;
        _zz_st_15_1 = nonce_2_5;
      end
      default : begin
        _zz_st_14_1 = nonce_3_4;
        _zz_st_15_1 = nonce_3_5;
      end
    endcase
  end

  always @(*) begin
    case(io_req_part)
      2'b00 : begin
        _zz_rFrame = maskFrame_0;
        _zz_noMaskFire = maskValid_0;
      end
      2'b01 : begin
        _zz_rFrame = maskFrame_1;
        _zz_noMaskFire = maskValid_1;
      end
      2'b10 : begin
        _zz_rFrame = maskFrame_2;
        _zz_noMaskFire = maskValid_2;
      end
      default : begin
        _zz_rFrame = maskFrame_3;
        _zz_noMaskFire = maskValid_3;
      end
    endcase
  end

  assign engineBusy = (phase != 3'b000);
  assign io_busy = engineBusy;
  assign io_rekey_ready = (! engineBusy);
  assign rekeyFire = (io_rekey_valid && io_rekey_ready);
  assign _zz_roundNext_0 = cnt[0];
  assign _zz_roundNext_0_1 = (st_0 + st_5);
  assign _zz_roundNext_10 = (st_15 ^ _zz_roundNext_0_1);
  assign _zz_roundNext_10_1 = {_zz_roundNext_10[15 : 0],_zz_roundNext_10[31 : 16]};
  assign _zz_roundNext_10_2 = (st_10 + _zz_roundNext_10_1);
  assign _zz_roundNext_0_2 = (st_5 ^ _zz_roundNext_10_2);
  assign _zz_roundNext_0_3 = {_zz_roundNext_0_2[19 : 0],_zz_roundNext_0_2[31 : 20]};
  assign _zz_roundNext_0_4 = (_zz_roundNext_0_1 + _zz_roundNext_0_3);
  assign _zz_roundNext_15 = (_zz_roundNext_10_1 ^ _zz_roundNext_0_4);
  assign _zz_roundNext_15_1 = {_zz_roundNext_15[23 : 0],_zz_roundNext_15[31 : 24]};
  assign _zz_roundNext_10_3 = (_zz_roundNext_10_2 + _zz_roundNext_15_1);
  assign _zz_roundNext_5 = (_zz_roundNext_0_3 ^ _zz_roundNext_10_3);
  assign _zz_roundNext_1 = (st_1 + st_6);
  assign _zz_roundNext_11 = (st_12 ^ _zz_roundNext_1);
  assign _zz_roundNext_11_1 = {_zz_roundNext_11[15 : 0],_zz_roundNext_11[31 : 16]};
  assign _zz_roundNext_11_2 = (st_11 + _zz_roundNext_11_1);
  assign _zz_roundNext_1_1 = (st_6 ^ _zz_roundNext_11_2);
  assign _zz_roundNext_1_2 = {_zz_roundNext_1_1[19 : 0],_zz_roundNext_1_1[31 : 20]};
  assign _zz_roundNext_1_3 = (_zz_roundNext_1 + _zz_roundNext_1_2);
  assign _zz_roundNext_12 = (_zz_roundNext_11_1 ^ _zz_roundNext_1_3);
  assign _zz_roundNext_12_1 = {_zz_roundNext_12[23 : 0],_zz_roundNext_12[31 : 24]};
  assign _zz_roundNext_11_3 = (_zz_roundNext_11_2 + _zz_roundNext_12_1);
  assign _zz_roundNext_6 = (_zz_roundNext_1_2 ^ _zz_roundNext_11_3);
  assign _zz_roundNext_2 = (st_2 + st_7);
  assign _zz_roundNext_8 = (st_13 ^ _zz_roundNext_2);
  assign _zz_roundNext_8_1 = {_zz_roundNext_8[15 : 0],_zz_roundNext_8[31 : 16]};
  assign _zz_roundNext_8_2 = (st_8 + _zz_roundNext_8_1);
  assign _zz_roundNext_2_1 = (st_7 ^ _zz_roundNext_8_2);
  assign _zz_roundNext_2_2 = {_zz_roundNext_2_1[19 : 0],_zz_roundNext_2_1[31 : 20]};
  assign _zz_roundNext_2_3 = (_zz_roundNext_2 + _zz_roundNext_2_2);
  assign _zz_roundNext_13 = (_zz_roundNext_8_1 ^ _zz_roundNext_2_3);
  assign _zz_roundNext_13_1 = {_zz_roundNext_13[23 : 0],_zz_roundNext_13[31 : 24]};
  assign _zz_roundNext_8_3 = (_zz_roundNext_8_2 + _zz_roundNext_13_1);
  assign _zz_roundNext_7 = (_zz_roundNext_2_2 ^ _zz_roundNext_8_3);
  assign _zz_roundNext_3 = (st_3 + st_4);
  assign _zz_roundNext_9 = (st_14 ^ _zz_roundNext_3);
  assign _zz_roundNext_9_1 = {_zz_roundNext_9[15 : 0],_zz_roundNext_9[31 : 16]};
  assign _zz_roundNext_9_2 = (st_9 + _zz_roundNext_9_1);
  assign _zz_roundNext_3_1 = (st_4 ^ _zz_roundNext_9_2);
  assign _zz_roundNext_3_2 = {_zz_roundNext_3_1[19 : 0],_zz_roundNext_3_1[31 : 20]};
  assign _zz_roundNext_3_3 = (_zz_roundNext_3 + _zz_roundNext_3_2);
  assign _zz_roundNext_14 = (_zz_roundNext_9_1 ^ _zz_roundNext_3_3);
  assign _zz_roundNext_14_1 = {_zz_roundNext_14[23 : 0],_zz_roundNext_14[31 : 24]};
  assign _zz_roundNext_9_3 = (_zz_roundNext_9_2 + _zz_roundNext_14_1);
  assign _zz_roundNext_4 = (_zz_roundNext_3_2 ^ _zz_roundNext_9_3);
  assign _zz_roundNext_0_5 = (st_0 + st_4);
  assign _zz_roundNext_8_4 = (st_12 ^ _zz_roundNext_0_5);
  assign _zz_roundNext_8_5 = {_zz_roundNext_8_4[15 : 0],_zz_roundNext_8_4[31 : 16]};
  assign _zz_roundNext_8_6 = (st_8 + _zz_roundNext_8_5);
  assign _zz_roundNext_0_6 = (st_4 ^ _zz_roundNext_8_6);
  assign _zz_roundNext_0_7 = {_zz_roundNext_0_6[19 : 0],_zz_roundNext_0_6[31 : 20]};
  assign _zz_roundNext_0_8 = (_zz_roundNext_0_5 + _zz_roundNext_0_7);
  assign _zz_roundNext_12_2 = (_zz_roundNext_8_5 ^ _zz_roundNext_0_8);
  assign _zz_roundNext_12_3 = {_zz_roundNext_12_2[23 : 0],_zz_roundNext_12_2[31 : 24]};
  assign _zz_roundNext_8_7 = (_zz_roundNext_8_6 + _zz_roundNext_12_3);
  assign _zz_roundNext_4_1 = (_zz_roundNext_0_7 ^ _zz_roundNext_8_7);
  assign _zz_roundNext_1_4 = (st_1 + st_5);
  assign _zz_roundNext_9_4 = (st_13 ^ _zz_roundNext_1_4);
  assign _zz_roundNext_9_5 = {_zz_roundNext_9_4[15 : 0],_zz_roundNext_9_4[31 : 16]};
  assign _zz_roundNext_9_6 = (st_9 + _zz_roundNext_9_5);
  assign _zz_roundNext_1_5 = (st_5 ^ _zz_roundNext_9_6);
  assign _zz_roundNext_1_6 = {_zz_roundNext_1_5[19 : 0],_zz_roundNext_1_5[31 : 20]};
  assign _zz_roundNext_1_7 = (_zz_roundNext_1_4 + _zz_roundNext_1_6);
  assign _zz_roundNext_13_2 = (_zz_roundNext_9_5 ^ _zz_roundNext_1_7);
  assign _zz_roundNext_13_3 = {_zz_roundNext_13_2[23 : 0],_zz_roundNext_13_2[31 : 24]};
  assign _zz_roundNext_9_7 = (_zz_roundNext_9_6 + _zz_roundNext_13_3);
  assign _zz_roundNext_5_1 = (_zz_roundNext_1_6 ^ _zz_roundNext_9_7);
  assign _zz_roundNext_2_4 = (st_2 + st_6);
  assign _zz_roundNext_10_4 = (st_14 ^ _zz_roundNext_2_4);
  assign _zz_roundNext_10_5 = {_zz_roundNext_10_4[15 : 0],_zz_roundNext_10_4[31 : 16]};
  assign _zz_roundNext_10_6 = (st_10 + _zz_roundNext_10_5);
  assign _zz_roundNext_2_5 = (st_6 ^ _zz_roundNext_10_6);
  assign _zz_roundNext_2_6 = {_zz_roundNext_2_5[19 : 0],_zz_roundNext_2_5[31 : 20]};
  assign _zz_roundNext_2_7 = (_zz_roundNext_2_4 + _zz_roundNext_2_6);
  assign _zz_roundNext_14_2 = (_zz_roundNext_10_5 ^ _zz_roundNext_2_7);
  assign _zz_roundNext_14_3 = {_zz_roundNext_14_2[23 : 0],_zz_roundNext_14_2[31 : 24]};
  assign _zz_roundNext_10_7 = (_zz_roundNext_10_6 + _zz_roundNext_14_3);
  assign _zz_roundNext_6_1 = (_zz_roundNext_2_6 ^ _zz_roundNext_10_7);
  assign _zz_roundNext_3_4 = (st_3 + st_7);
  assign _zz_roundNext_11_4 = (st_15 ^ _zz_roundNext_3_4);
  assign _zz_roundNext_11_5 = {_zz_roundNext_11_4[15 : 0],_zz_roundNext_11_4[31 : 16]};
  assign _zz_roundNext_11_6 = (st_11 + _zz_roundNext_11_5);
  assign _zz_roundNext_3_5 = (st_7 ^ _zz_roundNext_11_6);
  assign _zz_roundNext_3_6 = {_zz_roundNext_3_5[19 : 0],_zz_roundNext_3_5[31 : 20]};
  assign _zz_roundNext_3_7 = (_zz_roundNext_3_4 + _zz_roundNext_3_6);
  assign _zz_roundNext_15_2 = (_zz_roundNext_11_5 ^ _zz_roundNext_3_7);
  assign _zz_roundNext_15_3 = {_zz_roundNext_15_2[23 : 0],_zz_roundNext_15_2[31 : 24]};
  assign _zz_roundNext_11_7 = (_zz_roundNext_11_6 + _zz_roundNext_15_3);
  assign _zz_roundNext_7_1 = (_zz_roundNext_3_6 ^ _zz_roundNext_11_7);
  assign roundNext_0 = (_zz_roundNext_0 ? _zz_roundNext_0_4 : _zz_roundNext_0_8);
  assign roundNext_1 = (_zz_roundNext_0 ? _zz_roundNext_1_3 : _zz_roundNext_1_7);
  assign roundNext_2 = (_zz_roundNext_0 ? _zz_roundNext_2_3 : _zz_roundNext_2_7);
  assign roundNext_3 = (_zz_roundNext_0 ? _zz_roundNext_3_3 : _zz_roundNext_3_7);
  assign roundNext_4 = (_zz_roundNext_0 ? {_zz_roundNext_4[24 : 0],_zz_roundNext_4[31 : 25]} : {_zz_roundNext_4_1[24 : 0],_zz_roundNext_4_1[31 : 25]});
  assign roundNext_5 = (_zz_roundNext_0 ? {_zz_roundNext_5[24 : 0],_zz_roundNext_5[31 : 25]} : {_zz_roundNext_5_1[24 : 0],_zz_roundNext_5_1[31 : 25]});
  assign roundNext_6 = (_zz_roundNext_0 ? {_zz_roundNext_6[24 : 0],_zz_roundNext_6[31 : 25]} : {_zz_roundNext_6_1[24 : 0],_zz_roundNext_6_1[31 : 25]});
  assign roundNext_7 = (_zz_roundNext_0 ? {_zz_roundNext_7[24 : 0],_zz_roundNext_7[31 : 25]} : {_zz_roundNext_7_1[24 : 0],_zz_roundNext_7_1[31 : 25]});
  assign roundNext_8 = (_zz_roundNext_0 ? _zz_roundNext_8_3 : _zz_roundNext_8_7);
  assign roundNext_9 = (_zz_roundNext_0 ? _zz_roundNext_9_3 : _zz_roundNext_9_7);
  assign roundNext_10 = (_zz_roundNext_0 ? _zz_roundNext_10_3 : _zz_roundNext_10_7);
  assign roundNext_11 = (_zz_roundNext_0 ? _zz_roundNext_11_3 : _zz_roundNext_11_7);
  assign roundNext_12 = (_zz_roundNext_0 ? _zz_roundNext_12_1 : _zz_roundNext_12_3);
  assign roundNext_13 = (_zz_roundNext_0 ? _zz_roundNext_13_1 : _zz_roundNext_13_3);
  assign roundNext_14 = (_zz_roundNext_0 ? _zz_roundNext_14_1 : _zz_roundNext_14_3);
  assign roundNext_15 = (_zz_roundNext_0 ? _zz_roundNext_15_1 : _zz_roundNext_15_3);
  assign nonceFlat_0 = {nonce_0_5,{nonce_0_4,{nonce_0_3,{nonce_0_2,{nonce_0_1,nonce_0_0}}}}};
  assign nonceFlat_1 = {nonce_1_5,{nonce_1_4,{nonce_1_3,{nonce_1_2,{nonce_1_1,nonce_1_0}}}}};
  assign nonceFlat_2 = {nonce_2_5,{nonce_2_4,{nonce_2_3,{nonce_2_2,{nonce_2_1,nonce_2_0}}}}};
  assign nonceFlat_3 = {nonce_3_5,{nonce_3_4,{nonce_3_3,{nonce_3_2,{nonce_3_1,nonce_3_0}}}}};
  assign reqNonce = _zz_reqNonce;
  assign nonceDup = (((((maskValid_0 && _zz_nonceDup) && (nonceFlat_0 == reqNonce)) || ((maskValid_1 && _zz_nonceDup_1) && (nonceFlat_1 == reqNonce))) || ((maskValid_2 && (_zz_nonceDup_2 != io_rekey_part)) && (nonceFlat_2 == reqNonce))) || ((maskValid_3 && (2'b11 != io_rekey_part)) && (nonceFlat_3 == reqNonce)));
  assign nonceDupFire = (rekeyFire && nonceDup);
  always @(*) begin
    dirtyAtFinal = 1'b0;
    case(phase)
      3'b100 : begin
        dirtyAtFinal = compDirty;
      end
      default : begin
      end
    endcase
  end

  assign _zz_1 = ({3'd0,1'b1} <<< io_rekey_part);
  assign when_MaskUnit_l313 = (cnt == 5'h13);
  assign when_MaskUnit_l346 = (cnt == 5'h13);
  assign _zz_2 = ({3'd0,1'b1} <<< actPart);
  assign _zz_maskFrame_0 = {_zz__zz_maskFrame_0,_zz__zz_maskFrame_0_1};
  assign _zz_3 = ({3'd0,1'b1} <<< actPart);
  assign _zz_maskValid_0 = (! compDirty);
  assign _zz_4 = ({7'd0,1'b1} <<< io_keyWr_idx);
  assign when_MaskUnit_l392 = (engineBusy || rekeyFire);
  assign nonceWrHit = (io_nonceWr_valid && (io_nonceWr_idx < 3'b110));
  assign when_MaskUnit_l400 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b000));
  assign _zz_5 = ({3'd0,1'b1} <<< io_nonceWr_part);
  assign _zz_6 = _zz_5[0];
  assign _zz_7 = _zz_5[1];
  assign _zz_8 = _zz_5[2];
  assign _zz_9 = _zz_5[3];
  assign when_MaskUnit_l400_1 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b001));
  assign when_MaskUnit_l400_2 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b010));
  assign when_MaskUnit_l400_3 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b011));
  assign when_MaskUnit_l400_4 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b100));
  assign when_MaskUnit_l400_5 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b101));
  assign _zz_10 = ({3'd0,1'b1} <<< io_nonceWr_part);
  assign when_MaskUnit_l407 = ((engineBusy && (io_nonceWr_part == actPart)) || (rekeyFire && (io_nonceWr_part == io_rekey_part)));
  assign io_maskReady = {maskValid_3,{maskValid_2,{maskValid_1,maskValid_0}}};
  assign io_rsp_valid = rValid;
  assign io_rsp_frame = rFrame;
  assign noMaskFire = ((io_en && io_req_valid) && (! _zz_noMaskFire));
  assign io_faultNoMask = _zz_io_faultNoMask;
  assign io_faultNonceDup = _zz_io_faultNonceDup;
  assign io_faultWrDuringRekey = _zz_io_faultWrDuringRekey;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      key_0 <= 32'h0;
      key_1 <= 32'h0;
      key_2 <= 32'h0;
      key_3 <= 32'h0;
      key_4 <= 32'h0;
      key_5 <= 32'h0;
      key_6 <= 32'h0;
      key_7 <= 32'h0;
      nonce_0_0 <= 32'h0;
      nonce_0_1 <= 32'h0;
      nonce_0_2 <= 32'h0;
      nonce_0_3 <= 32'h0;
      nonce_0_4 <= 32'h0;
      nonce_0_5 <= 32'h0;
      nonce_1_0 <= 32'h0;
      nonce_1_1 <= 32'h0;
      nonce_1_2 <= 32'h0;
      nonce_1_3 <= 32'h0;
      nonce_1_4 <= 32'h0;
      nonce_1_5 <= 32'h0;
      nonce_2_0 <= 32'h0;
      nonce_2_1 <= 32'h0;
      nonce_2_2 <= 32'h0;
      nonce_2_3 <= 32'h0;
      nonce_2_4 <= 32'h0;
      nonce_2_5 <= 32'h0;
      nonce_3_0 <= 32'h0;
      nonce_3_1 <= 32'h0;
      nonce_3_2 <= 32'h0;
      nonce_3_3 <= 32'h0;
      nonce_3_4 <= 32'h0;
      nonce_3_5 <= 32'h0;
      maskFrame_0 <= 32'h0;
      maskFrame_1 <= 32'h0;
      maskFrame_2 <= 32'h0;
      maskFrame_3 <= 32'h0;
      maskValid_0 <= 1'b0;
      maskValid_1 <= 1'b0;
      maskValid_2 <= 1'b0;
      maskValid_3 <= 1'b0;
      phase <= 3'b000;
      st_0 <= 32'h0;
      st_1 <= 32'h0;
      st_2 <= 32'h0;
      st_3 <= 32'h0;
      st_4 <= 32'h0;
      st_5 <= 32'h0;
      st_6 <= 32'h0;
      st_7 <= 32'h0;
      st_8 <= 32'h0;
      st_9 <= 32'h0;
      st_10 <= 32'h0;
      st_11 <= 32'h0;
      st_12 <= 32'h0;
      st_13 <= 32'h0;
      st_14 <= 32'h0;
      st_15 <= 32'h0;
      cnt <= 5'h0;
      actPart <= 2'b00;
      compDirty <= 1'b0;
      rValid <= 1'b0;
      rFrame <= 32'h0;
      _zz_io_faultNoMask <= 1'b0;
      _zz_io_faultNonceDup <= 1'b0;
      _zz_io_faultWrDuringRekey <= 1'b0;
    end else begin
      case(phase)
        3'b000 : begin
          if(rekeyFire) begin
            st_0 <= 32'h61707865;
            st_1 <= 32'h3320646e;
            st_2 <= 32'h79622d32;
            st_3 <= 32'h6b206574;
            st_4 <= key_0;
            st_5 <= key_1;
            st_6 <= key_2;
            st_7 <= key_3;
            st_8 <= key_4;
            st_9 <= key_5;
            st_10 <= key_6;
            st_11 <= key_7;
            st_12 <= _zz_st_12;
            st_13 <= _zz_st_13;
            st_14 <= _zz_st_14;
            st_15 <= _zz_st_15;
            actPart <= io_rekey_part;
            cnt <= 5'h0;
            compDirty <= 1'b0;
            if(_zz_1[0]) begin
              maskValid_0 <= 1'b0;
            end
            if(_zz_1[1]) begin
              maskValid_1 <= 1'b0;
            end
            if(_zz_1[2]) begin
              maskValid_2 <= 1'b0;
            end
            if(_zz_1[3]) begin
              maskValid_3 <= 1'b0;
            end
            phase <= 3'b001;
          end
        end
        3'b001 : begin
          st_0 <= roundNext_0;
          st_1 <= roundNext_1;
          st_2 <= roundNext_2;
          st_3 <= roundNext_3;
          st_4 <= roundNext_4;
          st_5 <= roundNext_5;
          st_6 <= roundNext_6;
          st_7 <= roundNext_7;
          st_8 <= roundNext_8;
          st_9 <= roundNext_9;
          st_10 <= roundNext_10;
          st_11 <= roundNext_11;
          st_12 <= roundNext_12;
          st_13 <= roundNext_13;
          st_14 <= roundNext_14;
          st_15 <= roundNext_15;
          cnt <= (cnt + 5'h01);
          if(when_MaskUnit_l313) begin
            phase <= 3'b010;
            cnt <= 5'h0;
          end
        end
        3'b010 : begin
          st_0 <= 32'h61707865;
          st_1 <= 32'h3320646e;
          st_2 <= 32'h79622d32;
          st_3 <= 32'h6b206574;
          st_4 <= st_0;
          st_5 <= st_1;
          st_6 <= st_2;
          st_7 <= st_3;
          st_8 <= st_12;
          st_9 <= st_13;
          st_10 <= st_14;
          st_11 <= st_15;
          st_12 <= 32'h0;
          st_13 <= 32'h0;
          st_14 <= _zz_st_14_1;
          st_15 <= _zz_st_15_1;
          phase <= 3'b011;
        end
        3'b011 : begin
          st_0 <= roundNext_0;
          st_1 <= roundNext_1;
          st_2 <= roundNext_2;
          st_3 <= roundNext_3;
          st_4 <= roundNext_4;
          st_5 <= roundNext_5;
          st_6 <= roundNext_6;
          st_7 <= roundNext_7;
          st_8 <= roundNext_8;
          st_9 <= roundNext_9;
          st_10 <= roundNext_10;
          st_11 <= roundNext_11;
          st_12 <= roundNext_12;
          st_13 <= roundNext_13;
          st_14 <= roundNext_14;
          st_15 <= roundNext_15;
          cnt <= (cnt + 5'h01);
          if(when_MaskUnit_l346) begin
            phase <= 3'b100;
          end
        end
        3'b100 : begin
          if(_zz_2[0]) begin
            maskFrame_0 <= _zz_maskFrame_0;
          end
          if(_zz_2[1]) begin
            maskFrame_1 <= _zz_maskFrame_0;
          end
          if(_zz_2[2]) begin
            maskFrame_2 <= _zz_maskFrame_0;
          end
          if(_zz_2[3]) begin
            maskFrame_3 <= _zz_maskFrame_0;
          end
          if(_zz_3[0]) begin
            maskValid_0 <= _zz_maskValid_0;
          end
          if(_zz_3[1]) begin
            maskValid_1 <= _zz_maskValid_0;
          end
          if(_zz_3[2]) begin
            maskValid_2 <= _zz_maskValid_0;
          end
          if(_zz_3[3]) begin
            maskValid_3 <= _zz_maskValid_0;
          end
          phase <= 3'b000;
        end
        default : begin
        end
      endcase
      if(io_keyWr_valid) begin
        if(_zz_4[0]) begin
          key_0 <= io_keyWr_data;
        end
        if(_zz_4[1]) begin
          key_1 <= io_keyWr_data;
        end
        if(_zz_4[2]) begin
          key_2 <= io_keyWr_data;
        end
        if(_zz_4[3]) begin
          key_3 <= io_keyWr_data;
        end
        if(_zz_4[4]) begin
          key_4 <= io_keyWr_data;
        end
        if(_zz_4[5]) begin
          key_5 <= io_keyWr_data;
        end
        if(_zz_4[6]) begin
          key_6 <= io_keyWr_data;
        end
        if(_zz_4[7]) begin
          key_7 <= io_keyWr_data;
        end
        maskValid_0 <= 1'b0;
        maskValid_1 <= 1'b0;
        maskValid_2 <= 1'b0;
        maskValid_3 <= 1'b0;
        if(when_MaskUnit_l392) begin
          compDirty <= 1'b1;
        end
      end
      if(when_MaskUnit_l400) begin
        if(_zz_6) begin
          nonce_0_0 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_0 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_0 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_0 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l400_1) begin
        if(_zz_6) begin
          nonce_0_1 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_1 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_1 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_1 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l400_2) begin
        if(_zz_6) begin
          nonce_0_2 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_2 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_2 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_2 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l400_3) begin
        if(_zz_6) begin
          nonce_0_3 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_3 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_3 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_3 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l400_4) begin
        if(_zz_6) begin
          nonce_0_4 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_4 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_4 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_4 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l400_5) begin
        if(_zz_6) begin
          nonce_0_5 <= io_nonceWr_data;
        end
        if(_zz_7) begin
          nonce_1_5 <= io_nonceWr_data;
        end
        if(_zz_8) begin
          nonce_2_5 <= io_nonceWr_data;
        end
        if(_zz_9) begin
          nonce_3_5 <= io_nonceWr_data;
        end
      end
      if(nonceWrHit) begin
        if(_zz_10[0]) begin
          maskValid_0 <= 1'b0;
        end
        if(_zz_10[1]) begin
          maskValid_1 <= 1'b0;
        end
        if(_zz_10[2]) begin
          maskValid_2 <= 1'b0;
        end
        if(_zz_10[3]) begin
          maskValid_3 <= 1'b0;
        end
        if(when_MaskUnit_l407) begin
          compDirty <= 1'b1;
        end
      end
      if(io_en) begin
        rValid <= io_req_valid;
        rFrame <= (io_req_frame ^ _zz_rFrame);
      end
      if(io_faultClearNoMask) begin
        _zz_io_faultNoMask <= 1'b0;
      end
      if(noMaskFire) begin
        _zz_io_faultNoMask <= 1'b1;
      end
      if(io_faultClearNonceDup) begin
        _zz_io_faultNonceDup <= 1'b0;
      end
      if(nonceDupFire) begin
        _zz_io_faultNonceDup <= 1'b1;
      end
      if(io_faultClearWrRekey) begin
        _zz_io_faultWrDuringRekey <= 1'b0;
      end
      if(dirtyAtFinal) begin
        _zz_io_faultWrDuringRekey <= 1'b1;
      end
    end
  end


endmodule

module ResultBank (
  input  wire          io_acquire_valid,
  input  wire [3:0]    io_acquire_slot,
  input  wire [3:0]    io_acquire_prod,
  output wire          io_acquire_granted,
  input  wire          io_write_valid,
  input  wire [3:0]    io_write_slot,
  input  wire [3:0]    io_write_prod,
  input  wire [63:0]   io_write_data,
  input  wire [3:0]    io_read_slot,
  output wire [63:0]   io_read_data,
  output wire          io_read_owned,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire [4:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg                 _zz_acqFree;
  reg                 _zz_wrQualified;
  reg        [3:0]    _zz_wrQualified_1;
  reg        [63:0]   _zz_io_read_data;
  reg                 _zz_io_read_owned;
  wire       [4:0]    _zz_io_occupancy_8;
  wire       [4:0]    _zz_io_occupancy_9;
  reg        [4:0]    _zz_io_occupancy_10;
  wire       [2:0]    _zz_io_occupancy_11;
  reg        [4:0]    _zz_io_occupancy_12;
  wire       [2:0]    _zz_io_occupancy_13;
  wire       [4:0]    _zz_io_occupancy_14;
  reg        [4:0]    _zz_io_occupancy_15;
  wire       [2:0]    _zz_io_occupancy_16;
  reg        [4:0]    _zz_io_occupancy_17;
  wire       [2:0]    _zz_io_occupancy_18;
  wire       [4:0]    _zz_io_occupancy_19;
  reg        [4:0]    _zz_io_occupancy_20;
  wire       [2:0]    _zz_io_occupancy_21;
  reg        [4:0]    _zz_io_occupancy_22;
  wire       [2:0]    _zz_io_occupancy_23;
  wire       [0:0]    _zz_io_occupancy_24;
  reg                 ownerValid_0;
  reg                 ownerValid_1;
  reg                 ownerValid_2;
  reg                 ownerValid_3;
  reg                 ownerValid_4;
  reg                 ownerValid_5;
  reg                 ownerValid_6;
  reg                 ownerValid_7;
  reg                 ownerValid_8;
  reg                 ownerValid_9;
  reg                 ownerValid_10;
  reg                 ownerValid_11;
  reg                 ownerValid_12;
  reg                 ownerValid_13;
  reg                 ownerValid_14;
  reg                 ownerValid_15;
  reg        [3:0]    ownerId_0;
  reg        [3:0]    ownerId_1;
  reg        [3:0]    ownerId_2;
  reg        [3:0]    ownerId_3;
  reg        [3:0]    ownerId_4;
  reg        [3:0]    ownerId_5;
  reg        [3:0]    ownerId_6;
  reg        [3:0]    ownerId_7;
  reg        [3:0]    ownerId_8;
  reg        [3:0]    ownerId_9;
  reg        [3:0]    ownerId_10;
  reg        [3:0]    ownerId_11;
  reg        [3:0]    ownerId_12;
  reg        [3:0]    ownerId_13;
  reg        [3:0]    ownerId_14;
  reg        [3:0]    ownerId_15;
  reg        [1:0]    age_0;
  reg        [1:0]    age_1;
  reg        [1:0]    age_2;
  reg        [1:0]    age_3;
  reg        [1:0]    age_4;
  reg        [1:0]    age_5;
  reg        [1:0]    age_6;
  reg        [1:0]    age_7;
  reg        [1:0]    age_8;
  reg        [1:0]    age_9;
  reg        [1:0]    age_10;
  reg        [1:0]    age_11;
  reg        [1:0]    age_12;
  reg        [1:0]    age_13;
  reg        [1:0]    age_14;
  reg        [1:0]    age_15;
  reg        [63:0]   store_0;
  reg        [63:0]   store_1;
  reg        [63:0]   store_2;
  reg        [63:0]   store_3;
  reg        [63:0]   store_4;
  reg        [63:0]   store_5;
  reg        [63:0]   store_6;
  reg        [63:0]   store_7;
  reg        [63:0]   store_8;
  reg        [63:0]   store_9;
  reg        [63:0]   store_10;
  reg        [63:0]   store_11;
  reg        [63:0]   store_12;
  reg        [63:0]   store_13;
  reg        [63:0]   store_14;
  reg        [63:0]   store_15;
  wire                ageAtEnd_0;
  wire                ageAtEnd_1;
  wire                ageAtEnd_2;
  wire                ageAtEnd_3;
  wire                ageAtEnd_4;
  wire                ageAtEnd_5;
  wire                ageAtEnd_6;
  wire                ageAtEnd_7;
  wire                ageAtEnd_8;
  wire                ageAtEnd_9;
  wire                ageAtEnd_10;
  wire                ageAtEnd_11;
  wire                ageAtEnd_12;
  wire                ageAtEnd_13;
  wire                ageAtEnd_14;
  wire                ageAtEnd_15;
  wire                acqFree;
  wire                when_ResultBank_l163;
  wire       [15:0]   _zz_1;
  wire       [15:0]   _zz_2;
  wire       [15:0]   _zz_3;
  wire                wrQualified;
  wire                when_ResultBank_l181;
  wire       [15:0]   _zz_4;
  wire                when_Common_l259;
  reg                 _zz_io_fault;
  wire       [4:0]    _zz_io_occupancy;
  wire       [4:0]    _zz_io_occupancy_1;
  wire       [4:0]    _zz_io_occupancy_2;
  wire       [4:0]    _zz_io_occupancy_3;
  wire       [4:0]    _zz_io_occupancy_4;
  wire       [4:0]    _zz_io_occupancy_5;
  wire       [4:0]    _zz_io_occupancy_6;
  wire       [4:0]    _zz_io_occupancy_7;

  assign _zz_io_occupancy_8 = (_zz_io_occupancy_9 + _zz_io_occupancy_14);
  assign _zz_io_occupancy_9 = (_zz_io_occupancy_10 + _zz_io_occupancy_12);
  assign _zz_io_occupancy_14 = (_zz_io_occupancy_15 + _zz_io_occupancy_17);
  assign _zz_io_occupancy_19 = (_zz_io_occupancy_20 + _zz_io_occupancy_22);
  assign _zz_io_occupancy_24 = ownerValid_15;
  assign _zz_io_occupancy_23 = {2'd0, _zz_io_occupancy_24};
  assign _zz_io_occupancy_11 = {ownerValid_2,{ownerValid_1,ownerValid_0}};
  assign _zz_io_occupancy_13 = {ownerValid_5,{ownerValid_4,ownerValid_3}};
  assign _zz_io_occupancy_16 = {ownerValid_8,{ownerValid_7,ownerValid_6}};
  assign _zz_io_occupancy_18 = {ownerValid_11,{ownerValid_10,ownerValid_9}};
  assign _zz_io_occupancy_21 = {ownerValid_14,{ownerValid_13,ownerValid_12}};
  always @(*) begin
    case(io_acquire_slot)
      4'b0000 : _zz_acqFree = ownerValid_0;
      4'b0001 : _zz_acqFree = ownerValid_1;
      4'b0010 : _zz_acqFree = ownerValid_2;
      4'b0011 : _zz_acqFree = ownerValid_3;
      4'b0100 : _zz_acqFree = ownerValid_4;
      4'b0101 : _zz_acqFree = ownerValid_5;
      4'b0110 : _zz_acqFree = ownerValid_6;
      4'b0111 : _zz_acqFree = ownerValid_7;
      4'b1000 : _zz_acqFree = ownerValid_8;
      4'b1001 : _zz_acqFree = ownerValid_9;
      4'b1010 : _zz_acqFree = ownerValid_10;
      4'b1011 : _zz_acqFree = ownerValid_11;
      4'b1100 : _zz_acqFree = ownerValid_12;
      4'b1101 : _zz_acqFree = ownerValid_13;
      4'b1110 : _zz_acqFree = ownerValid_14;
      default : _zz_acqFree = ownerValid_15;
    endcase
  end

  always @(*) begin
    case(io_write_slot)
      4'b0000 : begin
        _zz_wrQualified = ownerValid_0;
        _zz_wrQualified_1 = ownerId_0;
      end
      4'b0001 : begin
        _zz_wrQualified = ownerValid_1;
        _zz_wrQualified_1 = ownerId_1;
      end
      4'b0010 : begin
        _zz_wrQualified = ownerValid_2;
        _zz_wrQualified_1 = ownerId_2;
      end
      4'b0011 : begin
        _zz_wrQualified = ownerValid_3;
        _zz_wrQualified_1 = ownerId_3;
      end
      4'b0100 : begin
        _zz_wrQualified = ownerValid_4;
        _zz_wrQualified_1 = ownerId_4;
      end
      4'b0101 : begin
        _zz_wrQualified = ownerValid_5;
        _zz_wrQualified_1 = ownerId_5;
      end
      4'b0110 : begin
        _zz_wrQualified = ownerValid_6;
        _zz_wrQualified_1 = ownerId_6;
      end
      4'b0111 : begin
        _zz_wrQualified = ownerValid_7;
        _zz_wrQualified_1 = ownerId_7;
      end
      4'b1000 : begin
        _zz_wrQualified = ownerValid_8;
        _zz_wrQualified_1 = ownerId_8;
      end
      4'b1001 : begin
        _zz_wrQualified = ownerValid_9;
        _zz_wrQualified_1 = ownerId_9;
      end
      4'b1010 : begin
        _zz_wrQualified = ownerValid_10;
        _zz_wrQualified_1 = ownerId_10;
      end
      4'b1011 : begin
        _zz_wrQualified = ownerValid_11;
        _zz_wrQualified_1 = ownerId_11;
      end
      4'b1100 : begin
        _zz_wrQualified = ownerValid_12;
        _zz_wrQualified_1 = ownerId_12;
      end
      4'b1101 : begin
        _zz_wrQualified = ownerValid_13;
        _zz_wrQualified_1 = ownerId_13;
      end
      4'b1110 : begin
        _zz_wrQualified = ownerValid_14;
        _zz_wrQualified_1 = ownerId_14;
      end
      default : begin
        _zz_wrQualified = ownerValid_15;
        _zz_wrQualified_1 = ownerId_15;
      end
    endcase
  end

  always @(*) begin
    case(io_read_slot)
      4'b0000 : begin
        _zz_io_read_data = store_0;
        _zz_io_read_owned = ownerValid_0;
      end
      4'b0001 : begin
        _zz_io_read_data = store_1;
        _zz_io_read_owned = ownerValid_1;
      end
      4'b0010 : begin
        _zz_io_read_data = store_2;
        _zz_io_read_owned = ownerValid_2;
      end
      4'b0011 : begin
        _zz_io_read_data = store_3;
        _zz_io_read_owned = ownerValid_3;
      end
      4'b0100 : begin
        _zz_io_read_data = store_4;
        _zz_io_read_owned = ownerValid_4;
      end
      4'b0101 : begin
        _zz_io_read_data = store_5;
        _zz_io_read_owned = ownerValid_5;
      end
      4'b0110 : begin
        _zz_io_read_data = store_6;
        _zz_io_read_owned = ownerValid_6;
      end
      4'b0111 : begin
        _zz_io_read_data = store_7;
        _zz_io_read_owned = ownerValid_7;
      end
      4'b1000 : begin
        _zz_io_read_data = store_8;
        _zz_io_read_owned = ownerValid_8;
      end
      4'b1001 : begin
        _zz_io_read_data = store_9;
        _zz_io_read_owned = ownerValid_9;
      end
      4'b1010 : begin
        _zz_io_read_data = store_10;
        _zz_io_read_owned = ownerValid_10;
      end
      4'b1011 : begin
        _zz_io_read_data = store_11;
        _zz_io_read_owned = ownerValid_11;
      end
      4'b1100 : begin
        _zz_io_read_data = store_12;
        _zz_io_read_owned = ownerValid_12;
      end
      4'b1101 : begin
        _zz_io_read_data = store_13;
        _zz_io_read_owned = ownerValid_13;
      end
      4'b1110 : begin
        _zz_io_read_data = store_14;
        _zz_io_read_owned = ownerValid_14;
      end
      default : begin
        _zz_io_read_data = store_15;
        _zz_io_read_owned = ownerValid_15;
      end
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_11)
      3'b000 : _zz_io_occupancy_10 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_10 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_10 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_10 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_10 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_10 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_10 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_10 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_13)
      3'b000 : _zz_io_occupancy_12 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_12 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_12 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_12 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_12 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_12 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_12 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_12 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_16)
      3'b000 : _zz_io_occupancy_15 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_15 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_15 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_15 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_15 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_15 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_15 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_15 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_18)
      3'b000 : _zz_io_occupancy_17 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_17 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_17 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_17 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_17 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_17 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_17 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_17 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_21)
      3'b000 : _zz_io_occupancy_20 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_20 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_20 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_20 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_20 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_20 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_20 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_20 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_23)
      3'b000 : _zz_io_occupancy_22 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_22 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_22 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_22 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_22 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_22 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_22 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_22 = _zz_io_occupancy_7;
    endcase
  end

  assign ageAtEnd_0 = (ownerValid_0 && (age_0 == 2'b10));
  assign ageAtEnd_1 = (ownerValid_1 && (age_1 == 2'b10));
  assign ageAtEnd_2 = (ownerValid_2 && (age_2 == 2'b10));
  assign ageAtEnd_3 = (ownerValid_3 && (age_3 == 2'b10));
  assign ageAtEnd_4 = (ownerValid_4 && (age_4 == 2'b10));
  assign ageAtEnd_5 = (ownerValid_5 && (age_5 == 2'b10));
  assign ageAtEnd_6 = (ownerValid_6 && (age_6 == 2'b10));
  assign ageAtEnd_7 = (ownerValid_7 && (age_7 == 2'b10));
  assign ageAtEnd_8 = (ownerValid_8 && (age_8 == 2'b10));
  assign ageAtEnd_9 = (ownerValid_9 && (age_9 == 2'b10));
  assign ageAtEnd_10 = (ownerValid_10 && (age_10 == 2'b10));
  assign ageAtEnd_11 = (ownerValid_11 && (age_11 == 2'b10));
  assign ageAtEnd_12 = (ownerValid_12 && (age_12 == 2'b10));
  assign ageAtEnd_13 = (ownerValid_13 && (age_13 == 2'b10));
  assign ageAtEnd_14 = (ownerValid_14 && (age_14 == 2'b10));
  assign ageAtEnd_15 = (ownerValid_15 && (age_15 == 2'b10));
  assign acqFree = (1'b1 && (! _zz_acqFree));
  assign io_acquire_granted = (io_acquire_valid && acqFree);
  assign when_ResultBank_l163 = (io_acquire_valid && acqFree);
  assign _zz_1 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign _zz_2 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign _zz_3 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign wrQualified = ((1'b1 && _zz_wrQualified) && (_zz_wrQualified_1 == io_write_prod));
  assign when_ResultBank_l181 = (io_write_valid && wrQualified);
  assign _zz_4 = ({15'd0,1'b1} <<< io_write_slot);
  assign when_Common_l259 = (io_write_valid && (! wrQualified));
  assign io_fault = _zz_io_fault;
  assign io_read_data = _zz_io_read_data;
  assign io_read_owned = (1'b1 && _zz_io_read_owned);
  assign _zz_io_occupancy = 5'h0;
  assign _zz_io_occupancy_1 = 5'h01;
  assign _zz_io_occupancy_2 = 5'h01;
  assign _zz_io_occupancy_3 = 5'h02;
  assign _zz_io_occupancy_4 = 5'h01;
  assign _zz_io_occupancy_5 = 5'h02;
  assign _zz_io_occupancy_6 = 5'h02;
  assign _zz_io_occupancy_7 = 5'h03;
  assign io_occupancy = (_zz_io_occupancy_8 + _zz_io_occupancy_19);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      ownerValid_0 <= 1'b0;
      ownerValid_1 <= 1'b0;
      ownerValid_2 <= 1'b0;
      ownerValid_3 <= 1'b0;
      ownerValid_4 <= 1'b0;
      ownerValid_5 <= 1'b0;
      ownerValid_6 <= 1'b0;
      ownerValid_7 <= 1'b0;
      ownerValid_8 <= 1'b0;
      ownerValid_9 <= 1'b0;
      ownerValid_10 <= 1'b0;
      ownerValid_11 <= 1'b0;
      ownerValid_12 <= 1'b0;
      ownerValid_13 <= 1'b0;
      ownerValid_14 <= 1'b0;
      ownerValid_15 <= 1'b0;
      ownerId_0 <= 4'b0000;
      ownerId_1 <= 4'b0000;
      ownerId_2 <= 4'b0000;
      ownerId_3 <= 4'b0000;
      ownerId_4 <= 4'b0000;
      ownerId_5 <= 4'b0000;
      ownerId_6 <= 4'b0000;
      ownerId_7 <= 4'b0000;
      ownerId_8 <= 4'b0000;
      ownerId_9 <= 4'b0000;
      ownerId_10 <= 4'b0000;
      ownerId_11 <= 4'b0000;
      ownerId_12 <= 4'b0000;
      ownerId_13 <= 4'b0000;
      ownerId_14 <= 4'b0000;
      ownerId_15 <= 4'b0000;
      age_0 <= 2'b00;
      age_1 <= 2'b00;
      age_2 <= 2'b00;
      age_3 <= 2'b00;
      age_4 <= 2'b00;
      age_5 <= 2'b00;
      age_6 <= 2'b00;
      age_7 <= 2'b00;
      age_8 <= 2'b00;
      age_9 <= 2'b00;
      age_10 <= 2'b00;
      age_11 <= 2'b00;
      age_12 <= 2'b00;
      age_13 <= 2'b00;
      age_14 <= 2'b00;
      age_15 <= 2'b00;
      store_0 <= 64'h0;
      store_1 <= 64'h0;
      store_2 <= 64'h0;
      store_3 <= 64'h0;
      store_4 <= 64'h0;
      store_5 <= 64'h0;
      store_6 <= 64'h0;
      store_7 <= 64'h0;
      store_8 <= 64'h0;
      store_9 <= 64'h0;
      store_10 <= 64'h0;
      store_11 <= 64'h0;
      store_12 <= 64'h0;
      store_13 <= 64'h0;
      store_14 <= 64'h0;
      store_15 <= 64'h0;
      _zz_io_fault <= 1'b0;
    end else begin
      if(ownerValid_0) begin
        if(ageAtEnd_0) begin
          ownerValid_0 <= 1'b0;
          age_0 <= 2'b00;
        end else begin
          age_0 <= (age_0 + 2'b01);
        end
      end
      if(ownerValid_1) begin
        if(ageAtEnd_1) begin
          ownerValid_1 <= 1'b0;
          age_1 <= 2'b00;
        end else begin
          age_1 <= (age_1 + 2'b01);
        end
      end
      if(ownerValid_2) begin
        if(ageAtEnd_2) begin
          ownerValid_2 <= 1'b0;
          age_2 <= 2'b00;
        end else begin
          age_2 <= (age_2 + 2'b01);
        end
      end
      if(ownerValid_3) begin
        if(ageAtEnd_3) begin
          ownerValid_3 <= 1'b0;
          age_3 <= 2'b00;
        end else begin
          age_3 <= (age_3 + 2'b01);
        end
      end
      if(ownerValid_4) begin
        if(ageAtEnd_4) begin
          ownerValid_4 <= 1'b0;
          age_4 <= 2'b00;
        end else begin
          age_4 <= (age_4 + 2'b01);
        end
      end
      if(ownerValid_5) begin
        if(ageAtEnd_5) begin
          ownerValid_5 <= 1'b0;
          age_5 <= 2'b00;
        end else begin
          age_5 <= (age_5 + 2'b01);
        end
      end
      if(ownerValid_6) begin
        if(ageAtEnd_6) begin
          ownerValid_6 <= 1'b0;
          age_6 <= 2'b00;
        end else begin
          age_6 <= (age_6 + 2'b01);
        end
      end
      if(ownerValid_7) begin
        if(ageAtEnd_7) begin
          ownerValid_7 <= 1'b0;
          age_7 <= 2'b00;
        end else begin
          age_7 <= (age_7 + 2'b01);
        end
      end
      if(ownerValid_8) begin
        if(ageAtEnd_8) begin
          ownerValid_8 <= 1'b0;
          age_8 <= 2'b00;
        end else begin
          age_8 <= (age_8 + 2'b01);
        end
      end
      if(ownerValid_9) begin
        if(ageAtEnd_9) begin
          ownerValid_9 <= 1'b0;
          age_9 <= 2'b00;
        end else begin
          age_9 <= (age_9 + 2'b01);
        end
      end
      if(ownerValid_10) begin
        if(ageAtEnd_10) begin
          ownerValid_10 <= 1'b0;
          age_10 <= 2'b00;
        end else begin
          age_10 <= (age_10 + 2'b01);
        end
      end
      if(ownerValid_11) begin
        if(ageAtEnd_11) begin
          ownerValid_11 <= 1'b0;
          age_11 <= 2'b00;
        end else begin
          age_11 <= (age_11 + 2'b01);
        end
      end
      if(ownerValid_12) begin
        if(ageAtEnd_12) begin
          ownerValid_12 <= 1'b0;
          age_12 <= 2'b00;
        end else begin
          age_12 <= (age_12 + 2'b01);
        end
      end
      if(ownerValid_13) begin
        if(ageAtEnd_13) begin
          ownerValid_13 <= 1'b0;
          age_13 <= 2'b00;
        end else begin
          age_13 <= (age_13 + 2'b01);
        end
      end
      if(ownerValid_14) begin
        if(ageAtEnd_14) begin
          ownerValid_14 <= 1'b0;
          age_14 <= 2'b00;
        end else begin
          age_14 <= (age_14 + 2'b01);
        end
      end
      if(ownerValid_15) begin
        if(ageAtEnd_15) begin
          ownerValid_15 <= 1'b0;
          age_15 <= 2'b00;
        end else begin
          age_15 <= (age_15 + 2'b01);
        end
      end
      if(when_ResultBank_l163) begin
        if(_zz_1[0]) begin
          ownerValid_0 <= 1'b1;
        end
        if(_zz_1[1]) begin
          ownerValid_1 <= 1'b1;
        end
        if(_zz_1[2]) begin
          ownerValid_2 <= 1'b1;
        end
        if(_zz_1[3]) begin
          ownerValid_3 <= 1'b1;
        end
        if(_zz_1[4]) begin
          ownerValid_4 <= 1'b1;
        end
        if(_zz_1[5]) begin
          ownerValid_5 <= 1'b1;
        end
        if(_zz_1[6]) begin
          ownerValid_6 <= 1'b1;
        end
        if(_zz_1[7]) begin
          ownerValid_7 <= 1'b1;
        end
        if(_zz_1[8]) begin
          ownerValid_8 <= 1'b1;
        end
        if(_zz_1[9]) begin
          ownerValid_9 <= 1'b1;
        end
        if(_zz_1[10]) begin
          ownerValid_10 <= 1'b1;
        end
        if(_zz_1[11]) begin
          ownerValid_11 <= 1'b1;
        end
        if(_zz_1[12]) begin
          ownerValid_12 <= 1'b1;
        end
        if(_zz_1[13]) begin
          ownerValid_13 <= 1'b1;
        end
        if(_zz_1[14]) begin
          ownerValid_14 <= 1'b1;
        end
        if(_zz_1[15]) begin
          ownerValid_15 <= 1'b1;
        end
        if(_zz_2[0]) begin
          ownerId_0 <= io_acquire_prod;
        end
        if(_zz_2[1]) begin
          ownerId_1 <= io_acquire_prod;
        end
        if(_zz_2[2]) begin
          ownerId_2 <= io_acquire_prod;
        end
        if(_zz_2[3]) begin
          ownerId_3 <= io_acquire_prod;
        end
        if(_zz_2[4]) begin
          ownerId_4 <= io_acquire_prod;
        end
        if(_zz_2[5]) begin
          ownerId_5 <= io_acquire_prod;
        end
        if(_zz_2[6]) begin
          ownerId_6 <= io_acquire_prod;
        end
        if(_zz_2[7]) begin
          ownerId_7 <= io_acquire_prod;
        end
        if(_zz_2[8]) begin
          ownerId_8 <= io_acquire_prod;
        end
        if(_zz_2[9]) begin
          ownerId_9 <= io_acquire_prod;
        end
        if(_zz_2[10]) begin
          ownerId_10 <= io_acquire_prod;
        end
        if(_zz_2[11]) begin
          ownerId_11 <= io_acquire_prod;
        end
        if(_zz_2[12]) begin
          ownerId_12 <= io_acquire_prod;
        end
        if(_zz_2[13]) begin
          ownerId_13 <= io_acquire_prod;
        end
        if(_zz_2[14]) begin
          ownerId_14 <= io_acquire_prod;
        end
        if(_zz_2[15]) begin
          ownerId_15 <= io_acquire_prod;
        end
        if(_zz_3[0]) begin
          age_0 <= 2'b00;
        end
        if(_zz_3[1]) begin
          age_1 <= 2'b00;
        end
        if(_zz_3[2]) begin
          age_2 <= 2'b00;
        end
        if(_zz_3[3]) begin
          age_3 <= 2'b00;
        end
        if(_zz_3[4]) begin
          age_4 <= 2'b00;
        end
        if(_zz_3[5]) begin
          age_5 <= 2'b00;
        end
        if(_zz_3[6]) begin
          age_6 <= 2'b00;
        end
        if(_zz_3[7]) begin
          age_7 <= 2'b00;
        end
        if(_zz_3[8]) begin
          age_8 <= 2'b00;
        end
        if(_zz_3[9]) begin
          age_9 <= 2'b00;
        end
        if(_zz_3[10]) begin
          age_10 <= 2'b00;
        end
        if(_zz_3[11]) begin
          age_11 <= 2'b00;
        end
        if(_zz_3[12]) begin
          age_12 <= 2'b00;
        end
        if(_zz_3[13]) begin
          age_13 <= 2'b00;
        end
        if(_zz_3[14]) begin
          age_14 <= 2'b00;
        end
        if(_zz_3[15]) begin
          age_15 <= 2'b00;
        end
      end
      if(when_ResultBank_l181) begin
        if(_zz_4[0]) begin
          store_0 <= io_write_data;
        end
        if(_zz_4[1]) begin
          store_1 <= io_write_data;
        end
        if(_zz_4[2]) begin
          store_2 <= io_write_data;
        end
        if(_zz_4[3]) begin
          store_3 <= io_write_data;
        end
        if(_zz_4[4]) begin
          store_4 <= io_write_data;
        end
        if(_zz_4[5]) begin
          store_5 <= io_write_data;
        end
        if(_zz_4[6]) begin
          store_6 <= io_write_data;
        end
        if(_zz_4[7]) begin
          store_7 <= io_write_data;
        end
        if(_zz_4[8]) begin
          store_8 <= io_write_data;
        end
        if(_zz_4[9]) begin
          store_9 <= io_write_data;
        end
        if(_zz_4[10]) begin
          store_10 <= io_write_data;
        end
        if(_zz_4[11]) begin
          store_11 <= io_write_data;
        end
        if(_zz_4[12]) begin
          store_12 <= io_write_data;
        end
        if(_zz_4[13]) begin
          store_13 <= io_write_data;
        end
        if(_zz_4[14]) begin
          store_14 <= io_write_data;
        end
        if(_zz_4[15]) begin
          store_15 <= io_write_data;
        end
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end


endmodule

module SharedUnit (
  input  wire          io_req_valid,
  input  wire [160:0]  io_req_payload,
  output wire          io_req_ready,
  output wire          io_rsp_valid,
  output wire [160:0]  io_rsp_payload,
  output wire          io_faultBpViolation,
  input  wire          io_faultClear,
  output wire [2:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg                 body_1_io_start;
  reg        [160:0]  body_1_io_req;
  wire                body_1_io_busy;
  wire                body_1_io_done;
  wire       [160:0]  body_1_io_rsp;
  reg        [160:0]  _zz_queue_head;
  wire       [1:0]    _zz_queue_rdPtr;
  wire       [1:0]    _zz_queue_wrPtr;
  wire       [2:0]    _zz_queue_cnt;
  wire       [2:0]    _zz_queue_cnt_1;
  wire       [0:0]    _zz_queue_cnt_2;
  wire       [2:0]    _zz_queue_cnt_3;
  wire       [0:0]    _zz_queue_cnt_4;
  wire       [2:0]    _zz_io_occupancy;
  wire       [0:0]    _zz_io_occupancy_1;
  reg        [160:0]  queue_slots_0;
  reg        [160:0]  queue_slots_1;
  reg        [160:0]  queue_slots_2;
  reg        [160:0]  queue_slots_3;
  reg        [1:0]    queue_rdPtr;
  reg        [1:0]    queue_wrPtr;
  reg        [2:0]    queue_cnt;
  wire       [160:0]  queue_head;
  wire                queueEmpty;
  wire                queueRoom;
  wire                acceptDirect;
  wire                acceptQueue;
  wire                bpViolation;
  reg                 _zz_io_faultBpViolation;
  wire                when_SharedUnit_l192;
  wire       [3:0]    _zz_1;

  assign _zz_queue_rdPtr = (queue_rdPtr + 2'b01);
  assign _zz_queue_wrPtr = (queue_wrPtr + 2'b01);
  assign _zz_queue_cnt = (queue_cnt + _zz_queue_cnt_1);
  assign _zz_queue_cnt_2 = (io_req_valid && acceptQueue);
  assign _zz_queue_cnt_1 = {2'd0, _zz_queue_cnt_2};
  assign _zz_queue_cnt_4 = when_SharedUnit_l192;
  assign _zz_queue_cnt_3 = {2'd0, _zz_queue_cnt_4};
  assign _zz_io_occupancy_1 = body_1_io_busy;
  assign _zz_io_occupancy = {2'd0, _zz_io_occupancy_1};
  SharedUnitOccupyStub body_1 (
    .io_start (body_1_io_start     ), //i
    .io_req   (body_1_io_req[160:0]), //i
    .io_busy  (body_1_io_busy      ), //o
    .io_done  (body_1_io_done      ), //o
    .io_rsp   (body_1_io_rsp[160:0]), //o
    .clk      (clk                 ), //i
    .reset    (reset               )  //i
  );
  always @(*) begin
    case(queue_rdPtr)
      2'b00 : _zz_queue_head = queue_slots_0;
      2'b01 : _zz_queue_head = queue_slots_1;
      2'b10 : _zz_queue_head = queue_slots_2;
      default : _zz_queue_head = queue_slots_3;
    endcase
  end

  assign queue_head = _zz_queue_head;
  assign queueEmpty = (queue_cnt == 3'b000);
  assign queueRoom = (queue_cnt < 3'b100);
  assign acceptDirect = ((! body_1_io_busy) && queueEmpty);
  assign acceptQueue = ((! acceptDirect) && queueRoom);
  assign io_req_ready = (acceptDirect || acceptQueue);
  assign bpViolation = (io_req_valid && (! io_req_ready));
  assign io_faultBpViolation = _zz_io_faultBpViolation;
  always @(*) begin
    body_1_io_start = 1'b0;
    if(when_SharedUnit_l192) begin
      body_1_io_start = 1'b1;
    end
    if(io_req_valid) begin
      if(acceptDirect) begin
        body_1_io_start = 1'b1;
      end
    end
  end

  always @(*) begin
    body_1_io_req = io_req_payload;
    if(when_SharedUnit_l192) begin
      body_1_io_req = queue_head;
    end
  end

  assign when_SharedUnit_l192 = ((! body_1_io_busy) && (! queueEmpty));
  assign _zz_1 = ({3'd0,1'b1} <<< queue_wrPtr);
  assign io_rsp_valid = body_1_io_done;
  assign io_rsp_payload = body_1_io_rsp;
  assign io_occupancy = (queue_cnt + _zz_io_occupancy);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      queue_slots_0 <= 161'h0;
      queue_slots_1 <= 161'h0;
      queue_slots_2 <= 161'h0;
      queue_slots_3 <= 161'h0;
      queue_rdPtr <= 2'b00;
      queue_wrPtr <= 2'b00;
      queue_cnt <= 3'b000;
      _zz_io_faultBpViolation <= 1'b0;
    end else begin
      if(io_faultClear) begin
        _zz_io_faultBpViolation <= 1'b0;
      end
      if(bpViolation) begin
        _zz_io_faultBpViolation <= 1'b1;
      end
      if(when_SharedUnit_l192) begin
        queue_rdPtr <= ((queue_rdPtr == 2'b11) ? 2'b00 : _zz_queue_rdPtr);
      end
      if(io_req_valid) begin
        if(!acceptDirect) begin
          if(acceptQueue) begin
            if(_zz_1[0]) begin
              queue_slots_0 <= io_req_payload;
            end
            if(_zz_1[1]) begin
              queue_slots_1 <= io_req_payload;
            end
            if(_zz_1[2]) begin
              queue_slots_2 <= io_req_payload;
            end
            if(_zz_1[3]) begin
              queue_slots_3 <= io_req_payload;
            end
            queue_wrPtr <= ((queue_wrPtr == 2'b11) ? 2'b00 : _zz_queue_wrPtr);
          end
        end
      end
      queue_cnt <= (_zz_queue_cnt - _zz_queue_cnt_3);
    end
  end


endmodule

module FabricMerge (
  output wire          io_fault,
  input  wire          io_faultClear,
  input  wire          io_push_0_strb,
  input  wire [31:0]   io_push_0_result_head_tag_wave,
  input  wire [15:0]   io_push_0_result_head_tag_thread,
  input  wire [15:0]   io_push_0_result_head_tag_lnid,
  input  wire [7:0]    io_push_0_result_head_tag_precision,
  input  wire [7:0]    io_push_0_result_head_tag_dim,
  input  wire [7:0]    io_push_0_result_head_seq,
  input  wire [7:0]    io_push_0_result_head_total,
  input  wire          io_push_0_result_head_last,
  input  wire [63:0]   io_push_0_result_body,
  output wire          io_push_0_stall,
  input  wire          io_push_1_strb,
  input  wire [31:0]   io_push_1_result_head_tag_wave,
  input  wire [15:0]   io_push_1_result_head_tag_thread,
  input  wire [15:0]   io_push_1_result_head_tag_lnid,
  input  wire [7:0]    io_push_1_result_head_tag_precision,
  input  wire [7:0]    io_push_1_result_head_tag_dim,
  input  wire [7:0]    io_push_1_result_head_seq,
  input  wire [7:0]    io_push_1_result_head_total,
  input  wire          io_push_1_result_head_last,
  input  wire [63:0]   io_push_1_result_body,
  output wire          io_push_1_stall,
  input  wire          io_push_2_strb,
  input  wire [31:0]   io_push_2_result_head_tag_wave,
  input  wire [15:0]   io_push_2_result_head_tag_thread,
  input  wire [15:0]   io_push_2_result_head_tag_lnid,
  input  wire [7:0]    io_push_2_result_head_tag_precision,
  input  wire [7:0]    io_push_2_result_head_tag_dim,
  input  wire [7:0]    io_push_2_result_head_seq,
  input  wire [7:0]    io_push_2_result_head_total,
  input  wire          io_push_2_result_head_last,
  input  wire [63:0]   io_push_2_result_body,
  output wire          io_push_2_stall,
  input  wire          io_push_3_strb,
  input  wire [31:0]   io_push_3_result_head_tag_wave,
  input  wire [15:0]   io_push_3_result_head_tag_thread,
  input  wire [15:0]   io_push_3_result_head_tag_lnid,
  input  wire [7:0]    io_push_3_result_head_tag_precision,
  input  wire [7:0]    io_push_3_result_head_tag_dim,
  input  wire [7:0]    io_push_3_result_head_seq,
  input  wire [7:0]    io_push_3_result_head_total,
  input  wire          io_push_3_result_head_last,
  input  wire [63:0]   io_push_3_result_body,
  output wire          io_push_3_stall,
  output wire          io_consumer_valid,
  input  wire          io_consumer_ready,
  output wire [31:0]   io_consumer_payload_head_tag_wave,
  output wire [15:0]   io_consumer_payload_head_tag_thread,
  output wire [15:0]   io_consumer_payload_head_tag_lnid,
  output wire [7:0]    io_consumer_payload_head_tag_precision,
  output wire [7:0]    io_consumer_payload_head_tag_dim,
  output wire [7:0]    io_consumer_payload_head_seq,
  output wire [7:0]    io_consumer_payload_head_total,
  output wire          io_consumer_payload_head_last,
  output wire [63:0]   io_consumer_payload_body,
  output wire [2:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  wire       [0:0]    _zz_lanes_0_wIdx;
  wire       [0:0]    _zz_lanes_1_wIdx;
  wire       [0:0]    _zz_lanes_2_wIdx;
  wire       [0:0]    _zz_lanes_3_wIdx;
  wire       [7:0]    _zz__zz_select_rrOh_2;
  wire       [7:0]    _zz__zz_select_rrOh_2_1;
  wire       [3:0]    _zz__zz_select_rrOh_2_2;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [2:0]    _zz_io_occupancy_5;
  reg        [31:0]   lanes_0_slots_0_head_tag_wave;
  reg        [15:0]   lanes_0_slots_0_head_tag_thread;
  reg        [15:0]   lanes_0_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_0_slots_0_head_tag_precision;
  reg        [7:0]    lanes_0_slots_0_head_tag_dim;
  reg        [7:0]    lanes_0_slots_0_head_seq;
  reg        [7:0]    lanes_0_slots_0_head_total;
  reg                 lanes_0_slots_0_head_last;
  reg        [63:0]   lanes_0_slots_0_body;
  reg        [0:0]    lanes_0_cnt;
  wire                lanes_0_full;
  wire                lanes_0_vld;
  wire                lanes_0_doPush;
  wire                lanes_0_shove;
  wire                lanes_0_doPop;
  wire       [0:0]    lanes_0_wIdx;
  wire                when_FabricMerge_l138;
  wire                when_FabricMerge_l143;
  wire                when_FabricMerge_l144;
  reg        [31:0]   lanes_1_slots_0_head_tag_wave;
  reg        [15:0]   lanes_1_slots_0_head_tag_thread;
  reg        [15:0]   lanes_1_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_1_slots_0_head_tag_precision;
  reg        [7:0]    lanes_1_slots_0_head_tag_dim;
  reg        [7:0]    lanes_1_slots_0_head_seq;
  reg        [7:0]    lanes_1_slots_0_head_total;
  reg                 lanes_1_slots_0_head_last;
  reg        [63:0]   lanes_1_slots_0_body;
  reg        [0:0]    lanes_1_cnt;
  wire                lanes_1_full;
  wire                lanes_1_vld;
  wire                lanes_1_doPush;
  wire                lanes_1_shove;
  wire                lanes_1_doPop;
  wire       [0:0]    lanes_1_wIdx;
  wire                when_FabricMerge_l138_1;
  wire                when_FabricMerge_l143_1;
  wire                when_FabricMerge_l144_1;
  reg        [31:0]   lanes_2_slots_0_head_tag_wave;
  reg        [15:0]   lanes_2_slots_0_head_tag_thread;
  reg        [15:0]   lanes_2_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_2_slots_0_head_tag_precision;
  reg        [7:0]    lanes_2_slots_0_head_tag_dim;
  reg        [7:0]    lanes_2_slots_0_head_seq;
  reg        [7:0]    lanes_2_slots_0_head_total;
  reg                 lanes_2_slots_0_head_last;
  reg        [63:0]   lanes_2_slots_0_body;
  reg        [0:0]    lanes_2_cnt;
  wire                lanes_2_full;
  wire                lanes_2_vld;
  wire                lanes_2_doPush;
  wire                lanes_2_shove;
  wire                lanes_2_doPop;
  wire       [0:0]    lanes_2_wIdx;
  wire                when_FabricMerge_l138_2;
  wire                when_FabricMerge_l143_2;
  wire                when_FabricMerge_l144_2;
  reg        [31:0]   lanes_3_slots_0_head_tag_wave;
  reg        [15:0]   lanes_3_slots_0_head_tag_thread;
  reg        [15:0]   lanes_3_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_3_slots_0_head_tag_precision;
  reg        [7:0]    lanes_3_slots_0_head_tag_dim;
  reg        [7:0]    lanes_3_slots_0_head_seq;
  reg        [7:0]    lanes_3_slots_0_head_total;
  reg                 lanes_3_slots_0_head_last;
  reg        [63:0]   lanes_3_slots_0_body;
  reg        [0:0]    lanes_3_cnt;
  wire                lanes_3_full;
  wire                lanes_3_vld;
  wire                lanes_3_doPush;
  wire                lanes_3_shove;
  wire                lanes_3_doPop;
  wire       [0:0]    lanes_3_wIdx;
  wire                when_FabricMerge_l138_3;
  wire                when_FabricMerge_l143_3;
  wire                when_FabricMerge_l144_3;
  reg        [3:0]    select_req;
  reg        [3:0]    select_ptrOh;
  wire       [3:0]    _zz_select_rrOh;
  wire       [7:0]    _zz_select_rrOh_1;
  wire       [7:0]    _zz_select_rrOh_2;
  wire       [3:0]    select_rrOh;
  reg                 select_locked;
  reg        [3:0]    select_lockedOh;
  wire       [3:0]    select_selOh;
  wire       [3:0]    select_drive;
  wire                when_FabricMerge_l180;
  wire                io_consumer_fire;
  wire       [160:0]  merge_contribs_0;
  wire       [160:0]  merge_contribs_1;
  wire       [160:0]  merge_contribs_2;
  wire       [160:0]  merge_contribs_3;
  wire       [160:0]  merge_merged;
  wire       [96:0]   _zz_io_consumer_payload_head_seq;
  wire       [79:0]   _zz_io_consumer_payload_head_tag_wave;
  wire                shoveAny;
  reg                 _zz_io_fault;

  assign _zz_lanes_0_wIdx = (lanes_0_cnt - 1'b1);
  assign _zz_lanes_1_wIdx = (lanes_1_cnt - 1'b1);
  assign _zz_lanes_2_wIdx = (lanes_2_cnt - 1'b1);
  assign _zz_lanes_3_wIdx = (lanes_3_cnt - 1'b1);
  assign _zz__zz_select_rrOh_2 = (_zz_select_rrOh_1 - _zz__zz_select_rrOh_2_1);
  assign _zz__zz_select_rrOh_2_2 = select_ptrOh;
  assign _zz__zz_select_rrOh_2_1 = {4'd0, _zz__zz_select_rrOh_2_2};
  assign _zz_io_occupancy = (_zz_io_occupancy_1 + _zz_io_occupancy_4);
  assign _zz_io_occupancy_1 = (_zz_io_occupancy_2 + _zz_io_occupancy_3);
  assign _zz_io_occupancy_2 = {2'd0, lanes_0_cnt};
  assign _zz_io_occupancy_3 = {2'd0, lanes_1_cnt};
  assign _zz_io_occupancy_4 = {2'd0, lanes_2_cnt};
  assign _zz_io_occupancy_5 = {2'd0, lanes_3_cnt};
  assign lanes_0_full = (lanes_0_cnt == 1'b1);
  assign lanes_0_vld = (lanes_0_cnt != 1'b0);
  assign io_push_0_stall = lanes_0_full;
  assign lanes_0_doPush = (io_push_0_strb && (! lanes_0_full));
  assign lanes_0_shove = (io_push_0_strb && lanes_0_full);
  assign lanes_0_wIdx = (lanes_0_doPop ? _zz_lanes_0_wIdx : lanes_0_cnt);
  assign when_FabricMerge_l138 = (lanes_0_wIdx == 1'b0);
  assign when_FabricMerge_l143 = (lanes_0_doPush && (! lanes_0_doPop));
  assign when_FabricMerge_l144 = ((! lanes_0_doPush) && lanes_0_doPop);
  assign lanes_1_full = (lanes_1_cnt == 1'b1);
  assign lanes_1_vld = (lanes_1_cnt != 1'b0);
  assign io_push_1_stall = lanes_1_full;
  assign lanes_1_doPush = (io_push_1_strb && (! lanes_1_full));
  assign lanes_1_shove = (io_push_1_strb && lanes_1_full);
  assign lanes_1_wIdx = (lanes_1_doPop ? _zz_lanes_1_wIdx : lanes_1_cnt);
  assign when_FabricMerge_l138_1 = (lanes_1_wIdx == 1'b0);
  assign when_FabricMerge_l143_1 = (lanes_1_doPush && (! lanes_1_doPop));
  assign when_FabricMerge_l144_1 = ((! lanes_1_doPush) && lanes_1_doPop);
  assign lanes_2_full = (lanes_2_cnt == 1'b1);
  assign lanes_2_vld = (lanes_2_cnt != 1'b0);
  assign io_push_2_stall = lanes_2_full;
  assign lanes_2_doPush = (io_push_2_strb && (! lanes_2_full));
  assign lanes_2_shove = (io_push_2_strb && lanes_2_full);
  assign lanes_2_wIdx = (lanes_2_doPop ? _zz_lanes_2_wIdx : lanes_2_cnt);
  assign when_FabricMerge_l138_2 = (lanes_2_wIdx == 1'b0);
  assign when_FabricMerge_l143_2 = (lanes_2_doPush && (! lanes_2_doPop));
  assign when_FabricMerge_l144_2 = ((! lanes_2_doPush) && lanes_2_doPop);
  assign lanes_3_full = (lanes_3_cnt == 1'b1);
  assign lanes_3_vld = (lanes_3_cnt != 1'b0);
  assign io_push_3_stall = lanes_3_full;
  assign lanes_3_doPush = (io_push_3_strb && (! lanes_3_full));
  assign lanes_3_shove = (io_push_3_strb && lanes_3_full);
  assign lanes_3_wIdx = (lanes_3_doPop ? _zz_lanes_3_wIdx : lanes_3_cnt);
  assign when_FabricMerge_l138_3 = (lanes_3_wIdx == 1'b0);
  assign when_FabricMerge_l143_3 = (lanes_3_doPush && (! lanes_3_doPop));
  assign when_FabricMerge_l144_3 = ((! lanes_3_doPush) && lanes_3_doPop);
  always @(*) begin
    select_req[0] = lanes_0_vld;
    select_req[1] = lanes_1_vld;
    select_req[2] = lanes_2_vld;
    select_req[3] = lanes_3_vld;
  end

  assign _zz_select_rrOh = select_req;
  assign _zz_select_rrOh_1 = {_zz_select_rrOh,_zz_select_rrOh};
  assign _zz_select_rrOh_2 = (_zz_select_rrOh_1 & (~ _zz__zz_select_rrOh_2));
  assign select_rrOh = (_zz_select_rrOh_2[7 : 4] | _zz_select_rrOh_2[3 : 0]);
  assign select_selOh = (select_locked ? select_lockedOh : select_rrOh);
  assign select_drive = (select_selOh & select_req);
  assign when_FabricMerge_l180 = (io_consumer_valid && (! io_consumer_ready));
  assign io_consumer_fire = (io_consumer_valid && io_consumer_ready);
  assign merge_contribs_0 = (select_drive[0] ? {lanes_0_slots_0_body,{lanes_0_slots_0_head_last,{lanes_0_slots_0_head_total,{lanes_0_slots_0_head_seq,{lanes_0_slots_0_head_tag_dim,{lanes_0_slots_0_head_tag_precision,{lanes_0_slots_0_head_tag_lnid,{lanes_0_slots_0_head_tag_thread,lanes_0_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_1 = (select_drive[1] ? {lanes_1_slots_0_body,{lanes_1_slots_0_head_last,{lanes_1_slots_0_head_total,{lanes_1_slots_0_head_seq,{lanes_1_slots_0_head_tag_dim,{lanes_1_slots_0_head_tag_precision,{lanes_1_slots_0_head_tag_lnid,{lanes_1_slots_0_head_tag_thread,lanes_1_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_2 = (select_drive[2] ? {lanes_2_slots_0_body,{lanes_2_slots_0_head_last,{lanes_2_slots_0_head_total,{lanes_2_slots_0_head_seq,{lanes_2_slots_0_head_tag_dim,{lanes_2_slots_0_head_tag_precision,{lanes_2_slots_0_head_tag_lnid,{lanes_2_slots_0_head_tag_thread,lanes_2_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_3 = (select_drive[3] ? {lanes_3_slots_0_body,{lanes_3_slots_0_head_last,{lanes_3_slots_0_head_total,{lanes_3_slots_0_head_seq,{lanes_3_slots_0_head_tag_dim,{lanes_3_slots_0_head_tag_precision,{lanes_3_slots_0_head_tag_lnid,{lanes_3_slots_0_head_tag_thread,lanes_3_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_merged = (((merge_contribs_0 | merge_contribs_1) | merge_contribs_2) | merge_contribs_3);
  assign io_consumer_valid = (|select_drive);
  assign _zz_io_consumer_payload_head_seq = merge_merged[96 : 0];
  assign _zz_io_consumer_payload_head_tag_wave = _zz_io_consumer_payload_head_seq[79 : 0];
  assign io_consumer_payload_head_tag_wave = _zz_io_consumer_payload_head_tag_wave[31 : 0];
  assign io_consumer_payload_head_tag_thread = _zz_io_consumer_payload_head_tag_wave[47 : 32];
  assign io_consumer_payload_head_tag_lnid = _zz_io_consumer_payload_head_tag_wave[63 : 48];
  assign io_consumer_payload_head_tag_precision = _zz_io_consumer_payload_head_tag_wave[71 : 64];
  assign io_consumer_payload_head_tag_dim = _zz_io_consumer_payload_head_tag_wave[79 : 72];
  assign io_consumer_payload_head_seq = _zz_io_consumer_payload_head_seq[87 : 80];
  assign io_consumer_payload_head_total = _zz_io_consumer_payload_head_seq[95 : 88];
  assign io_consumer_payload_head_last = _zz_io_consumer_payload_head_seq[96];
  assign io_consumer_payload_body = merge_merged[160 : 97];
  assign lanes_0_doPop = (select_drive[0] && io_consumer_fire);
  assign lanes_1_doPop = (select_drive[1] && io_consumer_fire);
  assign lanes_2_doPop = (select_drive[2] && io_consumer_fire);
  assign lanes_3_doPop = (select_drive[3] && io_consumer_fire);
  assign shoveAny = (((lanes_0_shove || lanes_1_shove) || lanes_2_shove) || lanes_3_shove);
  assign io_fault = _zz_io_fault;
  assign io_occupancy = (_zz_io_occupancy + _zz_io_occupancy_5);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      lanes_0_cnt <= 1'b0;
      lanes_1_cnt <= 1'b0;
      lanes_2_cnt <= 1'b0;
      lanes_3_cnt <= 1'b0;
      select_ptrOh <= 4'b0001;
      select_locked <= 1'b0;
      select_lockedOh <= 4'b0000;
      _zz_io_fault <= 1'b0;
    end else begin
      if(when_FabricMerge_l143) begin
        lanes_0_cnt <= (lanes_0_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l144) begin
          lanes_0_cnt <= (lanes_0_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l143_1) begin
        lanes_1_cnt <= (lanes_1_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l144_1) begin
          lanes_1_cnt <= (lanes_1_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l143_2) begin
        lanes_2_cnt <= (lanes_2_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l144_2) begin
          lanes_2_cnt <= (lanes_2_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l143_3) begin
        lanes_3_cnt <= (lanes_3_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l144_3) begin
          lanes_3_cnt <= (lanes_3_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l180) begin
        select_locked <= 1'b1;
        select_lockedOh <= select_selOh;
      end else begin
        select_locked <= 1'b0;
      end
      if(io_consumer_fire) begin
        select_ptrOh <= {select_selOh[2 : 0],select_selOh[3 : 3]};
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(shoveAny) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(lanes_0_doPush) begin
      if(when_FabricMerge_l138) begin
        lanes_0_slots_0_head_tag_wave <= io_push_0_result_head_tag_wave;
        lanes_0_slots_0_head_tag_thread <= io_push_0_result_head_tag_thread;
        lanes_0_slots_0_head_tag_lnid <= io_push_0_result_head_tag_lnid;
        lanes_0_slots_0_head_tag_precision <= io_push_0_result_head_tag_precision;
        lanes_0_slots_0_head_tag_dim <= io_push_0_result_head_tag_dim;
        lanes_0_slots_0_head_seq <= io_push_0_result_head_seq;
        lanes_0_slots_0_head_total <= io_push_0_result_head_total;
        lanes_0_slots_0_head_last <= io_push_0_result_head_last;
        lanes_0_slots_0_body <= io_push_0_result_body;
      end
    end
    if(lanes_1_doPush) begin
      if(when_FabricMerge_l138_1) begin
        lanes_1_slots_0_head_tag_wave <= io_push_1_result_head_tag_wave;
        lanes_1_slots_0_head_tag_thread <= io_push_1_result_head_tag_thread;
        lanes_1_slots_0_head_tag_lnid <= io_push_1_result_head_tag_lnid;
        lanes_1_slots_0_head_tag_precision <= io_push_1_result_head_tag_precision;
        lanes_1_slots_0_head_tag_dim <= io_push_1_result_head_tag_dim;
        lanes_1_slots_0_head_seq <= io_push_1_result_head_seq;
        lanes_1_slots_0_head_total <= io_push_1_result_head_total;
        lanes_1_slots_0_head_last <= io_push_1_result_head_last;
        lanes_1_slots_0_body <= io_push_1_result_body;
      end
    end
    if(lanes_2_doPush) begin
      if(when_FabricMerge_l138_2) begin
        lanes_2_slots_0_head_tag_wave <= io_push_2_result_head_tag_wave;
        lanes_2_slots_0_head_tag_thread <= io_push_2_result_head_tag_thread;
        lanes_2_slots_0_head_tag_lnid <= io_push_2_result_head_tag_lnid;
        lanes_2_slots_0_head_tag_precision <= io_push_2_result_head_tag_precision;
        lanes_2_slots_0_head_tag_dim <= io_push_2_result_head_tag_dim;
        lanes_2_slots_0_head_seq <= io_push_2_result_head_seq;
        lanes_2_slots_0_head_total <= io_push_2_result_head_total;
        lanes_2_slots_0_head_last <= io_push_2_result_head_last;
        lanes_2_slots_0_body <= io_push_2_result_body;
      end
    end
    if(lanes_3_doPush) begin
      if(when_FabricMerge_l138_3) begin
        lanes_3_slots_0_head_tag_wave <= io_push_3_result_head_tag_wave;
        lanes_3_slots_0_head_tag_thread <= io_push_3_result_head_tag_thread;
        lanes_3_slots_0_head_tag_lnid <= io_push_3_result_head_tag_lnid;
        lanes_3_slots_0_head_tag_precision <= io_push_3_result_head_tag_precision;
        lanes_3_slots_0_head_tag_dim <= io_push_3_result_head_tag_dim;
        lanes_3_slots_0_head_seq <= io_push_3_result_head_seq;
        lanes_3_slots_0_head_total <= io_push_3_result_head_total;
        lanes_3_slots_0_head_last <= io_push_3_result_head_last;
        lanes_3_slots_0_body <= io_push_3_result_body;
      end
    end
  end


endmodule

module MmioConfig (
  input  wire [11:0]   io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output reg  [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  output reg           io_viewWr_valid,
  output reg  [3:0]    io_viewWr_idx,
  output reg           io_viewWr_en,
  output reg  [15:0]   io_viewWr_lnid,
  output reg           io_bankWr_valid,
  output reg  [7:0]    io_bankWr_lbid,
  output reg           io_bankWr_mapped,
  output wire          io_faultDupOwner,
  output wire          io_faultBadWrite,
  input  wire          io_faultClearDup,
  input  wire          io_faultClearBad,
  input  wire          clk,
  input  wire          reset
);

  reg        [31:0]   fwdMem_spinal_port0;
  reg        [0:0]    revMem_spinal_port0;
  reg        [31:0]   lbidMem_spinal_port0;
  reg        [15:0]   initCnt;
  reg                 initDone;
  wire                sweeping;
  wire                when_MmioConfig_l244;
  reg                 revWrEn;
  reg        [15:0]   revWrAddr;
  reg        [0:0]    revWrData;
  reg                 fwdWrEn;
  reg        [7:0]    fwdWrAddr;
  reg        [31:0]   fwdWrData;
  reg                 lbWrEn;
  reg        [7:0]    lbWrAddr;
  reg        [31:0]   lbWrData;
  wire                when_MmioConfig_l271;
  reg                 busy;
  wire                aligned;
  wire       [1:0]    region;
  wire       [7:0]    wordIdx;
  wire                acceptW;
  wire                acceptR;
  wire                memRdEn;
  wire       [31:0]   fwdRd;
  wire       [31:0]   lbRd;
  reg        [1:0]    rdSel;
  reg                 acceptR_regNext;
  wire                lbidWrite;
  wire                lbRsvBad;
  wire                chkLbBadWr;
  wire                lbidCommit;
  wire                lnidWrite;
  reg        [7:0]    pSlot;
  reg        [31:0]   pWord;
  wire                pV;
  wire       [7:0]    pPoint;
  wire       [15:0]   pLnid;
  wire                pRsvBad;
  wire       [15:0]   revChkAddr;
  wire       [0:0]    revChk;
  wire                revChkPresent;
  wire                oldV;
  wire       [15:0]   oldLnid;
  reg                 chkDupOwn;
  reg                 chkBadWr;
  wire                when_MmioConfig_l408;
  reg                 _zz_io_faultDupOwner;
  wire                when_Common_l259;
  reg                 _zz_io_faultBadWrite;
  reg [31:0] fwdMem [0:255];
  reg [0:0] revMem [0:65535];
  reg [31:0] lbidMem [0:255];

  always @(posedge clk) begin
    if(memRdEn) begin
      fwdMem_spinal_port0 <= fwdMem[wordIdx];
    end
  end

  always @(posedge clk) begin
    if(fwdWrEn) begin
      fwdMem[fwdWrAddr] <= fwdWrData;
    end
  end

  always @(posedge clk) begin
    if(memRdEn) begin
      revMem_spinal_port0 <= revMem[revChkAddr];
    end
  end

  always @(posedge clk) begin
    if(revWrEn) begin
      revMem[revWrAddr] <= revWrData;
    end
  end

  always @(posedge clk) begin
    if(memRdEn) begin
      lbidMem_spinal_port0 <= lbidMem[wordIdx];
    end
  end

  always @(posedge clk) begin
    if(lbWrEn) begin
      lbidMem[lbWrAddr] <= lbWrData;
    end
  end

  assign sweeping = (! initDone);
  assign when_MmioConfig_l244 = (initCnt == 16'hffff);
  always @(*) begin
    revWrEn = 1'b0;
    if(sweeping) begin
      revWrEn = 1'b1;
    end
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              revWrEn = 1'b1;
            end
          end
        end else begin
          if(oldV) begin
            revWrEn = 1'b1;
          end
        end
      end
    end
  end

  always @(*) begin
    revWrAddr = 16'h0;
    if(sweeping) begin
      revWrAddr = initCnt;
    end
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              revWrAddr = pLnid;
            end
          end
        end else begin
          if(oldV) begin
            revWrAddr = oldLnid;
          end
        end
      end
    end
  end

  always @(*) begin
    revWrData = 1'b0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              revWrData = 1'b1;
            end
          end
        end else begin
          if(oldV) begin
            revWrData = 1'b0;
          end
        end
      end
    end
  end

  always @(*) begin
    fwdWrEn = 1'b0;
    if(sweeping) begin
      if(when_MmioConfig_l271) begin
        fwdWrEn = 1'b1;
      end
    end
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              fwdWrEn = 1'b1;
            end
          end
        end else begin
          if(oldV) begin
            fwdWrEn = 1'b1;
          end
        end
      end
    end
  end

  always @(*) begin
    fwdWrAddr = 8'h0;
    if(sweeping) begin
      if(when_MmioConfig_l271) begin
        fwdWrAddr = initCnt[7:0];
      end
    end
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              fwdWrAddr = pSlot;
            end
          end
        end else begin
          if(oldV) begin
            fwdWrAddr = pSlot;
          end
        end
      end
    end
  end

  always @(*) begin
    fwdWrData = 32'h0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              fwdWrData = pWord;
            end
          end
        end else begin
          if(oldV) begin
            fwdWrData = 32'h0;
          end
        end
      end
    end
  end

  always @(*) begin
    lbWrEn = 1'b0;
    if(sweeping) begin
      if(when_MmioConfig_l271) begin
        lbWrEn = 1'b1;
      end
    end
    if(lbidCommit) begin
      lbWrEn = 1'b1;
    end
  end

  always @(*) begin
    lbWrAddr = 8'h0;
    if(sweeping) begin
      if(when_MmioConfig_l271) begin
        lbWrAddr = initCnt[7:0];
      end
    end
    if(lbidCommit) begin
      lbWrAddr = wordIdx;
    end
  end

  always @(*) begin
    lbWrData = 32'h0;
    if(lbidCommit) begin
      lbWrData = io_wdata;
    end
  end

  assign when_MmioConfig_l271 = (initCnt < 16'h0100);
  assign io_ready = (initDone && (! busy));
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign region = io_addr[11 : 10];
  assign wordIdx = io_addr[9 : 2];
  assign acceptW = (io_ready && io_wstrobe);
  assign acceptR = ((io_ready && (! io_wstrobe)) && io_rstrobe);
  assign memRdEn = (acceptR || acceptW);
  assign fwdRd = fwdMem_spinal_port0;
  assign lbRd = lbidMem_spinal_port0;
  assign io_rvalid = acceptR_regNext;
  always @(*) begin
    io_rdata = 32'h0;
    case(rdSel)
      2'b01 : begin
        io_rdata = fwdRd;
      end
      2'b10 : begin
        io_rdata = lbRd;
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    io_viewWr_valid = 1'b0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              io_viewWr_valid = 1'b1;
            end
          end
        end else begin
          if(oldV) begin
            io_viewWr_valid = 1'b1;
          end
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_idx = 4'b0000;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              io_viewWr_idx = pSlot[3:0];
            end
          end
        end else begin
          if(oldV) begin
            io_viewWr_idx = pSlot[3:0];
          end
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_en = 1'b0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              io_viewWr_en = 1'b1;
            end
          end
        end else begin
          if(oldV) begin
            io_viewWr_en = 1'b0;
          end
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_lnid = 16'h0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(!revChkPresent) begin
              io_viewWr_lnid = pLnid;
            end
          end
        end else begin
          if(oldV) begin
            io_viewWr_lnid = oldLnid;
          end
        end
      end
    end
  end

  always @(*) begin
    io_bankWr_valid = 1'b0;
    if(lbidCommit) begin
      io_bankWr_valid = 1'b1;
    end
  end

  always @(*) begin
    io_bankWr_lbid = 8'h0;
    if(lbidCommit) begin
      io_bankWr_lbid = wordIdx;
    end
  end

  always @(*) begin
    io_bankWr_mapped = 1'b0;
    if(lbidCommit) begin
      io_bankWr_mapped = io_wdata[31];
    end
  end

  assign lbidWrite = ((acceptW && aligned) && (region == 2'b10));
  assign lbRsvBad = ((io_wdata & 32'h7fff0000) != 32'h0);
  assign chkLbBadWr = (lbidWrite && lbRsvBad);
  assign lbidCommit = (lbidWrite && (! lbRsvBad));
  assign lnidWrite = ((acceptW && aligned) && (region == 2'b01));
  assign pV = pWord[31];
  assign pPoint = pWord[23 : 16];
  assign pLnid = pWord[15 : 0];
  assign pRsvBad = ((pWord & 32'h7f000000) != 32'h0);
  assign revChkAddr = io_wdata[15 : 0];
  assign revChk = revMem_spinal_port0;
  assign revChkPresent = revChk[0];
  assign oldV = fwdRd[31];
  assign oldLnid = fwdRd[15 : 0];
  always @(*) begin
    chkDupOwn = 1'b0;
    if(busy) begin
      if(!pRsvBad) begin
        if(pV) begin
          if(!when_MmioConfig_l408) begin
            if(revChkPresent) begin
              chkDupOwn = 1'b1;
            end
          end
        end
      end
    end
  end

  always @(*) begin
    chkBadWr = 1'b0;
    if(busy) begin
      if(pRsvBad) begin
        chkBadWr = 1'b1;
      end else begin
        if(pV) begin
          if(when_MmioConfig_l408) begin
            chkBadWr = 1'b1;
          end
        end
      end
    end
  end

  assign when_MmioConfig_l408 = (((8'h10 <= pSlot) || oldV) || (8'h04 <= pPoint));
  assign io_faultDupOwner = _zz_io_faultDupOwner;
  assign when_Common_l259 = (chkBadWr || chkLbBadWr);
  assign io_faultBadWrite = _zz_io_faultBadWrite;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      initCnt <= 16'h0;
      initDone <= 1'b0;
      busy <= 1'b0;
      rdSel <= 2'b00;
      acceptR_regNext <= 1'b0;
      pSlot <= 8'h0;
      pWord <= 32'h0;
      _zz_io_faultDupOwner <= 1'b0;
      _zz_io_faultBadWrite <= 1'b0;
    end else begin
      if(sweeping) begin
        initCnt <= (initCnt + 16'h0001);
        if(when_MmioConfig_l244) begin
          initDone <= 1'b1;
        end
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdSel <= 2'b00;
        if(aligned) begin
          rdSel <= region;
        end
      end
      if(lnidWrite) begin
        busy <= 1'b1;
        pSlot <= wordIdx;
        pWord <= io_wdata;
      end
      if(busy) begin
        busy <= 1'b0;
      end
      if(io_faultClearDup) begin
        _zz_io_faultDupOwner <= 1'b0;
      end
      if(chkDupOwn) begin
        _zz_io_faultDupOwner <= 1'b1;
      end
      if(io_faultClearBad) begin
        _zz_io_faultBadWrite <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_faultBadWrite <= 1'b1;
      end
    end
  end


endmodule

module OwnershipTable (
  input  wire [11:0]   io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output reg  [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  input  wire [31:0]   io_query_frame,
  output wire          io_query_devOwned,
  output wire          io_faultCollide,
  input  wire          io_faultClearCollide,
  output wire          io_faultBadWrite,
  input  wire          io_faultClearBadWrite,
  input  wire          clk,
  input  wire          reset
);

  reg        [25:0]   _zz_io_query_devOwned;
  reg        [25:0]   _zz_chkTag;
  reg        [63:0]   validBits;
  reg        [25:0]   tagVec_0;
  reg        [25:0]   tagVec_1;
  reg        [25:0]   tagVec_2;
  reg        [25:0]   tagVec_3;
  reg        [25:0]   tagVec_4;
  reg        [25:0]   tagVec_5;
  reg        [25:0]   tagVec_6;
  reg        [25:0]   tagVec_7;
  reg        [25:0]   tagVec_8;
  reg        [25:0]   tagVec_9;
  reg        [25:0]   tagVec_10;
  reg        [25:0]   tagVec_11;
  reg        [25:0]   tagVec_12;
  reg        [25:0]   tagVec_13;
  reg        [25:0]   tagVec_14;
  reg        [25:0]   tagVec_15;
  reg        [25:0]   tagVec_16;
  reg        [25:0]   tagVec_17;
  reg        [25:0]   tagVec_18;
  reg        [25:0]   tagVec_19;
  reg        [25:0]   tagVec_20;
  reg        [25:0]   tagVec_21;
  reg        [25:0]   tagVec_22;
  reg        [25:0]   tagVec_23;
  reg        [25:0]   tagVec_24;
  reg        [25:0]   tagVec_25;
  reg        [25:0]   tagVec_26;
  reg        [25:0]   tagVec_27;
  reg        [25:0]   tagVec_28;
  reg        [25:0]   tagVec_29;
  reg        [25:0]   tagVec_30;
  reg        [25:0]   tagVec_31;
  reg        [25:0]   tagVec_32;
  reg        [25:0]   tagVec_33;
  reg        [25:0]   tagVec_34;
  reg        [25:0]   tagVec_35;
  reg        [25:0]   tagVec_36;
  reg        [25:0]   tagVec_37;
  reg        [25:0]   tagVec_38;
  reg        [25:0]   tagVec_39;
  reg        [25:0]   tagVec_40;
  reg        [25:0]   tagVec_41;
  reg        [25:0]   tagVec_42;
  reg        [25:0]   tagVec_43;
  reg        [25:0]   tagVec_44;
  reg        [25:0]   tagVec_45;
  reg        [25:0]   tagVec_46;
  reg        [25:0]   tagVec_47;
  reg        [25:0]   tagVec_48;
  reg        [25:0]   tagVec_49;
  reg        [25:0]   tagVec_50;
  reg        [25:0]   tagVec_51;
  reg        [25:0]   tagVec_52;
  reg        [25:0]   tagVec_53;
  reg        [25:0]   tagVec_54;
  reg        [25:0]   tagVec_55;
  reg        [25:0]   tagVec_56;
  reg        [25:0]   tagVec_57;
  reg        [25:0]   tagVec_58;
  reg        [25:0]   tagVec_59;
  reg        [25:0]   tagVec_60;
  reg        [25:0]   tagVec_61;
  reg        [25:0]   tagVec_62;
  reg        [25:0]   tagVec_63;
  wire       [5:0]    qIdx;
  wire       [25:0]   qTag;
  wire                aligned;
  wire                region;
  wire       [5:0]    word;
  wire                acceptW;
  wire                acceptR;
  wire                selW;
  wire                idxWr;
  wire                statusWr;
  wire                setWr;
  wire                clrWr;
  reg        [31:0]   idxReg;
  wire       [31:0]   wFrame;
  wire       [5:0]    wIdx;
  wire       [25:0]   wTag;
  wire       [31:0]   idxFrm;
  reg        [5:0]    chkAddr;
  wire       [25:0]   chkTag;
  wire       [25:0]   idxTag;
  wire                devStateAtIdx;
  reg        [1:0]    rdSel;
  reg                 rState;
  reg                 acceptR_regNext;
  wire                when_OwnershipTable_l297;
  wire                when_OwnershipTable_l298;
  wire                when_OwnershipTable_l299;
  reg                 collide;
  wire                slotBusy;
  wire                slotMine;
  wire                when_OwnershipTable_l318;
  wire       [63:0]   _zz_1;
  wire                when_OwnershipTable_l321;
  wire                when_OwnershipTable_l330;
  reg                 _zz_io_faultCollide;
  reg                 _zz_io_faultBadWrite;

  always @(*) begin
    case(qIdx)
      6'b000000 : _zz_io_query_devOwned = tagVec_0;
      6'b000001 : _zz_io_query_devOwned = tagVec_1;
      6'b000010 : _zz_io_query_devOwned = tagVec_2;
      6'b000011 : _zz_io_query_devOwned = tagVec_3;
      6'b000100 : _zz_io_query_devOwned = tagVec_4;
      6'b000101 : _zz_io_query_devOwned = tagVec_5;
      6'b000110 : _zz_io_query_devOwned = tagVec_6;
      6'b000111 : _zz_io_query_devOwned = tagVec_7;
      6'b001000 : _zz_io_query_devOwned = tagVec_8;
      6'b001001 : _zz_io_query_devOwned = tagVec_9;
      6'b001010 : _zz_io_query_devOwned = tagVec_10;
      6'b001011 : _zz_io_query_devOwned = tagVec_11;
      6'b001100 : _zz_io_query_devOwned = tagVec_12;
      6'b001101 : _zz_io_query_devOwned = tagVec_13;
      6'b001110 : _zz_io_query_devOwned = tagVec_14;
      6'b001111 : _zz_io_query_devOwned = tagVec_15;
      6'b010000 : _zz_io_query_devOwned = tagVec_16;
      6'b010001 : _zz_io_query_devOwned = tagVec_17;
      6'b010010 : _zz_io_query_devOwned = tagVec_18;
      6'b010011 : _zz_io_query_devOwned = tagVec_19;
      6'b010100 : _zz_io_query_devOwned = tagVec_20;
      6'b010101 : _zz_io_query_devOwned = tagVec_21;
      6'b010110 : _zz_io_query_devOwned = tagVec_22;
      6'b010111 : _zz_io_query_devOwned = tagVec_23;
      6'b011000 : _zz_io_query_devOwned = tagVec_24;
      6'b011001 : _zz_io_query_devOwned = tagVec_25;
      6'b011010 : _zz_io_query_devOwned = tagVec_26;
      6'b011011 : _zz_io_query_devOwned = tagVec_27;
      6'b011100 : _zz_io_query_devOwned = tagVec_28;
      6'b011101 : _zz_io_query_devOwned = tagVec_29;
      6'b011110 : _zz_io_query_devOwned = tagVec_30;
      6'b011111 : _zz_io_query_devOwned = tagVec_31;
      6'b100000 : _zz_io_query_devOwned = tagVec_32;
      6'b100001 : _zz_io_query_devOwned = tagVec_33;
      6'b100010 : _zz_io_query_devOwned = tagVec_34;
      6'b100011 : _zz_io_query_devOwned = tagVec_35;
      6'b100100 : _zz_io_query_devOwned = tagVec_36;
      6'b100101 : _zz_io_query_devOwned = tagVec_37;
      6'b100110 : _zz_io_query_devOwned = tagVec_38;
      6'b100111 : _zz_io_query_devOwned = tagVec_39;
      6'b101000 : _zz_io_query_devOwned = tagVec_40;
      6'b101001 : _zz_io_query_devOwned = tagVec_41;
      6'b101010 : _zz_io_query_devOwned = tagVec_42;
      6'b101011 : _zz_io_query_devOwned = tagVec_43;
      6'b101100 : _zz_io_query_devOwned = tagVec_44;
      6'b101101 : _zz_io_query_devOwned = tagVec_45;
      6'b101110 : _zz_io_query_devOwned = tagVec_46;
      6'b101111 : _zz_io_query_devOwned = tagVec_47;
      6'b110000 : _zz_io_query_devOwned = tagVec_48;
      6'b110001 : _zz_io_query_devOwned = tagVec_49;
      6'b110010 : _zz_io_query_devOwned = tagVec_50;
      6'b110011 : _zz_io_query_devOwned = tagVec_51;
      6'b110100 : _zz_io_query_devOwned = tagVec_52;
      6'b110101 : _zz_io_query_devOwned = tagVec_53;
      6'b110110 : _zz_io_query_devOwned = tagVec_54;
      6'b110111 : _zz_io_query_devOwned = tagVec_55;
      6'b111000 : _zz_io_query_devOwned = tagVec_56;
      6'b111001 : _zz_io_query_devOwned = tagVec_57;
      6'b111010 : _zz_io_query_devOwned = tagVec_58;
      6'b111011 : _zz_io_query_devOwned = tagVec_59;
      6'b111100 : _zz_io_query_devOwned = tagVec_60;
      6'b111101 : _zz_io_query_devOwned = tagVec_61;
      6'b111110 : _zz_io_query_devOwned = tagVec_62;
      default : _zz_io_query_devOwned = tagVec_63;
    endcase
  end

  always @(*) begin
    case(chkAddr)
      6'b000000 : _zz_chkTag = tagVec_0;
      6'b000001 : _zz_chkTag = tagVec_1;
      6'b000010 : _zz_chkTag = tagVec_2;
      6'b000011 : _zz_chkTag = tagVec_3;
      6'b000100 : _zz_chkTag = tagVec_4;
      6'b000101 : _zz_chkTag = tagVec_5;
      6'b000110 : _zz_chkTag = tagVec_6;
      6'b000111 : _zz_chkTag = tagVec_7;
      6'b001000 : _zz_chkTag = tagVec_8;
      6'b001001 : _zz_chkTag = tagVec_9;
      6'b001010 : _zz_chkTag = tagVec_10;
      6'b001011 : _zz_chkTag = tagVec_11;
      6'b001100 : _zz_chkTag = tagVec_12;
      6'b001101 : _zz_chkTag = tagVec_13;
      6'b001110 : _zz_chkTag = tagVec_14;
      6'b001111 : _zz_chkTag = tagVec_15;
      6'b010000 : _zz_chkTag = tagVec_16;
      6'b010001 : _zz_chkTag = tagVec_17;
      6'b010010 : _zz_chkTag = tagVec_18;
      6'b010011 : _zz_chkTag = tagVec_19;
      6'b010100 : _zz_chkTag = tagVec_20;
      6'b010101 : _zz_chkTag = tagVec_21;
      6'b010110 : _zz_chkTag = tagVec_22;
      6'b010111 : _zz_chkTag = tagVec_23;
      6'b011000 : _zz_chkTag = tagVec_24;
      6'b011001 : _zz_chkTag = tagVec_25;
      6'b011010 : _zz_chkTag = tagVec_26;
      6'b011011 : _zz_chkTag = tagVec_27;
      6'b011100 : _zz_chkTag = tagVec_28;
      6'b011101 : _zz_chkTag = tagVec_29;
      6'b011110 : _zz_chkTag = tagVec_30;
      6'b011111 : _zz_chkTag = tagVec_31;
      6'b100000 : _zz_chkTag = tagVec_32;
      6'b100001 : _zz_chkTag = tagVec_33;
      6'b100010 : _zz_chkTag = tagVec_34;
      6'b100011 : _zz_chkTag = tagVec_35;
      6'b100100 : _zz_chkTag = tagVec_36;
      6'b100101 : _zz_chkTag = tagVec_37;
      6'b100110 : _zz_chkTag = tagVec_38;
      6'b100111 : _zz_chkTag = tagVec_39;
      6'b101000 : _zz_chkTag = tagVec_40;
      6'b101001 : _zz_chkTag = tagVec_41;
      6'b101010 : _zz_chkTag = tagVec_42;
      6'b101011 : _zz_chkTag = tagVec_43;
      6'b101100 : _zz_chkTag = tagVec_44;
      6'b101101 : _zz_chkTag = tagVec_45;
      6'b101110 : _zz_chkTag = tagVec_46;
      6'b101111 : _zz_chkTag = tagVec_47;
      6'b110000 : _zz_chkTag = tagVec_48;
      6'b110001 : _zz_chkTag = tagVec_49;
      6'b110010 : _zz_chkTag = tagVec_50;
      6'b110011 : _zz_chkTag = tagVec_51;
      6'b110100 : _zz_chkTag = tagVec_52;
      6'b110101 : _zz_chkTag = tagVec_53;
      6'b110110 : _zz_chkTag = tagVec_54;
      6'b110111 : _zz_chkTag = tagVec_55;
      6'b111000 : _zz_chkTag = tagVec_56;
      6'b111001 : _zz_chkTag = tagVec_57;
      6'b111010 : _zz_chkTag = tagVec_58;
      6'b111011 : _zz_chkTag = tagVec_59;
      6'b111100 : _zz_chkTag = tagVec_60;
      6'b111101 : _zz_chkTag = tagVec_61;
      6'b111110 : _zz_chkTag = tagVec_62;
      default : _zz_chkTag = tagVec_63;
    endcase
  end

  assign io_ready = 1'b1;
  assign qIdx = io_query_frame[5 : 0];
  assign qTag = io_query_frame[31 : 6];
  assign io_query_devOwned = (validBits[qIdx] && (_zz_io_query_devOwned == qTag));
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign region = (io_addr[11 : 8] == 4'b0010);
  assign word = io_addr[7 : 2];
  assign acceptW = (io_ready && io_wstrobe);
  assign acceptR = ((io_ready && (! io_wstrobe)) && io_rstrobe);
  assign selW = ((acceptW && aligned) && region);
  assign idxWr = (selW && (word == 6'h0));
  assign statusWr = (selW && (word == 6'h01));
  assign setWr = (selW && (word == 6'h02));
  assign clrWr = (selW && (word == 6'h03));
  assign wFrame = io_wdata;
  assign wIdx = wFrame[5 : 0];
  assign wTag = wFrame[31 : 6];
  assign idxFrm = idxReg;
  always @(*) begin
    chkAddr = idxFrm[5 : 0];
    if(io_wstrobe) begin
      chkAddr = wIdx;
    end
  end

  assign chkTag = _zz_chkTag;
  assign idxTag = idxFrm[31 : 6];
  assign devStateAtIdx = (validBits[chkAddr] && (chkTag == idxTag));
  assign io_rvalid = acceptR_regNext;
  assign when_OwnershipTable_l297 = (aligned && region);
  assign when_OwnershipTable_l298 = (word == 6'h0);
  assign when_OwnershipTable_l299 = (word == 6'h01);
  always @(*) begin
    io_rdata = 32'h0;
    case(rdSel)
      2'b01 : begin
        io_rdata = idxReg;
      end
      2'b10 : begin
        io_rdata[0] = rState;
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    collide = 1'b0;
    if(setWr) begin
      if(!when_OwnershipTable_l318) begin
        if(when_OwnershipTable_l321) begin
          collide = 1'b1;
        end
      end
    end
  end

  assign slotBusy = validBits[wIdx];
  assign slotMine = (chkTag == wTag);
  assign when_OwnershipTable_l318 = (! slotBusy);
  assign _zz_1 = ({63'd0,1'b1} <<< wIdx);
  assign when_OwnershipTable_l321 = (! slotMine);
  assign when_OwnershipTable_l330 = (slotBusy && slotMine);
  assign io_faultCollide = _zz_io_faultCollide;
  assign io_faultBadWrite = _zz_io_faultBadWrite;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      validBits <= 64'h0;
      tagVec_0 <= 26'h0;
      tagVec_1 <= 26'h0;
      tagVec_2 <= 26'h0;
      tagVec_3 <= 26'h0;
      tagVec_4 <= 26'h0;
      tagVec_5 <= 26'h0;
      tagVec_6 <= 26'h0;
      tagVec_7 <= 26'h0;
      tagVec_8 <= 26'h0;
      tagVec_9 <= 26'h0;
      tagVec_10 <= 26'h0;
      tagVec_11 <= 26'h0;
      tagVec_12 <= 26'h0;
      tagVec_13 <= 26'h0;
      tagVec_14 <= 26'h0;
      tagVec_15 <= 26'h0;
      tagVec_16 <= 26'h0;
      tagVec_17 <= 26'h0;
      tagVec_18 <= 26'h0;
      tagVec_19 <= 26'h0;
      tagVec_20 <= 26'h0;
      tagVec_21 <= 26'h0;
      tagVec_22 <= 26'h0;
      tagVec_23 <= 26'h0;
      tagVec_24 <= 26'h0;
      tagVec_25 <= 26'h0;
      tagVec_26 <= 26'h0;
      tagVec_27 <= 26'h0;
      tagVec_28 <= 26'h0;
      tagVec_29 <= 26'h0;
      tagVec_30 <= 26'h0;
      tagVec_31 <= 26'h0;
      tagVec_32 <= 26'h0;
      tagVec_33 <= 26'h0;
      tagVec_34 <= 26'h0;
      tagVec_35 <= 26'h0;
      tagVec_36 <= 26'h0;
      tagVec_37 <= 26'h0;
      tagVec_38 <= 26'h0;
      tagVec_39 <= 26'h0;
      tagVec_40 <= 26'h0;
      tagVec_41 <= 26'h0;
      tagVec_42 <= 26'h0;
      tagVec_43 <= 26'h0;
      tagVec_44 <= 26'h0;
      tagVec_45 <= 26'h0;
      tagVec_46 <= 26'h0;
      tagVec_47 <= 26'h0;
      tagVec_48 <= 26'h0;
      tagVec_49 <= 26'h0;
      tagVec_50 <= 26'h0;
      tagVec_51 <= 26'h0;
      tagVec_52 <= 26'h0;
      tagVec_53 <= 26'h0;
      tagVec_54 <= 26'h0;
      tagVec_55 <= 26'h0;
      tagVec_56 <= 26'h0;
      tagVec_57 <= 26'h0;
      tagVec_58 <= 26'h0;
      tagVec_59 <= 26'h0;
      tagVec_60 <= 26'h0;
      tagVec_61 <= 26'h0;
      tagVec_62 <= 26'h0;
      tagVec_63 <= 26'h0;
      idxReg <= 32'h0;
      rdSel <= 2'b00;
      rState <= 1'b0;
      acceptR_regNext <= 1'b0;
      _zz_io_faultCollide <= 1'b0;
      _zz_io_faultBadWrite <= 1'b0;
    end else begin
      if(idxWr) begin
        idxReg <= io_wdata;
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdSel <= 2'b00;
        rState <= devStateAtIdx;
        if(when_OwnershipTable_l297) begin
          if(when_OwnershipTable_l298) begin
            rdSel <= 2'b01;
          end
          if(when_OwnershipTable_l299) begin
            rdSel <= 2'b10;
          end
        end
      end
      if(setWr) begin
        if(when_OwnershipTable_l318) begin
          validBits[wIdx] <= 1'b1;
          if(_zz_1[0]) begin
            tagVec_0 <= wTag;
          end
          if(_zz_1[1]) begin
            tagVec_1 <= wTag;
          end
          if(_zz_1[2]) begin
            tagVec_2 <= wTag;
          end
          if(_zz_1[3]) begin
            tagVec_3 <= wTag;
          end
          if(_zz_1[4]) begin
            tagVec_4 <= wTag;
          end
          if(_zz_1[5]) begin
            tagVec_5 <= wTag;
          end
          if(_zz_1[6]) begin
            tagVec_6 <= wTag;
          end
          if(_zz_1[7]) begin
            tagVec_7 <= wTag;
          end
          if(_zz_1[8]) begin
            tagVec_8 <= wTag;
          end
          if(_zz_1[9]) begin
            tagVec_9 <= wTag;
          end
          if(_zz_1[10]) begin
            tagVec_10 <= wTag;
          end
          if(_zz_1[11]) begin
            tagVec_11 <= wTag;
          end
          if(_zz_1[12]) begin
            tagVec_12 <= wTag;
          end
          if(_zz_1[13]) begin
            tagVec_13 <= wTag;
          end
          if(_zz_1[14]) begin
            tagVec_14 <= wTag;
          end
          if(_zz_1[15]) begin
            tagVec_15 <= wTag;
          end
          if(_zz_1[16]) begin
            tagVec_16 <= wTag;
          end
          if(_zz_1[17]) begin
            tagVec_17 <= wTag;
          end
          if(_zz_1[18]) begin
            tagVec_18 <= wTag;
          end
          if(_zz_1[19]) begin
            tagVec_19 <= wTag;
          end
          if(_zz_1[20]) begin
            tagVec_20 <= wTag;
          end
          if(_zz_1[21]) begin
            tagVec_21 <= wTag;
          end
          if(_zz_1[22]) begin
            tagVec_22 <= wTag;
          end
          if(_zz_1[23]) begin
            tagVec_23 <= wTag;
          end
          if(_zz_1[24]) begin
            tagVec_24 <= wTag;
          end
          if(_zz_1[25]) begin
            tagVec_25 <= wTag;
          end
          if(_zz_1[26]) begin
            tagVec_26 <= wTag;
          end
          if(_zz_1[27]) begin
            tagVec_27 <= wTag;
          end
          if(_zz_1[28]) begin
            tagVec_28 <= wTag;
          end
          if(_zz_1[29]) begin
            tagVec_29 <= wTag;
          end
          if(_zz_1[30]) begin
            tagVec_30 <= wTag;
          end
          if(_zz_1[31]) begin
            tagVec_31 <= wTag;
          end
          if(_zz_1[32]) begin
            tagVec_32 <= wTag;
          end
          if(_zz_1[33]) begin
            tagVec_33 <= wTag;
          end
          if(_zz_1[34]) begin
            tagVec_34 <= wTag;
          end
          if(_zz_1[35]) begin
            tagVec_35 <= wTag;
          end
          if(_zz_1[36]) begin
            tagVec_36 <= wTag;
          end
          if(_zz_1[37]) begin
            tagVec_37 <= wTag;
          end
          if(_zz_1[38]) begin
            tagVec_38 <= wTag;
          end
          if(_zz_1[39]) begin
            tagVec_39 <= wTag;
          end
          if(_zz_1[40]) begin
            tagVec_40 <= wTag;
          end
          if(_zz_1[41]) begin
            tagVec_41 <= wTag;
          end
          if(_zz_1[42]) begin
            tagVec_42 <= wTag;
          end
          if(_zz_1[43]) begin
            tagVec_43 <= wTag;
          end
          if(_zz_1[44]) begin
            tagVec_44 <= wTag;
          end
          if(_zz_1[45]) begin
            tagVec_45 <= wTag;
          end
          if(_zz_1[46]) begin
            tagVec_46 <= wTag;
          end
          if(_zz_1[47]) begin
            tagVec_47 <= wTag;
          end
          if(_zz_1[48]) begin
            tagVec_48 <= wTag;
          end
          if(_zz_1[49]) begin
            tagVec_49 <= wTag;
          end
          if(_zz_1[50]) begin
            tagVec_50 <= wTag;
          end
          if(_zz_1[51]) begin
            tagVec_51 <= wTag;
          end
          if(_zz_1[52]) begin
            tagVec_52 <= wTag;
          end
          if(_zz_1[53]) begin
            tagVec_53 <= wTag;
          end
          if(_zz_1[54]) begin
            tagVec_54 <= wTag;
          end
          if(_zz_1[55]) begin
            tagVec_55 <= wTag;
          end
          if(_zz_1[56]) begin
            tagVec_56 <= wTag;
          end
          if(_zz_1[57]) begin
            tagVec_57 <= wTag;
          end
          if(_zz_1[58]) begin
            tagVec_58 <= wTag;
          end
          if(_zz_1[59]) begin
            tagVec_59 <= wTag;
          end
          if(_zz_1[60]) begin
            tagVec_60 <= wTag;
          end
          if(_zz_1[61]) begin
            tagVec_61 <= wTag;
          end
          if(_zz_1[62]) begin
            tagVec_62 <= wTag;
          end
          if(_zz_1[63]) begin
            tagVec_63 <= wTag;
          end
        end
      end
      if(clrWr) begin
        if(when_OwnershipTable_l330) begin
          validBits[wIdx] <= 1'b0;
        end
      end
      if(io_faultClearCollide) begin
        _zz_io_faultCollide <= 1'b0;
      end
      if(collide) begin
        _zz_io_faultCollide <= 1'b1;
      end
      if(io_faultClearBadWrite) begin
        _zz_io_faultBadWrite <= 1'b0;
      end
      if(statusWr) begin
        _zz_io_faultBadWrite <= 1'b1;
      end
    end
  end


endmodule

module HiuPipeline (
  input  wire          io_req_valid,
  output wire          io_req_ready,
  input  wire [1:0]    io_req_part,
  input  wire [31:0]   io_req_vpn,
  input  wire          io_req_write,
  input  wire          io_hold,
  output reg  [31:0]   io_owner_frame,
  input  wire          io_owner_devOwned,
  output wire          io_mask_req_valid,
  output wire [1:0]    io_mask_req_part,
  output wire [31:0]   io_mask_req_frame,
  input  wire          io_mask_rsp_valid,
  input  wire [31:0]   io_mask_rsp_frame,
  input  wire          io_install_valid,
  output wire          io_install_ready,
  input  wire [1:0]    io_install_part,
  input  wire [3:0]    io_install_idx,
  input  wire [27:0]   io_install_tag,
  input  wire [31:0]   io_install_frame,
  input  wire          io_install_perm_r,
  input  wire          io_install_perm_w,
  input  wire          io_install_perm_x,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  input  wire          io_hostRsp_valid,
  input  wire [31:0]   io_hostRsp_frame,
  input  wire          io_hostRsp_perm_r,
  input  wire          io_hostRsp_perm_w,
  input  wire          io_hostRsp_perm_x,
  output wire          io_rsp_valid,
  output wire          io_rsp_granted,
  output wire [1:0]    io_rsp_part,
  output wire          io_rsp_write,
  output wire          io_rsp_fromFill,
  output reg  [31:0]   io_rsp_frame,
  output reg           io_rsp_perm_r,
  output reg           io_rsp_perm_w,
  output reg           io_rsp_perm_x,
  output wire [2:0]    io_occupancy,
  output wire          io_faultPerm,
  input  wire          io_faultClear,
  output wire          io_missNotice,
  input  wire          io_missClear,
  input  wire          clk,
  input  wire          reset
);

  wire                xlate_io_rsp_hit;
  wire                xlate_io_rsp_fromFill;
  wire       [31:0]   xlate_io_rsp_frame;
  wire                xlate_io_rsp_perm_r;
  wire                xlate_io_rsp_perm_w;
  wire                xlate_io_rsp_perm_x;
  wire                xlate_io_rsp_hostPresent;
  wire       [31:0]   xlate_io_rsp_hostFrame;
  wire                xlate_io_rsp_hostPerm_r;
  wire                xlate_io_rsp_hostPerm_w;
  wire                xlate_io_rsp_hostPerm_x;
  wire                xlate_io_install_ready;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [0:0]    _zz_io_occupancy_5;
  wire       [2:0]    _zz_io_occupancy_6;
  wire       [0:0]    _zz_io_occupancy_7;
  wire       [2:0]    _zz_io_occupancy_8;
  wire       [0:0]    _zz_io_occupancy_9;
  wire       [2:0]    _zz_io_occupancy_10;
  wire       [0:0]    _zz_io_occupancy_11;
  wire       [2:0]    _zz_io_occupancy_12;
  wire       [0:0]    _zz_io_occupancy_13;
  wire       [2:0]    _zz_io_occupancy_14;
  wire       [0:0]    _zz_io_occupancy_15;
  reg                 s1_valid;
  reg        [1:0]    s1_part;
  reg        [31:0]   s1_vpn;
  reg                 s1_write;
  reg                 s2_valid;
  reg        [1:0]    s2_part;
  reg        [31:0]   s2_vpn;
  reg                 s2_write;
  reg                 s3_valid;
  reg        [1:0]    s3_part;
  reg        [31:0]   s3_vpn;
  reg                 s3_write;
  reg        [31:0]   lookFrame;
  reg                 lookPerm_r;
  reg                 lookPerm_w;
  reg                 lookPerm_x;
  wire                lookAny;
  reg        [1:0]    s4_part;
  reg                 s4_write;
  reg                 s4_anyHit;
  reg                 s4_fromFill;
  reg        [31:0]   s4_frame;
  reg                 s4_perm_r;
  reg                 s4_perm_w;
  reg                 s4_perm_x;
  reg                 s5_valid;
  reg        [1:0]    s5_part;
  reg                 s5_write;
  reg                 s5_anyHit;
  reg                 s5_fromFill;
  reg        [31:0]   s5_frame;
  reg        [31:0]   s5_masked;
  reg                 s5_perm_r;
  reg                 s5_perm_w;
  reg                 s5_perm_x;
  reg                 s6_valid;
  reg        [1:0]    s6_part;
  reg                 s6_write;
  reg                 s6_anyHit;
  reg                 s6_fromFill;
  reg        [31:0]   s6_frame;
  reg        [31:0]   s6_masked;
  reg                 s6_perm_r;
  reg                 s6_perm_w;
  reg                 s6_perm_x;
  wire                missWait;
  wire                advance;
  wire                when_HiuPipeline_l391;
  wire                entitle;
  wire                granted;
  wire                permViol;
  reg                 _zz_io_faultPerm;
  reg                 _zz_io_missNotice;

  assign _zz_io_occupancy = (_zz_io_occupancy_1 + _zz_io_occupancy_12);
  assign _zz_io_occupancy_1 = (_zz_io_occupancy_2 + _zz_io_occupancy_10);
  assign _zz_io_occupancy_2 = (_zz_io_occupancy_3 + _zz_io_occupancy_8);
  assign _zz_io_occupancy_3 = (_zz_io_occupancy_4 + _zz_io_occupancy_6);
  assign _zz_io_occupancy_5 = s1_valid;
  assign _zz_io_occupancy_4 = {2'd0, _zz_io_occupancy_5};
  assign _zz_io_occupancy_7 = s2_valid;
  assign _zz_io_occupancy_6 = {2'd0, _zz_io_occupancy_7};
  assign _zz_io_occupancy_9 = s3_valid;
  assign _zz_io_occupancy_8 = {2'd0, _zz_io_occupancy_9};
  assign _zz_io_occupancy_11 = io_mask_rsp_valid;
  assign _zz_io_occupancy_10 = {2'd0, _zz_io_occupancy_11};
  assign _zz_io_occupancy_13 = s5_valid;
  assign _zz_io_occupancy_12 = {2'd0, _zz_io_occupancy_13};
  assign _zz_io_occupancy_15 = s6_valid;
  assign _zz_io_occupancy_14 = {2'd0, _zz_io_occupancy_15};
  XlateStore xlate (
    .io_lookup_valid    (s3_valid                    ), //i
    .io_lookup_part     (s3_part[1:0]                ), //i
    .io_lookup_vpn      (s3_vpn[31:0]                ), //i
    .io_rsp_hit         (xlate_io_rsp_hit            ), //o
    .io_rsp_fromFill    (xlate_io_rsp_fromFill       ), //o
    .io_rsp_frame       (xlate_io_rsp_frame[31:0]    ), //o
    .io_rsp_perm_r      (xlate_io_rsp_perm_r         ), //o
    .io_rsp_perm_w      (xlate_io_rsp_perm_w         ), //o
    .io_rsp_perm_x      (xlate_io_rsp_perm_x         ), //o
    .io_rsp_hostPresent (xlate_io_rsp_hostPresent    ), //o
    .io_rsp_hostFrame   (xlate_io_rsp_hostFrame[31:0]), //o
    .io_rsp_hostPerm_r  (xlate_io_rsp_hostPerm_r     ), //o
    .io_rsp_hostPerm_w  (xlate_io_rsp_hostPerm_w     ), //o
    .io_rsp_hostPerm_x  (xlate_io_rsp_hostPerm_x     ), //o
    .io_hostRsp_valid   (io_hostRsp_valid            ), //i
    .io_hostRsp_frame   (io_hostRsp_frame[31:0]      ), //i
    .io_hostRsp_perm_r  (io_hostRsp_perm_r           ), //i
    .io_hostRsp_perm_w  (io_hostRsp_perm_w           ), //i
    .io_hostRsp_perm_x  (io_hostRsp_perm_x           ), //i
    .io_install_valid   (io_install_valid            ), //i
    .io_install_ready   (xlate_io_install_ready      ), //o
    .io_install_part    (io_install_part[1:0]        ), //i
    .io_install_idx     (io_install_idx[3:0]         ), //i
    .io_install_tag     (io_install_tag[27:0]        ), //i
    .io_install_frame   (io_install_frame[31:0]      ), //i
    .io_install_perm_r  (io_install_perm_r           ), //i
    .io_install_perm_w  (io_install_perm_w           ), //i
    .io_install_perm_x  (io_install_perm_x           ), //i
    .io_flush_valid     (io_flush_valid              ), //i
    .io_flush_part      (io_flush_part[1:0]          ), //i
    .clk                (clk                         ), //i
    .reset              (reset                       )  //i
  );
  assign io_install_ready = xlate_io_install_ready;
  always @(*) begin
    lookFrame = 32'h0;
    if(xlate_io_rsp_hit) begin
      lookFrame = xlate_io_rsp_frame;
    end else begin
      if(xlate_io_rsp_hostPresent) begin
        lookFrame = xlate_io_rsp_hostFrame;
      end
    end
  end

  always @(*) begin
    lookPerm_r = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_r = xlate_io_rsp_perm_r;
    end else begin
      if(xlate_io_rsp_hostPresent) begin
        lookPerm_r = xlate_io_rsp_hostPerm_r;
      end
    end
  end

  always @(*) begin
    lookPerm_w = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_w = xlate_io_rsp_perm_w;
    end else begin
      if(xlate_io_rsp_hostPresent) begin
        lookPerm_w = xlate_io_rsp_hostPerm_w;
      end
    end
  end

  always @(*) begin
    lookPerm_x = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_x = xlate_io_rsp_perm_x;
    end else begin
      if(xlate_io_rsp_hostPresent) begin
        lookPerm_x = xlate_io_rsp_hostPerm_x;
      end
    end
  end

  assign lookAny = (xlate_io_rsp_hit || xlate_io_rsp_hostPresent);
  assign io_mask_req_valid = s3_valid;
  assign io_mask_req_part = s3_part;
  assign io_mask_req_frame = lookFrame;
  assign missWait = ((s3_valid && (! xlate_io_rsp_hit)) && (! xlate_io_rsp_hostPresent));
  assign advance = ((! io_hold) && (! missWait));
  assign io_req_ready = advance;
  always @(*) begin
    io_owner_frame = 32'h0;
    if(when_HiuPipeline_l391) begin
      io_owner_frame = s6_frame;
    end
  end

  assign when_HiuPipeline_l391 = (s6_valid && s6_anyHit);
  assign entitle = (s6_write ? s6_perm_w : s6_perm_r);
  assign granted = (((s6_valid && s6_anyHit) && io_owner_devOwned) && entitle);
  assign permViol = ((s6_valid && s6_anyHit) && (! (io_owner_devOwned && entitle)));
  assign io_rsp_valid = (s6_valid && advance);
  assign io_rsp_granted = granted;
  assign io_rsp_part = s6_part;
  assign io_rsp_write = s6_write;
  assign io_rsp_fromFill = s6_fromFill;
  always @(*) begin
    io_rsp_frame = 32'h0;
    if(granted) begin
      io_rsp_frame = s6_masked;
    end
  end

  always @(*) begin
    io_rsp_perm_r = 1'b0;
    if(granted) begin
      io_rsp_perm_r = s6_perm_r;
    end
  end

  always @(*) begin
    io_rsp_perm_w = 1'b0;
    if(granted) begin
      io_rsp_perm_w = s6_perm_w;
    end
  end

  always @(*) begin
    io_rsp_perm_x = 1'b0;
    if(granted) begin
      io_rsp_perm_x = s6_perm_x;
    end
  end

  assign io_occupancy = (_zz_io_occupancy + _zz_io_occupancy_14);
  assign io_faultPerm = _zz_io_faultPerm;
  assign io_missNotice = _zz_io_missNotice;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      s1_valid <= 1'b0;
      s2_valid <= 1'b0;
      s3_valid <= 1'b0;
      s5_valid <= 1'b0;
      s6_valid <= 1'b0;
      _zz_io_faultPerm <= 1'b0;
      _zz_io_missNotice <= 1'b0;
    end else begin
      if(advance) begin
        s1_valid <= io_req_valid;
        s2_valid <= s1_valid;
        s3_valid <= s2_valid;
        s5_valid <= io_mask_rsp_valid;
        s6_valid <= s5_valid;
      end
      if(io_faultClear) begin
        _zz_io_faultPerm <= 1'b0;
      end
      if(permViol) begin
        _zz_io_faultPerm <= 1'b1;
      end
      if(io_missClear) begin
        _zz_io_missNotice <= 1'b0;
      end
      if(missWait) begin
        _zz_io_missNotice <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(advance) begin
      s1_part <= io_req_part;
      s1_vpn <= io_req_vpn;
      s1_write <= io_req_write;
      s2_part <= s1_part;
      s2_vpn <= s1_vpn;
      s2_write <= s1_write;
      s3_part <= s2_part;
      s3_vpn <= s2_vpn;
      s3_write <= s2_write;
      s4_part <= s3_part;
      s4_write <= s3_write;
      s4_anyHit <= lookAny;
      s4_fromFill <= xlate_io_rsp_fromFill;
      s4_frame <= lookFrame;
      s4_perm_r <= lookPerm_r;
      s4_perm_w <= lookPerm_w;
      s4_perm_x <= lookPerm_x;
      s5_part <= s4_part;
      s5_write <= s4_write;
      s5_anyHit <= s4_anyHit;
      s5_fromFill <= s4_fromFill;
      s5_frame <= s4_frame;
      s5_masked <= io_mask_rsp_frame;
      s5_perm_r <= s4_perm_r;
      s5_perm_w <= s4_perm_w;
      s5_perm_x <= s4_perm_x;
      s6_part <= s5_part;
      s6_write <= s5_write;
      s6_anyHit <= s5_anyHit;
      s6_fromFill <= s5_fromFill;
      s6_frame <= s5_frame;
      s6_masked <= s5_masked;
      s6_perm_r <= s5_perm_r;
      s6_perm_w <= s5_perm_w;
      s6_perm_x <= s5_perm_x;
    end
  end


endmodule

module MemOrderGate (
  input  wire [2:0]    io_cfgPreds_0,
  input  wire [2:0]    io_cfgPreds_1,
  input  wire [2:0]    io_cfgPreds_2,
  input  wire [2:0]    io_cfgPreds_3,
  input  wire          io_epochClear,
  input  wire          io_up_0_valid,
  output wire          io_up_0_ready,
  input  wire [127:0]  io_up_0_payload,
  input  wire          io_up_1_valid,
  output wire          io_up_1_ready,
  input  wire [127:0]  io_up_1_payload,
  input  wire          io_up_2_valid,
  output wire          io_up_2_ready,
  input  wire [127:0]  io_up_2_payload,
  input  wire          io_up_3_valid,
  output wire          io_up_3_ready,
  input  wire [127:0]  io_up_3_payload,
  output wire          io_down_0_valid,
  input  wire          io_down_0_ready,
  output wire [127:0]  io_down_0_payload,
  output wire          io_down_1_valid,
  input  wire          io_down_1_ready,
  output wire [127:0]  io_down_1_payload,
  output wire          io_down_2_valid,
  input  wire          io_down_2_ready,
  output wire [127:0]  io_down_2_payload,
  output wire          io_down_3_valid,
  input  wire          io_down_3_ready,
  output wire [127:0]  io_down_3_payload,
  input  wire [3:0]    io_complete,
  output wire [3:0]    io_token,
  output reg  [3:0]    io_gateOpen,
  output wire [2:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg        [2:0]    _zz_io_occupancy_8;
  wire       [2:0]    _zz_io_occupancy_9;
  reg        [2:0]    _zz_io_occupancy_10;
  wire       [2:0]    _zz_io_occupancy_11;
  wire       [0:0]    _zz_io_occupancy_12;
  reg                 token_0;
  reg                 token_1;
  reg                 token_2;
  reg                 token_3;
  wire                when_MemOrderGate_l155;
  wire                when_MemOrderGate_l155_1;
  wire                when_MemOrderGate_l155_2;
  wire                when_MemOrderGate_l155_3;
  wire                gates_0_waitVec_0;
  wire                gates_0_waitVec_1;
  wire                gates_0_waitVec_2;
  wire                gates_0_open;
  wire                gates_1_waitVec_0;
  wire                gates_1_waitVec_1;
  wire                gates_1_waitVec_2;
  wire                gates_1_open;
  wire                gates_2_waitVec_0;
  wire                gates_2_waitVec_1;
  wire                gates_2_waitVec_2;
  wire                gates_2_open;
  wire                gates_3_waitVec_0;
  wire                gates_3_waitVec_1;
  wire                gates_3_waitVec_2;
  wire                gates_3_open;
  wire                referenced_0;
  wire                referenced_1;
  wire                referenced_2;
  wire                referenced_3;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [2:0]    _zz_io_occupancy_5;
  wire       [2:0]    _zz_io_occupancy_6;
  wire       [2:0]    _zz_io_occupancy_7;

  assign _zz_io_occupancy_12 = (referenced_3 && (! token_3));
  assign _zz_io_occupancy_11 = {2'd0, _zz_io_occupancy_12};
  assign _zz_io_occupancy_9 = {(referenced_2 && (! token_2)),{(referenced_1 && (! token_1)),(referenced_0 && (! token_0))}};
  always @(*) begin
    case(_zz_io_occupancy_9)
      3'b000 : _zz_io_occupancy_8 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_8 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_8 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_8 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_8 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_8 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_8 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_8 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_11)
      3'b000 : _zz_io_occupancy_10 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_10 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_10 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_10 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_10 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_10 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_10 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_10 = _zz_io_occupancy_7;
    endcase
  end

  assign when_MemOrderGate_l155 = io_complete[0];
  assign when_MemOrderGate_l155_1 = io_complete[1];
  assign when_MemOrderGate_l155_2 = io_complete[2];
  assign when_MemOrderGate_l155_3 = io_complete[3];
  assign io_token = {token_3,{token_2,{token_1,token_0}}};
  assign gates_0_waitVec_0 = (io_cfgPreds_0[0] && (! token_1));
  assign gates_0_waitVec_1 = (io_cfgPreds_0[1] && (! token_2));
  assign gates_0_waitVec_2 = (io_cfgPreds_0[2] && (! token_3));
  assign gates_0_open = (! (|{gates_0_waitVec_2,{gates_0_waitVec_1,gates_0_waitVec_0}}));
  always @(*) begin
    io_gateOpen[0] = gates_0_open;
    io_gateOpen[1] = gates_1_open;
    io_gateOpen[2] = gates_2_open;
    io_gateOpen[3] = gates_3_open;
  end

  assign io_down_0_valid = (io_up_0_valid && gates_0_open);
  assign io_down_0_payload = io_up_0_payload;
  assign io_up_0_ready = (gates_0_open && io_down_0_ready);
  assign gates_1_waitVec_0 = (io_cfgPreds_1[0] && (! token_0));
  assign gates_1_waitVec_1 = (io_cfgPreds_1[1] && (! token_2));
  assign gates_1_waitVec_2 = (io_cfgPreds_1[2] && (! token_3));
  assign gates_1_open = (! (|{gates_1_waitVec_2,{gates_1_waitVec_1,gates_1_waitVec_0}}));
  assign io_down_1_valid = (io_up_1_valid && gates_1_open);
  assign io_down_1_payload = io_up_1_payload;
  assign io_up_1_ready = (gates_1_open && io_down_1_ready);
  assign gates_2_waitVec_0 = (io_cfgPreds_2[0] && (! token_0));
  assign gates_2_waitVec_1 = (io_cfgPreds_2[1] && (! token_1));
  assign gates_2_waitVec_2 = (io_cfgPreds_2[2] && (! token_3));
  assign gates_2_open = (! (|{gates_2_waitVec_2,{gates_2_waitVec_1,gates_2_waitVec_0}}));
  assign io_down_2_valid = (io_up_2_valid && gates_2_open);
  assign io_down_2_payload = io_up_2_payload;
  assign io_up_2_ready = (gates_2_open && io_down_2_ready);
  assign gates_3_waitVec_0 = (io_cfgPreds_3[0] && (! token_0));
  assign gates_3_waitVec_1 = (io_cfgPreds_3[1] && (! token_1));
  assign gates_3_waitVec_2 = (io_cfgPreds_3[2] && (! token_2));
  assign gates_3_open = (! (|{gates_3_waitVec_2,{gates_3_waitVec_1,gates_3_waitVec_0}}));
  assign io_down_3_valid = (io_up_3_valid && gates_3_open);
  assign io_down_3_payload = io_up_3_payload;
  assign io_up_3_ready = (gates_3_open && io_down_3_ready);
  assign referenced_0 = ((io_cfgPreds_1[0] || io_cfgPreds_2[0]) || io_cfgPreds_3[0]);
  assign referenced_1 = ((io_cfgPreds_0[0] || io_cfgPreds_2[1]) || io_cfgPreds_3[1]);
  assign referenced_2 = ((io_cfgPreds_0[1] || io_cfgPreds_1[1]) || io_cfgPreds_3[2]);
  assign referenced_3 = ((io_cfgPreds_0[2] || io_cfgPreds_1[2]) || io_cfgPreds_2[2]);
  assign _zz_io_occupancy = 3'b000;
  assign _zz_io_occupancy_1 = 3'b001;
  assign _zz_io_occupancy_2 = 3'b001;
  assign _zz_io_occupancy_3 = 3'b010;
  assign _zz_io_occupancy_4 = 3'b001;
  assign _zz_io_occupancy_5 = 3'b010;
  assign _zz_io_occupancy_6 = 3'b010;
  assign _zz_io_occupancy_7 = 3'b011;
  assign io_occupancy = (_zz_io_occupancy_8 + _zz_io_occupancy_10);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      token_0 <= 1'b0;
      token_1 <= 1'b0;
      token_2 <= 1'b0;
      token_3 <= 1'b0;
    end else begin
      if(io_epochClear) begin
        token_0 <= 1'b0;
      end
      if(when_MemOrderGate_l155) begin
        token_0 <= 1'b1;
      end
      if(io_epochClear) begin
        token_1 <= 1'b0;
      end
      if(when_MemOrderGate_l155_1) begin
        token_1 <= 1'b1;
      end
      if(io_epochClear) begin
        token_2 <= 1'b0;
      end
      if(when_MemOrderGate_l155_2) begin
        token_2 <= 1'b1;
      end
      if(io_epochClear) begin
        token_3 <= 1'b0;
      end
      if(when_MemOrderGate_l155_3) begin
        token_3 <= 1'b1;
      end
    end
  end


endmodule

module Reassembly (
  input  wire          io_open_valid,
  input  wire [31:0]   io_open_tag_wave,
  input  wire [15:0]   io_open_tag_thread,
  input  wire [15:0]   io_open_tag_lnid,
  input  wire [7:0]    io_open_tag_precision,
  input  wire [7:0]    io_open_tag_dim,
  input  wire [7:0]    io_open_base,
  output wire          io_open_granted,
  input  wire          io_frag_valid,
  input  wire [31:0]   io_frag_head_tag_wave,
  input  wire [15:0]   io_frag_head_tag_thread,
  input  wire [15:0]   io_frag_head_tag_lnid,
  input  wire [7:0]    io_frag_head_tag_precision,
  input  wire [7:0]    io_frag_head_tag_dim,
  input  wire [7:0]    io_frag_head_seq,
  input  wire [7:0]    io_frag_head_total,
  input  wire          io_frag_head_last,
  input  wire [63:0]   io_frag_body,
  output wire          io_wr_valid,
  output wire [7:0]    io_wr_base,
  output wire [3:0]    io_wr_off,
  output wire [63:0]   io_wr_body,
  output wire          io_deliver_valid,
  input  wire          io_deliver_ready,
  output wire [31:0]   io_deliver_payload_tag_wave,
  output wire [15:0]   io_deliver_payload_tag_thread,
  output wire [15:0]   io_deliver_payload_tag_lnid,
  output wire [7:0]    io_deliver_payload_tag_precision,
  output wire [7:0]    io_deliver_payload_tag_dim,
  output wire [7:0]    io_deliver_payload_base,
  output wire [7:0]    io_deliver_payload_total,
  output wire [2:0]    io_incomplete,
  output wire [2:0]    io_occupancy,
  input  wire          io_abort_valid,
  input  wire [31:0]   io_abort_tag_wave,
  input  wire [15:0]   io_abort_tag_thread,
  input  wire [15:0]   io_abort_tag_lnid,
  input  wire [7:0]    io_abort_tag_precision,
  input  wire [7:0]    io_abort_tag_dim,
  output wire          io_clr_valid,
  output wire [7:0]    io_clr_base,
  output wire [7:0]    io_abortCount,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire          io_capAbsent,
  input  wire          io_capAbsentClear,
  input  wire          clk,
  input  wire          reset
);

  reg        [7:0]    _zz_fr_cBase_3;
  reg        [7:0]    _zz_fr_cTotal;
  reg                 _zz_fr_cKnown;
  reg        [15:0]   _zz_fr_cSeen;
  wire       [3:0]    _zz_fr_off;
  reg        [15:0]   _zz_fr_endBad;
  wire       [4:0]    _zz_fr_endBad_1;
  wire                _zz_op_clash;
  wire                _zz_op_clash_1;
  wire                _zz_op_clash_2;
  wire                _zz_op_clash_3;
  wire                _zz_op_clash_4;
  wire                _zz_op_clash_5;
  wire                _zz_op_clash_6;
  wire                _zz_op_clash_7;
  wire                _zz_op_clash_8;
  wire                _zz_op_clash_9;
  wire                _zz_op_clash_10;
  wire                _zz_op_clash_11;
  wire       [3:0]    _zz_op_freeOh_1;
  reg        [15:0]   _zz_dv_done_0;
  wire       [4:0]    _zz_dv_done_0_1;
  reg        [15:0]   _zz_dv_done_1;
  wire       [4:0]    _zz_dv_done_1_1;
  reg        [15:0]   _zz_dv_done_2;
  wire       [4:0]    _zz_dv_done_2_1;
  reg        [15:0]   _zz_dv_done_3;
  wire       [4:0]    _zz_dv_done_3_1;
  wire       [3:0]    _zz_dv_grantOh_1;
  reg        [31:0]   _zz_io_deliver_payload_tag_wave_4;
  reg        [15:0]   _zz_io_deliver_payload_tag_thread;
  reg        [15:0]   _zz_io_deliver_payload_tag_lnid;
  reg        [7:0]    _zz_io_deliver_payload_tag_precision;
  reg        [7:0]    _zz_io_deliver_payload_tag_dim;
  reg        [7:0]    _zz_io_deliver_payload_base;
  reg        [7:0]    _zz_io_deliver_payload_total;
  reg        [7:0]    _zz_ab_cBase_2;
  wire       [1:0]    _zz_ab_cBase_3;
  reg        [2:0]    _zz_io_incomplete_8;
  wire       [2:0]    _zz_io_incomplete_9;
  reg        [2:0]    _zz_io_incomplete_10;
  wire       [2:0]    _zz_io_incomplete_11;
  wire       [0:0]    _zz_io_incomplete_12;
  reg        [2:0]    _zz_io_occupancy_8;
  wire       [2:0]    _zz_io_occupancy_9;
  reg        [2:0]    _zz_io_occupancy_10;
  wire       [2:0]    _zz_io_occupancy_11;
  wire       [0:0]    _zz_io_occupancy_12;
  reg                 ctx_0_active;
  reg        [31:0]   ctx_0_tag_wave;
  reg        [15:0]   ctx_0_tag_thread;
  reg        [15:0]   ctx_0_tag_lnid;
  reg        [7:0]    ctx_0_tag_precision;
  reg        [7:0]    ctx_0_tag_dim;
  reg        [7:0]    ctx_0_base;
  reg        [7:0]    ctx_0_total;
  reg                 ctx_0_totalKnown;
  reg        [15:0]   ctx_0_seen;
  reg                 ctx_0_last;
  reg                 ctx_1_active;
  reg        [31:0]   ctx_1_tag_wave;
  reg        [15:0]   ctx_1_tag_thread;
  reg        [15:0]   ctx_1_tag_lnid;
  reg        [7:0]    ctx_1_tag_precision;
  reg        [7:0]    ctx_1_tag_dim;
  reg        [7:0]    ctx_1_base;
  reg        [7:0]    ctx_1_total;
  reg                 ctx_1_totalKnown;
  reg        [15:0]   ctx_1_seen;
  reg                 ctx_1_last;
  reg                 ctx_2_active;
  reg        [31:0]   ctx_2_tag_wave;
  reg        [15:0]   ctx_2_tag_thread;
  reg        [15:0]   ctx_2_tag_lnid;
  reg        [7:0]    ctx_2_tag_precision;
  reg        [7:0]    ctx_2_tag_dim;
  reg        [7:0]    ctx_2_base;
  reg        [7:0]    ctx_2_total;
  reg                 ctx_2_totalKnown;
  reg        [15:0]   ctx_2_seen;
  reg                 ctx_2_last;
  reg                 ctx_3_active;
  reg        [31:0]   ctx_3_tag_wave;
  reg        [15:0]   ctx_3_tag_thread;
  reg        [15:0]   ctx_3_tag_lnid;
  reg        [7:0]    ctx_3_tag_precision;
  reg        [7:0]    ctx_3_tag_dim;
  reg        [7:0]    ctx_3_base;
  reg        [7:0]    ctx_3_total;
  reg                 ctx_3_totalKnown;
  reg        [15:0]   ctx_3_seen;
  reg                 ctx_3_last;
  wire       [15:0]   fullMask_0;
  wire       [15:0]   fullMask_1;
  wire       [15:0]   fullMask_2;
  wire       [15:0]   fullMask_3;
  wire       [15:0]   fullMask_4;
  wire       [15:0]   fullMask_5;
  wire       [15:0]   fullMask_6;
  wire       [15:0]   fullMask_7;
  wire       [15:0]   fullMask_8;
  wire       [15:0]   fullMask_9;
  wire       [15:0]   fullMask_10;
  wire       [15:0]   fullMask_11;
  wire       [15:0]   fullMask_12;
  wire       [15:0]   fullMask_13;
  wire       [15:0]   fullMask_14;
  wire       [15:0]   fullMask_15;
  wire       [15:0]   fullMask_16;
  wire                fr_hit_0;
  wire                fr_hit_1;
  wire                fr_hit_2;
  wire                fr_hit_3;
  wire                fr_hitAny;
  wire                _zz_fr_cBase;
  wire                _zz_fr_cBase_1;
  wire       [1:0]    _zz_fr_cBase_2;
  wire       [7:0]    fr_cBase;
  wire       [7:0]    fr_cTotal;
  wire                fr_cKnown;
  wire       [15:0]   fr_cSeen;
  wire       [7:0]    fr_effTotal;
  wire                fr_capaRej;
  wire                fr_strayRej;
  wire                fr_totBad;
  wire                fr_overRej;
  wire       [3:0]    fr_off;
  wire       [15:0]   fr_ohSeq;
  wire                fr_dupRej;
  wire                fr_accept;
  wire       [15:0]   fr_newSeen;
  wire                fr_endBad;
  wire                when_Reassembly_l363;
  wire                when_Reassembly_l363_1;
  wire                when_Reassembly_l363_2;
  wire                when_Reassembly_l363_3;
  wire                fr_rejEvt;
  wire                fr_endEvt;
  wire                fr_capaEvt;
  wire                op_clash;
  wire                op_free_0;
  wire                op_free_1;
  wire                op_free_2;
  wire                op_free_3;
  wire                op_freeAny;
  wire       [3:0]    _zz_op_freeOh;
  wire       [3:0]    op_freeOh;
  wire                op_grant;
  wire                when_Reassembly_l396;
  wire                when_Reassembly_l396_1;
  wire                when_Reassembly_l396_2;
  wire                when_Reassembly_l396_3;
  wire                op_clashEvt;
  wire                dv_done_0;
  wire                dv_done_1;
  wire                dv_done_2;
  wire                dv_done_3;
  wire                dv_doneAny;
  wire       [3:0]    _zz_dv_grantOh;
  wire       [3:0]    dv_grantOh;
  wire                _zz_io_deliver_payload_tag_wave;
  wire                _zz_io_deliver_payload_tag_wave_1;
  wire                _zz_io_deliver_payload_tag_wave_2;
  wire       [1:0]    _zz_io_deliver_payload_tag_wave_3;
  wire                io_deliver_fire;
  wire                when_Reassembly_l435;
  wire                when_Reassembly_l435_1;
  wire                when_Reassembly_l435_2;
  wire                when_Reassembly_l435_3;
  wire                ab_hit_0;
  wire                ab_hit_1;
  wire                ab_hit_2;
  wire                ab_hit_3;
  wire                ab_hitAny;
  wire                ab_fire;
  wire                _zz_ab_cBase;
  wire                _zz_ab_cBase_1;
  wire       [7:0]    ab_cBase;
  wire                when_Reassembly_l474;
  wire                when_Reassembly_l474_1;
  wire                when_Reassembly_l474_2;
  wire                when_Reassembly_l474_3;
  reg        [7:0]    ab_cnt;
  wire                when_Reassembly_l485;
  wire       [2:0]    _zz_io_incomplete;
  wire       [2:0]    _zz_io_incomplete_1;
  wire       [2:0]    _zz_io_incomplete_2;
  wire       [2:0]    _zz_io_incomplete_3;
  wire       [2:0]    _zz_io_incomplete_4;
  wire       [2:0]    _zz_io_incomplete_5;
  wire       [2:0]    _zz_io_incomplete_6;
  wire       [2:0]    _zz_io_incomplete_7;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [2:0]    _zz_io_occupancy_5;
  wire       [2:0]    _zz_io_occupancy_6;
  wire       [2:0]    _zz_io_occupancy_7;
  wire                when_Common_l259;
  reg                 _zz_io_fault;
  reg                 capBit;

  assign _zz_fr_off = io_frag_head_seq[3:0];
  assign _zz_fr_endBad_1 = fr_effTotal[4:0];
  assign _zz_op_freeOh_1 = (_zz_op_freeOh - 4'b0001);
  assign _zz_dv_done_0_1 = ctx_0_total[4:0];
  assign _zz_dv_done_1_1 = ctx_1_total[4:0];
  assign _zz_dv_done_2_1 = ctx_2_total[4:0];
  assign _zz_dv_done_3_1 = ctx_3_total[4:0];
  assign _zz_dv_grantOh_1 = (_zz_dv_grantOh - 4'b0001);
  assign _zz_io_incomplete_12 = (ctx_3_active && (! ctx_3_last));
  assign _zz_io_incomplete_11 = {2'd0, _zz_io_incomplete_12};
  assign _zz_io_occupancy_12 = ctx_3_active;
  assign _zz_io_occupancy_11 = {2'd0, _zz_io_occupancy_12};
  assign _zz_ab_cBase_3 = {_zz_ab_cBase_1,_zz_ab_cBase};
  assign _zz_io_incomplete_9 = {(ctx_2_active && (! ctx_2_last)),{(ctx_1_active && (! ctx_1_last)),(ctx_0_active && (! ctx_0_last))}};
  assign _zz_io_occupancy_9 = {ctx_2_active,{ctx_1_active,ctx_0_active}};
  assign _zz_op_clash = (((_zz_op_clash_1 && _zz_op_clash_2) && (ctx_0_tag_lnid == io_open_tag_lnid)) && (ctx_0_tag_precision == io_open_tag_precision));
  assign _zz_op_clash_3 = (ctx_0_tag_dim == io_open_tag_dim);
  assign _zz_op_clash_4 = (((_zz_op_clash_5 && _zz_op_clash_6) && (ctx_1_tag_lnid == io_open_tag_lnid)) && (ctx_1_tag_precision == io_open_tag_precision));
  assign _zz_op_clash_7 = (ctx_1_tag_dim == io_open_tag_dim);
  assign _zz_op_clash_8 = (((ctx_2_tag_wave == io_open_tag_wave) && (ctx_2_tag_thread == io_open_tag_thread)) && (ctx_2_tag_lnid == io_open_tag_lnid));
  assign _zz_op_clash_9 = (ctx_2_tag_precision == io_open_tag_precision);
  assign _zz_op_clash_10 = ((ctx_3_tag_wave == io_open_tag_wave) && (ctx_3_tag_thread == io_open_tag_thread));
  assign _zz_op_clash_11 = (ctx_3_tag_lnid == io_open_tag_lnid);
  assign _zz_op_clash_1 = (ctx_0_tag_wave == io_open_tag_wave);
  assign _zz_op_clash_2 = (ctx_0_tag_thread == io_open_tag_thread);
  assign _zz_op_clash_5 = (ctx_1_tag_wave == io_open_tag_wave);
  assign _zz_op_clash_6 = (ctx_1_tag_thread == io_open_tag_thread);
  always @(*) begin
    case(_zz_fr_cBase_2)
      2'b00 : begin
        _zz_fr_cBase_3 = ctx_0_base;
        _zz_fr_cTotal = ctx_0_total;
        _zz_fr_cKnown = ctx_0_totalKnown;
        _zz_fr_cSeen = ctx_0_seen;
      end
      2'b01 : begin
        _zz_fr_cBase_3 = ctx_1_base;
        _zz_fr_cTotal = ctx_1_total;
        _zz_fr_cKnown = ctx_1_totalKnown;
        _zz_fr_cSeen = ctx_1_seen;
      end
      2'b10 : begin
        _zz_fr_cBase_3 = ctx_2_base;
        _zz_fr_cTotal = ctx_2_total;
        _zz_fr_cKnown = ctx_2_totalKnown;
        _zz_fr_cSeen = ctx_2_seen;
      end
      default : begin
        _zz_fr_cBase_3 = ctx_3_base;
        _zz_fr_cTotal = ctx_3_total;
        _zz_fr_cKnown = ctx_3_totalKnown;
        _zz_fr_cSeen = ctx_3_seen;
      end
    endcase
  end

  always @(*) begin
    case(_zz_fr_endBad_1)
      5'b00000 : _zz_fr_endBad = fullMask_0;
      5'b00001 : _zz_fr_endBad = fullMask_1;
      5'b00010 : _zz_fr_endBad = fullMask_2;
      5'b00011 : _zz_fr_endBad = fullMask_3;
      5'b00100 : _zz_fr_endBad = fullMask_4;
      5'b00101 : _zz_fr_endBad = fullMask_5;
      5'b00110 : _zz_fr_endBad = fullMask_6;
      5'b00111 : _zz_fr_endBad = fullMask_7;
      5'b01000 : _zz_fr_endBad = fullMask_8;
      5'b01001 : _zz_fr_endBad = fullMask_9;
      5'b01010 : _zz_fr_endBad = fullMask_10;
      5'b01011 : _zz_fr_endBad = fullMask_11;
      5'b01100 : _zz_fr_endBad = fullMask_12;
      5'b01101 : _zz_fr_endBad = fullMask_13;
      5'b01110 : _zz_fr_endBad = fullMask_14;
      5'b01111 : _zz_fr_endBad = fullMask_15;
      default : _zz_fr_endBad = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_0_1)
      5'b00000 : _zz_dv_done_0 = fullMask_0;
      5'b00001 : _zz_dv_done_0 = fullMask_1;
      5'b00010 : _zz_dv_done_0 = fullMask_2;
      5'b00011 : _zz_dv_done_0 = fullMask_3;
      5'b00100 : _zz_dv_done_0 = fullMask_4;
      5'b00101 : _zz_dv_done_0 = fullMask_5;
      5'b00110 : _zz_dv_done_0 = fullMask_6;
      5'b00111 : _zz_dv_done_0 = fullMask_7;
      5'b01000 : _zz_dv_done_0 = fullMask_8;
      5'b01001 : _zz_dv_done_0 = fullMask_9;
      5'b01010 : _zz_dv_done_0 = fullMask_10;
      5'b01011 : _zz_dv_done_0 = fullMask_11;
      5'b01100 : _zz_dv_done_0 = fullMask_12;
      5'b01101 : _zz_dv_done_0 = fullMask_13;
      5'b01110 : _zz_dv_done_0 = fullMask_14;
      5'b01111 : _zz_dv_done_0 = fullMask_15;
      default : _zz_dv_done_0 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_1_1)
      5'b00000 : _zz_dv_done_1 = fullMask_0;
      5'b00001 : _zz_dv_done_1 = fullMask_1;
      5'b00010 : _zz_dv_done_1 = fullMask_2;
      5'b00011 : _zz_dv_done_1 = fullMask_3;
      5'b00100 : _zz_dv_done_1 = fullMask_4;
      5'b00101 : _zz_dv_done_1 = fullMask_5;
      5'b00110 : _zz_dv_done_1 = fullMask_6;
      5'b00111 : _zz_dv_done_1 = fullMask_7;
      5'b01000 : _zz_dv_done_1 = fullMask_8;
      5'b01001 : _zz_dv_done_1 = fullMask_9;
      5'b01010 : _zz_dv_done_1 = fullMask_10;
      5'b01011 : _zz_dv_done_1 = fullMask_11;
      5'b01100 : _zz_dv_done_1 = fullMask_12;
      5'b01101 : _zz_dv_done_1 = fullMask_13;
      5'b01110 : _zz_dv_done_1 = fullMask_14;
      5'b01111 : _zz_dv_done_1 = fullMask_15;
      default : _zz_dv_done_1 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_2_1)
      5'b00000 : _zz_dv_done_2 = fullMask_0;
      5'b00001 : _zz_dv_done_2 = fullMask_1;
      5'b00010 : _zz_dv_done_2 = fullMask_2;
      5'b00011 : _zz_dv_done_2 = fullMask_3;
      5'b00100 : _zz_dv_done_2 = fullMask_4;
      5'b00101 : _zz_dv_done_2 = fullMask_5;
      5'b00110 : _zz_dv_done_2 = fullMask_6;
      5'b00111 : _zz_dv_done_2 = fullMask_7;
      5'b01000 : _zz_dv_done_2 = fullMask_8;
      5'b01001 : _zz_dv_done_2 = fullMask_9;
      5'b01010 : _zz_dv_done_2 = fullMask_10;
      5'b01011 : _zz_dv_done_2 = fullMask_11;
      5'b01100 : _zz_dv_done_2 = fullMask_12;
      5'b01101 : _zz_dv_done_2 = fullMask_13;
      5'b01110 : _zz_dv_done_2 = fullMask_14;
      5'b01111 : _zz_dv_done_2 = fullMask_15;
      default : _zz_dv_done_2 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_3_1)
      5'b00000 : _zz_dv_done_3 = fullMask_0;
      5'b00001 : _zz_dv_done_3 = fullMask_1;
      5'b00010 : _zz_dv_done_3 = fullMask_2;
      5'b00011 : _zz_dv_done_3 = fullMask_3;
      5'b00100 : _zz_dv_done_3 = fullMask_4;
      5'b00101 : _zz_dv_done_3 = fullMask_5;
      5'b00110 : _zz_dv_done_3 = fullMask_6;
      5'b00111 : _zz_dv_done_3 = fullMask_7;
      5'b01000 : _zz_dv_done_3 = fullMask_8;
      5'b01001 : _zz_dv_done_3 = fullMask_9;
      5'b01010 : _zz_dv_done_3 = fullMask_10;
      5'b01011 : _zz_dv_done_3 = fullMask_11;
      5'b01100 : _zz_dv_done_3 = fullMask_12;
      5'b01101 : _zz_dv_done_3 = fullMask_13;
      5'b01110 : _zz_dv_done_3 = fullMask_14;
      5'b01111 : _zz_dv_done_3 = fullMask_15;
      default : _zz_dv_done_3 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_io_deliver_payload_tag_wave_3)
      2'b00 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_0_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_0_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_0_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_0_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_0_tag_dim;
        _zz_io_deliver_payload_base = ctx_0_base;
        _zz_io_deliver_payload_total = ctx_0_total;
      end
      2'b01 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_1_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_1_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_1_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_1_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_1_tag_dim;
        _zz_io_deliver_payload_base = ctx_1_base;
        _zz_io_deliver_payload_total = ctx_1_total;
      end
      2'b10 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_2_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_2_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_2_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_2_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_2_tag_dim;
        _zz_io_deliver_payload_base = ctx_2_base;
        _zz_io_deliver_payload_total = ctx_2_total;
      end
      default : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_3_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_3_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_3_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_3_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_3_tag_dim;
        _zz_io_deliver_payload_base = ctx_3_base;
        _zz_io_deliver_payload_total = ctx_3_total;
      end
    endcase
  end

  always @(*) begin
    case(_zz_ab_cBase_3)
      2'b00 : _zz_ab_cBase_2 = ctx_0_base;
      2'b01 : _zz_ab_cBase_2 = ctx_1_base;
      2'b10 : _zz_ab_cBase_2 = ctx_2_base;
      default : _zz_ab_cBase_2 = ctx_3_base;
    endcase
  end

  always @(*) begin
    case(_zz_io_incomplete_9)
      3'b000 : _zz_io_incomplete_8 = _zz_io_incomplete;
      3'b001 : _zz_io_incomplete_8 = _zz_io_incomplete_1;
      3'b010 : _zz_io_incomplete_8 = _zz_io_incomplete_2;
      3'b011 : _zz_io_incomplete_8 = _zz_io_incomplete_3;
      3'b100 : _zz_io_incomplete_8 = _zz_io_incomplete_4;
      3'b101 : _zz_io_incomplete_8 = _zz_io_incomplete_5;
      3'b110 : _zz_io_incomplete_8 = _zz_io_incomplete_6;
      default : _zz_io_incomplete_8 = _zz_io_incomplete_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_incomplete_11)
      3'b000 : _zz_io_incomplete_10 = _zz_io_incomplete;
      3'b001 : _zz_io_incomplete_10 = _zz_io_incomplete_1;
      3'b010 : _zz_io_incomplete_10 = _zz_io_incomplete_2;
      3'b011 : _zz_io_incomplete_10 = _zz_io_incomplete_3;
      3'b100 : _zz_io_incomplete_10 = _zz_io_incomplete_4;
      3'b101 : _zz_io_incomplete_10 = _zz_io_incomplete_5;
      3'b110 : _zz_io_incomplete_10 = _zz_io_incomplete_6;
      default : _zz_io_incomplete_10 = _zz_io_incomplete_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_9)
      3'b000 : _zz_io_occupancy_8 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_8 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_8 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_8 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_8 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_8 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_8 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_8 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_11)
      3'b000 : _zz_io_occupancy_10 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_10 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_10 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_10 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_10 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_10 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_10 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_10 = _zz_io_occupancy_7;
    endcase
  end

  assign fullMask_0 = 16'h0;
  assign fullMask_1 = 16'h0001;
  assign fullMask_2 = 16'h0003;
  assign fullMask_3 = 16'h0007;
  assign fullMask_4 = 16'h000f;
  assign fullMask_5 = 16'h001f;
  assign fullMask_6 = 16'h003f;
  assign fullMask_7 = 16'h007f;
  assign fullMask_8 = 16'h00ff;
  assign fullMask_9 = 16'h01ff;
  assign fullMask_10 = 16'h03ff;
  assign fullMask_11 = 16'h07ff;
  assign fullMask_12 = 16'h0fff;
  assign fullMask_13 = 16'h1fff;
  assign fullMask_14 = 16'h3fff;
  assign fullMask_15 = 16'h7fff;
  assign fullMask_16 = 16'hffff;
  assign fr_hit_0 = (ctx_0_active && (((((ctx_0_tag_wave == io_frag_head_tag_wave) && (ctx_0_tag_thread == io_frag_head_tag_thread)) && (ctx_0_tag_lnid == io_frag_head_tag_lnid)) && (ctx_0_tag_precision == io_frag_head_tag_precision)) && (ctx_0_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_1 = (ctx_1_active && (((((ctx_1_tag_wave == io_frag_head_tag_wave) && (ctx_1_tag_thread == io_frag_head_tag_thread)) && (ctx_1_tag_lnid == io_frag_head_tag_lnid)) && (ctx_1_tag_precision == io_frag_head_tag_precision)) && (ctx_1_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_2 = (ctx_2_active && (((((ctx_2_tag_wave == io_frag_head_tag_wave) && (ctx_2_tag_thread == io_frag_head_tag_thread)) && (ctx_2_tag_lnid == io_frag_head_tag_lnid)) && (ctx_2_tag_precision == io_frag_head_tag_precision)) && (ctx_2_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_3 = (ctx_3_active && (((((ctx_3_tag_wave == io_frag_head_tag_wave) && (ctx_3_tag_thread == io_frag_head_tag_thread)) && (ctx_3_tag_lnid == io_frag_head_tag_lnid)) && (ctx_3_tag_precision == io_frag_head_tag_precision)) && (ctx_3_tag_dim == io_frag_head_tag_dim)));
  assign fr_hitAny = (((fr_hit_0 || fr_hit_1) || fr_hit_2) || fr_hit_3);
  assign _zz_fr_cBase = (fr_hit_1 || fr_hit_3);
  assign _zz_fr_cBase_1 = (fr_hit_2 || fr_hit_3);
  assign _zz_fr_cBase_2 = {_zz_fr_cBase_1,_zz_fr_cBase};
  assign fr_cBase = _zz_fr_cBase_3;
  assign fr_cTotal = _zz_fr_cTotal;
  assign fr_cKnown = _zz_fr_cKnown;
  assign fr_cSeen = _zz_fr_cSeen;
  assign fr_effTotal = (fr_cKnown ? fr_cTotal : io_frag_head_total);
  assign fr_capaRej = (8'h10 < io_frag_head_total);
  assign fr_strayRej = ((! fr_capaRej) && (! fr_hitAny));
  assign fr_totBad = ((((! fr_capaRej) && fr_hitAny) && fr_cKnown) && (io_frag_head_total != fr_cTotal));
  assign fr_overRej = ((((! fr_capaRej) && fr_hitAny) && (! fr_totBad)) && ((io_frag_head_seq == 8'h0) || (fr_effTotal < io_frag_head_seq)));
  assign fr_off = (_zz_fr_off - 4'b0001);
  assign fr_ohSeq = (16'h0001 <<< fr_off);
  assign fr_dupRej = (((((! fr_capaRej) && fr_hitAny) && (! fr_totBad)) && (! fr_overRej)) && (|(fr_cSeen & fr_ohSeq)));
  assign fr_accept = (((((io_frag_valid && fr_hitAny) && (! fr_capaRej)) && (! fr_totBad)) && (! fr_overRej)) && (! fr_dupRej));
  assign fr_newSeen = (fr_cSeen | fr_ohSeq);
  assign fr_endBad = (io_frag_head_last && (fr_newSeen != _zz_fr_endBad));
  assign when_Reassembly_l363 = (fr_accept && fr_hit_0);
  assign when_Reassembly_l363_1 = (fr_accept && fr_hit_1);
  assign when_Reassembly_l363_2 = (fr_accept && fr_hit_2);
  assign when_Reassembly_l363_3 = (fr_accept && fr_hit_3);
  assign fr_rejEvt = (io_frag_valid && (((fr_strayRej || fr_totBad) || fr_overRej) || fr_dupRej));
  assign fr_endEvt = (fr_accept && fr_endBad);
  assign fr_capaEvt = (io_frag_valid && fr_capaRej);
  assign io_wr_valid = fr_accept;
  assign io_wr_base = fr_cBase;
  assign io_wr_off = fr_off;
  assign io_wr_body = io_frag_body;
  assign op_clash = ((((ctx_0_active && (_zz_op_clash && _zz_op_clash_3)) || (ctx_1_active && (_zz_op_clash_4 && _zz_op_clash_7))) || (ctx_2_active && ((_zz_op_clash_8 && _zz_op_clash_9) && (ctx_2_tag_dim == io_open_tag_dim)))) || (ctx_3_active && (((_zz_op_clash_10 && _zz_op_clash_11) && (ctx_3_tag_precision == io_open_tag_precision)) && (ctx_3_tag_dim == io_open_tag_dim))));
  assign op_free_0 = (! ctx_0_active);
  assign op_free_1 = (! ctx_1_active);
  assign op_free_2 = (! ctx_2_active);
  assign op_free_3 = (! ctx_3_active);
  assign op_freeAny = (((op_free_0 || op_free_1) || op_free_2) || op_free_3);
  assign _zz_op_freeOh = {op_free_3,{op_free_2,{op_free_1,op_free_0}}};
  assign op_freeOh = (_zz_op_freeOh & (~ _zz_op_freeOh_1));
  assign op_grant = ((io_open_valid && (! op_clash)) && op_freeAny);
  assign io_open_granted = op_grant;
  assign when_Reassembly_l396 = (op_grant && op_freeOh[0]);
  assign when_Reassembly_l396_1 = (op_grant && op_freeOh[1]);
  assign when_Reassembly_l396_2 = (op_grant && op_freeOh[2]);
  assign when_Reassembly_l396_3 = (op_grant && op_freeOh[3]);
  assign op_clashEvt = (io_open_valid && op_clash);
  assign dv_done_0 = (((ctx_0_active && ctx_0_last) && ctx_0_totalKnown) && (ctx_0_seen == _zz_dv_done_0));
  assign dv_done_1 = (((ctx_1_active && ctx_1_last) && ctx_1_totalKnown) && (ctx_1_seen == _zz_dv_done_1));
  assign dv_done_2 = (((ctx_2_active && ctx_2_last) && ctx_2_totalKnown) && (ctx_2_seen == _zz_dv_done_2));
  assign dv_done_3 = (((ctx_3_active && ctx_3_last) && ctx_3_totalKnown) && (ctx_3_seen == _zz_dv_done_3));
  assign dv_doneAny = (((dv_done_0 || dv_done_1) || dv_done_2) || dv_done_3);
  assign _zz_dv_grantOh = {dv_done_3,{dv_done_2,{dv_done_1,dv_done_0}}};
  assign dv_grantOh = (_zz_dv_grantOh & (~ _zz_dv_grantOh_1));
  assign io_deliver_valid = dv_doneAny;
  assign _zz_io_deliver_payload_tag_wave = dv_grantOh[3];
  assign _zz_io_deliver_payload_tag_wave_1 = (dv_grantOh[1] || _zz_io_deliver_payload_tag_wave);
  assign _zz_io_deliver_payload_tag_wave_2 = (dv_grantOh[2] || _zz_io_deliver_payload_tag_wave);
  assign _zz_io_deliver_payload_tag_wave_3 = {_zz_io_deliver_payload_tag_wave_2,_zz_io_deliver_payload_tag_wave_1};
  assign io_deliver_payload_tag_wave = _zz_io_deliver_payload_tag_wave_4;
  assign io_deliver_payload_tag_thread = _zz_io_deliver_payload_tag_thread;
  assign io_deliver_payload_tag_lnid = _zz_io_deliver_payload_tag_lnid;
  assign io_deliver_payload_tag_precision = _zz_io_deliver_payload_tag_precision;
  assign io_deliver_payload_tag_dim = _zz_io_deliver_payload_tag_dim;
  assign io_deliver_payload_base = _zz_io_deliver_payload_base;
  assign io_deliver_payload_total = _zz_io_deliver_payload_total;
  assign io_deliver_fire = (io_deliver_valid && io_deliver_ready);
  assign when_Reassembly_l435 = (io_deliver_fire && dv_grantOh[0]);
  assign when_Reassembly_l435_1 = (io_deliver_fire && dv_grantOh[1]);
  assign when_Reassembly_l435_2 = (io_deliver_fire && dv_grantOh[2]);
  assign when_Reassembly_l435_3 = (io_deliver_fire && dv_grantOh[3]);
  assign ab_hit_0 = (ctx_0_active && (((((ctx_0_tag_wave == io_abort_tag_wave) && (ctx_0_tag_thread == io_abort_tag_thread)) && (ctx_0_tag_lnid == io_abort_tag_lnid)) && (ctx_0_tag_precision == io_abort_tag_precision)) && (ctx_0_tag_dim == io_abort_tag_dim)));
  assign ab_hit_1 = (ctx_1_active && (((((ctx_1_tag_wave == io_abort_tag_wave) && (ctx_1_tag_thread == io_abort_tag_thread)) && (ctx_1_tag_lnid == io_abort_tag_lnid)) && (ctx_1_tag_precision == io_abort_tag_precision)) && (ctx_1_tag_dim == io_abort_tag_dim)));
  assign ab_hit_2 = (ctx_2_active && (((((ctx_2_tag_wave == io_abort_tag_wave) && (ctx_2_tag_thread == io_abort_tag_thread)) && (ctx_2_tag_lnid == io_abort_tag_lnid)) && (ctx_2_tag_precision == io_abort_tag_precision)) && (ctx_2_tag_dim == io_abort_tag_dim)));
  assign ab_hit_3 = (ctx_3_active && (((((ctx_3_tag_wave == io_abort_tag_wave) && (ctx_3_tag_thread == io_abort_tag_thread)) && (ctx_3_tag_lnid == io_abort_tag_lnid)) && (ctx_3_tag_precision == io_abort_tag_precision)) && (ctx_3_tag_dim == io_abort_tag_dim)));
  assign ab_hitAny = (((ab_hit_0 || ab_hit_1) || ab_hit_2) || ab_hit_3);
  assign ab_fire = (io_abort_valid && ab_hitAny);
  assign _zz_ab_cBase = (ab_hit_1 || ab_hit_3);
  assign _zz_ab_cBase_1 = (ab_hit_2 || ab_hit_3);
  assign ab_cBase = _zz_ab_cBase_2;
  assign when_Reassembly_l474 = (ab_fire && ab_hit_0);
  assign when_Reassembly_l474_1 = (ab_fire && ab_hit_1);
  assign when_Reassembly_l474_2 = (ab_fire && ab_hit_2);
  assign when_Reassembly_l474_3 = (ab_fire && ab_hit_3);
  assign when_Reassembly_l485 = (ab_fire && (ab_cnt != 8'hff));
  assign io_abortCount = ab_cnt;
  assign io_clr_valid = ab_fire;
  assign io_clr_base = ab_cBase;
  assign _zz_io_incomplete = 3'b000;
  assign _zz_io_incomplete_1 = 3'b001;
  assign _zz_io_incomplete_2 = 3'b001;
  assign _zz_io_incomplete_3 = 3'b010;
  assign _zz_io_incomplete_4 = 3'b001;
  assign _zz_io_incomplete_5 = 3'b010;
  assign _zz_io_incomplete_6 = 3'b010;
  assign _zz_io_incomplete_7 = 3'b011;
  assign io_incomplete = (_zz_io_incomplete_8 + _zz_io_incomplete_10);
  assign _zz_io_occupancy = 3'b000;
  assign _zz_io_occupancy_1 = 3'b001;
  assign _zz_io_occupancy_2 = 3'b001;
  assign _zz_io_occupancy_3 = 3'b010;
  assign _zz_io_occupancy_4 = 3'b001;
  assign _zz_io_occupancy_5 = 3'b010;
  assign _zz_io_occupancy_6 = 3'b010;
  assign _zz_io_occupancy_7 = 3'b011;
  assign io_occupancy = (_zz_io_occupancy_8 + _zz_io_occupancy_10);
  assign when_Common_l259 = ((fr_rejEvt || fr_endEvt) || op_clashEvt);
  assign io_fault = _zz_io_fault;
  assign io_capAbsent = capBit;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      ctx_0_active <= 1'b0;
      ctx_0_totalKnown <= 1'b0;
      ctx_0_seen <= 16'h0;
      ctx_0_last <= 1'b0;
      ctx_1_active <= 1'b0;
      ctx_1_totalKnown <= 1'b0;
      ctx_1_seen <= 16'h0;
      ctx_1_last <= 1'b0;
      ctx_2_active <= 1'b0;
      ctx_2_totalKnown <= 1'b0;
      ctx_2_seen <= 16'h0;
      ctx_2_last <= 1'b0;
      ctx_3_active <= 1'b0;
      ctx_3_totalKnown <= 1'b0;
      ctx_3_seen <= 16'h0;
      ctx_3_last <= 1'b0;
      ab_cnt <= 8'h0;
      _zz_io_fault <= 1'b0;
      capBit <= 1'b0;
    end else begin
      if(when_Reassembly_l363) begin
        ctx_0_seen <= fr_newSeen;
        ctx_0_last <= (ctx_0_last || io_frag_head_last);
        ctx_0_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l363_1) begin
        ctx_1_seen <= fr_newSeen;
        ctx_1_last <= (ctx_1_last || io_frag_head_last);
        ctx_1_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l363_2) begin
        ctx_2_seen <= fr_newSeen;
        ctx_2_last <= (ctx_2_last || io_frag_head_last);
        ctx_2_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l363_3) begin
        ctx_3_seen <= fr_newSeen;
        ctx_3_last <= (ctx_3_last || io_frag_head_last);
        ctx_3_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l396) begin
        ctx_0_active <= 1'b1;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l396_1) begin
        ctx_1_active <= 1'b1;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l396_2) begin
        ctx_2_active <= 1'b1;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l396_3) begin
        ctx_3_active <= 1'b1;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l435) begin
        ctx_0_active <= 1'b0;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l435_1) begin
        ctx_1_active <= 1'b0;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l435_2) begin
        ctx_2_active <= 1'b0;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l435_3) begin
        ctx_3_active <= 1'b0;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l474) begin
        ctx_0_active <= 1'b0;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l474_1) begin
        ctx_1_active <= 1'b0;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l474_2) begin
        ctx_2_active <= 1'b0;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l474_3) begin
        ctx_3_active <= 1'b0;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l485) begin
        ab_cnt <= (ab_cnt + 8'h01);
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_fault <= 1'b1;
      end
      if(io_capAbsentClear) begin
        capBit <= 1'b0;
      end
      if(fr_capaEvt) begin
        capBit <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(when_Reassembly_l363) begin
      ctx_0_total <= fr_effTotal;
    end
    if(when_Reassembly_l363_1) begin
      ctx_1_total <= fr_effTotal;
    end
    if(when_Reassembly_l363_2) begin
      ctx_2_total <= fr_effTotal;
    end
    if(when_Reassembly_l363_3) begin
      ctx_3_total <= fr_effTotal;
    end
    if(when_Reassembly_l396) begin
      ctx_0_tag_wave <= io_open_tag_wave;
      ctx_0_tag_thread <= io_open_tag_thread;
      ctx_0_tag_lnid <= io_open_tag_lnid;
      ctx_0_tag_precision <= io_open_tag_precision;
      ctx_0_tag_dim <= io_open_tag_dim;
      ctx_0_base <= io_open_base;
    end
    if(when_Reassembly_l396_1) begin
      ctx_1_tag_wave <= io_open_tag_wave;
      ctx_1_tag_thread <= io_open_tag_thread;
      ctx_1_tag_lnid <= io_open_tag_lnid;
      ctx_1_tag_precision <= io_open_tag_precision;
      ctx_1_tag_dim <= io_open_tag_dim;
      ctx_1_base <= io_open_base;
    end
    if(when_Reassembly_l396_2) begin
      ctx_2_tag_wave <= io_open_tag_wave;
      ctx_2_tag_thread <= io_open_tag_thread;
      ctx_2_tag_lnid <= io_open_tag_lnid;
      ctx_2_tag_precision <= io_open_tag_precision;
      ctx_2_tag_dim <= io_open_tag_dim;
      ctx_2_base <= io_open_base;
    end
    if(when_Reassembly_l396_3) begin
      ctx_3_tag_wave <= io_open_tag_wave;
      ctx_3_tag_thread <= io_open_tag_thread;
      ctx_3_tag_lnid <= io_open_tag_lnid;
      ctx_3_tag_precision <= io_open_tag_precision;
      ctx_3_tag_dim <= io_open_tag_dim;
      ctx_3_base <= io_open_base;
    end
  end


endmodule

module RouteJudge (
  input  wire          io_tokIn_valid,
  input  wire [31:0]   io_tokIn_payload_tag_wave,
  input  wire [15:0]   io_tokIn_payload_tag_thread,
  input  wire [15:0]   io_tokIn_payload_tag_lnid,
  input  wire [7:0]    io_tokIn_payload_tag_precision,
  input  wire [7:0]    io_tokIn_payload_tag_dim,
  input  wire [7:0]    io_tokIn_payload_lbid,
  input  wire [3:0]    io_tokIn_payload_srcKind,
  output wire          io_tokOut_valid,
  output wire [31:0]   io_tokOut_payload_tag_wave,
  output wire [15:0]   io_tokOut_payload_tag_thread,
  output wire [15:0]   io_tokOut_payload_tag_lnid,
  output wire [7:0]    io_tokOut_payload_tag_precision,
  output wire [7:0]    io_tokOut_payload_tag_dim,
  output wire [7:0]    io_tokOut_payload_lbid,
  output wire [3:0]    io_tokOut_payload_srcKind,
  input  wire          io_viewWr_valid,
  input  wire [3:0]    io_viewWr_idx,
  input  wire          io_viewWr_en,
  input  wire [15:0]   io_viewWr_lnid,
  input  wire          io_bankWr_valid,
  input  wire [7:0]    io_bankWr_lbid,
  input  wire          io_bankWr_mapped,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire          io_faultFire,
  input  wire          clk,
  input  wire          reset
);

  wire                _zz_viewHit;
  wire                _zz_viewHit_1;
  wire                _zz_viewHit_2;
  wire                _zz_viewHit_3;
  wire                _zz_viewHit_4;
  wire                _zz_viewHit_5;
  reg                 viewValid_0;
  reg                 viewValid_1;
  reg                 viewValid_2;
  reg                 viewValid_3;
  reg                 viewValid_4;
  reg                 viewValid_5;
  reg                 viewValid_6;
  reg                 viewValid_7;
  reg                 viewValid_8;
  reg                 viewValid_9;
  reg                 viewValid_10;
  reg                 viewValid_11;
  reg                 viewValid_12;
  reg                 viewValid_13;
  reg                 viewValid_14;
  reg                 viewValid_15;
  reg        [15:0]   viewName_0;
  reg        [15:0]   viewName_1;
  reg        [15:0]   viewName_2;
  reg        [15:0]   viewName_3;
  reg        [15:0]   viewName_4;
  reg        [15:0]   viewName_5;
  reg        [15:0]   viewName_6;
  reg        [15:0]   viewName_7;
  reg        [15:0]   viewName_8;
  reg        [15:0]   viewName_9;
  reg        [15:0]   viewName_10;
  reg        [15:0]   viewName_11;
  reg        [15:0]   viewName_12;
  reg        [15:0]   viewName_13;
  reg        [15:0]   viewName_14;
  reg        [15:0]   viewName_15;
  reg        [255:0]  bankPresent;
  wire       [15:0]   _zz_1;
  wire       [15:0]   _zz_2;
  wire                viewHit;
  wire                missLnid;
  wire                missLbid;
  wire                anyMiss;
  wire                faultFire;
  reg                 _zz_io_fault;

  assign _zz_viewHit = (((((((_zz_viewHit_1 || _zz_viewHit_2) || (viewValid_3 && _zz_viewHit_3)) || (viewValid_4 && (viewName_4 == io_tokIn_payload_tag_lnid))) || (viewValid_5 && (viewName_5 == io_tokIn_payload_tag_lnid))) || (viewValid_6 && (viewName_6 == io_tokIn_payload_tag_lnid))) || (viewValid_7 && (viewName_7 == io_tokIn_payload_tag_lnid))) || (viewValid_8 && (viewName_8 == io_tokIn_payload_tag_lnid)));
  assign _zz_viewHit_4 = (viewValid_9 && (viewName_9 == io_tokIn_payload_tag_lnid));
  assign _zz_viewHit_5 = (viewName_10 == io_tokIn_payload_tag_lnid);
  assign _zz_viewHit_1 = ((viewValid_0 && (viewName_0 == io_tokIn_payload_tag_lnid)) || (viewValid_1 && (viewName_1 == io_tokIn_payload_tag_lnid)));
  assign _zz_viewHit_2 = (viewValid_2 && (viewName_2 == io_tokIn_payload_tag_lnid));
  assign _zz_viewHit_3 = (viewName_3 == io_tokIn_payload_tag_lnid);
  assign _zz_1 = ({15'd0,1'b1} <<< io_viewWr_idx);
  assign _zz_2 = ({15'd0,1'b1} <<< io_viewWr_idx);
  assign viewHit = (((((((_zz_viewHit || _zz_viewHit_4) || (viewValid_10 && _zz_viewHit_5)) || (viewValid_11 && (viewName_11 == io_tokIn_payload_tag_lnid))) || (viewValid_12 && (viewName_12 == io_tokIn_payload_tag_lnid))) || (viewValid_13 && (viewName_13 == io_tokIn_payload_tag_lnid))) || (viewValid_14 && (viewName_14 == io_tokIn_payload_tag_lnid))) || (viewValid_15 && (viewName_15 == io_tokIn_payload_tag_lnid)));
  assign missLnid = (! viewHit);
  assign missLbid = ((io_tokIn_payload_srcKind == 4'b0001) && (! bankPresent[io_tokIn_payload_lbid]));
  assign anyMiss = (missLnid || missLbid);
  assign faultFire = (io_tokIn_valid && anyMiss);
  assign io_tokOut_valid = io_tokIn_valid;
  assign io_tokOut_payload_tag_wave = io_tokIn_payload_tag_wave;
  assign io_tokOut_payload_tag_thread = io_tokIn_payload_tag_thread;
  assign io_tokOut_payload_tag_lnid = io_tokIn_payload_tag_lnid;
  assign io_tokOut_payload_tag_precision = io_tokIn_payload_tag_precision;
  assign io_tokOut_payload_tag_dim = io_tokIn_payload_tag_dim;
  assign io_tokOut_payload_lbid = io_tokIn_payload_lbid;
  assign io_tokOut_payload_srcKind = io_tokIn_payload_srcKind;
  assign io_faultFire = faultFire;
  assign io_fault = _zz_io_fault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      viewValid_0 <= 1'b0;
      viewValid_1 <= 1'b0;
      viewValid_2 <= 1'b0;
      viewValid_3 <= 1'b0;
      viewValid_4 <= 1'b0;
      viewValid_5 <= 1'b0;
      viewValid_6 <= 1'b0;
      viewValid_7 <= 1'b0;
      viewValid_8 <= 1'b0;
      viewValid_9 <= 1'b0;
      viewValid_10 <= 1'b0;
      viewValid_11 <= 1'b0;
      viewValid_12 <= 1'b0;
      viewValid_13 <= 1'b0;
      viewValid_14 <= 1'b0;
      viewValid_15 <= 1'b0;
      viewName_0 <= 16'h0;
      viewName_1 <= 16'h0;
      viewName_2 <= 16'h0;
      viewName_3 <= 16'h0;
      viewName_4 <= 16'h0;
      viewName_5 <= 16'h0;
      viewName_6 <= 16'h0;
      viewName_7 <= 16'h0;
      viewName_8 <= 16'h0;
      viewName_9 <= 16'h0;
      viewName_10 <= 16'h0;
      viewName_11 <= 16'h0;
      viewName_12 <= 16'h0;
      viewName_13 <= 16'h0;
      viewName_14 <= 16'h0;
      viewName_15 <= 16'h0;
      bankPresent <= 256'h0;
      _zz_io_fault <= 1'b0;
    end else begin
      if(io_viewWr_valid) begin
        if(_zz_1[0]) begin
          viewValid_0 <= io_viewWr_en;
        end
        if(_zz_1[1]) begin
          viewValid_1 <= io_viewWr_en;
        end
        if(_zz_1[2]) begin
          viewValid_2 <= io_viewWr_en;
        end
        if(_zz_1[3]) begin
          viewValid_3 <= io_viewWr_en;
        end
        if(_zz_1[4]) begin
          viewValid_4 <= io_viewWr_en;
        end
        if(_zz_1[5]) begin
          viewValid_5 <= io_viewWr_en;
        end
        if(_zz_1[6]) begin
          viewValid_6 <= io_viewWr_en;
        end
        if(_zz_1[7]) begin
          viewValid_7 <= io_viewWr_en;
        end
        if(_zz_1[8]) begin
          viewValid_8 <= io_viewWr_en;
        end
        if(_zz_1[9]) begin
          viewValid_9 <= io_viewWr_en;
        end
        if(_zz_1[10]) begin
          viewValid_10 <= io_viewWr_en;
        end
        if(_zz_1[11]) begin
          viewValid_11 <= io_viewWr_en;
        end
        if(_zz_1[12]) begin
          viewValid_12 <= io_viewWr_en;
        end
        if(_zz_1[13]) begin
          viewValid_13 <= io_viewWr_en;
        end
        if(_zz_1[14]) begin
          viewValid_14 <= io_viewWr_en;
        end
        if(_zz_1[15]) begin
          viewValid_15 <= io_viewWr_en;
        end
        if(_zz_2[0]) begin
          viewName_0 <= io_viewWr_lnid;
        end
        if(_zz_2[1]) begin
          viewName_1 <= io_viewWr_lnid;
        end
        if(_zz_2[2]) begin
          viewName_2 <= io_viewWr_lnid;
        end
        if(_zz_2[3]) begin
          viewName_3 <= io_viewWr_lnid;
        end
        if(_zz_2[4]) begin
          viewName_4 <= io_viewWr_lnid;
        end
        if(_zz_2[5]) begin
          viewName_5 <= io_viewWr_lnid;
        end
        if(_zz_2[6]) begin
          viewName_6 <= io_viewWr_lnid;
        end
        if(_zz_2[7]) begin
          viewName_7 <= io_viewWr_lnid;
        end
        if(_zz_2[8]) begin
          viewName_8 <= io_viewWr_lnid;
        end
        if(_zz_2[9]) begin
          viewName_9 <= io_viewWr_lnid;
        end
        if(_zz_2[10]) begin
          viewName_10 <= io_viewWr_lnid;
        end
        if(_zz_2[11]) begin
          viewName_11 <= io_viewWr_lnid;
        end
        if(_zz_2[12]) begin
          viewName_12 <= io_viewWr_lnid;
        end
        if(_zz_2[13]) begin
          viewName_13 <= io_viewWr_lnid;
        end
        if(_zz_2[14]) begin
          viewName_14 <= io_viewWr_lnid;
        end
        if(_zz_2[15]) begin
          viewName_15 <= io_viewWr_lnid;
        end
      end
      if(io_bankWr_valid) begin
        bankPresent[io_bankWr_lbid] <= io_bankWr_mapped;
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(faultFire) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end


endmodule

module OperandDecode (
  input  wire          io_iValid,
  input  wire          io_iMalformed,
  input  wire          io_iCapAbsent,
  input  wire          io_iExecValid,
  input  wire [31:0]   io_iInstr_0,
  input  wire [31:0]   io_iInstr_1,
  input  wire [31:0]   io_iInstr_2,
  input  wire [31:0]   io_iInstr_3,
  input  wire [31:0]   io_iInstr_4,
  input  wire [31:0]   io_iInstr_5,
  input  wire [31:0]   io_iInstr_6,
  input  wire [31:0]   io_iInstr_7,
  input  wire [31:0]   io_iInstr_8,
  input  wire [31:0]   io_iInstr_9,
  input  wire [31:0]   io_iInstr_10,
  input  wire [31:0]   io_iInstr_11,
  input  wire [31:0]   io_iInstr_12,
  input  wire          io_iSlotPresent_0,
  input  wire          io_iSlotPresent_1,
  input  wire          io_iSlotPresent_2,
  input  wire          io_iSlotPresent_3,
  input  wire [3:0]    io_iSlotCode_0,
  input  wire [3:0]    io_iSlotCode_1,
  input  wire [3:0]    io_iSlotCode_2,
  input  wire [3:0]    io_iSlotCode_3,
  input  wire [7:0]    io_iSlotOff_0,
  input  wire [7:0]    io_iSlotOff_1,
  input  wire [7:0]    io_iSlotOff_2,
  input  wire [7:0]    io_iSlotOff_3,
  input  wire          io_iFaultClear,
  output wire          io_oValid,
  output wire          io_oMalformed,
  output wire          io_oCapAbsent,
  output wire          io_oExecValid,
  output wire          io_oPortPresent,
  output wire [15:0]   io_oPortDest,
  output wire          io_oImm16Present,
  output wire [15:0]   io_oImm16,
  output wire          io_oImm32Present,
  output wire [31:0]   io_oImm32,
  output wire          io_oImm64Present,
  output wire [63:0]   io_oImm64,
  output wire          io_oMemPresent,
  output wire [3:0]    io_oMemAddrMode,
  output wire [11:0]   io_oMemStride,
  output wire [31:0]   io_oMemOffset,
  output wire          io_oSubValid_0,
  output wire          io_oSubValid_1,
  output wire          io_oSubValid_2,
  output wire          io_oSubValid_3,
  output wire [15:0]   io_oSubO_0,
  output wire [15:0]   io_oSubO_1,
  output wire [15:0]   io_oSubO_2,
  output wire [15:0]   io_oSubO_3,
  output wire [15:0]   io_oSubA_0,
  output wire [15:0]   io_oSubA_1,
  output wire [15:0]   io_oSubA_2,
  output wire [15:0]   io_oSubA_3,
  output wire [15:0]   io_oSubB_0,
  output wire [15:0]   io_oSubB_1,
  output wire [15:0]   io_oSubB_2,
  output wire [15:0]   io_oSubB_3,
  output wire [2:0]    io_oSubCount,
  output wire          io_oOprefAValid,
  output wire [7:0]    io_oOprefALbid,
  output wire [3:0]    io_oOprefASrcKind,
  output wire          io_oOprefBValid,
  output wire [7:0]    io_oOprefBLbid,
  output wire [3:0]    io_oOprefBSrcKind,
  output wire          io_oPrecPresent,
  output wire [7:0]    io_oPrecMode,
  output wire [7:0]    io_oPrecDim,
  output wire          io_oReasmBind_valid,
  output wire [7:0]    io_oReasmBind_payload,
  output wire          io_oFault,
  input  wire          clk,
  input  wire          reset
);

  wire       [15:0]   _zz_slots_body_0;
  wire       [15:0]   _zz_slots_body_0_1;
  wire       [15:0]   _zz_slots_body_0_2;
  wire                _zz_slots_body_0_3;
  wire       [15:0]   _zz_slots_body_0_4;
  wire       [7:0]    _zz_slots_body_0_5;
  wire       [15:0]   _zz_slots_body_0_6;
  wire                _zz_slots_body_0_7;
  wire       [15:0]   _zz_slots_body_0_8;
  wire       [7:0]    _zz_slots_body_0_9;
  wire       [31:0]   _zz_slots_w1_0_1;
  wire       [31:0]   _zz_slots_w1_0_2;
  wire       [31:0]   _zz_slots_w1_0_3;
  wire                _zz_slots_w1_0_4;
  wire       [31:0]   _zz_slots_w1_0_5;
  wire       [7:0]    _zz_slots_w1_0_6;
  wire       [31:0]   _zz_slots_w1_0_7;
  wire                _zz_slots_w1_0_8;
  wire       [31:0]   _zz_slots_w1_0_9;
  wire       [7:0]    _zz_slots_w1_0_10;
  wire       [31:0]   _zz_slots_w2_0_1;
  wire       [31:0]   _zz_slots_w2_0_2;
  wire       [31:0]   _zz_slots_w2_0_3;
  wire                _zz_slots_w2_0_4;
  wire       [31:0]   _zz_slots_w2_0_5;
  wire       [7:0]    _zz_slots_w2_0_6;
  wire       [31:0]   _zz_slots_w2_0_7;
  wire                _zz_slots_w2_0_8;
  wire       [31:0]   _zz_slots_w2_0_9;
  wire       [7:0]    _zz_slots_w2_0_10;
  wire       [15:0]   _zz_slots_body_1;
  wire       [15:0]   _zz_slots_body_1_1;
  wire       [15:0]   _zz_slots_body_1_2;
  wire                _zz_slots_body_1_3;
  wire       [15:0]   _zz_slots_body_1_4;
  wire       [7:0]    _zz_slots_body_1_5;
  wire       [15:0]   _zz_slots_body_1_6;
  wire                _zz_slots_body_1_7;
  wire       [15:0]   _zz_slots_body_1_8;
  wire       [7:0]    _zz_slots_body_1_9;
  wire       [31:0]   _zz_slots_w1_1_1;
  wire       [31:0]   _zz_slots_w1_1_2;
  wire       [31:0]   _zz_slots_w1_1_3;
  wire                _zz_slots_w1_1_4;
  wire       [31:0]   _zz_slots_w1_1_5;
  wire       [7:0]    _zz_slots_w1_1_6;
  wire       [31:0]   _zz_slots_w1_1_7;
  wire                _zz_slots_w1_1_8;
  wire       [31:0]   _zz_slots_w1_1_9;
  wire       [7:0]    _zz_slots_w1_1_10;
  wire       [31:0]   _zz_slots_w2_1_1;
  wire       [31:0]   _zz_slots_w2_1_2;
  wire       [31:0]   _zz_slots_w2_1_3;
  wire                _zz_slots_w2_1_4;
  wire       [31:0]   _zz_slots_w2_1_5;
  wire       [7:0]    _zz_slots_w2_1_6;
  wire       [31:0]   _zz_slots_w2_1_7;
  wire                _zz_slots_w2_1_8;
  wire       [31:0]   _zz_slots_w2_1_9;
  wire       [7:0]    _zz_slots_w2_1_10;
  wire       [15:0]   _zz_slots_body_2;
  wire       [15:0]   _zz_slots_body_2_1;
  wire       [15:0]   _zz_slots_body_2_2;
  wire                _zz_slots_body_2_3;
  wire       [15:0]   _zz_slots_body_2_4;
  wire       [7:0]    _zz_slots_body_2_5;
  wire       [15:0]   _zz_slots_body_2_6;
  wire                _zz_slots_body_2_7;
  wire       [15:0]   _zz_slots_body_2_8;
  wire       [7:0]    _zz_slots_body_2_9;
  wire       [31:0]   _zz_slots_w1_2_1;
  wire       [31:0]   _zz_slots_w1_2_2;
  wire       [31:0]   _zz_slots_w1_2_3;
  wire                _zz_slots_w1_2_4;
  wire       [31:0]   _zz_slots_w1_2_5;
  wire       [7:0]    _zz_slots_w1_2_6;
  wire       [31:0]   _zz_slots_w1_2_7;
  wire                _zz_slots_w1_2_8;
  wire       [31:0]   _zz_slots_w1_2_9;
  wire       [7:0]    _zz_slots_w1_2_10;
  wire       [31:0]   _zz_slots_w2_2_1;
  wire       [31:0]   _zz_slots_w2_2_2;
  wire       [31:0]   _zz_slots_w2_2_3;
  wire                _zz_slots_w2_2_4;
  wire       [31:0]   _zz_slots_w2_2_5;
  wire       [7:0]    _zz_slots_w2_2_6;
  wire       [31:0]   _zz_slots_w2_2_7;
  wire                _zz_slots_w2_2_8;
  wire       [31:0]   _zz_slots_w2_2_9;
  wire       [7:0]    _zz_slots_w2_2_10;
  wire       [15:0]   _zz_slots_body_3;
  wire       [15:0]   _zz_slots_body_3_1;
  wire       [15:0]   _zz_slots_body_3_2;
  wire                _zz_slots_body_3_3;
  wire       [15:0]   _zz_slots_body_3_4;
  wire       [7:0]    _zz_slots_body_3_5;
  wire       [15:0]   _zz_slots_body_3_6;
  wire                _zz_slots_body_3_7;
  wire       [15:0]   _zz_slots_body_3_8;
  wire       [7:0]    _zz_slots_body_3_9;
  wire       [31:0]   _zz_slots_w1_3_1;
  wire       [31:0]   _zz_slots_w1_3_2;
  wire       [31:0]   _zz_slots_w1_3_3;
  wire                _zz_slots_w1_3_4;
  wire       [31:0]   _zz_slots_w1_3_5;
  wire       [7:0]    _zz_slots_w1_3_6;
  wire       [31:0]   _zz_slots_w1_3_7;
  wire                _zz_slots_w1_3_8;
  wire       [31:0]   _zz_slots_w1_3_9;
  wire       [7:0]    _zz_slots_w1_3_10;
  wire       [31:0]   _zz_slots_w2_3_1;
  wire       [31:0]   _zz_slots_w2_3_2;
  wire       [31:0]   _zz_slots_w2_3_3;
  wire                _zz_slots_w2_3_4;
  wire       [31:0]   _zz_slots_w2_3_5;
  wire       [7:0]    _zz_slots_w2_3_6;
  wire       [31:0]   _zz_slots_w2_3_7;
  wire                _zz_slots_w2_3_8;
  wire       [31:0]   _zz_slots_w2_3_9;
  wire       [7:0]    _zz_slots_w2_3_10;
  wire       [31:0]   _zz_parse_imm64;
  wire       [31:0]   _zz_parse_imm64_1;
  wire       [31:0]   _zz_parse_imm64_2;
  wire       [31:0]   _zz_parse_imm64_3;
  wire       [2:0]    _zz_parse_oprefA_1;
  wire       [0:0]    _zz_parse_oprefA_1_1;
  wire       [2:0]    _zz_parse_oprefA_2;
  wire       [2:0]    _zz_parse_oprefA_2_1;
  wire       [0:0]    _zz_parse_oprefA_2_2;
  wire       [2:0]    _zz_parse_oprefA_2_3;
  wire       [0:0]    _zz_parse_oprefA_2_4;
  wire       [2:0]    _zz_parse_oprefA_3;
  wire       [2:0]    _zz_parse_oprefA_3_1;
  wire       [2:0]    _zz_parse_oprefA_3_2;
  wire       [0:0]    _zz_parse_oprefA_3_3;
  wire       [2:0]    _zz_parse_oprefA_3_4;
  wire       [0:0]    _zz_parse_oprefA_3_5;
  wire       [2:0]    _zz_parse_oprefA_3_6;
  wire       [0:0]    _zz_parse_oprefA_3_7;
  wire       [2:0]    _zz_parse_oprefB_1;
  wire       [0:0]    _zz_parse_oprefB_1_1;
  wire       [2:0]    _zz_parse_oprefB_2;
  wire       [2:0]    _zz_parse_oprefB_2_1;
  wire       [0:0]    _zz_parse_oprefB_2_2;
  wire       [2:0]    _zz_parse_oprefB_2_3;
  wire       [0:0]    _zz_parse_oprefB_2_4;
  wire       [2:0]    _zz_parse_oprefB_3;
  wire       [2:0]    _zz_parse_oprefB_3_1;
  wire       [2:0]    _zz_parse_oprefB_3_2;
  wire       [0:0]    _zz_parse_oprefB_3_3;
  wire       [2:0]    _zz_parse_oprefB_3_4;
  wire       [0:0]    _zz_parse_oprefB_3_5;
  wire       [2:0]    _zz_parse_oprefB_3_6;
  wire       [0:0]    _zz_parse_oprefB_3_7;
  wire       [2:0]    _zz_parse_subSel_0_1;
  wire       [0:0]    _zz_parse_subSel_0_1_1;
  wire       [2:0]    _zz_parse_subSel_0_2;
  wire       [2:0]    _zz_parse_subSel_0_2_1;
  wire       [0:0]    _zz_parse_subSel_0_2_2;
  wire       [2:0]    _zz_parse_subSel_0_2_3;
  wire       [0:0]    _zz_parse_subSel_0_2_4;
  wire       [2:0]    _zz_parse_subSel_0_3;
  wire       [2:0]    _zz_parse_subSel_0_3_1;
  wire       [2:0]    _zz_parse_subSel_0_3_2;
  wire       [0:0]    _zz_parse_subSel_0_3_3;
  wire       [2:0]    _zz_parse_subSel_0_3_4;
  wire       [0:0]    _zz_parse_subSel_0_3_5;
  wire       [2:0]    _zz_parse_subSel_0_3_6;
  wire       [0:0]    _zz_parse_subSel_0_3_7;
  wire       [2:0]    _zz_parse_subSel_1_1;
  wire       [0:0]    _zz_parse_subSel_1_1_1;
  wire       [2:0]    _zz_parse_subSel_1_2;
  wire       [2:0]    _zz_parse_subSel_1_2_1;
  wire       [0:0]    _zz_parse_subSel_1_2_2;
  wire       [2:0]    _zz_parse_subSel_1_2_3;
  wire       [0:0]    _zz_parse_subSel_1_2_4;
  wire       [2:0]    _zz_parse_subSel_1_3;
  wire       [2:0]    _zz_parse_subSel_1_3_1;
  wire       [2:0]    _zz_parse_subSel_1_3_2;
  wire       [0:0]    _zz_parse_subSel_1_3_3;
  wire       [2:0]    _zz_parse_subSel_1_3_4;
  wire       [0:0]    _zz_parse_subSel_1_3_5;
  wire       [2:0]    _zz_parse_subSel_1_3_6;
  wire       [0:0]    _zz_parse_subSel_1_3_7;
  wire       [2:0]    _zz_parse_subSel_2_1;
  wire       [0:0]    _zz_parse_subSel_2_1_1;
  wire       [2:0]    _zz_parse_subSel_2_2;
  wire       [2:0]    _zz_parse_subSel_2_2_1;
  wire       [0:0]    _zz_parse_subSel_2_2_2;
  wire       [2:0]    _zz_parse_subSel_2_2_3;
  wire       [0:0]    _zz_parse_subSel_2_2_4;
  wire       [2:0]    _zz_parse_subSel_2_3;
  wire       [2:0]    _zz_parse_subSel_2_3_1;
  wire       [2:0]    _zz_parse_subSel_2_3_2;
  wire       [0:0]    _zz_parse_subSel_2_3_3;
  wire       [2:0]    _zz_parse_subSel_2_3_4;
  wire       [0:0]    _zz_parse_subSel_2_3_5;
  wire       [2:0]    _zz_parse_subSel_2_3_6;
  wire       [0:0]    _zz_parse_subSel_2_3_7;
  wire       [2:0]    _zz_parse_subSel_3_1;
  wire       [0:0]    _zz_parse_subSel_3_1_1;
  wire       [2:0]    _zz_parse_subSel_3_2;
  wire       [2:0]    _zz_parse_subSel_3_2_1;
  wire       [0:0]    _zz_parse_subSel_3_2_2;
  wire       [2:0]    _zz_parse_subSel_3_2_3;
  wire       [0:0]    _zz_parse_subSel_3_2_4;
  wire       [2:0]    _zz_parse_subSel_3_3;
  wire       [2:0]    _zz_parse_subSel_3_3_1;
  wire       [2:0]    _zz_parse_subSel_3_3_2;
  wire       [0:0]    _zz_parse_subSel_3_3_3;
  wire       [2:0]    _zz_parse_subSel_3_3_4;
  wire       [0:0]    _zz_parse_subSel_3_3_5;
  wire       [2:0]    _zz_parse_subSel_3_3_6;
  wire       [0:0]    _zz_parse_subSel_3_3_7;
  wire       [2:0]    _zz_parse_subCount;
  wire       [2:0]    _zz_parse_subCount_1;
  wire       [2:0]    _zz_parse_subCount_2;
  wire       [0:0]    _zz_parse_subCount_3;
  wire       [2:0]    _zz_parse_subCount_4;
  wire       [0:0]    _zz_parse_subCount_5;
  wire       [2:0]    _zz_parse_subCount_6;
  wire       [0:0]    _zz_parse_subCount_7;
  wire       [2:0]    _zz_parse_subCount_8;
  wire       [0:0]    _zz_parse_subCount_9;
  wire       [15:0]   slots_hi16_0;
  wire       [15:0]   slots_hi16_1;
  wire       [15:0]   slots_hi16_2;
  wire       [15:0]   slots_hi16_3;
  wire       [15:0]   slots_hi16_4;
  wire       [15:0]   slots_hi16_5;
  wire       [15:0]   slots_hi16_6;
  wire       [15:0]   slots_hi16_7;
  wire       [15:0]   slots_hi16_8;
  wire       [15:0]   slots_hi16_9;
  wire       [15:0]   slots_hi16_10;
  wire       [15:0]   slots_hi16_11;
  wire       [15:0]   slots_hi16_12;
  wire       [15:0]   slots_body_0;
  wire       [15:0]   slots_body_1;
  wire       [15:0]   slots_body_2;
  wire       [15:0]   slots_body_3;
  wire       [31:0]   slots_w1_0;
  wire       [31:0]   slots_w1_1;
  wire       [31:0]   slots_w1_2;
  wire       [31:0]   slots_w1_3;
  wire       [31:0]   slots_w2_0;
  wire       [31:0]   slots_w2_1;
  wire       [31:0]   slots_w2_2;
  wire       [31:0]   slots_w2_3;
  wire       [7:0]    _zz_slots_w1_0;
  wire       [7:0]    _zz_slots_w2_0;
  wire       [7:0]    _zz_slots_w1_1;
  wire       [7:0]    _zz_slots_w2_1;
  wire       [7:0]    _zz_slots_w1_2;
  wire       [7:0]    _zz_slots_w2_2;
  wire       [7:0]    _zz_slots_w1_3;
  wire       [7:0]    _zz_slots_w2_3;
  wire                parse_isPort_0;
  wire                parse_isPort_1;
  wire                parse_isPort_2;
  wire                parse_isPort_3;
  wire                parse_isImm16_0;
  wire                parse_isImm16_1;
  wire                parse_isImm16_2;
  wire                parse_isImm16_3;
  wire                parse_isImm32_0;
  wire                parse_isImm32_1;
  wire                parse_isImm32_2;
  wire                parse_isImm32_3;
  wire                parse_isImm64_0;
  wire                parse_isImm64_1;
  wire                parse_isImm64_2;
  wire                parse_isImm64_3;
  wire                parse_isMem_0;
  wire                parse_isMem_1;
  wire                parse_isMem_2;
  wire                parse_isMem_3;
  wire                parse_isSub_0;
  wire                parse_isSub_1;
  wire                parse_isSub_2;
  wire                parse_isSub_3;
  wire                parse_isOpref_0;
  wire                parse_isOpref_1;
  wire                parse_isOpref_2;
  wire                parse_isOpref_3;
  wire                parse_isPrec_0;
  wire                parse_isPrec_1;
  wire                parse_isPrec_2;
  wire                parse_isPrec_3;
  wire                parse_isAcctgt_0;
  wire                parse_isAcctgt_1;
  wire                parse_isAcctgt_2;
  wire                parse_isAcctgt_3;
  wire                parse_portPresent;
  wire       [15:0]   parse_portDest;
  wire                parse_imm16Present;
  wire       [15:0]   parse_imm16;
  wire                parse_imm32Present;
  wire       [31:0]   parse_imm32;
  wire                parse_imm64Present;
  wire       [63:0]   parse_imm64;
  wire                parse_memPresent;
  wire       [3:0]    parse_memAddrMode;
  wire       [11:0]   parse_memStride;
  wire       [31:0]   parse_memOffset;
  wire                parse_precPresent;
  wire       [7:0]    parse_precMode;
  wire       [7:0]    parse_precDim;
  wire                parse_acctgtPresent;
  wire       [7:0]    parse_acctgtLbid;
  wire                parse_oprefA_0;
  wire                parse_oprefA_1;
  wire                parse_oprefA_2;
  wire                parse_oprefA_3;
  wire                parse_oprefB_0;
  wire                parse_oprefB_1;
  wire                parse_oprefB_2;
  wire                parse_oprefB_3;
  wire                parse_oprefAValid;
  wire                parse_oprefBValid;
  wire       [7:0]    parse_oprefALbid;
  wire       [3:0]    parse_oprefASrcKind;
  wire       [7:0]    parse_oprefBLbid;
  wire       [3:0]    parse_oprefBSrcKind;
  wire                parse_subSel_0_0;
  wire                parse_subSel_0_1;
  wire                parse_subSel_0_2;
  wire                parse_subSel_0_3;
  wire                parse_subSel_1_0;
  wire                parse_subSel_1_1;
  wire                parse_subSel_1_2;
  wire                parse_subSel_1_3;
  wire                parse_subSel_2_0;
  wire                parse_subSel_2_1;
  wire                parse_subSel_2_2;
  wire                parse_subSel_2_3;
  wire                parse_subSel_3_0;
  wire                parse_subSel_3_1;
  wire                parse_subSel_3_2;
  wire                parse_subSel_3_3;
  wire                parse_subValid_0;
  wire                parse_subValid_1;
  wire                parse_subValid_2;
  wire                parse_subValid_3;
  wire       [15:0]   parse_subO_0;
  wire       [15:0]   parse_subO_1;
  wire       [15:0]   parse_subO_2;
  wire       [15:0]   parse_subO_3;
  wire       [15:0]   parse_subA_0;
  wire       [15:0]   parse_subA_1;
  wire       [15:0]   parse_subA_2;
  wire       [15:0]   parse_subA_3;
  wire       [15:0]   parse_subB_0;
  wire       [15:0]   parse_subB_1;
  wire       [15:0]   parse_subB_2;
  wire       [15:0]   parse_subB_3;
  wire       [2:0]    parse_subCount;
  wire                judge_oprefResvBad;
  wire                judge_srcKindBad;
  wire                judge_acctgtResvBad;
  wire                judge_bodyMal;
  wire                when_Common_l259;
  reg                 _zz_io_oFault;

  assign _zz_parse_oprefA_1_1 = parse_isOpref_0;
  assign _zz_parse_oprefA_1 = {2'd0, _zz_parse_oprefA_1_1};
  assign _zz_parse_oprefA_2 = (_zz_parse_oprefA_2_1 + _zz_parse_oprefA_2_3);
  assign _zz_parse_oprefA_2_2 = parse_isOpref_0;
  assign _zz_parse_oprefA_2_1 = {2'd0, _zz_parse_oprefA_2_2};
  assign _zz_parse_oprefA_2_4 = parse_isOpref_1;
  assign _zz_parse_oprefA_2_3 = {2'd0, _zz_parse_oprefA_2_4};
  assign _zz_parse_oprefA_3 = (_zz_parse_oprefA_3_1 + _zz_parse_oprefA_3_6);
  assign _zz_parse_oprefA_3_1 = (_zz_parse_oprefA_3_2 + _zz_parse_oprefA_3_4);
  assign _zz_parse_oprefA_3_3 = parse_isOpref_0;
  assign _zz_parse_oprefA_3_2 = {2'd0, _zz_parse_oprefA_3_3};
  assign _zz_parse_oprefA_3_5 = parse_isOpref_1;
  assign _zz_parse_oprefA_3_4 = {2'd0, _zz_parse_oprefA_3_5};
  assign _zz_parse_oprefA_3_7 = parse_isOpref_2;
  assign _zz_parse_oprefA_3_6 = {2'd0, _zz_parse_oprefA_3_7};
  assign _zz_parse_oprefB_1_1 = parse_isOpref_0;
  assign _zz_parse_oprefB_1 = {2'd0, _zz_parse_oprefB_1_1};
  assign _zz_parse_oprefB_2 = (_zz_parse_oprefB_2_1 + _zz_parse_oprefB_2_3);
  assign _zz_parse_oprefB_2_2 = parse_isOpref_0;
  assign _zz_parse_oprefB_2_1 = {2'd0, _zz_parse_oprefB_2_2};
  assign _zz_parse_oprefB_2_4 = parse_isOpref_1;
  assign _zz_parse_oprefB_2_3 = {2'd0, _zz_parse_oprefB_2_4};
  assign _zz_parse_oprefB_3 = (_zz_parse_oprefB_3_1 + _zz_parse_oprefB_3_6);
  assign _zz_parse_oprefB_3_1 = (_zz_parse_oprefB_3_2 + _zz_parse_oprefB_3_4);
  assign _zz_parse_oprefB_3_3 = parse_isOpref_0;
  assign _zz_parse_oprefB_3_2 = {2'd0, _zz_parse_oprefB_3_3};
  assign _zz_parse_oprefB_3_5 = parse_isOpref_1;
  assign _zz_parse_oprefB_3_4 = {2'd0, _zz_parse_oprefB_3_5};
  assign _zz_parse_oprefB_3_7 = parse_isOpref_2;
  assign _zz_parse_oprefB_3_6 = {2'd0, _zz_parse_oprefB_3_7};
  assign _zz_parse_subSel_0_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_0_1 = {2'd0, _zz_parse_subSel_0_1_1};
  assign _zz_parse_subSel_0_2 = (_zz_parse_subSel_0_2_1 + _zz_parse_subSel_0_2_3);
  assign _zz_parse_subSel_0_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_0_2_1 = {2'd0, _zz_parse_subSel_0_2_2};
  assign _zz_parse_subSel_0_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_0_2_3 = {2'd0, _zz_parse_subSel_0_2_4};
  assign _zz_parse_subSel_0_3 = (_zz_parse_subSel_0_3_1 + _zz_parse_subSel_0_3_6);
  assign _zz_parse_subSel_0_3_1 = (_zz_parse_subSel_0_3_2 + _zz_parse_subSel_0_3_4);
  assign _zz_parse_subSel_0_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_0_3_2 = {2'd0, _zz_parse_subSel_0_3_3};
  assign _zz_parse_subSel_0_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_0_3_4 = {2'd0, _zz_parse_subSel_0_3_5};
  assign _zz_parse_subSel_0_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_0_3_6 = {2'd0, _zz_parse_subSel_0_3_7};
  assign _zz_parse_subSel_1_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_1_1 = {2'd0, _zz_parse_subSel_1_1_1};
  assign _zz_parse_subSel_1_2 = (_zz_parse_subSel_1_2_1 + _zz_parse_subSel_1_2_3);
  assign _zz_parse_subSel_1_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_1_2_1 = {2'd0, _zz_parse_subSel_1_2_2};
  assign _zz_parse_subSel_1_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_1_2_3 = {2'd0, _zz_parse_subSel_1_2_4};
  assign _zz_parse_subSel_1_3 = (_zz_parse_subSel_1_3_1 + _zz_parse_subSel_1_3_6);
  assign _zz_parse_subSel_1_3_1 = (_zz_parse_subSel_1_3_2 + _zz_parse_subSel_1_3_4);
  assign _zz_parse_subSel_1_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_1_3_2 = {2'd0, _zz_parse_subSel_1_3_3};
  assign _zz_parse_subSel_1_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_1_3_4 = {2'd0, _zz_parse_subSel_1_3_5};
  assign _zz_parse_subSel_1_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_1_3_6 = {2'd0, _zz_parse_subSel_1_3_7};
  assign _zz_parse_subSel_2_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_2_1 = {2'd0, _zz_parse_subSel_2_1_1};
  assign _zz_parse_subSel_2_2 = (_zz_parse_subSel_2_2_1 + _zz_parse_subSel_2_2_3);
  assign _zz_parse_subSel_2_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_2_2_1 = {2'd0, _zz_parse_subSel_2_2_2};
  assign _zz_parse_subSel_2_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_2_2_3 = {2'd0, _zz_parse_subSel_2_2_4};
  assign _zz_parse_subSel_2_3 = (_zz_parse_subSel_2_3_1 + _zz_parse_subSel_2_3_6);
  assign _zz_parse_subSel_2_3_1 = (_zz_parse_subSel_2_3_2 + _zz_parse_subSel_2_3_4);
  assign _zz_parse_subSel_2_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_2_3_2 = {2'd0, _zz_parse_subSel_2_3_3};
  assign _zz_parse_subSel_2_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_2_3_4 = {2'd0, _zz_parse_subSel_2_3_5};
  assign _zz_parse_subSel_2_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_2_3_6 = {2'd0, _zz_parse_subSel_2_3_7};
  assign _zz_parse_subSel_3_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_3_1 = {2'd0, _zz_parse_subSel_3_1_1};
  assign _zz_parse_subSel_3_2 = (_zz_parse_subSel_3_2_1 + _zz_parse_subSel_3_2_3);
  assign _zz_parse_subSel_3_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_3_2_1 = {2'd0, _zz_parse_subSel_3_2_2};
  assign _zz_parse_subSel_3_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_3_2_3 = {2'd0, _zz_parse_subSel_3_2_4};
  assign _zz_parse_subSel_3_3 = (_zz_parse_subSel_3_3_1 + _zz_parse_subSel_3_3_6);
  assign _zz_parse_subSel_3_3_1 = (_zz_parse_subSel_3_3_2 + _zz_parse_subSel_3_3_4);
  assign _zz_parse_subSel_3_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_3_3_2 = {2'd0, _zz_parse_subSel_3_3_3};
  assign _zz_parse_subSel_3_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_3_3_4 = {2'd0, _zz_parse_subSel_3_3_5};
  assign _zz_parse_subSel_3_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_3_3_6 = {2'd0, _zz_parse_subSel_3_3_7};
  assign _zz_parse_subCount = (_zz_parse_subCount_1 + _zz_parse_subCount_6);
  assign _zz_parse_subCount_1 = (_zz_parse_subCount_2 + _zz_parse_subCount_4);
  assign _zz_parse_subCount_3 = parse_isSub_0;
  assign _zz_parse_subCount_2 = {2'd0, _zz_parse_subCount_3};
  assign _zz_parse_subCount_5 = parse_isSub_1;
  assign _zz_parse_subCount_4 = {2'd0, _zz_parse_subCount_5};
  assign _zz_parse_subCount_7 = parse_isSub_2;
  assign _zz_parse_subCount_6 = {2'd0, _zz_parse_subCount_7};
  assign _zz_parse_subCount_9 = parse_isSub_3;
  assign _zz_parse_subCount_8 = {2'd0, _zz_parse_subCount_9};
  assign _zz_slots_body_0 = ((((((_zz_slots_body_0_1 | _zz_slots_body_0_2) | (_zz_slots_body_0_3 ? slots_hi16_2 : _zz_slots_body_0_4)) | ((io_iSlotOff_0 == _zz_slots_body_0_5) ? slots_hi16_3 : 16'h0)) | ((io_iSlotOff_0 == 8'h04) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_0 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_0 == 8'h06) ? slots_hi16_6 : 16'h0));
  assign _zz_slots_body_0_6 = ((io_iSlotOff_0 == 8'h07) ? slots_hi16_7 : 16'h0);
  assign _zz_slots_body_0_7 = (io_iSlotOff_0 == 8'h08);
  assign _zz_slots_body_0_8 = 16'h0;
  assign _zz_slots_body_0_9 = 8'h09;
  assign _zz_slots_body_0_1 = ((io_iSlotOff_0 == 8'h0) ? slots_hi16_0 : 16'h0);
  assign _zz_slots_body_0_2 = ((io_iSlotOff_0 == 8'h01) ? slots_hi16_1 : 16'h0);
  assign _zz_slots_body_0_3 = (io_iSlotOff_0 == 8'h02);
  assign _zz_slots_body_0_4 = 16'h0;
  assign _zz_slots_body_0_5 = 8'h03;
  assign _zz_slots_w1_0_1 = ((((((_zz_slots_w1_0_2 | _zz_slots_w1_0_3) | (_zz_slots_w1_0_4 ? io_iInstr_2 : _zz_slots_w1_0_5)) | ((_zz_slots_w1_0 == _zz_slots_w1_0_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w1_0 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_0 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_0 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w1_0_7 = ((_zz_slots_w1_0 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w1_0_8 = (_zz_slots_w1_0 == 8'h08);
  assign _zz_slots_w1_0_9 = 32'h0;
  assign _zz_slots_w1_0_10 = 8'h09;
  assign _zz_slots_w1_0_2 = ((_zz_slots_w1_0 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w1_0_3 = ((_zz_slots_w1_0 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w1_0_4 = (_zz_slots_w1_0 == 8'h02);
  assign _zz_slots_w1_0_5 = 32'h0;
  assign _zz_slots_w1_0_6 = 8'h03;
  assign _zz_slots_w2_0_1 = ((((((_zz_slots_w2_0_2 | _zz_slots_w2_0_3) | (_zz_slots_w2_0_4 ? io_iInstr_2 : _zz_slots_w2_0_5)) | ((_zz_slots_w2_0 == _zz_slots_w2_0_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w2_0 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_0 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_0 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w2_0_7 = ((_zz_slots_w2_0 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w2_0_8 = (_zz_slots_w2_0 == 8'h08);
  assign _zz_slots_w2_0_9 = 32'h0;
  assign _zz_slots_w2_0_10 = 8'h09;
  assign _zz_slots_w2_0_2 = ((_zz_slots_w2_0 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w2_0_3 = ((_zz_slots_w2_0 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w2_0_4 = (_zz_slots_w2_0 == 8'h02);
  assign _zz_slots_w2_0_5 = 32'h0;
  assign _zz_slots_w2_0_6 = 8'h03;
  assign _zz_slots_body_1 = ((((((_zz_slots_body_1_1 | _zz_slots_body_1_2) | (_zz_slots_body_1_3 ? slots_hi16_2 : _zz_slots_body_1_4)) | ((io_iSlotOff_1 == _zz_slots_body_1_5) ? slots_hi16_3 : 16'h0)) | ((io_iSlotOff_1 == 8'h04) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_1 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_1 == 8'h06) ? slots_hi16_6 : 16'h0));
  assign _zz_slots_body_1_6 = ((io_iSlotOff_1 == 8'h07) ? slots_hi16_7 : 16'h0);
  assign _zz_slots_body_1_7 = (io_iSlotOff_1 == 8'h08);
  assign _zz_slots_body_1_8 = 16'h0;
  assign _zz_slots_body_1_9 = 8'h09;
  assign _zz_slots_body_1_1 = ((io_iSlotOff_1 == 8'h0) ? slots_hi16_0 : 16'h0);
  assign _zz_slots_body_1_2 = ((io_iSlotOff_1 == 8'h01) ? slots_hi16_1 : 16'h0);
  assign _zz_slots_body_1_3 = (io_iSlotOff_1 == 8'h02);
  assign _zz_slots_body_1_4 = 16'h0;
  assign _zz_slots_body_1_5 = 8'h03;
  assign _zz_slots_w1_1_1 = ((((((_zz_slots_w1_1_2 | _zz_slots_w1_1_3) | (_zz_slots_w1_1_4 ? io_iInstr_2 : _zz_slots_w1_1_5)) | ((_zz_slots_w1_1 == _zz_slots_w1_1_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w1_1 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_1 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_1 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w1_1_7 = ((_zz_slots_w1_1 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w1_1_8 = (_zz_slots_w1_1 == 8'h08);
  assign _zz_slots_w1_1_9 = 32'h0;
  assign _zz_slots_w1_1_10 = 8'h09;
  assign _zz_slots_w1_1_2 = ((_zz_slots_w1_1 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w1_1_3 = ((_zz_slots_w1_1 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w1_1_4 = (_zz_slots_w1_1 == 8'h02);
  assign _zz_slots_w1_1_5 = 32'h0;
  assign _zz_slots_w1_1_6 = 8'h03;
  assign _zz_slots_w2_1_1 = ((((((_zz_slots_w2_1_2 | _zz_slots_w2_1_3) | (_zz_slots_w2_1_4 ? io_iInstr_2 : _zz_slots_w2_1_5)) | ((_zz_slots_w2_1 == _zz_slots_w2_1_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w2_1 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_1 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_1 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w2_1_7 = ((_zz_slots_w2_1 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w2_1_8 = (_zz_slots_w2_1 == 8'h08);
  assign _zz_slots_w2_1_9 = 32'h0;
  assign _zz_slots_w2_1_10 = 8'h09;
  assign _zz_slots_w2_1_2 = ((_zz_slots_w2_1 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w2_1_3 = ((_zz_slots_w2_1 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w2_1_4 = (_zz_slots_w2_1 == 8'h02);
  assign _zz_slots_w2_1_5 = 32'h0;
  assign _zz_slots_w2_1_6 = 8'h03;
  assign _zz_slots_body_2 = ((((((_zz_slots_body_2_1 | _zz_slots_body_2_2) | (_zz_slots_body_2_3 ? slots_hi16_2 : _zz_slots_body_2_4)) | ((io_iSlotOff_2 == _zz_slots_body_2_5) ? slots_hi16_3 : 16'h0)) | ((io_iSlotOff_2 == 8'h04) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_2 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_2 == 8'h06) ? slots_hi16_6 : 16'h0));
  assign _zz_slots_body_2_6 = ((io_iSlotOff_2 == 8'h07) ? slots_hi16_7 : 16'h0);
  assign _zz_slots_body_2_7 = (io_iSlotOff_2 == 8'h08);
  assign _zz_slots_body_2_8 = 16'h0;
  assign _zz_slots_body_2_9 = 8'h09;
  assign _zz_slots_body_2_1 = ((io_iSlotOff_2 == 8'h0) ? slots_hi16_0 : 16'h0);
  assign _zz_slots_body_2_2 = ((io_iSlotOff_2 == 8'h01) ? slots_hi16_1 : 16'h0);
  assign _zz_slots_body_2_3 = (io_iSlotOff_2 == 8'h02);
  assign _zz_slots_body_2_4 = 16'h0;
  assign _zz_slots_body_2_5 = 8'h03;
  assign _zz_slots_w1_2_1 = ((((((_zz_slots_w1_2_2 | _zz_slots_w1_2_3) | (_zz_slots_w1_2_4 ? io_iInstr_2 : _zz_slots_w1_2_5)) | ((_zz_slots_w1_2 == _zz_slots_w1_2_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w1_2 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_2 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_2 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w1_2_7 = ((_zz_slots_w1_2 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w1_2_8 = (_zz_slots_w1_2 == 8'h08);
  assign _zz_slots_w1_2_9 = 32'h0;
  assign _zz_slots_w1_2_10 = 8'h09;
  assign _zz_slots_w1_2_2 = ((_zz_slots_w1_2 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w1_2_3 = ((_zz_slots_w1_2 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w1_2_4 = (_zz_slots_w1_2 == 8'h02);
  assign _zz_slots_w1_2_5 = 32'h0;
  assign _zz_slots_w1_2_6 = 8'h03;
  assign _zz_slots_w2_2_1 = ((((((_zz_slots_w2_2_2 | _zz_slots_w2_2_3) | (_zz_slots_w2_2_4 ? io_iInstr_2 : _zz_slots_w2_2_5)) | ((_zz_slots_w2_2 == _zz_slots_w2_2_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w2_2 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_2 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_2 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w2_2_7 = ((_zz_slots_w2_2 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w2_2_8 = (_zz_slots_w2_2 == 8'h08);
  assign _zz_slots_w2_2_9 = 32'h0;
  assign _zz_slots_w2_2_10 = 8'h09;
  assign _zz_slots_w2_2_2 = ((_zz_slots_w2_2 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w2_2_3 = ((_zz_slots_w2_2 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w2_2_4 = (_zz_slots_w2_2 == 8'h02);
  assign _zz_slots_w2_2_5 = 32'h0;
  assign _zz_slots_w2_2_6 = 8'h03;
  assign _zz_slots_body_3 = ((((((_zz_slots_body_3_1 | _zz_slots_body_3_2) | (_zz_slots_body_3_3 ? slots_hi16_2 : _zz_slots_body_3_4)) | ((io_iSlotOff_3 == _zz_slots_body_3_5) ? slots_hi16_3 : 16'h0)) | ((io_iSlotOff_3 == 8'h04) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_3 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_3 == 8'h06) ? slots_hi16_6 : 16'h0));
  assign _zz_slots_body_3_6 = ((io_iSlotOff_3 == 8'h07) ? slots_hi16_7 : 16'h0);
  assign _zz_slots_body_3_7 = (io_iSlotOff_3 == 8'h08);
  assign _zz_slots_body_3_8 = 16'h0;
  assign _zz_slots_body_3_9 = 8'h09;
  assign _zz_slots_body_3_1 = ((io_iSlotOff_3 == 8'h0) ? slots_hi16_0 : 16'h0);
  assign _zz_slots_body_3_2 = ((io_iSlotOff_3 == 8'h01) ? slots_hi16_1 : 16'h0);
  assign _zz_slots_body_3_3 = (io_iSlotOff_3 == 8'h02);
  assign _zz_slots_body_3_4 = 16'h0;
  assign _zz_slots_body_3_5 = 8'h03;
  assign _zz_slots_w1_3_1 = ((((((_zz_slots_w1_3_2 | _zz_slots_w1_3_3) | (_zz_slots_w1_3_4 ? io_iInstr_2 : _zz_slots_w1_3_5)) | ((_zz_slots_w1_3 == _zz_slots_w1_3_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w1_3 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_3 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_3 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w1_3_7 = ((_zz_slots_w1_3 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w1_3_8 = (_zz_slots_w1_3 == 8'h08);
  assign _zz_slots_w1_3_9 = 32'h0;
  assign _zz_slots_w1_3_10 = 8'h09;
  assign _zz_slots_w1_3_2 = ((_zz_slots_w1_3 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w1_3_3 = ((_zz_slots_w1_3 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w1_3_4 = (_zz_slots_w1_3 == 8'h02);
  assign _zz_slots_w1_3_5 = 32'h0;
  assign _zz_slots_w1_3_6 = 8'h03;
  assign _zz_slots_w2_3_1 = ((((((_zz_slots_w2_3_2 | _zz_slots_w2_3_3) | (_zz_slots_w2_3_4 ? io_iInstr_2 : _zz_slots_w2_3_5)) | ((_zz_slots_w2_3 == _zz_slots_w2_3_6) ? io_iInstr_3 : 32'h0)) | ((_zz_slots_w2_3 == 8'h04) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_3 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_3 == 8'h06) ? io_iInstr_6 : 32'h0));
  assign _zz_slots_w2_3_7 = ((_zz_slots_w2_3 == 8'h07) ? io_iInstr_7 : 32'h0);
  assign _zz_slots_w2_3_8 = (_zz_slots_w2_3 == 8'h08);
  assign _zz_slots_w2_3_9 = 32'h0;
  assign _zz_slots_w2_3_10 = 8'h09;
  assign _zz_slots_w2_3_2 = ((_zz_slots_w2_3 == 8'h0) ? io_iInstr_0 : 32'h0);
  assign _zz_slots_w2_3_3 = ((_zz_slots_w2_3 == 8'h01) ? io_iInstr_1 : 32'h0);
  assign _zz_slots_w2_3_4 = (_zz_slots_w2_3 == 8'h02);
  assign _zz_slots_w2_3_5 = 32'h0;
  assign _zz_slots_w2_3_6 = 8'h03;
  assign _zz_parse_imm64 = 32'h0;
  assign _zz_parse_imm64_1 = 32'h0;
  assign _zz_parse_imm64_2 = 32'h0;
  assign _zz_parse_imm64_3 = 32'h0;
  assign slots_hi16_0 = io_iInstr_0[31 : 16];
  assign slots_hi16_1 = io_iInstr_1[31 : 16];
  assign slots_hi16_2 = io_iInstr_2[31 : 16];
  assign slots_hi16_3 = io_iInstr_3[31 : 16];
  assign slots_hi16_4 = io_iInstr_4[31 : 16];
  assign slots_hi16_5 = io_iInstr_5[31 : 16];
  assign slots_hi16_6 = io_iInstr_6[31 : 16];
  assign slots_hi16_7 = io_iInstr_7[31 : 16];
  assign slots_hi16_8 = io_iInstr_8[31 : 16];
  assign slots_hi16_9 = io_iInstr_9[31 : 16];
  assign slots_hi16_10 = io_iInstr_10[31 : 16];
  assign slots_hi16_11 = io_iInstr_11[31 : 16];
  assign slots_hi16_12 = io_iInstr_12[31 : 16];
  assign _zz_slots_w1_0 = (io_iSlotOff_0 + 8'h01);
  assign _zz_slots_w2_0 = (io_iSlotOff_0 + 8'h02);
  assign slots_body_0 = ((((((_zz_slots_body_0 | _zz_slots_body_0_6) | (_zz_slots_body_0_7 ? slots_hi16_8 : _zz_slots_body_0_8)) | ((io_iSlotOff_0 == _zz_slots_body_0_9) ? slots_hi16_9 : 16'h0)) | ((io_iSlotOff_0 == 8'h0a) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_0 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_0 == 8'h0c) ? slots_hi16_12 : 16'h0));
  assign slots_w1_0 = ((((((_zz_slots_w1_0_1 | _zz_slots_w1_0_7) | (_zz_slots_w1_0_8 ? io_iInstr_8 : _zz_slots_w1_0_9)) | ((_zz_slots_w1_0 == _zz_slots_w1_0_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign slots_w2_0 = ((((((_zz_slots_w2_0_1 | _zz_slots_w2_0_7) | (_zz_slots_w2_0_8 ? io_iInstr_8 : _zz_slots_w2_0_9)) | ((_zz_slots_w2_0 == _zz_slots_w2_0_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign _zz_slots_w1_1 = (io_iSlotOff_1 + 8'h01);
  assign _zz_slots_w2_1 = (io_iSlotOff_1 + 8'h02);
  assign slots_body_1 = ((((((_zz_slots_body_1 | _zz_slots_body_1_6) | (_zz_slots_body_1_7 ? slots_hi16_8 : _zz_slots_body_1_8)) | ((io_iSlotOff_1 == _zz_slots_body_1_9) ? slots_hi16_9 : 16'h0)) | ((io_iSlotOff_1 == 8'h0a) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_1 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_1 == 8'h0c) ? slots_hi16_12 : 16'h0));
  assign slots_w1_1 = ((((((_zz_slots_w1_1_1 | _zz_slots_w1_1_7) | (_zz_slots_w1_1_8 ? io_iInstr_8 : _zz_slots_w1_1_9)) | ((_zz_slots_w1_1 == _zz_slots_w1_1_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign slots_w2_1 = ((((((_zz_slots_w2_1_1 | _zz_slots_w2_1_7) | (_zz_slots_w2_1_8 ? io_iInstr_8 : _zz_slots_w2_1_9)) | ((_zz_slots_w2_1 == _zz_slots_w2_1_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign _zz_slots_w1_2 = (io_iSlotOff_2 + 8'h01);
  assign _zz_slots_w2_2 = (io_iSlotOff_2 + 8'h02);
  assign slots_body_2 = ((((((_zz_slots_body_2 | _zz_slots_body_2_6) | (_zz_slots_body_2_7 ? slots_hi16_8 : _zz_slots_body_2_8)) | ((io_iSlotOff_2 == _zz_slots_body_2_9) ? slots_hi16_9 : 16'h0)) | ((io_iSlotOff_2 == 8'h0a) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_2 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_2 == 8'h0c) ? slots_hi16_12 : 16'h0));
  assign slots_w1_2 = ((((((_zz_slots_w1_2_1 | _zz_slots_w1_2_7) | (_zz_slots_w1_2_8 ? io_iInstr_8 : _zz_slots_w1_2_9)) | ((_zz_slots_w1_2 == _zz_slots_w1_2_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign slots_w2_2 = ((((((_zz_slots_w2_2_1 | _zz_slots_w2_2_7) | (_zz_slots_w2_2_8 ? io_iInstr_8 : _zz_slots_w2_2_9)) | ((_zz_slots_w2_2 == _zz_slots_w2_2_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign _zz_slots_w1_3 = (io_iSlotOff_3 + 8'h01);
  assign _zz_slots_w2_3 = (io_iSlotOff_3 + 8'h02);
  assign slots_body_3 = ((((((_zz_slots_body_3 | _zz_slots_body_3_6) | (_zz_slots_body_3_7 ? slots_hi16_8 : _zz_slots_body_3_8)) | ((io_iSlotOff_3 == _zz_slots_body_3_9) ? slots_hi16_9 : 16'h0)) | ((io_iSlotOff_3 == 8'h0a) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_3 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_3 == 8'h0c) ? slots_hi16_12 : 16'h0));
  assign slots_w1_3 = ((((((_zz_slots_w1_3_1 | _zz_slots_w1_3_7) | (_zz_slots_w1_3_8 ? io_iInstr_8 : _zz_slots_w1_3_9)) | ((_zz_slots_w1_3 == _zz_slots_w1_3_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign slots_w2_3 = ((((((_zz_slots_w2_3_1 | _zz_slots_w2_3_7) | (_zz_slots_w2_3_8 ? io_iInstr_8 : _zz_slots_w2_3_9)) | ((_zz_slots_w2_3 == _zz_slots_w2_3_10) ? io_iInstr_9 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0a) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0c) ? io_iInstr_12 : 32'h0));
  assign parse_isPort_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0001));
  assign parse_isPort_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0001));
  assign parse_isPort_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0001));
  assign parse_isPort_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0001));
  assign parse_isImm16_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0010));
  assign parse_isImm16_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0010));
  assign parse_isImm16_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0010));
  assign parse_isImm16_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0010));
  assign parse_isImm32_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0011));
  assign parse_isImm32_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0011));
  assign parse_isImm32_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0011));
  assign parse_isImm32_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0011));
  assign parse_isImm64_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0100));
  assign parse_isImm64_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0100));
  assign parse_isImm64_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0100));
  assign parse_isImm64_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0100));
  assign parse_isMem_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0101));
  assign parse_isMem_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0101));
  assign parse_isMem_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0101));
  assign parse_isMem_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0101));
  assign parse_isSub_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0110));
  assign parse_isSub_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0110));
  assign parse_isSub_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0110));
  assign parse_isSub_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0110));
  assign parse_isOpref_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0111));
  assign parse_isOpref_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0111));
  assign parse_isOpref_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0111));
  assign parse_isOpref_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0111));
  assign parse_isPrec_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b1000));
  assign parse_isPrec_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b1000));
  assign parse_isPrec_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b1000));
  assign parse_isPrec_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b1000));
  assign parse_isAcctgt_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b1001));
  assign parse_isAcctgt_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b1001));
  assign parse_isAcctgt_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b1001));
  assign parse_isAcctgt_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b1001));
  assign parse_portPresent = (((parse_isPort_0 || parse_isPort_1) || parse_isPort_2) || parse_isPort_3);
  assign parse_portDest = ((((parse_isPort_0 ? slots_body_0 : 16'h0) | (parse_isPort_1 ? slots_body_1 : 16'h0)) | (parse_isPort_2 ? slots_body_2 : 16'h0)) | (parse_isPort_3 ? slots_body_3 : 16'h0));
  assign parse_imm16Present = (((parse_isImm16_0 || parse_isImm16_1) || parse_isImm16_2) || parse_isImm16_3);
  assign parse_imm16 = ((((parse_isImm16_0 ? slots_body_0 : 16'h0) | (parse_isImm16_1 ? slots_body_1 : 16'h0)) | (parse_isImm16_2 ? slots_body_2 : 16'h0)) | (parse_isImm16_3 ? slots_body_3 : 16'h0));
  assign parse_imm32Present = (((parse_isImm32_0 || parse_isImm32_1) || parse_isImm32_2) || parse_isImm32_3);
  assign parse_imm32 = ((((parse_isImm32_0 ? slots_w1_0 : 32'h0) | (parse_isImm32_1 ? slots_w1_1 : 32'h0)) | (parse_isImm32_2 ? slots_w1_2 : 32'h0)) | (parse_isImm32_3 ? slots_w1_3 : 32'h0));
  assign parse_imm64Present = (((parse_isImm64_0 || parse_isImm64_1) || parse_isImm64_2) || parse_isImm64_3);
  assign parse_imm64 = {((((parse_isImm64_0 ? slots_w2_0 : _zz_parse_imm64) | (parse_isImm64_1 ? slots_w2_1 : _zz_parse_imm64_1)) | (parse_isImm64_2 ? slots_w2_2 : 32'h0)) | (parse_isImm64_3 ? slots_w2_3 : 32'h0)),((((parse_isImm64_0 ? slots_w1_0 : _zz_parse_imm64_2) | (parse_isImm64_1 ? slots_w1_1 : _zz_parse_imm64_3)) | (parse_isImm64_2 ? slots_w1_2 : 32'h0)) | (parse_isImm64_3 ? slots_w1_3 : 32'h0))};
  assign parse_memPresent = (((parse_isMem_0 || parse_isMem_1) || parse_isMem_2) || parse_isMem_3);
  assign parse_memAddrMode = ((((parse_isMem_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_isMem_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_isMem_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_isMem_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_memStride = ((((parse_isMem_0 ? slots_body_0[15 : 4] : 12'h0) | (parse_isMem_1 ? slots_body_1[15 : 4] : 12'h0)) | (parse_isMem_2 ? slots_body_2[15 : 4] : 12'h0)) | (parse_isMem_3 ? slots_body_3[15 : 4] : 12'h0));
  assign parse_memOffset = ((((parse_isMem_0 ? slots_w1_0 : 32'h0) | (parse_isMem_1 ? slots_w1_1 : 32'h0)) | (parse_isMem_2 ? slots_w1_2 : 32'h0)) | (parse_isMem_3 ? slots_w1_3 : 32'h0));
  assign parse_precPresent = (((parse_isPrec_0 || parse_isPrec_1) || parse_isPrec_2) || parse_isPrec_3);
  assign parse_precMode = ((((parse_isPrec_0 ? slots_body_0[7 : 0] : 8'h0) | (parse_isPrec_1 ? slots_body_1[7 : 0] : 8'h0)) | (parse_isPrec_2 ? slots_body_2[7 : 0] : 8'h0)) | (parse_isPrec_3 ? slots_body_3[7 : 0] : 8'h0));
  assign parse_precDim = ((((parse_isPrec_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_isPrec_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_isPrec_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_isPrec_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_acctgtPresent = (((parse_isAcctgt_0 || parse_isAcctgt_1) || parse_isAcctgt_2) || parse_isAcctgt_3);
  assign parse_acctgtLbid = ((((parse_isAcctgt_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_isAcctgt_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_isAcctgt_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_isAcctgt_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_oprefA_0 = (parse_isOpref_0 && (3'b000 == 3'b000));
  assign parse_oprefA_1 = (parse_isOpref_1 && (_zz_parse_oprefA_1 == 3'b000));
  assign parse_oprefA_2 = (parse_isOpref_2 && (_zz_parse_oprefA_2 == 3'b000));
  assign parse_oprefA_3 = (parse_isOpref_3 && (_zz_parse_oprefA_3 == 3'b000));
  assign parse_oprefB_0 = (parse_isOpref_0 && (3'b000 == 3'b001));
  assign parse_oprefB_1 = (parse_isOpref_1 && (_zz_parse_oprefB_1 == 3'b001));
  assign parse_oprefB_2 = (parse_isOpref_2 && (_zz_parse_oprefB_2 == 3'b001));
  assign parse_oprefB_3 = (parse_isOpref_3 && (_zz_parse_oprefB_3 == 3'b001));
  assign parse_oprefAValid = (((parse_oprefA_0 || parse_oprefA_1) || parse_oprefA_2) || parse_oprefA_3);
  assign parse_oprefBValid = (((parse_oprefB_0 || parse_oprefB_1) || parse_oprefB_2) || parse_oprefB_3);
  assign parse_oprefALbid = ((((parse_oprefA_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_oprefA_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_oprefA_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_oprefA_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_oprefASrcKind = ((((parse_oprefA_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_oprefA_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_oprefA_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_oprefA_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_oprefBLbid = ((((parse_oprefB_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_oprefB_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_oprefB_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_oprefB_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_oprefBSrcKind = ((((parse_oprefB_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_oprefB_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_oprefB_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_oprefB_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_subSel_0_0 = (parse_isSub_0 && (3'b000 == 3'b000));
  assign parse_subSel_0_1 = (parse_isSub_1 && (_zz_parse_subSel_0_1 == 3'b000));
  assign parse_subSel_0_2 = (parse_isSub_2 && (_zz_parse_subSel_0_2 == 3'b000));
  assign parse_subSel_0_3 = (parse_isSub_3 && (_zz_parse_subSel_0_3 == 3'b000));
  assign parse_subSel_1_0 = (parse_isSub_0 && (3'b000 == 3'b001));
  assign parse_subSel_1_1 = (parse_isSub_1 && (_zz_parse_subSel_1_1 == 3'b001));
  assign parse_subSel_1_2 = (parse_isSub_2 && (_zz_parse_subSel_1_2 == 3'b001));
  assign parse_subSel_1_3 = (parse_isSub_3 && (_zz_parse_subSel_1_3 == 3'b001));
  assign parse_subSel_2_0 = (parse_isSub_0 && (3'b000 == 3'b010));
  assign parse_subSel_2_1 = (parse_isSub_1 && (_zz_parse_subSel_2_1 == 3'b010));
  assign parse_subSel_2_2 = (parse_isSub_2 && (_zz_parse_subSel_2_2 == 3'b010));
  assign parse_subSel_2_3 = (parse_isSub_3 && (_zz_parse_subSel_2_3 == 3'b010));
  assign parse_subSel_3_0 = (parse_isSub_0 && (3'b000 == 3'b011));
  assign parse_subSel_3_1 = (parse_isSub_1 && (_zz_parse_subSel_3_1 == 3'b011));
  assign parse_subSel_3_2 = (parse_isSub_2 && (_zz_parse_subSel_3_2 == 3'b011));
  assign parse_subSel_3_3 = (parse_isSub_3 && (_zz_parse_subSel_3_3 == 3'b011));
  assign parse_subValid_0 = (((parse_subSel_0_0 || parse_subSel_0_1) || parse_subSel_0_2) || parse_subSel_0_3);
  assign parse_subValid_1 = (((parse_subSel_1_0 || parse_subSel_1_1) || parse_subSel_1_2) || parse_subSel_1_3);
  assign parse_subValid_2 = (((parse_subSel_2_0 || parse_subSel_2_1) || parse_subSel_2_2) || parse_subSel_2_3);
  assign parse_subValid_3 = (((parse_subSel_3_0 || parse_subSel_3_1) || parse_subSel_3_2) || parse_subSel_3_3);
  assign parse_subO_0 = ((((parse_subSel_0_0 ? slots_body_0 : 16'h0) | (parse_subSel_0_1 ? slots_body_1 : 16'h0)) | (parse_subSel_0_2 ? slots_body_2 : 16'h0)) | (parse_subSel_0_3 ? slots_body_3 : 16'h0));
  assign parse_subO_1 = ((((parse_subSel_1_0 ? slots_body_0 : 16'h0) | (parse_subSel_1_1 ? slots_body_1 : 16'h0)) | (parse_subSel_1_2 ? slots_body_2 : 16'h0)) | (parse_subSel_1_3 ? slots_body_3 : 16'h0));
  assign parse_subO_2 = ((((parse_subSel_2_0 ? slots_body_0 : 16'h0) | (parse_subSel_2_1 ? slots_body_1 : 16'h0)) | (parse_subSel_2_2 ? slots_body_2 : 16'h0)) | (parse_subSel_2_3 ? slots_body_3 : 16'h0));
  assign parse_subO_3 = ((((parse_subSel_3_0 ? slots_body_0 : 16'h0) | (parse_subSel_3_1 ? slots_body_1 : 16'h0)) | (parse_subSel_3_2 ? slots_body_2 : 16'h0)) | (parse_subSel_3_3 ? slots_body_3 : 16'h0));
  assign parse_subA_0 = ((((parse_subSel_0_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_0_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_0_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_0_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_1 = ((((parse_subSel_1_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_1_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_1_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_1_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_2 = ((((parse_subSel_2_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_2_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_2_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_2_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_3 = ((((parse_subSel_3_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_3_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_3_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_3_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subB_0 = ((((parse_subSel_0_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_0_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_0_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_0_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_1 = ((((parse_subSel_1_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_1_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_1_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_1_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_2 = ((((parse_subSel_2_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_2_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_2_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_2_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_3 = ((((parse_subSel_3_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_3_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_3_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_3_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subCount = (_zz_parse_subCount + _zz_parse_subCount_8);
  assign judge_oprefResvBad = ((((parse_isOpref_0 && (slots_body_0[7 : 4] != 4'b0000)) || (parse_isOpref_1 && (slots_body_1[7 : 4] != 4'b0000))) || (parse_isOpref_2 && (slots_body_2[7 : 4] != 4'b0000))) || (parse_isOpref_3 && (slots_body_3[7 : 4] != 4'b0000)));
  assign judge_srcKindBad = ((((parse_isOpref_0 && (4'b0011 <= slots_body_0[3 : 0])) || (parse_isOpref_1 && (4'b0011 <= slots_body_1[3 : 0]))) || (parse_isOpref_2 && (4'b0011 <= slots_body_2[3 : 0]))) || (parse_isOpref_3 && (4'b0011 <= slots_body_3[3 : 0])));
  assign judge_acctgtResvBad = ((((parse_isAcctgt_0 && (slots_body_0[7 : 0] != 8'h0)) || (parse_isAcctgt_1 && (slots_body_1[7 : 0] != 8'h0))) || (parse_isAcctgt_2 && (slots_body_2[7 : 0] != 8'h0))) || (parse_isAcctgt_3 && (slots_body_3[7 : 0] != 8'h0)));
  assign judge_bodyMal = ((! io_iCapAbsent) && ((judge_oprefResvBad || judge_srcKindBad) || judge_acctgtResvBad));
  assign io_oValid = io_iValid;
  assign io_oMalformed = (io_iMalformed || judge_bodyMal);
  assign io_oCapAbsent = io_iCapAbsent;
  assign io_oExecValid = (io_iExecValid && (! judge_bodyMal));
  assign io_oPortPresent = (io_oExecValid && parse_portPresent);
  assign io_oPortDest = ((io_oExecValid && parse_portPresent) ? parse_portDest : 16'h0);
  assign io_oImm16Present = (io_oExecValid && parse_imm16Present);
  assign io_oImm16 = ((io_oExecValid && parse_imm16Present) ? parse_imm16 : 16'h0);
  assign io_oImm32Present = (io_oExecValid && parse_imm32Present);
  assign io_oImm32 = ((io_oExecValid && parse_imm32Present) ? parse_imm32 : 32'h0);
  assign io_oImm64Present = (io_oExecValid && parse_imm64Present);
  assign io_oImm64 = ((io_oExecValid && parse_imm64Present) ? parse_imm64 : 64'h0);
  assign io_oMemPresent = (io_oExecValid && parse_memPresent);
  assign io_oMemAddrMode = ((io_oExecValid && parse_memPresent) ? parse_memAddrMode : 4'b0000);
  assign io_oMemStride = ((io_oExecValid && parse_memPresent) ? parse_memStride : 12'h0);
  assign io_oMemOffset = ((io_oExecValid && parse_memPresent) ? parse_memOffset : 32'h0);
  assign io_oSubValid_0 = (io_oExecValid && parse_subValid_0);
  assign io_oSubO_0 = ((io_oExecValid && parse_subValid_0) ? parse_subO_0 : 16'h0);
  assign io_oSubA_0 = ((io_oExecValid && parse_subValid_0) ? parse_subA_0 : 16'h0);
  assign io_oSubB_0 = ((io_oExecValid && parse_subValid_0) ? parse_subB_0 : 16'h0);
  assign io_oSubValid_1 = (io_oExecValid && parse_subValid_1);
  assign io_oSubO_1 = ((io_oExecValid && parse_subValid_1) ? parse_subO_1 : 16'h0);
  assign io_oSubA_1 = ((io_oExecValid && parse_subValid_1) ? parse_subA_1 : 16'h0);
  assign io_oSubB_1 = ((io_oExecValid && parse_subValid_1) ? parse_subB_1 : 16'h0);
  assign io_oSubValid_2 = (io_oExecValid && parse_subValid_2);
  assign io_oSubO_2 = ((io_oExecValid && parse_subValid_2) ? parse_subO_2 : 16'h0);
  assign io_oSubA_2 = ((io_oExecValid && parse_subValid_2) ? parse_subA_2 : 16'h0);
  assign io_oSubB_2 = ((io_oExecValid && parse_subValid_2) ? parse_subB_2 : 16'h0);
  assign io_oSubValid_3 = (io_oExecValid && parse_subValid_3);
  assign io_oSubO_3 = ((io_oExecValid && parse_subValid_3) ? parse_subO_3 : 16'h0);
  assign io_oSubA_3 = ((io_oExecValid && parse_subValid_3) ? parse_subA_3 : 16'h0);
  assign io_oSubB_3 = ((io_oExecValid && parse_subValid_3) ? parse_subB_3 : 16'h0);
  assign io_oSubCount = (io_oExecValid ? parse_subCount : 3'b000);
  assign io_oOprefAValid = (io_oExecValid && parse_oprefAValid);
  assign io_oOprefALbid = ((io_oExecValid && parse_oprefAValid) ? parse_oprefALbid : 8'h0);
  assign io_oOprefASrcKind = ((io_oExecValid && parse_oprefAValid) ? parse_oprefASrcKind : 4'b0000);
  assign io_oOprefBValid = (io_oExecValid && parse_oprefBValid);
  assign io_oOprefBLbid = ((io_oExecValid && parse_oprefBValid) ? parse_oprefBLbid : 8'h0);
  assign io_oOprefBSrcKind = ((io_oExecValid && parse_oprefBValid) ? parse_oprefBSrcKind : 4'b0000);
  assign io_oPrecPresent = (io_oExecValid && parse_precPresent);
  assign io_oPrecMode = ((io_oExecValid && parse_precPresent) ? parse_precMode : 8'h0);
  assign io_oPrecDim = ((io_oExecValid && parse_precPresent) ? parse_precDim : 8'h0);
  assign io_oReasmBind_valid = (io_oExecValid && parse_acctgtPresent);
  assign io_oReasmBind_payload = ((io_oExecValid && parse_acctgtPresent) ? parse_acctgtLbid : 8'h0);
  assign when_Common_l259 = (io_iValid && judge_bodyMal);
  assign io_oFault = _zz_io_oFault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      _zz_io_oFault <= 1'b0;
    end else begin
      if(io_iFaultClear) begin
        _zz_io_oFault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_oFault <= 1'b1;
      end
    end
  end


endmodule

module DecodeWalk (
  input  wire          io_iValid,
  input  wire [31:0]   io_iInstr_0,
  input  wire [31:0]   io_iInstr_1,
  input  wire [31:0]   io_iInstr_2,
  input  wire [31:0]   io_iInstr_3,
  input  wire [31:0]   io_iInstr_4,
  input  wire [31:0]   io_iInstr_5,
  input  wire [31:0]   io_iInstr_6,
  input  wire [31:0]   io_iInstr_7,
  input  wire [31:0]   io_iInstr_8,
  input  wire [31:0]   io_iInstr_9,
  input  wire [31:0]   io_iInstr_10,
  input  wire [31:0]   io_iInstr_11,
  input  wire [31:0]   io_iInstr_12,
  input  wire          io_iFaultClear,
  output wire          io_oValid,
  output wire          io_oMalformed,
  output wire          io_oCapAbsent,
  output wire          io_oExecValid,
  output wire [31:0]   io_oInstr_0,
  output wire [31:0]   io_oInstr_1,
  output wire [31:0]   io_oInstr_2,
  output wire [31:0]   io_oInstr_3,
  output wire [31:0]   io_oInstr_4,
  output wire [31:0]   io_oInstr_5,
  output wire [31:0]   io_oInstr_6,
  output wire [31:0]   io_oInstr_7,
  output wire [31:0]   io_oInstr_8,
  output wire [31:0]   io_oInstr_9,
  output wire [31:0]   io_oInstr_10,
  output wire [31:0]   io_oInstr_11,
  output wire [31:0]   io_oInstr_12,
  output wire          io_oSlotPresent_0,
  output wire          io_oSlotPresent_1,
  output wire          io_oSlotPresent_2,
  output wire          io_oSlotPresent_3,
  output wire [3:0]    io_oSlotCode_0,
  output wire [3:0]    io_oSlotCode_1,
  output wire [3:0]    io_oSlotCode_2,
  output wire [3:0]    io_oSlotCode_3,
  output wire [7:0]    io_oSlotOff_0,
  output wire [7:0]    io_oSlotOff_1,
  output wire [7:0]    io_oSlotOff_2,
  output wire [7:0]    io_oSlotOff_3,
  output wire          io_oFault,
  input  wire          clk,
  input  wire          reset
);

  reg        [15:0]   _zz_walk_head_0;
  wire       [3:0]    _zz_walk_head_0_1;
  reg                 _zz_walk_defd_0;
  wire       [3:0]    _zz_walk_defd_0_1;
  reg        [7:0]    _zz_walk_stepW_0;
  wire       [3:0]    _zz_walk_stepW_0_1;
  reg        [15:0]   _zz_walk_head_1;
  wire       [3:0]    _zz_walk_head_1_1;
  reg                 _zz_walk_defd_1;
  wire       [3:0]    _zz_walk_defd_1_1;
  reg        [7:0]    _zz_walk_stepW_1;
  wire       [3:0]    _zz_walk_stepW_1_1;
  reg        [15:0]   _zz_walk_head_2;
  wire       [3:0]    _zz_walk_head_2_1;
  reg                 _zz_walk_defd_2;
  wire       [3:0]    _zz_walk_defd_2_1;
  reg        [7:0]    _zz_walk_stepW_2;
  wire       [3:0]    _zz_walk_stepW_2_1;
  reg        [15:0]   _zz_walk_head_3;
  wire       [3:0]    _zz_walk_head_3_1;
  reg                 _zz_walk_defd_3;
  wire       [3:0]    _zz_walk_defd_3_1;
  reg        [7:0]    _zz_walk_stepW_3;
  wire       [3:0]    _zz_walk_stepW_3_1;
  wire       [2:0]    _zz_judge_dupBad;
  wire       [2:0]    _zz_judge_dupBad_1;
  wire       [2:0]    _zz_judge_dupBad_2;
  wire       [2:0]    _zz_judge_dupBad_3;
  wire       [0:0]    _zz_judge_dupBad_4;
  wire       [2:0]    _zz_judge_dupBad_5;
  wire       [0:0]    _zz_judge_dupBad_6;
  wire       [2:0]    _zz_judge_dupBad_7;
  wire       [0:0]    _zz_judge_dupBad_8;
  wire       [2:0]    _zz_judge_dupBad_9;
  wire       [0:0]    _zz_judge_dupBad_10;
  wire       [2:0]    _zz_judge_dupBad_11;
  wire       [2:0]    _zz_judge_dupBad_12;
  wire       [2:0]    _zz_judge_dupBad_13;
  wire       [2:0]    _zz_judge_dupBad_14;
  wire       [0:0]    _zz_judge_dupBad_15;
  wire       [2:0]    _zz_judge_dupBad_16;
  wire       [0:0]    _zz_judge_dupBad_17;
  wire       [2:0]    _zz_judge_dupBad_18;
  wire       [0:0]    _zz_judge_dupBad_19;
  wire       [2:0]    _zz_judge_dupBad_20;
  wire       [0:0]    _zz_judge_dupBad_21;
  wire       [2:0]    _zz_judge_dupBad_22;
  wire       [2:0]    _zz_judge_dupBad_23;
  wire       [2:0]    _zz_judge_dupBad_24;
  wire       [2:0]    _zz_judge_dupBad_25;
  wire       [0:0]    _zz_judge_dupBad_26;
  wire       [2:0]    _zz_judge_dupBad_27;
  wire       [0:0]    _zz_judge_dupBad_28;
  wire       [2:0]    _zz_judge_dupBad_29;
  wire       [0:0]    _zz_judge_dupBad_30;
  wire       [2:0]    _zz_judge_dupBad_31;
  wire       [0:0]    _zz_judge_dupBad_32;
  wire       [2:0]    _zz_judge_dupBad_33;
  wire       [2:0]    _zz_judge_dupBad_34;
  wire       [2:0]    _zz_judge_dupBad_35;
  wire       [2:0]    _zz_judge_dupBad_36;
  wire       [0:0]    _zz_judge_dupBad_37;
  wire       [2:0]    _zz_judge_dupBad_38;
  wire       [0:0]    _zz_judge_dupBad_39;
  wire       [2:0]    _zz_judge_dupBad_40;
  wire       [0:0]    _zz_judge_dupBad_41;
  wire       [2:0]    _zz_judge_dupBad_42;
  wire       [0:0]    _zz_judge_dupBad_43;
  wire       [2:0]    _zz_judge_dupBad_44;
  wire       [2:0]    _zz_judge_dupBad_45;
  wire       [2:0]    _zz_judge_dupBad_46;
  wire       [2:0]    _zz_judge_dupBad_47;
  wire       [0:0]    _zz_judge_dupBad_48;
  wire       [2:0]    _zz_judge_dupBad_49;
  wire       [0:0]    _zz_judge_dupBad_50;
  wire       [2:0]    _zz_judge_dupBad_51;
  wire       [0:0]    _zz_judge_dupBad_52;
  wire       [2:0]    _zz_judge_dupBad_53;
  wire       [0:0]    _zz_judge_dupBad_54;
  wire       [2:0]    _zz_judge_dupBad_55;
  wire       [2:0]    _zz_judge_dupBad_56;
  wire       [2:0]    _zz_judge_dupBad_57;
  wire       [2:0]    _zz_judge_dupBad_58;
  wire       [0:0]    _zz_judge_dupBad_59;
  wire       [2:0]    _zz_judge_dupBad_60;
  wire       [0:0]    _zz_judge_dupBad_61;
  wire       [2:0]    _zz_judge_dupBad_62;
  wire       [0:0]    _zz_judge_dupBad_63;
  wire       [2:0]    _zz_judge_dupBad_64;
  wire       [0:0]    _zz_judge_dupBad_65;
  wire       [2:0]    _zz_judge_dupBad_66;
  wire       [2:0]    _zz_judge_dupBad_67;
  wire       [2:0]    _zz_judge_dupBad_68;
  wire       [2:0]    _zz_judge_dupBad_69;
  wire       [0:0]    _zz_judge_dupBad_70;
  wire       [2:0]    _zz_judge_dupBad_71;
  wire       [0:0]    _zz_judge_dupBad_72;
  wire       [2:0]    _zz_judge_dupBad_73;
  wire       [0:0]    _zz_judge_dupBad_74;
  wire       [2:0]    _zz_judge_dupBad_75;
  wire       [0:0]    _zz_judge_dupBad_76;
  wire       [2:0]    _zz_judge_dupBad_77;
  wire       [2:0]    _zz_judge_dupBad_78;
  wire       [2:0]    _zz_judge_dupBad_79;
  wire       [2:0]    _zz_judge_dupBad_80;
  wire       [0:0]    _zz_judge_dupBad_81;
  wire       [2:0]    _zz_judge_dupBad_82;
  wire       [0:0]    _zz_judge_dupBad_83;
  wire       [2:0]    _zz_judge_dupBad_84;
  wire       [0:0]    _zz_judge_dupBad_85;
  wire       [2:0]    _zz_judge_dupBad_86;
  wire       [0:0]    _zz_judge_dupBad_87;
  wire                kindDefined_0;
  wire                kindDefined_1;
  wire                kindDefined_2;
  wire                kindDefined_3;
  wire                kindDefined_4;
  wire                kindDefined_5;
  wire                kindDefined_6;
  wire                kindDefined_7;
  wire                kindDefined_8;
  wire                kindDefined_9;
  wire                kindDefined_10;
  wire                kindDefined_11;
  wire                kindDefined_12;
  wire                kindDefined_13;
  wire                kindDefined_14;
  wire                kindDefined_15;
  wire       [7:0]    kindWords_0;
  wire       [7:0]    kindWords_1;
  wire       [7:0]    kindWords_2;
  wire       [7:0]    kindWords_3;
  wire       [7:0]    kindWords_4;
  wire       [7:0]    kindWords_5;
  wire       [7:0]    kindWords_6;
  wire       [7:0]    kindWords_7;
  wire       [7:0]    kindWords_8;
  wire       [7:0]    kindWords_9;
  wire       [7:0]    kindWords_10;
  wire       [7:0]    kindWords_11;
  wire       [7:0]    kindWords_12;
  wire       [7:0]    kindWords_13;
  wire       [7:0]    kindWords_14;
  wire       [7:0]    kindWords_15;
  wire       [15:0]   walk_lo16_0;
  wire       [15:0]   walk_lo16_1;
  wire       [15:0]   walk_lo16_2;
  wire       [15:0]   walk_lo16_3;
  wire       [15:0]   walk_lo16_4;
  wire       [15:0]   walk_lo16_5;
  wire       [15:0]   walk_lo16_6;
  wire       [15:0]   walk_lo16_7;
  wire       [15:0]   walk_lo16_8;
  wire       [15:0]   walk_lo16_9;
  wire       [15:0]   walk_lo16_10;
  wire       [15:0]   walk_lo16_11;
  wire       [15:0]   walk_lo16_12;
  wire       [3:0]    walk_ptr_0;
  wire       [3:0]    walk_ptr_1;
  wire       [3:0]    walk_ptr_2;
  wire       [3:0]    walk_ptr_3;
  wire       [3:0]    walk_ptr_4;
  wire                walk_ended_0;
  wire                walk_ended_1;
  wire                walk_ended_2;
  wire                walk_ended_3;
  wire                walk_ended_4;
  wire                walk_walked_0;
  wire                walk_walked_1;
  wire                walk_walked_2;
  wire                walk_walked_3;
  wire       [7:0]    walk_off_0;
  wire       [7:0]    walk_off_1;
  wire       [7:0]    walk_off_2;
  wire       [7:0]    walk_off_3;
  wire       [7:0]    walk_off_4;
  wire       [15:0]   walk_head_0;
  wire       [15:0]   walk_head_1;
  wire       [15:0]   walk_head_2;
  wire       [15:0]   walk_head_3;
  wire       [3:0]    walk_selfCode_0;
  wire       [3:0]    walk_selfCode_1;
  wire       [3:0]    walk_selfCode_2;
  wire       [3:0]    walk_selfCode_3;
  wire       [7:0]    walk_wordsFld_0;
  wire       [7:0]    walk_wordsFld_1;
  wire       [7:0]    walk_wordsFld_2;
  wire       [7:0]    walk_wordsFld_3;
  wire                walk_defd_0;
  wire                walk_defd_1;
  wire                walk_defd_2;
  wire                walk_defd_3;
  wire       [7:0]    walk_stepW_0;
  wire       [7:0]    walk_stepW_1;
  wire       [7:0]    walk_stepW_2;
  wire       [7:0]    walk_stepW_3;
  wire       [7:0]    judge_declLen;
  wire       [7:0]    judge_resvFld;
  wire                judge_capAbsent;
  wire                judge_lenBad;
  wire                judge_capBad;
  wire                judge_junkBad;
  wire                judge_selfBad;
  wire                judge_wordsBad;
  wire                judge_dupBad;
  wire                judge_resvBad;
  wire                judge_mal;
  reg                 outStage_rValid;
  reg                 outStage_rMal;
  reg                 outStage_rCapa;
  reg        [31:0]   outStage_masked_0;
  wire       [31:0]   outStage_masked_1;
  wire       [31:0]   outStage_masked_2;
  wire       [31:0]   outStage_masked_3;
  wire       [31:0]   outStage_masked_4;
  wire       [31:0]   outStage_masked_5;
  wire       [31:0]   outStage_masked_6;
  wire       [31:0]   outStage_masked_7;
  wire       [31:0]   outStage_masked_8;
  wire       [31:0]   outStage_masked_9;
  wire       [31:0]   outStage_masked_10;
  wire       [31:0]   outStage_masked_11;
  wire       [31:0]   outStage_masked_12;
  reg        [31:0]   outStage_rInstr_0;
  reg        [31:0]   outStage_rInstr_1;
  reg        [31:0]   outStage_rInstr_2;
  reg        [31:0]   outStage_rInstr_3;
  reg        [31:0]   outStage_rInstr_4;
  reg        [31:0]   outStage_rInstr_5;
  reg        [31:0]   outStage_rInstr_6;
  reg        [31:0]   outStage_rInstr_7;
  reg        [31:0]   outStage_rInstr_8;
  reg        [31:0]   outStage_rInstr_9;
  reg        [31:0]   outStage_rInstr_10;
  reg        [31:0]   outStage_rInstr_11;
  reg        [31:0]   outStage_rInstr_12;
  reg                 outStage_rPresent_0;
  reg                 outStage_rPresent_1;
  reg                 outStage_rPresent_2;
  reg                 outStage_rPresent_3;
  reg        [3:0]    outStage_rCode_0;
  reg        [3:0]    outStage_rCode_1;
  reg        [3:0]    outStage_rCode_2;
  reg        [3:0]    outStage_rCode_3;
  reg        [7:0]    outStage_rOff_0;
  reg        [7:0]    outStage_rOff_1;
  reg        [7:0]    outStage_rOff_2;
  reg        [7:0]    outStage_rOff_3;
  wire                when_Common_l259;
  reg                 _zz_io_oFault;

  assign _zz_walk_head_0_1 = walk_off_0[3:0];
  assign _zz_walk_head_1_1 = walk_off_1[3:0];
  assign _zz_walk_head_2_1 = walk_off_2[3:0];
  assign _zz_walk_head_3_1 = walk_off_3[3:0];
  assign _zz_judge_dupBad = (_zz_judge_dupBad_1 + _zz_judge_dupBad_9);
  assign _zz_judge_dupBad_1 = (_zz_judge_dupBad_2 + _zz_judge_dupBad_7);
  assign _zz_judge_dupBad_2 = (_zz_judge_dupBad_3 + _zz_judge_dupBad_5);
  assign _zz_judge_dupBad_4 = (walk_walked_0 && (walk_ptr_0 == 4'b0101));
  assign _zz_judge_dupBad_3 = {2'd0, _zz_judge_dupBad_4};
  assign _zz_judge_dupBad_6 = (walk_walked_1 && (walk_ptr_1 == 4'b0101));
  assign _zz_judge_dupBad_5 = {2'd0, _zz_judge_dupBad_6};
  assign _zz_judge_dupBad_8 = (walk_walked_2 && (walk_ptr_2 == 4'b0101));
  assign _zz_judge_dupBad_7 = {2'd0, _zz_judge_dupBad_8};
  assign _zz_judge_dupBad_10 = (walk_walked_3 && (walk_ptr_3 == 4'b0101));
  assign _zz_judge_dupBad_9 = {2'd0, _zz_judge_dupBad_10};
  assign _zz_judge_dupBad_11 = (_zz_judge_dupBad_12 + _zz_judge_dupBad_20);
  assign _zz_judge_dupBad_12 = (_zz_judge_dupBad_13 + _zz_judge_dupBad_18);
  assign _zz_judge_dupBad_13 = (_zz_judge_dupBad_14 + _zz_judge_dupBad_16);
  assign _zz_judge_dupBad_15 = (walk_walked_0 && (walk_ptr_0 == 4'b0001));
  assign _zz_judge_dupBad_14 = {2'd0, _zz_judge_dupBad_15};
  assign _zz_judge_dupBad_17 = (walk_walked_1 && (walk_ptr_1 == 4'b0001));
  assign _zz_judge_dupBad_16 = {2'd0, _zz_judge_dupBad_17};
  assign _zz_judge_dupBad_19 = (walk_walked_2 && (walk_ptr_2 == 4'b0001));
  assign _zz_judge_dupBad_18 = {2'd0, _zz_judge_dupBad_19};
  assign _zz_judge_dupBad_21 = (walk_walked_3 && (walk_ptr_3 == 4'b0001));
  assign _zz_judge_dupBad_20 = {2'd0, _zz_judge_dupBad_21};
  assign _zz_judge_dupBad_22 = (_zz_judge_dupBad_23 + _zz_judge_dupBad_31);
  assign _zz_judge_dupBad_23 = (_zz_judge_dupBad_24 + _zz_judge_dupBad_29);
  assign _zz_judge_dupBad_24 = (_zz_judge_dupBad_25 + _zz_judge_dupBad_27);
  assign _zz_judge_dupBad_26 = (walk_walked_0 && (walk_ptr_0 == 4'b1001));
  assign _zz_judge_dupBad_25 = {2'd0, _zz_judge_dupBad_26};
  assign _zz_judge_dupBad_28 = (walk_walked_1 && (walk_ptr_1 == 4'b1001));
  assign _zz_judge_dupBad_27 = {2'd0, _zz_judge_dupBad_28};
  assign _zz_judge_dupBad_30 = (walk_walked_2 && (walk_ptr_2 == 4'b1001));
  assign _zz_judge_dupBad_29 = {2'd0, _zz_judge_dupBad_30};
  assign _zz_judge_dupBad_32 = (walk_walked_3 && (walk_ptr_3 == 4'b1001));
  assign _zz_judge_dupBad_31 = {2'd0, _zz_judge_dupBad_32};
  assign _zz_judge_dupBad_33 = (_zz_judge_dupBad_34 + _zz_judge_dupBad_42);
  assign _zz_judge_dupBad_34 = (_zz_judge_dupBad_35 + _zz_judge_dupBad_40);
  assign _zz_judge_dupBad_35 = (_zz_judge_dupBad_36 + _zz_judge_dupBad_38);
  assign _zz_judge_dupBad_37 = (walk_walked_0 && (walk_ptr_0 == 4'b0010));
  assign _zz_judge_dupBad_36 = {2'd0, _zz_judge_dupBad_37};
  assign _zz_judge_dupBad_39 = (walk_walked_1 && (walk_ptr_1 == 4'b0010));
  assign _zz_judge_dupBad_38 = {2'd0, _zz_judge_dupBad_39};
  assign _zz_judge_dupBad_41 = (walk_walked_2 && (walk_ptr_2 == 4'b0010));
  assign _zz_judge_dupBad_40 = {2'd0, _zz_judge_dupBad_41};
  assign _zz_judge_dupBad_43 = (walk_walked_3 && (walk_ptr_3 == 4'b0010));
  assign _zz_judge_dupBad_42 = {2'd0, _zz_judge_dupBad_43};
  assign _zz_judge_dupBad_44 = (_zz_judge_dupBad_45 + _zz_judge_dupBad_53);
  assign _zz_judge_dupBad_45 = (_zz_judge_dupBad_46 + _zz_judge_dupBad_51);
  assign _zz_judge_dupBad_46 = (_zz_judge_dupBad_47 + _zz_judge_dupBad_49);
  assign _zz_judge_dupBad_48 = (walk_walked_0 && (walk_ptr_0 == 4'b0111));
  assign _zz_judge_dupBad_47 = {2'd0, _zz_judge_dupBad_48};
  assign _zz_judge_dupBad_50 = (walk_walked_1 && (walk_ptr_1 == 4'b0111));
  assign _zz_judge_dupBad_49 = {2'd0, _zz_judge_dupBad_50};
  assign _zz_judge_dupBad_52 = (walk_walked_2 && (walk_ptr_2 == 4'b0111));
  assign _zz_judge_dupBad_51 = {2'd0, _zz_judge_dupBad_52};
  assign _zz_judge_dupBad_54 = (walk_walked_3 && (walk_ptr_3 == 4'b0111));
  assign _zz_judge_dupBad_53 = {2'd0, _zz_judge_dupBad_54};
  assign _zz_judge_dupBad_55 = (_zz_judge_dupBad_56 + _zz_judge_dupBad_64);
  assign _zz_judge_dupBad_56 = (_zz_judge_dupBad_57 + _zz_judge_dupBad_62);
  assign _zz_judge_dupBad_57 = (_zz_judge_dupBad_58 + _zz_judge_dupBad_60);
  assign _zz_judge_dupBad_59 = (walk_walked_0 && (walk_ptr_0 == 4'b0011));
  assign _zz_judge_dupBad_58 = {2'd0, _zz_judge_dupBad_59};
  assign _zz_judge_dupBad_61 = (walk_walked_1 && (walk_ptr_1 == 4'b0011));
  assign _zz_judge_dupBad_60 = {2'd0, _zz_judge_dupBad_61};
  assign _zz_judge_dupBad_63 = (walk_walked_2 && (walk_ptr_2 == 4'b0011));
  assign _zz_judge_dupBad_62 = {2'd0, _zz_judge_dupBad_63};
  assign _zz_judge_dupBad_65 = (walk_walked_3 && (walk_ptr_3 == 4'b0011));
  assign _zz_judge_dupBad_64 = {2'd0, _zz_judge_dupBad_65};
  assign _zz_judge_dupBad_66 = (_zz_judge_dupBad_67 + _zz_judge_dupBad_75);
  assign _zz_judge_dupBad_67 = (_zz_judge_dupBad_68 + _zz_judge_dupBad_73);
  assign _zz_judge_dupBad_68 = (_zz_judge_dupBad_69 + _zz_judge_dupBad_71);
  assign _zz_judge_dupBad_70 = (walk_walked_0 && (walk_ptr_0 == 4'b1000));
  assign _zz_judge_dupBad_69 = {2'd0, _zz_judge_dupBad_70};
  assign _zz_judge_dupBad_72 = (walk_walked_1 && (walk_ptr_1 == 4'b1000));
  assign _zz_judge_dupBad_71 = {2'd0, _zz_judge_dupBad_72};
  assign _zz_judge_dupBad_74 = (walk_walked_2 && (walk_ptr_2 == 4'b1000));
  assign _zz_judge_dupBad_73 = {2'd0, _zz_judge_dupBad_74};
  assign _zz_judge_dupBad_76 = (walk_walked_3 && (walk_ptr_3 == 4'b1000));
  assign _zz_judge_dupBad_75 = {2'd0, _zz_judge_dupBad_76};
  assign _zz_judge_dupBad_77 = (_zz_judge_dupBad_78 + _zz_judge_dupBad_86);
  assign _zz_judge_dupBad_78 = (_zz_judge_dupBad_79 + _zz_judge_dupBad_84);
  assign _zz_judge_dupBad_79 = (_zz_judge_dupBad_80 + _zz_judge_dupBad_82);
  assign _zz_judge_dupBad_81 = (walk_walked_0 && (walk_ptr_0 == 4'b0100));
  assign _zz_judge_dupBad_80 = {2'd0, _zz_judge_dupBad_81};
  assign _zz_judge_dupBad_83 = (walk_walked_1 && (walk_ptr_1 == 4'b0100));
  assign _zz_judge_dupBad_82 = {2'd0, _zz_judge_dupBad_83};
  assign _zz_judge_dupBad_85 = (walk_walked_2 && (walk_ptr_2 == 4'b0100));
  assign _zz_judge_dupBad_84 = {2'd0, _zz_judge_dupBad_85};
  assign _zz_judge_dupBad_87 = (walk_walked_3 && (walk_ptr_3 == 4'b0100));
  assign _zz_judge_dupBad_86 = {2'd0, _zz_judge_dupBad_87};
  assign _zz_walk_defd_0_1 = walk_ptr_0;
  assign _zz_walk_stepW_0_1 = walk_ptr_0;
  assign _zz_walk_defd_1_1 = walk_ptr_1;
  assign _zz_walk_stepW_1_1 = walk_ptr_1;
  assign _zz_walk_defd_2_1 = walk_ptr_2;
  assign _zz_walk_stepW_2_1 = walk_ptr_2;
  assign _zz_walk_defd_3_1 = walk_ptr_3;
  assign _zz_walk_stepW_3_1 = walk_ptr_3;
  always @(*) begin
    case(_zz_walk_head_0_1)
      4'b0000 : _zz_walk_head_0 = walk_lo16_0;
      4'b0001 : _zz_walk_head_0 = walk_lo16_1;
      4'b0010 : _zz_walk_head_0 = walk_lo16_2;
      4'b0011 : _zz_walk_head_0 = walk_lo16_3;
      4'b0100 : _zz_walk_head_0 = walk_lo16_4;
      4'b0101 : _zz_walk_head_0 = walk_lo16_5;
      4'b0110 : _zz_walk_head_0 = walk_lo16_6;
      4'b0111 : _zz_walk_head_0 = walk_lo16_7;
      4'b1000 : _zz_walk_head_0 = walk_lo16_8;
      4'b1001 : _zz_walk_head_0 = walk_lo16_9;
      4'b1010 : _zz_walk_head_0 = walk_lo16_10;
      4'b1011 : _zz_walk_head_0 = walk_lo16_11;
      default : _zz_walk_head_0 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_0_1)
      4'b0000 : _zz_walk_defd_0 = kindDefined_0;
      4'b0001 : _zz_walk_defd_0 = kindDefined_1;
      4'b0010 : _zz_walk_defd_0 = kindDefined_2;
      4'b0011 : _zz_walk_defd_0 = kindDefined_3;
      4'b0100 : _zz_walk_defd_0 = kindDefined_4;
      4'b0101 : _zz_walk_defd_0 = kindDefined_5;
      4'b0110 : _zz_walk_defd_0 = kindDefined_6;
      4'b0111 : _zz_walk_defd_0 = kindDefined_7;
      4'b1000 : _zz_walk_defd_0 = kindDefined_8;
      4'b1001 : _zz_walk_defd_0 = kindDefined_9;
      4'b1010 : _zz_walk_defd_0 = kindDefined_10;
      4'b1011 : _zz_walk_defd_0 = kindDefined_11;
      4'b1100 : _zz_walk_defd_0 = kindDefined_12;
      4'b1101 : _zz_walk_defd_0 = kindDefined_13;
      4'b1110 : _zz_walk_defd_0 = kindDefined_14;
      default : _zz_walk_defd_0 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_0_1)
      4'b0000 : _zz_walk_stepW_0 = kindWords_0;
      4'b0001 : _zz_walk_stepW_0 = kindWords_1;
      4'b0010 : _zz_walk_stepW_0 = kindWords_2;
      4'b0011 : _zz_walk_stepW_0 = kindWords_3;
      4'b0100 : _zz_walk_stepW_0 = kindWords_4;
      4'b0101 : _zz_walk_stepW_0 = kindWords_5;
      4'b0110 : _zz_walk_stepW_0 = kindWords_6;
      4'b0111 : _zz_walk_stepW_0 = kindWords_7;
      4'b1000 : _zz_walk_stepW_0 = kindWords_8;
      4'b1001 : _zz_walk_stepW_0 = kindWords_9;
      4'b1010 : _zz_walk_stepW_0 = kindWords_10;
      4'b1011 : _zz_walk_stepW_0 = kindWords_11;
      4'b1100 : _zz_walk_stepW_0 = kindWords_12;
      4'b1101 : _zz_walk_stepW_0 = kindWords_13;
      4'b1110 : _zz_walk_stepW_0 = kindWords_14;
      default : _zz_walk_stepW_0 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_1_1)
      4'b0000 : _zz_walk_head_1 = walk_lo16_0;
      4'b0001 : _zz_walk_head_1 = walk_lo16_1;
      4'b0010 : _zz_walk_head_1 = walk_lo16_2;
      4'b0011 : _zz_walk_head_1 = walk_lo16_3;
      4'b0100 : _zz_walk_head_1 = walk_lo16_4;
      4'b0101 : _zz_walk_head_1 = walk_lo16_5;
      4'b0110 : _zz_walk_head_1 = walk_lo16_6;
      4'b0111 : _zz_walk_head_1 = walk_lo16_7;
      4'b1000 : _zz_walk_head_1 = walk_lo16_8;
      4'b1001 : _zz_walk_head_1 = walk_lo16_9;
      4'b1010 : _zz_walk_head_1 = walk_lo16_10;
      4'b1011 : _zz_walk_head_1 = walk_lo16_11;
      default : _zz_walk_head_1 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_1_1)
      4'b0000 : _zz_walk_defd_1 = kindDefined_0;
      4'b0001 : _zz_walk_defd_1 = kindDefined_1;
      4'b0010 : _zz_walk_defd_1 = kindDefined_2;
      4'b0011 : _zz_walk_defd_1 = kindDefined_3;
      4'b0100 : _zz_walk_defd_1 = kindDefined_4;
      4'b0101 : _zz_walk_defd_1 = kindDefined_5;
      4'b0110 : _zz_walk_defd_1 = kindDefined_6;
      4'b0111 : _zz_walk_defd_1 = kindDefined_7;
      4'b1000 : _zz_walk_defd_1 = kindDefined_8;
      4'b1001 : _zz_walk_defd_1 = kindDefined_9;
      4'b1010 : _zz_walk_defd_1 = kindDefined_10;
      4'b1011 : _zz_walk_defd_1 = kindDefined_11;
      4'b1100 : _zz_walk_defd_1 = kindDefined_12;
      4'b1101 : _zz_walk_defd_1 = kindDefined_13;
      4'b1110 : _zz_walk_defd_1 = kindDefined_14;
      default : _zz_walk_defd_1 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_1_1)
      4'b0000 : _zz_walk_stepW_1 = kindWords_0;
      4'b0001 : _zz_walk_stepW_1 = kindWords_1;
      4'b0010 : _zz_walk_stepW_1 = kindWords_2;
      4'b0011 : _zz_walk_stepW_1 = kindWords_3;
      4'b0100 : _zz_walk_stepW_1 = kindWords_4;
      4'b0101 : _zz_walk_stepW_1 = kindWords_5;
      4'b0110 : _zz_walk_stepW_1 = kindWords_6;
      4'b0111 : _zz_walk_stepW_1 = kindWords_7;
      4'b1000 : _zz_walk_stepW_1 = kindWords_8;
      4'b1001 : _zz_walk_stepW_1 = kindWords_9;
      4'b1010 : _zz_walk_stepW_1 = kindWords_10;
      4'b1011 : _zz_walk_stepW_1 = kindWords_11;
      4'b1100 : _zz_walk_stepW_1 = kindWords_12;
      4'b1101 : _zz_walk_stepW_1 = kindWords_13;
      4'b1110 : _zz_walk_stepW_1 = kindWords_14;
      default : _zz_walk_stepW_1 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_2_1)
      4'b0000 : _zz_walk_head_2 = walk_lo16_0;
      4'b0001 : _zz_walk_head_2 = walk_lo16_1;
      4'b0010 : _zz_walk_head_2 = walk_lo16_2;
      4'b0011 : _zz_walk_head_2 = walk_lo16_3;
      4'b0100 : _zz_walk_head_2 = walk_lo16_4;
      4'b0101 : _zz_walk_head_2 = walk_lo16_5;
      4'b0110 : _zz_walk_head_2 = walk_lo16_6;
      4'b0111 : _zz_walk_head_2 = walk_lo16_7;
      4'b1000 : _zz_walk_head_2 = walk_lo16_8;
      4'b1001 : _zz_walk_head_2 = walk_lo16_9;
      4'b1010 : _zz_walk_head_2 = walk_lo16_10;
      4'b1011 : _zz_walk_head_2 = walk_lo16_11;
      default : _zz_walk_head_2 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_2_1)
      4'b0000 : _zz_walk_defd_2 = kindDefined_0;
      4'b0001 : _zz_walk_defd_2 = kindDefined_1;
      4'b0010 : _zz_walk_defd_2 = kindDefined_2;
      4'b0011 : _zz_walk_defd_2 = kindDefined_3;
      4'b0100 : _zz_walk_defd_2 = kindDefined_4;
      4'b0101 : _zz_walk_defd_2 = kindDefined_5;
      4'b0110 : _zz_walk_defd_2 = kindDefined_6;
      4'b0111 : _zz_walk_defd_2 = kindDefined_7;
      4'b1000 : _zz_walk_defd_2 = kindDefined_8;
      4'b1001 : _zz_walk_defd_2 = kindDefined_9;
      4'b1010 : _zz_walk_defd_2 = kindDefined_10;
      4'b1011 : _zz_walk_defd_2 = kindDefined_11;
      4'b1100 : _zz_walk_defd_2 = kindDefined_12;
      4'b1101 : _zz_walk_defd_2 = kindDefined_13;
      4'b1110 : _zz_walk_defd_2 = kindDefined_14;
      default : _zz_walk_defd_2 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_2_1)
      4'b0000 : _zz_walk_stepW_2 = kindWords_0;
      4'b0001 : _zz_walk_stepW_2 = kindWords_1;
      4'b0010 : _zz_walk_stepW_2 = kindWords_2;
      4'b0011 : _zz_walk_stepW_2 = kindWords_3;
      4'b0100 : _zz_walk_stepW_2 = kindWords_4;
      4'b0101 : _zz_walk_stepW_2 = kindWords_5;
      4'b0110 : _zz_walk_stepW_2 = kindWords_6;
      4'b0111 : _zz_walk_stepW_2 = kindWords_7;
      4'b1000 : _zz_walk_stepW_2 = kindWords_8;
      4'b1001 : _zz_walk_stepW_2 = kindWords_9;
      4'b1010 : _zz_walk_stepW_2 = kindWords_10;
      4'b1011 : _zz_walk_stepW_2 = kindWords_11;
      4'b1100 : _zz_walk_stepW_2 = kindWords_12;
      4'b1101 : _zz_walk_stepW_2 = kindWords_13;
      4'b1110 : _zz_walk_stepW_2 = kindWords_14;
      default : _zz_walk_stepW_2 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_3_1)
      4'b0000 : _zz_walk_head_3 = walk_lo16_0;
      4'b0001 : _zz_walk_head_3 = walk_lo16_1;
      4'b0010 : _zz_walk_head_3 = walk_lo16_2;
      4'b0011 : _zz_walk_head_3 = walk_lo16_3;
      4'b0100 : _zz_walk_head_3 = walk_lo16_4;
      4'b0101 : _zz_walk_head_3 = walk_lo16_5;
      4'b0110 : _zz_walk_head_3 = walk_lo16_6;
      4'b0111 : _zz_walk_head_3 = walk_lo16_7;
      4'b1000 : _zz_walk_head_3 = walk_lo16_8;
      4'b1001 : _zz_walk_head_3 = walk_lo16_9;
      4'b1010 : _zz_walk_head_3 = walk_lo16_10;
      4'b1011 : _zz_walk_head_3 = walk_lo16_11;
      default : _zz_walk_head_3 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_3_1)
      4'b0000 : _zz_walk_defd_3 = kindDefined_0;
      4'b0001 : _zz_walk_defd_3 = kindDefined_1;
      4'b0010 : _zz_walk_defd_3 = kindDefined_2;
      4'b0011 : _zz_walk_defd_3 = kindDefined_3;
      4'b0100 : _zz_walk_defd_3 = kindDefined_4;
      4'b0101 : _zz_walk_defd_3 = kindDefined_5;
      4'b0110 : _zz_walk_defd_3 = kindDefined_6;
      4'b0111 : _zz_walk_defd_3 = kindDefined_7;
      4'b1000 : _zz_walk_defd_3 = kindDefined_8;
      4'b1001 : _zz_walk_defd_3 = kindDefined_9;
      4'b1010 : _zz_walk_defd_3 = kindDefined_10;
      4'b1011 : _zz_walk_defd_3 = kindDefined_11;
      4'b1100 : _zz_walk_defd_3 = kindDefined_12;
      4'b1101 : _zz_walk_defd_3 = kindDefined_13;
      4'b1110 : _zz_walk_defd_3 = kindDefined_14;
      default : _zz_walk_defd_3 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_3_1)
      4'b0000 : _zz_walk_stepW_3 = kindWords_0;
      4'b0001 : _zz_walk_stepW_3 = kindWords_1;
      4'b0010 : _zz_walk_stepW_3 = kindWords_2;
      4'b0011 : _zz_walk_stepW_3 = kindWords_3;
      4'b0100 : _zz_walk_stepW_3 = kindWords_4;
      4'b0101 : _zz_walk_stepW_3 = kindWords_5;
      4'b0110 : _zz_walk_stepW_3 = kindWords_6;
      4'b0111 : _zz_walk_stepW_3 = kindWords_7;
      4'b1000 : _zz_walk_stepW_3 = kindWords_8;
      4'b1001 : _zz_walk_stepW_3 = kindWords_9;
      4'b1010 : _zz_walk_stepW_3 = kindWords_10;
      4'b1011 : _zz_walk_stepW_3 = kindWords_11;
      4'b1100 : _zz_walk_stepW_3 = kindWords_12;
      4'b1101 : _zz_walk_stepW_3 = kindWords_13;
      4'b1110 : _zz_walk_stepW_3 = kindWords_14;
      default : _zz_walk_stepW_3 = kindWords_15;
    endcase
  end

  assign kindDefined_0 = 1'b0;
  assign kindDefined_1 = 1'b1;
  assign kindDefined_2 = 1'b1;
  assign kindDefined_3 = 1'b1;
  assign kindDefined_4 = 1'b1;
  assign kindDefined_5 = 1'b1;
  assign kindDefined_6 = 1'b1;
  assign kindDefined_7 = 1'b1;
  assign kindDefined_8 = 1'b1;
  assign kindDefined_9 = 1'b1;
  assign kindDefined_10 = 1'b0;
  assign kindDefined_11 = 1'b0;
  assign kindDefined_12 = 1'b0;
  assign kindDefined_13 = 1'b0;
  assign kindDefined_14 = 1'b0;
  assign kindDefined_15 = 1'b1;
  assign kindWords_0 = 8'h01;
  assign kindWords_1 = 8'h01;
  assign kindWords_2 = 8'h01;
  assign kindWords_3 = 8'h02;
  assign kindWords_4 = 8'h03;
  assign kindWords_5 = 8'h02;
  assign kindWords_6 = 8'h02;
  assign kindWords_7 = 8'h01;
  assign kindWords_8 = 8'h01;
  assign kindWords_9 = 8'h01;
  assign kindWords_10 = 8'h01;
  assign kindWords_11 = 8'h01;
  assign kindWords_12 = 8'h01;
  assign kindWords_13 = 8'h01;
  assign kindWords_14 = 8'h01;
  assign kindWords_15 = 8'h01;
  assign walk_lo16_0 = io_iInstr_0[15 : 0];
  assign walk_lo16_1 = io_iInstr_1[15 : 0];
  assign walk_lo16_2 = io_iInstr_2[15 : 0];
  assign walk_lo16_3 = io_iInstr_3[15 : 0];
  assign walk_lo16_4 = io_iInstr_4[15 : 0];
  assign walk_lo16_5 = io_iInstr_5[15 : 0];
  assign walk_lo16_6 = io_iInstr_6[15 : 0];
  assign walk_lo16_7 = io_iInstr_7[15 : 0];
  assign walk_lo16_8 = io_iInstr_8[15 : 0];
  assign walk_lo16_9 = io_iInstr_9[15 : 0];
  assign walk_lo16_10 = io_iInstr_10[15 : 0];
  assign walk_lo16_11 = io_iInstr_11[15 : 0];
  assign walk_lo16_12 = io_iInstr_12[15 : 0];
  assign walk_ptr_0 = io_iInstr_0[23 : 20];
  assign walk_ended_0 = (walk_ptr_0 == 4'b0000);
  assign walk_off_0 = 8'h01;
  assign walk_walked_0 = (! walk_ended_0);
  assign walk_head_0 = _zz_walk_head_0;
  assign walk_selfCode_0 = walk_head_0[11 : 8];
  assign walk_wordsFld_0 = walk_head_0[7 : 0];
  assign walk_defd_0 = _zz_walk_defd_0;
  assign walk_stepW_0 = _zz_walk_stepW_0;
  assign walk_ptr_1 = walk_head_0[15 : 12];
  assign walk_ended_1 = (walk_ended_0 || (walk_ptr_1 == 4'b0000));
  assign walk_off_1 = (walk_off_0 + (walk_walked_0 ? walk_stepW_0 : 8'h0));
  assign walk_walked_1 = (! walk_ended_1);
  assign walk_head_1 = _zz_walk_head_1;
  assign walk_selfCode_1 = walk_head_1[11 : 8];
  assign walk_wordsFld_1 = walk_head_1[7 : 0];
  assign walk_defd_1 = _zz_walk_defd_1;
  assign walk_stepW_1 = _zz_walk_stepW_1;
  assign walk_ptr_2 = walk_head_1[15 : 12];
  assign walk_ended_2 = (walk_ended_1 || (walk_ptr_2 == 4'b0000));
  assign walk_off_2 = (walk_off_1 + (walk_walked_1 ? walk_stepW_1 : 8'h0));
  assign walk_walked_2 = (! walk_ended_2);
  assign walk_head_2 = _zz_walk_head_2;
  assign walk_selfCode_2 = walk_head_2[11 : 8];
  assign walk_wordsFld_2 = walk_head_2[7 : 0];
  assign walk_defd_2 = _zz_walk_defd_2;
  assign walk_stepW_2 = _zz_walk_stepW_2;
  assign walk_ptr_3 = walk_head_2[15 : 12];
  assign walk_ended_3 = (walk_ended_2 || (walk_ptr_3 == 4'b0000));
  assign walk_off_3 = (walk_off_2 + (walk_walked_2 ? walk_stepW_2 : 8'h0));
  assign walk_walked_3 = (! walk_ended_3);
  assign walk_head_3 = _zz_walk_head_3;
  assign walk_selfCode_3 = walk_head_3[11 : 8];
  assign walk_wordsFld_3 = walk_head_3[7 : 0];
  assign walk_defd_3 = _zz_walk_defd_3;
  assign walk_stepW_3 = _zz_walk_stepW_3;
  assign walk_ptr_4 = walk_head_3[15 : 12];
  assign walk_ended_4 = (walk_ended_3 || (walk_ptr_4 == 4'b0000));
  assign walk_off_4 = (walk_off_3 + (walk_walked_3 ? walk_stepW_3 : 8'h0));
  assign judge_declLen = io_iInstr_0[7 : 0];
  assign judge_resvFld = io_iInstr_0[15 : 8];
  assign judge_capAbsent = (8'h0d < judge_declLen);
  assign judge_lenBad = (walk_ended_4 && (judge_declLen != walk_off_4));
  assign judge_capBad = ((! judge_capAbsent) && (! walk_ended_4));
  assign judge_junkBad = ((((walk_walked_0 && (! walk_defd_0)) || (walk_walked_1 && (! walk_defd_1))) || (walk_walked_2 && (! walk_defd_2))) || (walk_walked_3 && (! walk_defd_3)));
  assign judge_selfBad = ((((walk_walked_0 && (walk_selfCode_0 != walk_ptr_0)) || (walk_walked_1 && (walk_selfCode_1 != walk_ptr_1))) || (walk_walked_2 && (walk_selfCode_2 != walk_ptr_2))) || (walk_walked_3 && (walk_selfCode_3 != walk_ptr_3)));
  assign judge_wordsBad = (((((walk_walked_0 && walk_defd_0) && (walk_wordsFld_0 != walk_stepW_0)) || ((walk_walked_1 && walk_defd_1) && (walk_wordsFld_1 != walk_stepW_1))) || ((walk_walked_2 && walk_defd_2) && (walk_wordsFld_2 != walk_stepW_2))) || ((walk_walked_3 && walk_defd_3) && (walk_wordsFld_3 != walk_stepW_3)));
  assign judge_dupBad = ((((((((3'b001 < _zz_judge_dupBad) || (3'b001 < _zz_judge_dupBad_11)) || (3'b001 < _zz_judge_dupBad_22)) || (3'b001 < _zz_judge_dupBad_33)) || (3'b010 < _zz_judge_dupBad_44)) || (3'b001 < _zz_judge_dupBad_55)) || (3'b001 < _zz_judge_dupBad_66)) || (3'b001 < _zz_judge_dupBad_77));
  assign judge_resvBad = (judge_resvFld != 8'h0);
  assign judge_mal = ((! judge_capAbsent) && ((((((judge_resvBad || judge_capBad) || judge_lenBad) || judge_junkBad) || judge_selfBad) || judge_wordsBad) || judge_dupBad));
  always @(*) begin
    outStage_masked_0 = io_iInstr_0;
    outStage_masked_0[15 : 8] = 8'h0;
  end

  assign outStage_masked_1 = io_iInstr_1;
  assign outStage_masked_2 = io_iInstr_2;
  assign outStage_masked_3 = io_iInstr_3;
  assign outStage_masked_4 = io_iInstr_4;
  assign outStage_masked_5 = io_iInstr_5;
  assign outStage_masked_6 = io_iInstr_6;
  assign outStage_masked_7 = io_iInstr_7;
  assign outStage_masked_8 = io_iInstr_8;
  assign outStage_masked_9 = io_iInstr_9;
  assign outStage_masked_10 = io_iInstr_10;
  assign outStage_masked_11 = io_iInstr_11;
  assign outStage_masked_12 = io_iInstr_12;
  assign io_oValid = outStage_rValid;
  assign io_oMalformed = outStage_rMal;
  assign io_oCapAbsent = outStage_rCapa;
  assign io_oExecValid = ((outStage_rValid && (! outStage_rMal)) && (! outStage_rCapa));
  assign io_oInstr_0 = outStage_rInstr_0;
  assign io_oInstr_1 = outStage_rInstr_1;
  assign io_oInstr_2 = outStage_rInstr_2;
  assign io_oInstr_3 = outStage_rInstr_3;
  assign io_oInstr_4 = outStage_rInstr_4;
  assign io_oInstr_5 = outStage_rInstr_5;
  assign io_oInstr_6 = outStage_rInstr_6;
  assign io_oInstr_7 = outStage_rInstr_7;
  assign io_oInstr_8 = outStage_rInstr_8;
  assign io_oInstr_9 = outStage_rInstr_9;
  assign io_oInstr_10 = outStage_rInstr_10;
  assign io_oInstr_11 = outStage_rInstr_11;
  assign io_oInstr_12 = outStage_rInstr_12;
  assign io_oSlotPresent_0 = outStage_rPresent_0;
  assign io_oSlotPresent_1 = outStage_rPresent_1;
  assign io_oSlotPresent_2 = outStage_rPresent_2;
  assign io_oSlotPresent_3 = outStage_rPresent_3;
  assign io_oSlotCode_0 = outStage_rCode_0;
  assign io_oSlotCode_1 = outStage_rCode_1;
  assign io_oSlotCode_2 = outStage_rCode_2;
  assign io_oSlotCode_3 = outStage_rCode_3;
  assign io_oSlotOff_0 = outStage_rOff_0;
  assign io_oSlotOff_1 = outStage_rOff_1;
  assign io_oSlotOff_2 = outStage_rOff_2;
  assign io_oSlotOff_3 = outStage_rOff_3;
  assign when_Common_l259 = (outStage_rValid && outStage_rMal);
  assign io_oFault = _zz_io_oFault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      outStage_rValid <= 1'b0;
      outStage_rMal <= 1'b0;
      outStage_rCapa <= 1'b0;
      _zz_io_oFault <= 1'b0;
    end else begin
      outStage_rValid <= io_iValid;
      outStage_rMal <= judge_mal;
      outStage_rCapa <= judge_capAbsent;
      if(io_iFaultClear) begin
        _zz_io_oFault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_oFault <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    outStage_rInstr_0 <= outStage_masked_0;
    outStage_rInstr_1 <= outStage_masked_1;
    outStage_rInstr_2 <= outStage_masked_2;
    outStage_rInstr_3 <= outStage_masked_3;
    outStage_rInstr_4 <= outStage_masked_4;
    outStage_rInstr_5 <= outStage_masked_5;
    outStage_rInstr_6 <= outStage_masked_6;
    outStage_rInstr_7 <= outStage_masked_7;
    outStage_rInstr_8 <= outStage_masked_8;
    outStage_rInstr_9 <= outStage_masked_9;
    outStage_rInstr_10 <= outStage_masked_10;
    outStage_rInstr_11 <= outStage_masked_11;
    outStage_rInstr_12 <= outStage_masked_12;
    outStage_rPresent_0 <= walk_walked_0;
    outStage_rPresent_1 <= walk_walked_1;
    outStage_rPresent_2 <= walk_walked_2;
    outStage_rPresent_3 <= walk_walked_3;
    outStage_rCode_0 <= (walk_walked_0 ? walk_ptr_0 : 4'b0000);
    outStage_rCode_1 <= (walk_walked_1 ? walk_ptr_1 : 4'b0000);
    outStage_rCode_2 <= (walk_walked_2 ? walk_ptr_2 : 4'b0000);
    outStage_rCode_3 <= (walk_walked_3 ? walk_ptr_3 : 4'b0000);
    outStage_rOff_0 <= (walk_walked_0 ? walk_off_0 : 8'h0);
    outStage_rOff_1 <= (walk_walked_1 ? walk_off_1 : 8'h0);
    outStage_rOff_2 <= (walk_walked_2 ? walk_off_2 : 8'h0);
    outStage_rOff_3 <= (walk_walked_3 ? walk_off_3 : 8'h0);
  end


endmodule

module SharedUnitOccupyStub (
  input  wire          io_start,
  input  wire [160:0]  io_req,
  output wire          io_busy,
  output reg           io_done,
  output wire [160:0]  io_rsp,
  input  wire          clk,
  input  wire          reset
);

  reg        [3:0]    remain;
  reg        [160:0]  held;
  reg                 busyReg;
  wire                when_SharedUnit_l95;

  assign io_busy = busyReg;
  always @(*) begin
    io_done = 1'b0;
    if(!io_start) begin
      if(busyReg) begin
        if(when_SharedUnit_l95) begin
          io_done = 1'b1;
        end
      end
    end
  end

  assign io_rsp = held;
  assign when_SharedUnit_l95 = (remain == 4'b0001);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      remain <= 4'b0000;
      held <= 161'h0;
      busyReg <= 1'b0;
    end else begin
      if(io_start) begin
        busyReg <= 1'b1;
        held <= io_req;
        remain <= 4'b1000;
      end else begin
        if(busyReg) begin
          remain <= (remain - 4'b0001);
          if(when_SharedUnit_l95) begin
            busyReg <= 1'b0;
          end
        end
      end
    end
  end


endmodule

module XlateStore (
  input  wire          io_lookup_valid,
  input  wire [1:0]    io_lookup_part,
  input  wire [31:0]   io_lookup_vpn,
  output wire          io_rsp_hit,
  output wire          io_rsp_fromFill,
  output reg  [31:0]   io_rsp_frame,
  output reg           io_rsp_perm_r,
  output reg           io_rsp_perm_w,
  output reg           io_rsp_perm_x,
  output wire          io_rsp_hostPresent,
  output wire [31:0]   io_rsp_hostFrame,
  output wire          io_rsp_hostPerm_r,
  output wire          io_rsp_hostPerm_w,
  output wire          io_rsp_hostPerm_x,
  input  wire          io_hostRsp_valid,
  input  wire [31:0]   io_hostRsp_frame,
  input  wire          io_hostRsp_perm_r,
  input  wire          io_hostRsp_perm_w,
  input  wire          io_hostRsp_perm_x,
  input  wire          io_install_valid,
  output wire          io_install_ready,
  input  wire [1:0]    io_install_part,
  input  wire [3:0]    io_install_idx,
  input  wire [27:0]   io_install_tag,
  input  wire [31:0]   io_install_frame,
  input  wire          io_install_perm_r,
  input  wire          io_install_perm_w,
  input  wire          io_install_perm_x,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  input  wire          clk,
  input  wire          reset
);

  wire       [62:0]   store_spinal_port1;
  reg                 _zz_io_install_ready;
  reg        [3:0]    _zz_commitLine_idx;
  reg        [27:0]   _zz_commitLine_tag;
  reg        [31:0]   _zz_commitLine_frame;
  reg                 _zz_commitLine_perm_r;
  reg                 _zz_commitLine_perm_w;
  reg                 _zz_commitLine_perm_x;
  wire       [5:0]    _zz_store_port;
  wire       [62:0]   _zz_store_port_1;
  reg        [15:0]   _zz_storeValid;
  reg        [3:0]    _zz_fillLine_idx;
  reg        [27:0]   _zz_fillLine_tag;
  reg        [31:0]   _zz_fillLine_frame;
  reg                 _zz_fillLine_perm_r;
  reg                 _zz_fillLine_perm_w;
  reg                 _zz_fillLine_perm_x;
  reg                 _zz_fillHit;
  reg        [15:0]   validBits_0;
  reg        [15:0]   validBits_1;
  reg        [15:0]   validBits_2;
  reg        [15:0]   validBits_3;
  reg                 fillPend_0;
  reg                 fillPend_1;
  reg                 fillPend_2;
  reg                 fillPend_3;
  reg        [3:0]    fillSlot_0_idx;
  reg        [27:0]   fillSlot_0_tag;
  reg        [31:0]   fillSlot_0_frame;
  reg                 fillSlot_0_perm_r;
  reg                 fillSlot_0_perm_w;
  reg                 fillSlot_0_perm_x;
  reg        [3:0]    fillSlot_1_idx;
  reg        [27:0]   fillSlot_1_tag;
  reg        [31:0]   fillSlot_1_frame;
  reg                 fillSlot_1_perm_r;
  reg                 fillSlot_1_perm_w;
  reg                 fillSlot_1_perm_x;
  reg        [3:0]    fillSlot_2_idx;
  reg        [27:0]   fillSlot_2_tag;
  reg        [31:0]   fillSlot_2_frame;
  reg                 fillSlot_2_perm_r;
  reg                 fillSlot_2_perm_w;
  reg                 fillSlot_2_perm_x;
  reg        [3:0]    fillSlot_3_idx;
  reg        [27:0]   fillSlot_3_tag;
  reg        [31:0]   fillSlot_3_frame;
  reg                 fillSlot_3_perm_r;
  reg                 fillSlot_3_perm_w;
  reg                 fillSlot_3_perm_x;
  wire                flushSamePart;
  wire       [3:0]    _zz_1;
  wire                when_XlateStore_l200;
  wire       [3:0]    _zz_2;
  wire                _zz_3;
  wire                _zz_4;
  wire                _zz_5;
  wire                _zz_6;
  wire       [3:0]    commitPend;
  wire                commitFire;
  wire                _zz_commitSel;
  wire       [1:0]    commitSel;
  wire       [3:0]    commitLine_idx;
  wire       [27:0]   commitLine_tag;
  wire       [31:0]   commitLine_frame;
  wire                commitLine_perm_r;
  wire                commitLine_perm_w;
  wire                commitLine_perm_x;
  wire       [27:0]   commitBody_tag;
  wire       [31:0]   commitBody_frame;
  wire                commitBody_perm_r;
  wire                commitBody_perm_w;
  wire                commitBody_perm_x;
  wire       [3:0]    _zz_8;
  wire       [3:0]    _zz_9;
  wire       [3:0]    _zz_10;
  wire       [3:0]    _zz_11;
  wire       [3:0]    reqIdx;
  wire       [27:0]   reqTag;
  wire       [5:0]    entryAddr;
  wire       [27:0]   storeBody_tag;
  wire       [31:0]   storeBody_frame;
  wire                storeBody_perm_r;
  wire                storeBody_perm_w;
  wire                storeBody_perm_x;
  wire       [62:0]   _zz_storeBody_tag;
  wire       [2:0]    _zz_storeBody_perm_r;
  wire                storeValid;
  wire                storeHit;
  wire       [3:0]    fillLine_idx;
  wire       [27:0]   fillLine_tag;
  wire       [31:0]   fillLine_frame;
  wire                fillLine_perm_r;
  wire                fillLine_perm_w;
  wire                fillLine_perm_x;
  wire                fillHit;
  (* ram_style = "distributed" *) reg [62:0] store [0:63];

  assign _zz_store_port = {commitSel,commitLine_idx};
  assign _zz_store_port_1 = {{commitBody_perm_x,{commitBody_perm_w,commitBody_perm_r}},{commitBody_frame,commitBody_tag}};
  always @(posedge clk) begin
    if(commitFire) begin
      store[_zz_store_port] <= _zz_store_port_1;
    end
  end

  assign store_spinal_port1 = store[entryAddr];
  always @(*) begin
    case(io_install_part)
      2'b00 : _zz_io_install_ready = fillPend_0;
      2'b01 : _zz_io_install_ready = fillPend_1;
      2'b10 : _zz_io_install_ready = fillPend_2;
      default : _zz_io_install_ready = fillPend_3;
    endcase
  end

  always @(*) begin
    case(commitSel)
      2'b00 : begin
        _zz_commitLine_idx = fillSlot_0_idx;
        _zz_commitLine_tag = fillSlot_0_tag;
        _zz_commitLine_frame = fillSlot_0_frame;
        _zz_commitLine_perm_r = fillSlot_0_perm_r;
        _zz_commitLine_perm_w = fillSlot_0_perm_w;
        _zz_commitLine_perm_x = fillSlot_0_perm_x;
      end
      2'b01 : begin
        _zz_commitLine_idx = fillSlot_1_idx;
        _zz_commitLine_tag = fillSlot_1_tag;
        _zz_commitLine_frame = fillSlot_1_frame;
        _zz_commitLine_perm_r = fillSlot_1_perm_r;
        _zz_commitLine_perm_w = fillSlot_1_perm_w;
        _zz_commitLine_perm_x = fillSlot_1_perm_x;
      end
      2'b10 : begin
        _zz_commitLine_idx = fillSlot_2_idx;
        _zz_commitLine_tag = fillSlot_2_tag;
        _zz_commitLine_frame = fillSlot_2_frame;
        _zz_commitLine_perm_r = fillSlot_2_perm_r;
        _zz_commitLine_perm_w = fillSlot_2_perm_w;
        _zz_commitLine_perm_x = fillSlot_2_perm_x;
      end
      default : begin
        _zz_commitLine_idx = fillSlot_3_idx;
        _zz_commitLine_tag = fillSlot_3_tag;
        _zz_commitLine_frame = fillSlot_3_frame;
        _zz_commitLine_perm_r = fillSlot_3_perm_r;
        _zz_commitLine_perm_w = fillSlot_3_perm_w;
        _zz_commitLine_perm_x = fillSlot_3_perm_x;
      end
    endcase
  end

  always @(*) begin
    case(io_lookup_part)
      2'b00 : begin
        _zz_storeValid = validBits_0;
        _zz_fillLine_idx = fillSlot_0_idx;
        _zz_fillLine_tag = fillSlot_0_tag;
        _zz_fillLine_frame = fillSlot_0_frame;
        _zz_fillLine_perm_r = fillSlot_0_perm_r;
        _zz_fillLine_perm_w = fillSlot_0_perm_w;
        _zz_fillLine_perm_x = fillSlot_0_perm_x;
        _zz_fillHit = fillPend_0;
      end
      2'b01 : begin
        _zz_storeValid = validBits_1;
        _zz_fillLine_idx = fillSlot_1_idx;
        _zz_fillLine_tag = fillSlot_1_tag;
        _zz_fillLine_frame = fillSlot_1_frame;
        _zz_fillLine_perm_r = fillSlot_1_perm_r;
        _zz_fillLine_perm_w = fillSlot_1_perm_w;
        _zz_fillLine_perm_x = fillSlot_1_perm_x;
        _zz_fillHit = fillPend_1;
      end
      2'b10 : begin
        _zz_storeValid = validBits_2;
        _zz_fillLine_idx = fillSlot_2_idx;
        _zz_fillLine_tag = fillSlot_2_tag;
        _zz_fillLine_frame = fillSlot_2_frame;
        _zz_fillLine_perm_r = fillSlot_2_perm_r;
        _zz_fillLine_perm_w = fillSlot_2_perm_w;
        _zz_fillLine_perm_x = fillSlot_2_perm_x;
        _zz_fillHit = fillPend_2;
      end
      default : begin
        _zz_storeValid = validBits_3;
        _zz_fillLine_idx = fillSlot_3_idx;
        _zz_fillLine_tag = fillSlot_3_tag;
        _zz_fillLine_frame = fillSlot_3_frame;
        _zz_fillLine_perm_r = fillSlot_3_perm_r;
        _zz_fillLine_perm_w = fillSlot_3_perm_w;
        _zz_fillLine_perm_x = fillSlot_3_perm_x;
        _zz_fillHit = fillPend_3;
      end
    endcase
  end

  assign flushSamePart = (io_flush_valid && (io_flush_part == io_install_part));
  assign _zz_1 = ({3'd0,1'b1} <<< io_install_part);
  assign io_install_ready = ((! _zz_io_install_ready) && (! flushSamePart));
  assign when_XlateStore_l200 = (io_install_valid && io_install_ready);
  assign _zz_2 = ({3'd0,1'b1} <<< io_install_part);
  assign _zz_3 = _zz_2[0];
  assign _zz_4 = _zz_2[1];
  assign _zz_5 = _zz_2[2];
  assign _zz_6 = _zz_2[3];
  assign commitPend = {fillPend_3,{fillPend_2,{fillPend_1,fillPend_0}}};
  assign commitFire = (|commitPend);
  assign _zz_commitSel = commitPend[0];
  assign commitSel = ((_zz_commitSel || commitPend[1]) ? (_zz_commitSel ? 2'b00 : 2'b01) : (commitPend[2] ? 2'b10 : 2'b11));
  assign commitLine_idx = _zz_commitLine_idx;
  assign commitLine_tag = _zz_commitLine_tag;
  assign commitLine_frame = _zz_commitLine_frame;
  assign commitLine_perm_r = _zz_commitLine_perm_r;
  assign commitLine_perm_w = _zz_commitLine_perm_w;
  assign commitLine_perm_x = _zz_commitLine_perm_x;
  assign commitBody_tag = commitLine_tag;
  assign commitBody_frame = commitLine_frame;
  assign commitBody_perm_r = commitLine_perm_r;
  assign commitBody_perm_w = commitLine_perm_w;
  assign commitBody_perm_x = commitLine_perm_x;
  assign _zz_8 = ({3'd0,1'b1} <<< commitSel);
  assign _zz_9 = ({3'd0,1'b1} <<< commitSel);
  assign _zz_10 = ({3'd0,1'b1} <<< io_flush_part);
  assign _zz_11 = ({3'd0,1'b1} <<< io_flush_part);
  assign reqIdx = io_lookup_vpn[3 : 0];
  assign reqTag = io_lookup_vpn[31 : 4];
  assign entryAddr = {io_lookup_part,reqIdx};
  assign _zz_storeBody_tag = store_spinal_port1;
  assign storeBody_tag = _zz_storeBody_tag[27 : 0];
  assign storeBody_frame = _zz_storeBody_tag[59 : 28];
  assign _zz_storeBody_perm_r = _zz_storeBody_tag[62 : 60];
  assign storeBody_perm_r = _zz_storeBody_perm_r[0];
  assign storeBody_perm_w = _zz_storeBody_perm_r[1];
  assign storeBody_perm_x = _zz_storeBody_perm_r[2];
  assign storeValid = _zz_storeValid[reqIdx];
  assign storeHit = ((io_lookup_valid && storeValid) && (storeBody_tag == reqTag));
  assign fillLine_idx = _zz_fillLine_idx;
  assign fillLine_tag = _zz_fillLine_tag;
  assign fillLine_frame = _zz_fillLine_frame;
  assign fillLine_perm_r = _zz_fillLine_perm_r;
  assign fillLine_perm_w = _zz_fillLine_perm_w;
  assign fillLine_perm_x = _zz_fillLine_perm_x;
  assign fillHit = (((io_lookup_valid && _zz_fillHit) && (fillLine_idx == reqIdx)) && (fillLine_tag == reqTag));
  assign io_rsp_hit = (fillHit || storeHit);
  assign io_rsp_fromFill = fillHit;
  always @(*) begin
    io_rsp_frame = 32'h0;
    if(fillHit) begin
      io_rsp_frame = fillLine_frame;
    end else begin
      if(storeHit) begin
        io_rsp_frame = storeBody_frame;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_r = 1'b0;
    if(fillHit) begin
      io_rsp_perm_r = fillLine_perm_r;
    end else begin
      if(storeHit) begin
        io_rsp_perm_r = storeBody_perm_r;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_w = 1'b0;
    if(fillHit) begin
      io_rsp_perm_w = fillLine_perm_w;
    end else begin
      if(storeHit) begin
        io_rsp_perm_w = storeBody_perm_w;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_x = 1'b0;
    if(fillHit) begin
      io_rsp_perm_x = fillLine_perm_x;
    end else begin
      if(storeHit) begin
        io_rsp_perm_x = storeBody_perm_x;
      end
    end
  end

  assign io_rsp_hostPresent = io_hostRsp_valid;
  assign io_rsp_hostFrame = io_hostRsp_frame;
  assign io_rsp_hostPerm_r = io_hostRsp_perm_r;
  assign io_rsp_hostPerm_w = io_hostRsp_perm_w;
  assign io_rsp_hostPerm_x = io_hostRsp_perm_x;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      validBits_0 <= 16'h0;
      validBits_1 <= 16'h0;
      validBits_2 <= 16'h0;
      validBits_3 <= 16'h0;
      fillPend_0 <= 1'b0;
      fillPend_1 <= 1'b0;
      fillPend_2 <= 1'b0;
      fillPend_3 <= 1'b0;
    end else begin
      if(when_XlateStore_l200) begin
        if(_zz_1[0]) begin
          fillPend_0 <= 1'b1;
        end
        if(_zz_1[1]) begin
          fillPend_1 <= 1'b1;
        end
        if(_zz_1[2]) begin
          fillPend_2 <= 1'b1;
        end
        if(_zz_1[3]) begin
          fillPend_3 <= 1'b1;
        end
      end
      if(commitFire) begin
        if(_zz_8[0]) begin
          validBits_0[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[1]) begin
          validBits_1[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[2]) begin
          validBits_2[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[3]) begin
          validBits_3[commitLine_idx] <= 1'b1;
        end
        if(_zz_9[0]) begin
          fillPend_0 <= 1'b0;
        end
        if(_zz_9[1]) begin
          fillPend_1 <= 1'b0;
        end
        if(_zz_9[2]) begin
          fillPend_2 <= 1'b0;
        end
        if(_zz_9[3]) begin
          fillPend_3 <= 1'b0;
        end
      end
      if(io_flush_valid) begin
        if(_zz_10[0]) begin
          validBits_0 <= 16'h0;
        end
        if(_zz_10[1]) begin
          validBits_1 <= 16'h0;
        end
        if(_zz_10[2]) begin
          validBits_2 <= 16'h0;
        end
        if(_zz_10[3]) begin
          validBits_3 <= 16'h0;
        end
        if(_zz_11[0]) begin
          fillPend_0 <= 1'b0;
        end
        if(_zz_11[1]) begin
          fillPend_1 <= 1'b0;
        end
        if(_zz_11[2]) begin
          fillPend_2 <= 1'b0;
        end
        if(_zz_11[3]) begin
          fillPend_3 <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(when_XlateStore_l200) begin
      if(_zz_3) begin
        fillSlot_0_idx <= io_install_idx;
      end
      if(_zz_4) begin
        fillSlot_1_idx <= io_install_idx;
      end
      if(_zz_5) begin
        fillSlot_2_idx <= io_install_idx;
      end
      if(_zz_6) begin
        fillSlot_3_idx <= io_install_idx;
      end
      if(_zz_3) begin
        fillSlot_0_tag <= io_install_tag;
      end
      if(_zz_4) begin
        fillSlot_1_tag <= io_install_tag;
      end
      if(_zz_5) begin
        fillSlot_2_tag <= io_install_tag;
      end
      if(_zz_6) begin
        fillSlot_3_tag <= io_install_tag;
      end
      if(_zz_3) begin
        fillSlot_0_frame <= io_install_frame;
      end
      if(_zz_4) begin
        fillSlot_1_frame <= io_install_frame;
      end
      if(_zz_5) begin
        fillSlot_2_frame <= io_install_frame;
      end
      if(_zz_6) begin
        fillSlot_3_frame <= io_install_frame;
      end
      if(_zz_3) begin
        fillSlot_0_perm_r <= io_install_perm_r;
      end
      if(_zz_4) begin
        fillSlot_1_perm_r <= io_install_perm_r;
      end
      if(_zz_5) begin
        fillSlot_2_perm_r <= io_install_perm_r;
      end
      if(_zz_6) begin
        fillSlot_3_perm_r <= io_install_perm_r;
      end
      if(_zz_3) begin
        fillSlot_0_perm_w <= io_install_perm_w;
      end
      if(_zz_4) begin
        fillSlot_1_perm_w <= io_install_perm_w;
      end
      if(_zz_5) begin
        fillSlot_2_perm_w <= io_install_perm_w;
      end
      if(_zz_6) begin
        fillSlot_3_perm_w <= io_install_perm_w;
      end
      if(_zz_3) begin
        fillSlot_0_perm_x <= io_install_perm_x;
      end
      if(_zz_4) begin
        fillSlot_1_perm_x <= io_install_perm_x;
      end
      if(_zz_5) begin
        fillSlot_2_perm_x <= io_install_perm_x;
      end
      if(_zz_6) begin
        fillSlot_3_perm_x <= io_install_perm_x;
      end
    end
  end


endmodule
