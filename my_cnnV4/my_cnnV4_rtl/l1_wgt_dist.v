`timescale 1ns / 1ns
// 第一层权重分发模块
// 1. 上级按顺序送入 6 组 5x5 权重
// 2. 本模块自动给出当前卷积核编号
// 3. 每 25 个权重自动产生 1 次 lane 内 last
module l1_wgt_dist
#(
    parameter LANE_NUM = 6,
    parameter LANE_SEL_WIDTH = (LANE_NUM <= 2) ? 1 : $clog2(LANE_NUM),
    parameter WEIGHT_WIDTH = 8,
    parameter K = 5
)
(
    input  clk,                                          // 时钟
    input  rstn,                                         // 低有效复位
    input  cfg_weight_valid,                             // 上级权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,    // 上级权重数据
    input  cfg_weight_last,                              // 整个权重流最后一拍
    input  lane_cfg_weight_ready,                        // 当前卷积核准备好

    output cfg_weight_ready,                             // 上级权重准备好
    output lane_cfg_weight_valid,                        // 下发权重有效
    output signed [WEIGHT_WIDTH-1:0] lane_cfg_weight_data,// 下发权重数据
    output lane_cfg_weight_last,                         // 当前卷积核最后一拍
    output [LANE_SEL_WIDTH-1:0] lane_cfg_weight_lane,    // 当前卷积核编号
    output reg load_busy,                                // 当前装载忙
    output reg load_done,                                // 整体装载完成脉冲
    output reg cfg_last_err,                             // 上级 last 时序错误
    output reg [LANE_SEL_WIDTH-1:0] dbg_lane_idx,        // 调试卷积核编号
    output reg [7:0] dbg_weight_idx                      // 调试组内权重编号
);

    localparam integer WIN_SIZE = K * K;

    wire cfg_fire;
    wire lane_last_exp;
    wire stream_last_exp;
    wire [LANE_SEL_WIDTH-1:0] cur_lane_idx;
    wire [7:0] cur_weight_idx;

    assign cfg_weight_ready = lane_cfg_weight_ready;
    assign lane_cfg_weight_valid = cfg_weight_valid;
    assign lane_cfg_weight_data = cfg_weight_data;
    assign cur_lane_idx = dbg_lane_idx;
    assign cur_weight_idx = dbg_weight_idx;
    assign lane_cfg_weight_lane = cur_lane_idx;

    assign lane_last_exp = (cur_weight_idx == WIN_SIZE - 1);
    assign stream_last_exp = lane_last_exp && (cur_lane_idx == LANE_NUM - 1);
    assign lane_cfg_weight_last = lane_cfg_weight_valid && lane_last_exp;
    assign cfg_fire = cfg_weight_valid && cfg_weight_ready;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            load_busy <= 1'b0;
            load_done <= 1'b0;
            cfg_last_err <= 1'b0;
            dbg_lane_idx <= {LANE_SEL_WIDTH{1'b0}};
            dbg_weight_idx <= 8'd0;
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
                    load_busy <= 1'b0;
                    load_done <= 1'b1;
                    dbg_lane_idx <= {LANE_SEL_WIDTH{1'b0}};
                    dbg_weight_idx <= 8'd0;
                end
                else
                begin
                    load_busy <= 1'b1;

                    if(lane_last_exp)
                    begin
                        dbg_lane_idx <= cur_lane_idx + 1'b1;
                        dbg_weight_idx <= 8'd0;
                    end
                    else
                    begin
                        dbg_weight_idx <= dbg_weight_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
