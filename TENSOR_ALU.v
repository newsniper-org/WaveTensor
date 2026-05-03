// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

module Tensor_ALU #(
    parameter ADDR_WIDTH = 64,
    parameter DIM_SIZE = 4
) (
    input clk,
    input rst,
    input [7:0] opcode,
    input [ADDR_WIDTH*DIM_SIZE*DIM_SIZE-1:0] matrix_a,
    input [ADDR_WIDTH*DIM_SIZE*DIM_SIZE-1:0] matrix_b,
    output reg [ADDR_WIDTH*DIM_SIZE*DIM_SIZE-1:0] result_matrix,
    output reg alu_valid
);

    reg [ADDR_WIDTH-1:0] a [0:DIM_SIZE-1][0:DIM_SIZE-1];
    reg [ADDR_WIDTH-1:0] b [0:DIM_SIZE-1][0:DIM_SIZE-1];
    reg [ADDR_WIDTH-1:0] res [0:DIM_SIZE-1][0:DIM_SIZE-1];
    integer i, j, k;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_valid <= 0;
        end else begin
            alu_valid <= 1;
            for (i = 0; i < DIM_SIZE; i = i + 1) begin
                for (j = 0; j < DIM_SIZE; j = j + 1) begin
                    a[i][j] <= matrix_a[(i*DIM_SIZE + j)*ADDR_WIDTH +: ADDR_WIDTH];
                    b[i][j] <= matrix_b[(i*DIM_SIZE + j)*ADDR_WIDTH +: ADDR_WIDTH];
                end
            end
            case (opcode)
                8'h30: begin  // MATMUL
                    for (i = 0; i < DIM_SIZE; i = i + 1) begin
                        for (j = 0; j < DIM_SIZE; j = j + 1) begin
                            res[i][j] <= 0;
                            for (k = 0; k < DIM_SIZE; k = k + 1) begin
                                res[i][j] <= res[i][j] + a[i][k] * b[k][j];
                            end
                            result_matrix[(i*DIM_SIZE + j)*ADDR_WIDTH +: ADDR_WIDTH] <= res[i][j];
                        end
                    end
                end
                8'h31: begin  // TENSOR_ADD
                    for (i = 0; i < DIM_SIZE; i = i + 1) begin
                        for (j = 0; j < DIM_SIZE; j = j + 1) begin
                            res[i][j] <= a[i][j] + b[i][j];
                            result_matrix[(i*DIM_SIZE + j)*ADDR_WIDTH +: ADDR_WIDTH] <= res[i][j];
                        end
                    end
                end
                8'h32: begin  // TENSOR_MUL
                    for (i = 0; i < DIM_SIZE; i = i + 1) begin
                        for (j = 0; j < DIM_SIZE; j = j + 1) begin
                            res[i][j] <= a[i][j] * b[i][j];
                            result_matrix[(i*DIM_SIZE + j)*ADDR_WIDTH +: ADDR_WIDTH] <= res[i][j];
                        end
                    end
                end
                default: result_matrix <= 0;
            endcase
        end
    end

endmodule