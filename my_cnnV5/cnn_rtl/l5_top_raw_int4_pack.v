`timescale 1ns / 1ns

// 第五层INT4打包版顶层
(* keep_hierarchy = "yes" *)
module l5_top_raw_int4_pack
#(
    parameter IN_CH_NUM = 12,
    parameter LANE_NUM = 6,
    parameter OUT_NUM = 10,
    parameter GROUP_NUM = IN_CH_NUM / LANE_NUM,
    parameter GROUP_SEL_WIDTH = (GROUP_NUM <= 2) ? 1 : $clog2(GROUP_NUM),
    parameter OUT_SEL_WIDTH = (OUT_NUM <= 2) ? 1 : $clog2(OUT_NUM),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter QUANT_WIDTH = 4,
    parameter INPUT_SHIFT = 4,
    parameter WEIGHT_SHIFT = 4,
    parameter IMG_W = 4,
    parameter IMG_H = 4,
    parameter OUT_WIDTH = 32,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter FC_KERNEL_NUM = 10,
    parameter FC_WEIGHT_NUM = 192
)
(
    input  clk,                                                    // 时钟
    input  rstn,                                                   // 低有效复位
    input  start,                                                  // 启动一次完整第五层计算
    input  [IN_CH_NUM-1:0] src_frame_valid,                        // 上一级12路输入帧有效
    input  signed [IN_CH_NUM*DATA_WIDTH-1:0] src_rd_data,          // 上一级12路读回数据
    input  [IN_CH_NUM-1:0] src_rd_valid,                           // 上一级12路读回有效
    input  cfg_weight_valid,                                       // FC串行权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,              // FC串行权重数据
    input  cfg_weight_last,                                        // FC串行权重最后一拍
    input  score_ready,                                            // 外部结果接收准备好

    output cfg_weight_ready,                                       // FC串行权重准备好
    output cfg_weight_done,                                        // FC预装载完成脉冲
    output cfg_last_err,                                           // FC last时序错误
    output ready,                                                  // 第五层可启动
    output busy,                                                   // 第五层忙
    output done,                                                   // 第五层结果就绪脉冲
    output weight_loaded,                                          // 10个神经元权重全部装好
    output [IN_CH_NUM-1:0] src_rd_en,                              // 读上一级12路缓存使能
    output [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d,             // 读上一级12路缓存地址
    output [IN_CH_NUM-1:0] src_rd_done,                            // 释放上一级12路输入帧
    output score_valid,                                            // 10路结果整体有效
    output signed [OUT_NUM*OUT_WIDTH-1:0] score_data               // 10路分类分数
);

    l5_top_raw_int4_core #(
        .USE_PACKED(1),
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .OUT_NUM(OUT_NUM),
        .GROUP_NUM(GROUP_NUM),
        .GROUP_SEL_WIDTH(GROUP_SEL_WIDTH),
        .OUT_SEL_WIDTH(OUT_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .QUANT_WIDTH(QUANT_WIDTH),
        .INPUT_SHIFT(INPUT_SHIFT),
        .WEIGHT_SHIFT(WEIGHT_SHIFT),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .OUT_WIDTH(OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .FC_KERNEL_NUM(FC_KERNEL_NUM),
        .FC_WEIGHT_NUM(FC_WEIGHT_NUM)
    ) u_l5_top_raw_int4_core (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_frame_valid),
        .src_rd_data(src_rd_data),
        .src_rd_valid(src_rd_valid),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .score_ready(score_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .cfg_last_err(cfg_last_err),
        .ready(ready),
        .busy(busy),
        .done(done),
        .weight_loaded(weight_loaded),
        .src_rd_en(src_rd_en),
        .src_rd_addr2d(src_rd_addr2d),
        .src_rd_done(src_rd_done),
        .score_valid(score_valid),
        .score_data(score_data)
    );

endmodule
