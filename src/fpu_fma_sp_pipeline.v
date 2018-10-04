`include "fpu_common.v"

module fp_fma_sp_pipeline
(
  input  wire                            clk,
  input  wire                            reset,

  input  wire [`FPU_RM_WIDTH-1:0]        cmd_rm,
  input  wire [`FPU_CMD_WIDTH-1:0]       cmd,

  input  wire [`FPR_RECODED_WIDTH-1:0]   rs1_data,
  input  wire [`FPR_RECODED_WIDTH-1:0]   rs2_data,
  input  wire [`FPR_RECODED_WIDTH-1:0]   rs3_data,

  output wire [`FPR_RECODED_WIDTH-1:0]   result,
  output wire [`FPU_EXC_WIDTH-1:0] exc
);

  wire [1:0] fma_op = cmd == `FPU_CMD_SUB || cmd == `FPU_CMD_MSUB ? 2'b01 :
                      cmd == `FPU_CMD_NMSUB                       ? 2'b10 :
                      cmd == `FPU_CMD_NMADD                       ? 2'b11 :
                                                                    2'b00;
  wire [`FPR_RECODED_WIDTH-1:0] one = 65'h80000000;
  wire [`FPR_RECODED_WIDTH-1:0] fma_multiplicand = rs1_data;
  wire [`FPR_RECODED_WIDTH-1:0] fma_multiplier =
    cmd == `FPU_CMD_ADD || cmd == `FPU_CMD_SUB ? one : rs2_data;
  wire [`FPR_RECODED_WIDTH-1:0] fma_addend =
    cmd == `FPU_CMD_MUL                        ? 65'b0      :
    cmd == `FPU_CMD_ADD || cmd == `FPU_CMD_SUB ? rs2_data :
                                                 rs3_data;
  
  reg [`FPR_RECODED_WIDTH+`FPU_EXC_WIDTH-1:0] pipereg [`FPU_PIPE_DEPTH(`FPU_PIPE_FMA_S)-1:0];

  mulAddSubRecodedFloatN #(8, 24) fma_sp
  (
    fma_op,
    fma_multiplicand[`SP_RECODED_WIDTH-1:0],
    fma_multiplier[`SP_RECODED_WIDTH-1:0],
    fma_addend[`SP_RECODED_WIDTH-1:0],
    cmd_rm[1:0],
    pipereg[0][`SP_RECODED_WIDTH-1:0],
    pipereg[0][`FPR_RECODED_WIDTH+`FPU_EXC_WIDTH-1:`FPR_RECODED_WIDTH]
  );
  
  always @(*) pipereg[0][`FPR_RECODED_WIDTH-1:`SP_RECODED_WIDTH] = 32'hFFFFFFFF;

  always @(posedge clk) begin : foo
    integer i;
    for(i = 1; i < `FPU_PIPE_DEPTH(`FPU_PIPE_FMA_S); i=i+1)
      pipereg[i] <= pipereg[i-1];
  end
  assign {exc,result} = pipereg[`FPU_PIPE_DEPTH(`FPU_PIPE_FMA_S)-1];

endmodule
