`timescale 1ns / 1ns
// 第一层对外顶层
// 1. 接收全局权重分发器输出的逻辑目标 {layer_id, kernel_id}
// 2. 只把第一层 (0,0) ~ (0,5) 翻译给 l1_core
// 3. 图像输入、地址管理、6 路卷积和 6 路输出缓存仍复用现有 l1_core
module l1_top
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
    parameter ADDR1D_WIDTH = 10,
    parameter LAYER_ID_WIDTH = 1,
    parameter KERNEL_ID_WIDTH = 4,
    parameter WEIGHT_IDX_WIDTH = 8,
    parameter L0_KERNEL_NUM = 6,
    parameter L0_WEIGHT_NUM = 25,
    parameter L1_KERNEL_NUM = 12,
    parameter L1_WEIGHT_NUM = 150,
    parameter DST2D_WIDTH = LAYER_ID_WIDTH + KERNEL_ID_WIDTH
)
(
    input  clk,                                              // 时钟
    input  rstn,                                             // 低有效复位
    input  frame_start,                                      // 图像装载开始
    input  [DATA_WIDTH-1:0] image_tdata,                     // 图像输入数据
    input  image_tvalid,                                     // 图像输入有效
    input  cfg_weight_valid,                                 // 全局串行权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,        // 全局串行权重数据
    input  cfg_weight_last,                                  // 全局串行权重最后一拍
    input  scan_start,                                       // 窗口扫描开始
    input  frame_release,                                    // 释放当前图像帧
    input  out_ready,                                        // 结果接收准备好
    input  [LANE_NUM-1:0] ofmap_rd_en,                       // 下一级各路读使能
    input  [LANE_NUM*ADDR2D_WIDTH-1:0] ofmap_rd_addr2d,      // 下一级各路读二维地址
    input  [LANE_NUM-1:0] ofmap_rd_done,                     // 下一级各路读完整帧

    output cfg_weight_ready,                                 // 全局串行权重准备好
    output cfg_weight_done,                                  // 全局预装载完成脉冲
    output cfg_last_err,                                     // 全局 last 时序错误
    output image_tready,                                     // 图像输入准备好
    output scan_ready,                                       // 扫描可启动
    output img_wr_done,                                      // 图像写完一帧脉冲
    output img_frame_valid,                                  // 图像帧有效
    output scan_busy,                                        // 扫描忙
    output scan_done,                                        // 扫描完成脉冲
    output out_valid,                                        // 结果有效
    output signed [OUT_WIDTH-1:0] out_data,                  // 0 号卷积核结果
    output weight_loaded,                                    // 第一层 6 路权重全部装好
    output conv_busy,                                        // 任一路卷积核忙
    output [LANE_NUM-1:0] lane_cfg_weight_ready,             // 各路权重准备好
    output [LANE_NUM-1:0] lane_cfg_weight_done,              // 各路权重装载完成脉冲
    output [LANE_NUM-1:0] lane_weight_loaded,                // 各路权重装好
    output [LANE_NUM-1:0] lane_conv_busy,                    // 各路卷积核忙
    output [LANE_NUM-1:0] lane_out_valid,                    // 各路结果有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] lane_out_data,    // 各路结果数据
    output [ADDR2D_WIDTH-1:0] dbg_img_wr_addr2d,             // 调试图像写二维地址
    output [ADDR2D_WIDTH-1:0] dbg_win_addr2d,                // 调试窗口读二维地址
    output dbg_win_addr_last,                                // 调试窗口最后一拍
    output [ADDR2D_WIDTH-1:0] dbg_out_wr_addr2d,             // 调试输出写二维地址
    output dbg_out_wr_last,                                  // 调试输出最后一拍
    output [ROW_ADDR_WIDTH-1:0] dbg_win_base_row,            // 调试窗口基地址行
    output [COL_ADDR_WIDTH-1:0] dbg_win_base_col,            // 调试窗口基地址列
    output [ROW_ADDR_WIDTH-1:0] dbg_win_krow,                // 调试窗口内行偏移
    output [COL_ADDR_WIDTH-1:0] dbg_win_kcol,                // 调试窗口内列偏移
    output dbg_rd_pending,                                   // 调试读请求在途
    output dbg_pix_valid,                                    // 调试像素保持有效
    output dbg_conv_in_last,                                 // 调试卷积输入最后一拍
    output ofmap_wr_ready,                                   // 6 路缓存同时可写
    output ofmap_wr_done,                                    // 6 路缓存同时写完一帧
    output ofmap_frame_valid,                                // 6 路缓存同时帧有效
    output [LANE_NUM-1:0] lane_ofmap_wr_ready,               // 各路输出缓存写准备好
    output [LANE_NUM-1:0] lane_ofmap_wr_done,                // 各路输出缓存写完一帧
    output [LANE_NUM-1:0] lane_ofmap_frame_valid,            // 各路输出缓存帧有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] ofmap_rd_data,    // 各路输出缓存读数据
    output [LANE_NUM-1:0] ofmap_rd_valid,                    // 各路输出缓存读有效
    output [DST2D_WIDTH-1:0] dbg_gw_weight_dst2d,            // 调试全局逻辑目标
    output [WEIGHT_IDX_WIDTH-1:0] dbg_gw_weight_idx,         // 调试全局组内编号
    output dbg_gw_dst_last,                                  // 调试全局当前目标最后一拍
    output dbg_gw_load_busy,                                 // 调试全局预装载忙
    output dbg_gw_preload_done,                              // 调试全局预装载完成保持
    output dbg_gw_is_l1_target,                              // 调试当前目标是否属于第一层
    output [LANE_SEL_WIDTH-1:0] dbg_gw_lane_idx              // 调试翻译后的第一层卷积核编号
);

    localparam [LAYER_ID_WIDTH-1:0] LAYER0_ID = {LAYER_ID_WIDTH{1'b0}};

    reg preload_done_reg;

    wire gw_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] gw_weight_data;
    wire [DST2D_WIDTH-1:0] gw_weight_dst2d;
    wire [WEIGHT_IDX_WIDTH-1:0] gw_weight_idx;
    wire gw_dst_last;
    wire gw_weight_ready;
    wire gw_load_busy;
    wire gw_load_done;
    wire gw_cfg_last_err;
    wire [LAYER_ID_WIDTH-1:0] gw_layer_id;
    wire [KERNEL_ID_WIDTH-1:0] gw_kernel_id;
    wire gw_is_l1_target;
    wire [LANE_SEL_WIDTH-1:0] gw_lane_idx;

    wire l1_cfg_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] l1_cfg_weight_data;
    wire l1_cfg_weight_last;
    wire [LANE_SEL_WIDTH-1:0] l1_cfg_weight_lane;
    wire l1_cfg_weight_ready;
    wire l1_scan_ready;
    wire l1_scan_busy;
    wire l1_scan_done;

    assign cfg_weight_ready = gw_weight_ready;
    assign cfg_weight_done = gw_load_done;
    assign cfg_last_err = gw_cfg_last_err;

    assign dbg_gw_weight_dst2d = gw_weight_dst2d;
    assign dbg_gw_weight_idx = gw_weight_idx;
    assign dbg_gw_dst_last = gw_dst_last;
    assign dbg_gw_load_busy = gw_load_busy;
    assign dbg_gw_preload_done = preload_done_reg;
    assign dbg_gw_is_l1_target = gw_is_l1_target;
    assign dbg_gw_lane_idx = gw_lane_idx;

    assign gw_layer_id = gw_weight_dst2d[DST2D_WIDTH-1:KERNEL_ID_WIDTH];
    assign gw_kernel_id = gw_weight_dst2d[KERNEL_ID_WIDTH-1:0];
    assign gw_is_l1_target = (gw_layer_id == LAYER0_ID) && (gw_kernel_id < L0_KERNEL_NUM);
    assign gw_lane_idx = gw_kernel_id[LANE_SEL_WIDTH-1:0];

    // 第一层目标走本地 6 路握手, 其他层目标当前阶段直接吞掉
    assign gw_weight_ready = gw_is_l1_target ? l1_cfg_weight_ready : 1'b1;

    assign l1_cfg_weight_valid = gw_weight_valid && gw_is_l1_target;
    assign l1_cfg_weight_data = gw_weight_data;
    assign l1_cfg_weight_last = gw_dst_last && gw_is_l1_target;
    assign l1_cfg_weight_lane = gw_lane_idx;

    // 当前阶段要求全局预装载完成后再允许启动第一层扫描
    assign scan_ready = l1_scan_ready && preload_done_reg;
    assign scan_busy = l1_scan_busy || gw_load_busy;
    assign scan_done = l1_scan_done;

    wgt_dist_global #(
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .LAYER_ID_WIDTH(LAYER_ID_WIDTH),
        .KERNEL_ID_WIDTH(KERNEL_ID_WIDTH),
        .WEIGHT_IDX_WIDTH(WEIGHT_IDX_WIDTH),
        .L0_KERNEL_NUM(L0_KERNEL_NUM),
        .L0_WEIGHT_NUM(L0_WEIGHT_NUM),
        .L1_KERNEL_NUM(L1_KERNEL_NUM),
        .L1_WEIGHT_NUM(L1_WEIGHT_NUM),
        .DST2D_WIDTH(DST2D_WIDTH)
    ) u_wgt_dist_global (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .weight_ready(gw_weight_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .weight_valid(gw_weight_valid),
        .weight_data(gw_weight_data),
        .weight_dst2d(gw_weight_dst2d),
        .weight_idx(gw_weight_idx),
        .dst_last(gw_dst_last),
        .load_busy(gw_load_busy),
        .load_done(gw_load_done),
        .cfg_last_err(gw_cfg_last_err)
    );

    l1_core #(
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
    ) u_l1_core (
        .clk(clk),
        .rstn(rstn),
        .frame_start(frame_start),
        .image_tdata(image_tdata),
        .image_tvalid(image_tvalid),
        .cfg_weight_valid(l1_cfg_weight_valid),
        .cfg_weight_data(l1_cfg_weight_data),
        .cfg_weight_last(l1_cfg_weight_last),
        .cfg_weight_lane(l1_cfg_weight_lane),
        .scan_start(scan_start && preload_done_reg),
        .frame_release(frame_release),
        .out_ready(out_ready),
        .ofmap_rd_en(ofmap_rd_en),
        .ofmap_rd_addr2d(ofmap_rd_addr2d),
        .ofmap_rd_done(ofmap_rd_done),
        .cfg_weight_ready(l1_cfg_weight_ready),
        .image_tready(image_tready),
        .scan_ready(l1_scan_ready),
        .cfg_weight_done(),
        .img_wr_done(img_wr_done),
        .img_frame_valid(img_frame_valid),
        .scan_busy(l1_scan_busy),
        .scan_done(l1_scan_done),
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

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            preload_done_reg <= 1'b0;
        end
        else if(gw_load_done)
        begin
            preload_done_reg <= 1'b1;
        end
    end

endmodule
