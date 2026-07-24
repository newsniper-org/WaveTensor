// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// fp_narrow_f32.vh — THE single f32 -> f16/bf16 narrowing function.
//
// v1.8.0d spec §23.10.10(d) bit-identity clause: 0x7C STORE_QUANT fp-dest
// narrow == 0x77 CVT NARROW_FROM_F32 for all 2^32 inputs INCLUDING the DAZ
// pre-stage. Enforcement mechanism: ONE Verilog function (this file,
// `include`d inside the module body — isa_subop_codes.vh convention) +
// ONE golden function (scripts/golden_fp32.py ref_narrow_f32). Call
// sites: FP_StepSeq.v (0x77 CVT NARROW step) and the PE_Core.v 0x7C
// fp-dest packer arm (v1.8.0d integration commit).
//
// Semantics (COMMIT-0 pins of §23.10.10(f), numbered as there):
//   (1) NaN of any payload -> DESTINATION canonical qNaN, sign dropped
//       (f16 0x7E00 / bf16 0x7FC0 = fp32 0x7FC00000 top 16 bits) — a NaN
//       can never degrade to Inf.
//   (3) RNE stated DISJOINTLY: dropped field D with round R = MSB(D),
//       sticky S = OR(D minus R); increment iff R & (S | kept-LSB) —
//       never "sticky of all dropped bits" (the confirmed off-by-one).
//       f16: R = source bit 12, S = |bits[11:0]|, kept-LSB = bit 13.
//       bf16: R = bit 15, S = |bits[14:0]|, kept-LSB = bit 16.
//   (4) Narrow overflow -> +/-Inf, never saturate-to-max-finite. The
//       bf16 increment ripples mantissa -> exponent so max-finite rounds
//       to Inf natively (NaN unreachable: the carry clears the mantissa).
//   (5) f32->f16 is FTZ-at-destination: |RN_unbounded(x)| < 2^-14 ->
//       signed zero AFTER the unbounded-exponent round (round-up-to-min-
//       normal survivors at binade -15 carry to -14 and live). DOCUMENTED
//       GPU DIVERGENCE: CUDA cvt.rn.f16.f32 preserves f16 subnormals —
//       GPU-lockstep harnesses mask the (0, 2^-14) result band. bf16
//       needs no destination flush (fp32/bf16 share the exponent range,
//       and a DAZ-flushed source can never reach bf16-subnormal space).
//   (7) The e==0 source arm (true zeros AND fp32 denormals) -> signed
//       zero. DAZ is pinned at BOTH RTL capture sites, and this function
//       maps the denormal field to signed zero anyway, so the result is
//       caller-DAZ-agnostic — bit-identical whether or not the caller
//       flushed first (the golden twin folds the DAZ pre-stage the same
//       way; the visible discriminator is the 0x007FFF80-0x007FFFFF
//       sliver, a directed test).
//
// yosys note (§23.8): callers assign the 16-bit result to a wire and
// consume it whole — no function-call result indexing.

function [15:0] fp_narrow_f32;
    input [31:0] nf_b;        // fp32 source bits (post-DAZ by pin; agnostic)
    input        nf_to_bf16;  // 0: f16 destination, 1: bf16 destination
    reg          nf_s;
    reg   [7:0]  nf_e;
    reg   [22:0] nf_m;
    reg          nf_r, nf_st, nf_l;
    reg   [11:0] nf_m11;      // f16 11-bit rounded significand + carry bit
    reg signed [9:0] nf_ex;
    begin
        nf_s = nf_b[31];
        nf_e = nf_b[30:23];
        nf_m = nf_b[22:0];
        if (nf_to_bf16) begin
            if (nf_e == 8'hFF)
                fp_narrow_f32 = (|nf_m) ? 16'h7FC0 : {nf_s, 15'h7F80};
            else if (nf_e == 8'h00)
                fp_narrow_f32 = {nf_s, 15'b0};
            else begin
                nf_r  = nf_b[15];
                nf_st = |nf_b[14:0];
                nf_l  = nf_b[16];
                fp_narrow_f32 = nf_b[31:16]
                              + {15'b0, nf_r & (nf_st | nf_l)};
            end
        end else begin
            if (nf_e == 8'hFF)
                fp_narrow_f32 = (|nf_m) ? 16'h7E00 : {nf_s, 15'h7C00};
            else if (nf_e == 8'h00)
                fp_narrow_f32 = {nf_s, 15'b0};
            else begin
                nf_r   = nf_m[12];             // m24 bit 12 == mantissa bit 12
                nf_st  = |nf_m[11:0];
                nf_l   = nf_m[13];
                nf_m11 = {2'b01, nf_m[22:13]}  // {hidden 1, kept 10} = m24>>13
                       + {11'b0, nf_r & (nf_st | nf_l)};
                nf_ex  = $signed({2'b00, nf_e}) - 10'sd127;
                if (nf_m11[11]) begin          // significand carry to 2^11
                    nf_m11 = 12'h400;
                    nf_ex  = nf_ex + 10'sd1;
                end
                if (nf_ex > 10'sd15)
                    fp_narrow_f32 = {nf_s, 15'h7C00};   // overflow -> Inf
                else if (nf_ex < -10'sd14)
                    fp_narrow_f32 = {nf_s, 15'b0};      // FTZ-at-destination
                else
                    fp_narrow_f32 = {nf_s, (nf_ex[4:0] + 5'd15), nf_m11[9:0]};
            end
        end
    end
endfunction
