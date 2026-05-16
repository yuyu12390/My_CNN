`timescale 1ns / 1ns
// 第一层带权重分发的包装顶层
// 1. 外部只需要顺序送入 6x25 个权重
// 2. 包装层自动完成卷积核编号分发
// 3. 计算核心仍复用现有 l1_top
module l1_top_w
#(
    parameter LANE_NUM = 6,
    parameter LANE_SEL_WIDTH = (LANE_NUM <= 2) ? 1 : $clog2(LANE_NUM),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter K = 5,
    parameter STRIDE = 1,
    parameter OUT_WIDTH = 32,
    parameter OFMAP_W = ((IMG_W - K) / STRIDE) + 1,
    parameter OFMAP_H = ((IMG_H - K) / STRIDE) + 1,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter ADDR1D_WIDTH = 10
)
(
    input  clk,                                            // 时钟
    input  rstn,                                           // 低有效复位
    input  frame_start,                                    // 图像装载开始
    input  [DATA_WIDTH-1:0] image_tdata,                   // 图像输入数据
    input  image_tvalid,                                   // 图像输入有效
    input  cfg_weight_valid,                               // 串行权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,      // 串行权重数据
    input  cfg_weight_last,                                // 整个权重流最后一拍
    input  scan_start,                                     // 窗口扫描开始
    input  frame_release,                                  // 释放当前图像帧
    input  out_ready,                                      // 结果接收准备好
    input  [LANE_NUM-1:0] ofmap_rd_en,                     // 下一级各路读使能
    input  [LANE_NUM*ADDR2D_WIDTH-1:0] ofmap_rd_addr2d,    // 下一级各路读二维地址
    input  [LANE_NUM-1:0] ofmap_rd_done,                   // 下一级各路读完整帧

    output cfg_weight_ready,                               // 串行权重准备好
    output cfg_weight_done,                                // 整体权重装载完成脉冲
    output cfg_last_err,                                   // 上级 last 时序错误
    output image_tready,                                   // 图像输入准备好
    output scan_ready,                                     // 扫描可启动
    output img_wr_done,                                    // 图像写完一帧脉冲
    output img_frame_valid,                                // 图像帧有效
    output scan_busy,                                      // 扫描忙
    output scan_done,                                      // 扫描完成脉冲
    output out_valid,                                      // 结果有效
    output signed [OUT_WIDTH-1:0] out_data,                // 0 号卷积核结果
    output weight_loaded,                                  // 6 路权重全部装好
    output conv_busy,                                      // 任一路卷积核忙
    output [LANE_NUM-1:0] lane_cfg_weight_ready,           // 各路权重准备好
    output [LANE_NUM-1:0] lane_cfg_weight_done,            // 各路权重装载完成脉冲
    output [LANE_NUM-1:0] lane_weight_loaded,              // 各路权重装好
    output [LANE_NUM-1:0] lane_conv_busy,                  // 各路卷积核忙
    output [LANE_NUM-1:0] lane_out_valid,                  // 各路结果有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] lane_out_data,  // 各路结果数据
    output [ADDR2D_WIDTH-1:0] dbg_img_wr_addr2d,           // 调试图像写二维地址
    output [ADDR2D_WIDTH-1:0] dbg_win_addr2d,              // 调试窗口读二维地址
    output dbg_win_addr_last,                              // 调试窗口最后一拍
    output [ADDR2D_WIDTH-1:0] dbg_out_wr_addr2d,           // 调试输出写二维地址
    output dbg_out_wr_last,                                // 调试输出最后一拍
    output [ROW_ADDR_WIDTH-1:0] dbg_win_base_row,          // 调试窗口基地址行
    output [COL_ADDR_WIDTH-1:0] dbg_win_base_col,          // 调试窗口基地址列
    output [ROW_ADDR_WIDTH-1:0] dbg_win_krow,              // 调试窗口内行偏移
    output [COL_ADDR_WIDTH-1:0] dbg_win_kcol,              // 调试窗口内列偏移
    output dbg_rd_pending,                                 // 调试读请求在途
    output dbg_pix_valid,                                  // 调试像素保持有效
    output dbg_conv_in_last,                               // 调试卷积输入最后一拍
    output ofmap_wr_ready,                                 // 6 路缓存同时可写
    output ofmap_wr_done,                                  // 6 路缓存同时写完一帧
    output ofmap_frame_valid,                              // 6 路缓存同时帧有效
    output [LANE_NUM-1:0] lane_ofmap_wr_ready,             // 各路输出缓存写准备好
    output [LANE_NUM-1:0] lane_ofmap_wr_done,              // 各路输出缓存写完一帧
    output [LANE_NUM-1:0] lane_ofmap_frame_valid,          // 各路输出缓存帧有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] ofmap_rd_data,  // 各路输出缓存读数据
    output [LANE_NUM-1:0] ofmap_rd_valid,                  // 各路输出缓存读有效
    output [LANE_SEL_WIDTH-1:0] dbg_cfg_lane_idx,          // 调试当前卷积核编号
    output [7:0] dbg_cfg_weight_idx,                       // 调试组内权重编号
    output dbg_cfg_load_busy                               // 调试权重装载忙
);

    wire dist_cfg_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] dist_cfg_weight_data;
    wire dist_cfg_weight_last;
    wire [LANE_SEL_WIDTH-1:0] dist_cfg_weight_lane;
    wire dist_lane_cfg_weight_ready;

    l1_wgt_dist #(
        .LANE_NUM(LANE_NUM),
        .LANE_SEL_WIDTH(LANE_SEL_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .K(K)
    ) u_l1_wgt_dist (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .lane_cfg_weight_ready(dist_lane_cfg_weight_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .lane_cfg_weight_valid(dist_cfg_weight_valid),
        .lane_cfg_weight_data(dist_cfg_weight_data),
        .lane_cfg_weight_last(dist_cfg_weight_last),
        .lane_cfg_weight_lane(dist_cfg_weight_lane),
        .load_busy(dbg_cfg_load_busy),
        .load_done(cfg_weight_done),
        .cfg_last_err(cfg_last_err),
        .dbg_lane_idx(dbg_cfg_lane_idx),
        .dbg_weight_idx(dbg_cfg_weight_idx)
    );

    l1_top #(
        .LANE_NUM(LANE_NUM),
        .LANE_SEL_WIDTH(LANE_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .OUT_WIDTH(OUT_WIDTH),
        .OFMAP_W(OFMAP_W),
        .OFMAP_H(OFMAP_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .ADDR1D_WIDTH(ADDR1D_WIDTH)
    ) u_l1_top (
        .clk(clk),
        .rstn(rstn),
        .frame_start(frame_start),
        .image_tdata(image_tdata),
        .image_tvalid(image_tvalid),
        .cfg_weight_valid(dist_cfg_weight_valid),
        .cfg_weight_data(dist_cfg_weight_data),
        .cfg_weight_last(dist_cfg_weight_last),
        .cfg_weight_lane(dist_cfg_weight_lane),
        .scan_start(scan_start),
        .frame_release(frame_release),
        .out_ready(out_ready),
        .ofmap_rd_en(ofmap_rd_en),
        .ofmap_rd_addr2d(ofmap_rd_addr2d),
        .ofmap_rd_done(ofmap_rd_done),
        .cfg_weight_ready(dist_lane_cfg_weight_ready),
        .image_tready(image_tready),
        .scan_ready(scan_ready),
        .cfg_weight_done(),
        .img_wr_done(img_wr_done),
        .img_frame_valid(img_frame_valid),
        .scan_busy(scan_busy),
        .scan_done(scan_done),
        .out_valid(out_valid),
        .out_data(out_data),
        .weight_loaded(weight_loaded),
        .conv_busy(conv_busy),
        .lane_cfg_weight_ready(lane_cfg_weight_ready),
        .lane_cfg_weight_done(lane_cfg_weight_done),
        .lane_weight_loaded(lane_weight_loaded),
        .lane_conv_busy(lane_conv_busy),
        .lane_out_valid(lane_out_valid),
        .lane_out_data(lane_out_data),
        .dbg_img_wr_addr2d(dbg_img_wr_addr2d),
        .dbg_win_addr2d(dbg_win_addr2d),
        .dbg_win_addr_last(dbg_win_addr_last),
        .dbg_out_wr_addr2d(dbg_out_wr_addr2d),
        .dbg_out_wr_last(dbg_out_wr_last),
        .dbg_win_base_row(dbg_win_base_row),
        .dbg_win_base_col(dbg_win_base_col),
        .dbg_win_krow(dbg_win_krow),
        .dbg_win_kcol(dbg_win_kcol),
        .dbg_rd_pending(dbg_rd_pending),
        .dbg_pix_valid(dbg_pix_valid),
        .dbg_conv_in_last(dbg_conv_in_last),
        .ofmap_wr_ready(ofmap_wr_ready),
        .ofmap_wr_done(ofmap_wr_done),
        .ofmap_frame_valid(ofmap_frame_valid),
        .lane_ofmap_wr_ready(lane_ofmap_wr_ready),
        .lane_ofmap_wr_done(lane_ofmap_wr_done),
        .lane_ofmap_frame_valid(lane_ofmap_frame_valid),
        .ofmap_rd_data(ofmap_rd_data),
        .ofmap_rd_valid(ofmap_rd_valid)
    );

endmodule
