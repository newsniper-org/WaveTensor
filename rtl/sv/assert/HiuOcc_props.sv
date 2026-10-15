// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// HiuOcc 후-formal 검사자 — 파이프 점유의 시점 · 보존 (3.10 v1.0 묶음 RTL 파도 W4, 2026-10-15).
// 태스크: rtl/formal/sby/HiuMask/occ.sby (머리가 앵커 · 엔진 · 합성 서술을 소유한다).
// 선-formal 계약: rtl/formal/tla/ActivePart.tla 닫힌 목록 3 (b) · 대안 DSample = "lag"(_alt_lag → Inv_WorkUnderBound).
//
// ## 왜 있는가
//
// `0xE14` 의 판정 α(DP-4)는 「t 에 수락된 기입을 t+1 의 DRAIN_ALLZERO 로 판정한다」 이고, 그것이 정본
// 「수락 에지 *직후*의 상태(같은 사이클의 요청 접수 포함)」 와 같으려면 t 에 접수된 요청이 t+1 의 점유에 이미
// 들어 있어야 한다. 어기면 옛 결속으로 받은 일이 결속 교체를 건넌다 (모델 _alt_lag — 격리 결함). 그 사실은
// 파이프 안에서만 잴 수 있다: assembly 는 hiu 를 절단해 점유가 자유 핀이고, descriptor.sby 는 CompletionUnit
// 단독이다. 그래서 HiuPipeline + MaskUnit 합성(HiuMask_comp — hiumask.sby 와 같은 결선)의 포트로 잰다.
//
//   h_occ_accept    req.fire(t) ⇒ occupancy(t+1) ≥ 1 — 같은 사이클 접수가 다음 사이클 점유에 든다.
//   h_occ_conserve  occupancy(t+1) = occupancy(t) + req.fire(t) − rsp.valid(t) — 일은 접수로만 들어오고 응답
//                   퇴장으로만 나간다. 단계 사이 인계(s3 → MaskUnit s4 → s5)에 0 틈이 있으면(한 사이클 어느 단의
//                   valid 에도 없으면) 여기서 깨진다 — 「파이프 → 하류 인계에 0 틈 없음」 의 v1.0 판: 이 파이프의
//                   퇴장(io.rsp)은 Wt64Top 최상위 io.hiuRsp 로 장치를 떠나므로 장치 안의 다른 카운트로 넘기는
//                   인계가 없다 (Wt64Top.scala io.hiuRsp 결선 · 모델 머리 「β 모서리의 RTL 도달 경로」).
//
// 합성 서술 (이 셋이 함께 「t 접수 ⇒ t+1 drainAllZero = 0」): h_occ_accept(여기) · assembly a_drain_order
// (cq.io.drain.pipe = hiu.io.occupancy 같은 사이클 결선) · descriptor.sby a_daz_fn(핀 = 일곱 항의 조합 술어 —
// 래치 없음). 그리고 actp.io.drainNow = cq.drainAllZero 결선은 assembly a_bind_upd(D 되읽기 = 판정 사이클 핀).
//
// ## 부착 — bind 문 텍스트 전개 (yosys 0.66 은 bind 를 묵살한다)
//
// 파일 끝 bind 문을 occ.sby [script] 가 HiuMask_comp 의 endmodule 앞에 텍스트로 넣는다 (assembly · hiumask
// 선례). 포트는 .* 로 HiuMask_comp 의 같은 이름 넷(최상위 포트)에 묶인다 — 이름이 사라지면 hierarchy 가 ERROR.
// HiuMask_props.sv 는 *읽기만* 한다(HiuMask_comp 결선 · ENV assume 재사용 — bind 두 줄은 전개하지 않으므로
// HiuPipeline_props · MaskUnit_props 는 이 태스크에 없다).
module HiuOcc_props (
  input wire       clk,
  input wire       reset,
  input wire       io_req_valid,
  input wire       io_req_ready,
  input wire       io_rsp_valid,
  input wire [2:0] io_occupancy
);
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  reg f_reset_d = 1'b1;
  always @(posedge clk) f_reset_d <= reset;
  wire f_ok = f_past_valid && !reset && !f_reset_d;
  wire fire = io_req_valid && io_req_ready;
  // 첫 접수 이전 표지 — W1 의 전건. 「점유 0 의 접수」 만으로는 s1 을 세지 않는 변이(OCC_LAG)가 hold 로 s1 에 잡혀
  // 보이지 않던 일을 s2 로 넘기며 점유 1 을 내 W1 이 살았다 (W4H 실측). reset 뒤 첫 접수면 파이프가 실제로 비었다.
  reg f_fired = 1'b0;
  always @(posedge clk) f_fired <= reset ? 1'b0 : (f_fired || fire);

`ifndef HIUOCC_COVER
  always @(posedge clk) if (f_ok) begin
    if ($past(fire)) h_occ_accept: assert (io_occupancy != 3'd0);
    h_occ_conserve: assert ({1'b0, io_occupancy} == {1'b0, $past(io_occupancy)} + {3'd0, $past(fire)} - {3'd0, $past(io_rsp_valid)});
  end
`endif

`ifdef HIUOCC_COVER
  // W1 ← HiuPipeline.occ_timing · h_occ_accept — reset 뒤 첫 접수(빈 파이프)가 다음 사이클 점유 1 이다
  always @(posedge clk) if (f_ok) w1_occ_first: cover ($past(fire && !f_fired) && io_occupancy == 3'd1);
  // W2 ← HiuPipeline.occ_timing · h_occ_conserve — 같은 사이클에 접수와 응답 퇴장이 겹치면 점유가 그대로다 (β 모서리의 RTL 경로)
  always @(posedge clk) if (f_ok) w2_occ_swap: cover ($past(fire && io_rsp_valid && io_occupancy != 3'd0) && io_occupancy == $past(io_occupancy));
  // W3 ← HiuPipeline.occ_timing · h_occ_conserve — 정지(ready 0) 중에는 일이 남은 채 점유가 그대로다 (단계 동결)
  always @(posedge clk) if (f_ok) w3_occ_hold: cover ($past(!io_req_ready && io_occupancy != 3'd0) && io_occupancy == $past(io_occupancy));
`endif
endmodule

bind HiuMask_comp HiuOcc_props u_occ (.*);
