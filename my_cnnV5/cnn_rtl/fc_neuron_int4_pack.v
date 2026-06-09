`timescale 1ns / 1ns

// 第五层INT4打包版单神经元
(* keep_hierarchy = "yes" *)
module fc_neuron_int4_pack
#(
    parameter LANE_NUM         = 6,
    parameter DATA_WIDTH       = 8,
    parameter WEIGHT_WIDTH     = 8,
    parameter QUANT_WIDTH      = 4,
    parameter INPUT_SHIFT      = 4,
    parameter WEIGHT_SHIFT     = 4,
    parameter GROUP_NUM        = 2,
    parameter BEATS_PER_GROUP  = 16,
    parameter TOTAL_WEIGHT_NUM = LANE_NUM * GROUP_NUM * BEATS_PER_GROUP,
    parameter OUT_WIDTH        = 32
)
(
    input  clk,                                                     // 时钟
    input  rstn,                                                    // 低有效复位
    input  cfg_weight_valid,                                        // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,               // 权重输入数据
    input  cfg_weight_last,                                         // 当前神经元权重最后一拍
    input  in_valid,                                                // 6路输入同拍有效
    input  signed [LANE_NUM*DATA_WIDTH-1:0] in_data,                // 6路输入数据
    input  in_last,                                                 // 当前输入向量最后一拍
    input  out_ready,                                               // 下游结果接收准备好

    output cfg_weight_ready,                                        // 权重输入准备好
    output cfg_weight_done,                                         // 权重装载完成脉冲
    output in_ready,                                                // 输入数据准备好
    output out_valid,                                               // 输出结果有效
    output signed [OUT_WIDTH-1:0] out_data,                         // 输出结果数据
    output busy,                                                    // 当前神经元忙
    output weight_loaded                                            // 已装好完整权重
);

    fc_neuron_int4_core #(
        .USE_PACKED(1),
        .LANE_NUM(LANE_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .QUANT_WIDTH(QUANT_WIDTH),
        .INPUT_SHIFT(INPUT_SHIFT),
        .WEIGHT_SHIFT(WEIGHT_SHIFT),
        .GROUP_NUM(GROUP_NUM),
        .BEATS_PER_GROUP(BEATS_PER_GROUP),
        .TOTAL_WEIGHT_NUM(TOTAL_WEIGHT_NUM),
        .OUT_WIDTH(OUT_WIDTH)
    ) u_fc_neuron_int4_core (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .busy(busy),
        .weight_loaded(weight_loaded)
    );

endmodule
