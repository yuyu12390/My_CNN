`timescale 1ns / 1ns

// FC原始权重分发模块
// 1. 直接接收fcw.txt这种纯FC串行权重流
// 2. 每192个权重分给1个神经元
// 3. 顺序为神经元0到神经元9
module fc_wgt_dist_raw
#(
    parameter WEIGHT_WIDTH = 8,
    parameter OUT_NUM = 10,
    parameter OUT_SEL_WIDTH = (OUT_NUM <= 2) ? 1 : $clog2(OUT_NUM),
    parameter WEIGHT_NUM_PER_OUT = 192,
    parameter WEIGHT_IDX_WIDTH = (WEIGHT_NUM_PER_OUT <= 2) ? 1 : $clog2(WEIGHT_NUM_PER_OUT)
)
(
    input  clk,                                              // 时钟
    input  rstn,                                             // 低有效复位
    input  cfg_weight_valid,                                 // 上级权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,        // 上级权重数据
    input  cfg_weight_last,                                  // 整体流最后一拍
    input  weight_ready,                                     // 下游准备好

    output cfg_weight_ready,                                 // 上级准备好
    output weight_valid,                                     // 下发权重有效
    output signed [WEIGHT_WIDTH-1:0] weight_data,            // 下发权重数据
    output [OUT_SEL_WIDTH-1:0] weight_out,                   // 目标神经元号
    output dst_last,                                         // 当前神经元最后一拍
    output reg load_busy,                                    // 当前装载忙
    output reg load_done,                                    // 整体装载完成脉冲
    output reg cfg_last_err                                  // 外部last错误脉冲
);

    reg [OUT_SEL_WIDTH-1:0] cur_out;
    reg [WEIGHT_IDX_WIDTH-1:0] cur_weight_idx;

    wire cfg_fire;
    wire dst_last_exp;
    wire stream_last_exp;

    assign cfg_weight_ready = weight_ready;
    assign weight_valid = cfg_weight_valid;
    assign weight_data = cfg_weight_data;
    assign weight_out = cur_out;

    assign cfg_fire = cfg_weight_valid && cfg_weight_ready;
    assign dst_last_exp = (cur_weight_idx == (WEIGHT_NUM_PER_OUT - 1));
    assign stream_last_exp = (cur_out == (OUT_NUM - 1)) && dst_last_exp;
    assign dst_last = weight_valid && dst_last_exp;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            cur_out <= {OUT_SEL_WIDTH{1'b0}};
            cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};
            load_busy <= 1'b0;
            load_done <= 1'b0;
            cfg_last_err <= 1'b0;
        end
        else
        begin
            load_done <= 1'b0;
            cfg_last_err <= 1'b0;

            if(cfg_fire)
            begin
                if(cfg_weight_last != stream_last_exp)
                begin
                    cfg_last_err <= 1'b1;
                end

                if(stream_last_exp)
                begin
                    cur_out <= {OUT_SEL_WIDTH{1'b0}};
                    cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};
                    load_busy <= 1'b0;
                    load_done <= 1'b1;
                end
                else
                begin
                    load_busy <= 1'b1;

                    if(dst_last_exp)
                    begin
                        cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};
                        cur_out <= cur_out + 1'b1;
                    end
                    else
                    begin
                        cur_weight_idx <= cur_weight_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
