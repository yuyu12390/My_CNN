`timescale 1ns / 1ns
// 第一层 6 核计算核心
// 1. 共享 1 套图像输入缓存和 1 套统一地址管理器
// 2. 同一窗口像素广播给 6 个卷积核并行计算
// 3. 6 路卷积结果同拍写入 6 个输出乒乓缓存
module l1_core
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
    input  cfg_weight_valid,                               // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,      // 权重输入数据
    input  cfg_weight_last,                                // 当前卷积核最后一拍
    input  [LANE_SEL_WIDTH-1:0] cfg_weight_lane,           // 权重目标卷积核编号
    input  scan_start,                                     // 窗口扫描开始
    input  frame_release,                                  // 释放当前图像帧
    input  out_ready,                                      // 允许 6 路结果一起提交
    input  [LANE_NUM-1:0] ofmap_rd_en,                     // 下一级各路读使能
    input  [LANE_NUM*ADDR2D_WIDTH-1:0] ofmap_rd_addr2d,    // 下一级各路读二维地址
    input  [LANE_NUM-1:0] ofmap_rd_done,                   // 下一级各路读完整帧

    output cfg_weight_ready,                               // 当前选中卷积核权重准备好
    output image_tready,                                   // 图像输入准备好
    output scan_ready,                                     // 扫描可启动
    output cfg_weight_done,                                // 任一路权重装载完成脉冲
    output img_wr_done,                                    // 图像写完一帧脉冲
    output img_frame_valid,                                // 图像帧有效
    output scan_busy,                                      // 扫描忙
    output reg scan_done,                                  // 扫描完成脉冲
    output out_valid,                                      // 6 路结果同时有效
    output signed [OUT_WIDTH-1:0] out_data,                // 0 号卷积核结果
    output weight_loaded,                                  // 6 路权重全部装好
    output conv_busy,                                      // 任一路卷积核忙
    output [LANE_NUM-1:0] lane_cfg_weight_ready,           // 各路权重准备好
    output [LANE_NUM-1:0] lane_cfg_weight_done,            // 各路权重装载完成脉冲
    output [LANE_NUM-1:0] lane_weight_loaded,              // 各路权重装好
    output [LANE_NUM-1:0] lane_conv_busy,                  // 各路卷积核忙
    output [LANE_NUM-1:0] lane_out_valid,                  // 各路结果有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] lane_out_data,  // 各路结果数据
    output [ADDR2D_WIDTH-1:0] dbg_img_wr_addr2d,           // 调试写二维地址
    output [ADDR2D_WIDTH-1:0] dbg_win_addr2d,              // 调试读二维地址
    output dbg_win_addr_last,                              // 调试窗口尾地址
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
    output [LANE_NUM-1:0] ofmap_rd_valid                   // 各路输出缓存读有效
);

    reg scan_req;
    reg scan_running;
    reg scan_launch_pulse;
    reg scan_all_seen;
    reg rd_pending;
    reg rd_last_pending;
    reg pix_valid_reg;
    reg [DATA_WIDTH-1:0] pix_data_reg;
    reg pix_last_reg;
    reg [LANE_NUM-1:0] cfg_weight_lane_hit;
    reg cfg_weight_ready_reg;

    integer lane_idx;

    wire img_addr_valid;
    wire img_addr_ready;
    wire [ADDR2D_WIDTH-1:0] img_addr2d;
    wire img_addr_last;
    wire img_frame_busy;
    wire img_frame_done;
    wire [ROW_ADDR_WIDTH-1:0] img_cur_row;
    wire [COL_ADDR_WIDTH-1:0] img_cur_col;
    wire buf_wr_done;
    wire buf_frame_valid;
    wire [DATA_WIDTH-1:0] buf_rd_data;
    wire buf_rd_valid;
    wire [ADDR1D_WIDTH-1:0] dbg_wr_addr1d_unused;
    wire [ADDR1D_WIDTH-1:0] dbg_rd_addr1d_unused;

    wire l1_rd_addr_valid;
    wire l1_rd_addr_ready;
    wire [ADDR2D_WIDTH-1:0] l1_rd_addr2d;
    wire l1_rd_addr_last;
    wire l1_wr_addr_valid;
    wire [ADDR2D_WIDTH-1:0] l1_wr_addr2d;
    wire l1_wr_last;
    wire l1_addr_busy;
    wire l1_map_done;
    wire [ROW_ADDR_WIDTH-1:0] l1_base_row;
    wire [COL_ADDR_WIDTH-1:0] l1_base_col;
    wire [ROW_ADDR_WIDTH-1:0] l1_krow;
    wire [COL_ADDR_WIDTH-1:0] l1_kcol;

    wire [LANE_NUM-1:0] lane_in_ready_vec;
    wire [LANE_NUM-1:0] lane_cfg_weight_ready_vec;
    wire [LANE_NUM-1:0] lane_cfg_weight_done_vec;
    wire [LANE_NUM-1:0] lane_out_valid_vec;
    wire [LANE_NUM-1:0] lane_conv_busy_vec;
    wire [LANE_NUM-1:0] lane_weight_loaded_vec;
    wire [LANE_NUM-1:0] lane_ofmap_wr_ready_vec;
    wire [LANE_NUM-1:0] lane_ofmap_wr_done_vec;
    wire [LANE_NUM-1:0] lane_ofmap_frame_valid_vec;
    wire [LANE_NUM-1:0] lane_ofmap_rd_valid_vec;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] lane_out_data_bus;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] lane_ofmap_rd_data_bus;

    wire scan_launch_cond;
    wire scan_finish_cond;
    wire rd_issue_fire;
    wire conv_in_fire;
    wire all_conv_in_ready;
    wire all_lane_out_valid;
    wire any_lane_out_valid;
    wire all_lane_ofmap_wr_ready;
    wire all_lane_commit_fire;

    assign dbg_img_wr_addr2d = img_addr2d;
    assign dbg_win_addr2d = l1_rd_addr2d;
    assign dbg_win_addr_last = l1_rd_addr_last;
    assign dbg_out_wr_addr2d = l1_wr_addr2d;
    assign dbg_out_wr_last = l1_wr_last;
    assign dbg_win_base_row = l1_base_row;
    assign dbg_win_base_col = l1_base_col;
    assign dbg_win_krow = l1_krow;
    assign dbg_win_kcol = l1_kcol;
    assign dbg_rd_pending = rd_pending;
    assign dbg_pix_valid = pix_valid_reg;
    assign dbg_conv_in_last = pix_last_reg;

    assign img_wr_done = buf_wr_done;
    assign img_frame_valid = buf_frame_valid;
    assign lane_cfg_weight_ready = lane_cfg_weight_ready_vec;
    assign lane_cfg_weight_done = lane_cfg_weight_done_vec;
    assign lane_weight_loaded = lane_weight_loaded_vec;
    assign lane_conv_busy = lane_conv_busy_vec;
    assign lane_out_valid = lane_out_valid_vec;
    assign lane_out_data = lane_out_data_bus;
    assign lane_ofmap_wr_ready = lane_ofmap_wr_ready_vec;
    assign lane_ofmap_wr_done = lane_ofmap_wr_done_vec;
    assign lane_ofmap_frame_valid = lane_ofmap_frame_valid_vec;
    assign ofmap_rd_data = lane_ofmap_rd_data_bus;
    assign ofmap_rd_valid = lane_ofmap_rd_valid_vec;

    assign cfg_weight_ready = cfg_weight_ready_reg;
    assign cfg_weight_done = |lane_cfg_weight_done_vec;
    assign weight_loaded = &lane_weight_loaded_vec;
    assign conv_busy = |lane_conv_busy_vec;
    assign out_valid = all_lane_out_valid;
    assign out_data = lane_out_data_bus[OUT_WIDTH-1:0];
    assign ofmap_wr_ready = all_lane_ofmap_wr_ready;
    assign ofmap_wr_done = &lane_ofmap_wr_done_vec;
    assign ofmap_frame_valid = &lane_ofmap_frame_valid_vec;

    // 只有图像帧有效、6 路权重已装好且各级都空闲时, 才允许启动一次完整扫描
    assign scan_launch_cond = scan_req
                           && !scan_running
                           && buf_frame_valid
                           && weight_loaded
                           && !l1_addr_busy
                           && !rd_pending
                           && !pix_valid_reg
                           && !conv_busy
                           && !any_lane_out_valid;

    // 只有全部窗口地址发完且读回和 6 路卷积结果都完全清空后, 才认为扫描结束
    assign scan_finish_cond = scan_running
                           && scan_all_seen
                           && !l1_addr_busy
                           && !rd_pending
                           && !pix_valid_reg
                           && !conv_busy
                           && !any_lane_out_valid;

    assign scan_ready = buf_frame_valid
                     && weight_loaded
                     && !scan_req
                     && !scan_running
                     && !l1_addr_busy
                     && !rd_pending
                     && !pix_valid_reg
                     && !conv_busy
                     && !any_lane_out_valid;

    assign scan_busy = scan_req
                    || scan_running
                    || l1_addr_busy
                    || rd_pending
                    || pix_valid_reg
                    || conv_busy
                    || any_lane_out_valid;

    // 顶层桥接采用单个未完成读请求, 只有 6 路都能同步接收时才继续发新地址
    assign all_conv_in_ready = &lane_in_ready_vec;
    assign all_lane_out_valid = &lane_out_valid_vec;
    assign any_lane_out_valid = |lane_out_valid_vec;
    assign all_lane_ofmap_wr_ready = &lane_ofmap_wr_ready_vec;

    assign l1_rd_addr_ready = scan_running
                           && buf_frame_valid
                           && !rd_pending
                           && !pix_valid_reg
                           && all_conv_in_ready;

    assign rd_issue_fire = l1_rd_addr_valid && l1_rd_addr_ready;
    assign conv_in_fire = pix_valid_reg && all_conv_in_ready;

    // 只有 6 路结果都有效且 6 路输出缓存都准备好后, 才允许同拍提交
    assign all_lane_commit_fire = out_ready
                               && l1_wr_addr_valid
                               && all_lane_out_valid
                               && all_lane_ofmap_wr_ready;

    always @(*)
    begin
        cfg_weight_lane_hit = {LANE_NUM{1'b0}};
        if(cfg_weight_lane < LANE_NUM)
        begin
            cfg_weight_lane_hit[cfg_weight_lane] = 1'b1;
        end
    end

    always @(*)
    begin
        cfg_weight_ready_reg = 1'b0;
        if(cfg_weight_lane < LANE_NUM)
        begin
            cfg_weight_ready_reg = lane_cfg_weight_ready_vec[cfg_weight_lane];
        end
    end

    img_in_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) u_img_in_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .frame_start(frame_start),
        .addr_ready(img_addr_ready),
        .addr_valid(img_addr_valid),
        .addr2d(img_addr2d),
        .addr_last(img_addr_last),
        .frame_busy(img_frame_busy),
        .frame_done(img_frame_done),
        .cur_row(img_cur_row),
        .cur_col(img_cur_col)
    );

    img_in_buf #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .DEPTH(IMG_W * IMG_H),
        .ADDR1D_WIDTH(ADDR1D_WIDTH)
    ) u_img_in_buf (
        .clk(clk),
        .rstn(rstn),
        .image_tdata(image_tdata),
        .image_tvalid(image_tvalid),
        .addr_valid(img_addr_valid),
        .addr2d(img_addr2d),
        .addr_last(img_addr_last),
        .rd_en(rd_issue_fire),
        .rd_addr2d(l1_rd_addr2d),
        .rd_done(frame_release),
        .image_tready(image_tready),
        .addr_ready(img_addr_ready),
        .wr_done(buf_wr_done),
        .frame_valid(buf_frame_valid),
        .rd_data(buf_rd_data),
        .rd_valid(buf_rd_valid),
        .dbg_wr_addr1d(dbg_wr_addr1d_unused),
        .dbg_rd_addr1d(dbg_rd_addr1d_unused)
    );

    l1_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) u_l1_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .start(scan_launch_pulse),
        .rd_addr_ready(l1_rd_addr_ready),
        .out_fire(all_lane_commit_fire),
        .rd_addr_valid(l1_rd_addr_valid),
        .rd_addr2d(l1_rd_addr2d),
        .rd_addr_last(l1_rd_addr_last),
        .wr_addr_valid(l1_wr_addr_valid),
        .wr_addr2d(l1_wr_addr2d),
        .wr_last(l1_wr_last),
        .busy(l1_addr_busy),
        .win_done(),
        .map_done(l1_map_done),
        .cur_base_row(l1_base_row),
        .cur_base_col(l1_base_col),
        .cur_krow(l1_krow),
        .cur_kcol(l1_kcol)
    );

    genvar gi;
    generate
        for(gi = 0; gi < LANE_NUM; gi = gi + 1)
        begin: g_lane
            wire lane_cfg_weight_valid_i;
            wire lane_cfg_weight_last_i;
            wire lane_in_valid_i;
            wire signed [OUT_WIDTH-1:0] lane_out_data_i;
            wire signed [OUT_WIDTH-1:0] lane_ofmap_rd_data_i;
            wire [ADDR2D_WIDTH-1:0] lane_ofmap_rd_addr2d_i;
            wire lane_ofmap_wr_bank_sel_unused;
            wire lane_ofmap_rd_bank_sel_unused;
            wire lane_ofmap_bank0_valid_unused;
            wire lane_ofmap_bank1_valid_unused;

            assign lane_cfg_weight_valid_i = cfg_weight_valid && cfg_weight_lane_hit[gi];
            assign lane_cfg_weight_last_i = cfg_weight_last && cfg_weight_lane_hit[gi];
            assign lane_in_valid_i = pix_valid_reg && all_conv_in_ready;
            assign lane_ofmap_rd_addr2d_i = ofmap_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign lane_out_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = lane_out_data_i;
            assign lane_ofmap_rd_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = lane_ofmap_rd_data_i;

            conv_l1 #(
                .DATA_WIDTH(DATA_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .K(K),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_conv_l1 (
                .clk(clk),
                .rstn(rstn),
                .cfg_weight_valid(lane_cfg_weight_valid_i),
                .cfg_weight_data(cfg_weight_data),
                .cfg_weight_last(lane_cfg_weight_last_i),
                .in_valid(lane_in_valid_i),
                .in_data(pix_data_reg),
                .in_last(pix_last_reg),
                .out_ready(all_lane_commit_fire),
                .cfg_weight_ready(lane_cfg_weight_ready_vec[gi]),
                .cfg_weight_done(lane_cfg_weight_done_vec[gi]),
                .in_ready(lane_in_ready_vec[gi]),
                .out_valid(lane_out_valid_vec[gi]),
                .out_data(lane_out_data_i),
                .busy(lane_conv_busy_vec[gi]),
                .weight_loaded(lane_weight_loaded_vec[gi])
            );

            pingpong_img_buf #(
                .DATA_WIDTH(OUT_WIDTH),
                .IMG_W(OFMAP_W),
                .IMG_H(OFMAP_H),
                .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
                .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
                .ADDR2D_WIDTH(ADDR2D_WIDTH),
                .DEPTH(OFMAP_W * OFMAP_H),
                .ADDR_WIDTH(ADDR1D_WIDTH)
            ) u_ofmap_buf (
                .clk(clk),
                .rstn(rstn),
                .wr_valid(all_lane_commit_fire),
                .wr_data(lane_out_data_i),
                .wr_addr2d(l1_wr_addr2d),
                .wr_last(l1_wr_last),
                .rd_en(ofmap_rd_en[gi]),
                .rd_addr2d(lane_ofmap_rd_addr2d_i),
                .rd_done(ofmap_rd_done[gi]),
                .wr_ready(lane_ofmap_wr_ready_vec[gi]),
                .wr_done(lane_ofmap_wr_done_vec[gi]),
                .rd_data(lane_ofmap_rd_data_i),
                .rd_valid(lane_ofmap_rd_valid_vec[gi]),
                .rd_frame_valid(lane_ofmap_frame_valid_vec[gi]),
                .wr_bank_sel(lane_ofmap_wr_bank_sel_unused),
                .rd_bank_sel(lane_ofmap_rd_bank_sel_unused),
                .bank0_valid(lane_ofmap_bank0_valid_unused),
                .bank1_valid(lane_ofmap_bank1_valid_unused)
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            scan_req <= 1'b0;
            scan_running <= 1'b0;
            scan_launch_pulse <= 1'b0;
            scan_all_seen <= 1'b0;
            scan_done <= 1'b0;
            rd_pending <= 1'b0;
            rd_last_pending <= 1'b0;
            pix_valid_reg <= 1'b0;
            pix_data_reg <= {DATA_WIDTH{1'b0}};
            pix_last_reg <= 1'b0;
        end
        else
        begin
            scan_launch_pulse <= 1'b0;
            scan_done <= 1'b0;

            if(scan_start)
            begin
                scan_req <= 1'b1;
            end

            if(scan_launch_cond)
            begin
                scan_req <= 1'b0;
                scan_running <= 1'b1;
                scan_launch_pulse <= 1'b1;
                scan_all_seen <= 1'b0;
            end

            if(l1_map_done)
            begin
                scan_all_seen <= 1'b1;
            end

            if(scan_finish_cond)
            begin
                scan_running <= 1'b0;
                scan_done <= 1'b1;
            end

            // 地址一旦发出, 顶层记住当前请求仍在等待图像缓存返回
            if(rd_issue_fire)
            begin
                rd_pending <= 1'b1;
                rd_last_pending <= l1_rd_addr_last;
            end

            // 图像缓存返回 1 个像素后, 先在顶层保持住, 再同步交给 6 路卷积核消费
            if(buf_rd_valid)
            begin
                rd_pending <= 1'b0;
                pix_valid_reg <= 1'b1;
                pix_data_reg <= buf_rd_data;
                pix_last_reg <= rd_last_pending;
            end

            if(conv_in_fire)
            begin
                pix_valid_reg <= 1'b0;
            end
        end
    end

endmodule
