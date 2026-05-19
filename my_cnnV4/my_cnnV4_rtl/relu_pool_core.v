`timescale 1ns / 1ns
// 第一层 relu+pool 纯计算核
// 1. 串行接收 1 个 2x2 窗口的 4 个 32bit 数据
// 2. 每个数据先做 ReLU 和右移量化
// 3. 对 4 个量化结果做最大池化, 输出 1 个 8bit 结果
module relu_pool_core
#(
    parameter IN_WIDTH = 32,
    parameter OUT_WIDTH = 8,
    parameter K = 2,
    parameter SHIFT_BITS = 10
)
(
    input  clk,                                       // 时钟
    input  rstn,                                      // 低有效复位
    input  in_valid,                                  // 输入数据有效
    input  signed [IN_WIDTH-1:0] in_data,             // 输入数据
    input  in_last,                                   // 当前窗口最后一个输入
    input  out_ready,                                 // 下游结果接收准备好

    output in_ready,                                  // 输入准备好
    output reg out_valid,                             // 输出结果有效
    output reg signed [OUT_WIDTH-1:0] out_data,       // 输出结果数据
    output reg busy                                   // 当前窗口计算中
);

    localparam integer WIN_SIZE = K * K;
    localparam integer IDX_WIDTH = (WIN_SIZE <= 1) ? 1 : $clog2(WIN_SIZE);

    reg [IDX_WIDTH-1:0] sample_cnt;
    reg signed [OUT_WIDTH-1:0] pool_max_reg;

    wire in_fire;
    wire signed [IN_WIDTH-1:0] relu_clip_val;
    wire signed [IN_WIDTH-1:0] relu_shift_val;
    wire signed [OUT_WIDTH-1:0] relu_quant_val;
    wire signed [OUT_WIDTH-1:0] pool_max_next;

    assign in_ready = !out_valid;
    assign in_fire = in_valid && in_ready;

    assign relu_clip_val = in_data[IN_WIDTH-1] ? {IN_WIDTH{1'b0}} : in_data;
    assign relu_shift_val = relu_clip_val >>> SHIFT_BITS;
    assign relu_quant_val = relu_shift_val[OUT_WIDTH-1:0];
    assign pool_max_next = ((sample_cnt == {IDX_WIDTH{1'b0}}) || (relu_quant_val > pool_max_reg))
                         ? relu_quant_val
                         : pool_max_reg;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            out_valid <= 1'b0;
            out_data <= {OUT_WIDTH{1'b0}};
            busy <= 1'b0;
            sample_cnt <= {IDX_WIDTH{1'b0}};
            pool_max_reg <= {OUT_WIDTH{1'b0}};
        end
        else
        begin
            if(out_valid && out_ready)
            begin
                out_valid <= 1'b0;
                busy <= 1'b0;
            end

            if(in_fire)
            begin
                busy <= 1'b1;

                if((sample_cnt == WIN_SIZE - 1) || in_last)
                begin
                    out_valid <= 1'b1;
                    out_data <= pool_max_next;
                    sample_cnt <= {IDX_WIDTH{1'b0}};
                    pool_max_reg <= {OUT_WIDTH{1'b0}};
                end
                else
                begin
                    sample_cnt <= sample_cnt + 1'b1;
                    pool_max_reg <= pool_max_next;
                end
            end
        end
    end

endmodule