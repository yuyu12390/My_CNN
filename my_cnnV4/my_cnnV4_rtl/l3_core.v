`timescale 1ns / 1ns

// 第三层局部集成核心
// 1. 复用 1 套窗口地址管理器, 统一扫描 6 路 12x12 输入特征图
// 2. 同拍读取 6 路输入像素, 广播给 12 个 l3_out_core
// 3. 12 路输出结果同拍写入 12 个 8x8 输出乒乓缓存
module l3_core
#(
    parameter SRC_NUM = 6,
    parameter OUT_NUM = 12,
    parameter SRC_SEL_WIDTH = (SRC_NUM <= 2) ? 1 : $clog2(SRC_NUM),
    parameter OUT_SEL_WIDTH = (OUT_NUM <= 2) ? 1 : $clog2(OUT_NUM),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter IMG_W = 12,
    parameter IMG_H = 12,
    parameter K = 5,
    parameter STRIDE = 1,
    parameter OUT_WIDTH = 32,
    parameter OFMAP_W = ((IMG_W - K) / STRIDE) + 1,
    parameter OFMAP_H = ((IMG_H - K) / STRIDE) + 1,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter ADDR1D_WIDTH = 8
)
(
    input  clk,                                                // 时钟
    input  rstn,                                               // 低有效复位
    input  start,                                              // 启动一次完整第三层扫描
    input  [SRC_NUM-1:0] src_frame_valid,                      // 上一级 6 路输入帧有效
    input  [SRC_NUM*DATA_WIDTH-1:0] src_rd_data,               // 上一级 6 路读回像素
    input  [SRC_NUM-1:0] src_rd_valid,                         // 上一级 6 路读回有效
    input  cfg_weight_valid,                                   // 本级权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,          // 本级权重输入数据
    input  cfg_weight_last,                                    // 当前 5x5 权重组最后一拍
    input  [OUT_SEL_WIDTH-1:0] cfg_weight_out,                 // 权重目标输出通道号
    input  [SRC_SEL_WIDTH-1:0] cfg_weight_cin,                 // 权重目标输入通道号
    input  [OUT_NUM-1:0] dst_rd_en,                            // 下一级读 12 路输出使能
    input  [OUT_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d,           // 下一级读 12 路输出地址
    input  [OUT_NUM-1:0] dst_rd_done,                          // 下一级读完整帧

    output ready,                                              // 本级可启动
    output busy,                                               // 本级忙
    output reg done,                                           // 本轮处理完成脉冲
    output cfg_weight_ready,                                   // 当前目标输出核准备接收权重
    output cfg_weight_done,                                    // 任一目标输出核装完 1 组权重脉冲
    output weight_loaded,                                      // 12 个输出核权重全部装好
    output [SRC_NUM-1:0] src_rd_en,                            // 读上一级 6 路缓存使能
    output [SRC_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d,           // 读上一级 6 路缓存地址
    output reg [SRC_NUM-1:0] src_rd_done,                      // 释放上一级 6 路输入帧
    output [OUT_NUM-1:0] dst_frame_valid,                      // 12 路输出帧有效
    output signed [OUT_NUM*OUT_WIDTH-1:0] dst_rd_data,         // 12 路输出读数据
    output [OUT_NUM-1:0] dst_rd_valid                          // 12 路输出读有效
);

    reg run_req;
    reg run_active;
    reg launch_pulse;
    reg rd_pending;
    reg rd_last_pending;
    reg pix_valid_reg;
    reg pix_last_reg;
    reg [SRC_NUM*DATA_WIDTH-1:0] pix_data_reg;
    reg [OUT_NUM-1:0] cfg_weight_out_hit;
    reg cfg_weight_ready_reg;

    integer out_idx;

    wire all_src_frame_valid;
    wire all_src_rd_valid;
    wire l3_rd_addr_valid;
    wire l3_rd_addr_ready;
    wire [ADDR2D_WIDTH-1:0] l3_rd_addr2d;
    wire l3_rd_addr_last;
    wire l3_wr_addr_valid;
    wire [ADDR2D_WIDTH-1:0] l3_wr_addr2d;
    wire l3_wr_last;
    wire l3_addr_busy;
    wire l3_map_done;

    wire [OUT_NUM-1:0] outcore_cfg_weight_ready_vec;
    wire [OUT_NUM-1:0] outcore_cfg_weight_done_vec;
    wire [OUT_NUM-1:0] outcore_in_ready_vec;
    wire [OUT_NUM-1:0] outcore_out_valid_vec;
    wire [OUT_NUM-1:0] outcore_busy_vec;
    wire [OUT_NUM-1:0] outcore_weight_loaded_vec;
    wire [OUT_NUM-1:0] dst_buf_wr_ready_vec;
    wire [OUT_NUM-1:0] dst_frame_valid_vec;
    wire [OUT_NUM-1:0] dst_rd_valid_vec;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] outcore_out_data_bus;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] dst_rd_data_bus;

    wire launch_cond;
    wire rd_issue_fire;
    wire all_outcore_in_ready;
    wire all_outcore_out_valid;
    wire any_outcore_busy;
    wire any_outcore_out_valid;
    wire all_dst_buf_wr_ready;
    wire all_outcore_commit_fire;

    assign all_src_frame_valid = &src_frame_valid;
    assign all_src_rd_valid = &src_rd_valid;

    assign cfg_weight_ready = cfg_weight_ready_reg;
    assign cfg_weight_done = |outcore_cfg_weight_done_vec;
    assign weight_loaded = &outcore_weight_loaded_vec;

    assign all_outcore_in_ready = &outcore_in_ready_vec;
    assign all_outcore_out_valid = &outcore_out_valid_vec;
    assign any_outcore_busy = |outcore_busy_vec;
    assign any_outcore_out_valid = |outcore_out_valid_vec;
    assign all_dst_buf_wr_ready = &dst_buf_wr_ready_vec;

    assign ready = all_src_frame_valid
                && weight_loaded
                && !run_req
                && !run_active
                && !l3_addr_busy
                && !rd_pending
                && !pix_valid_reg
                && !any_outcore_busy
                && !any_outcore_out_valid
                && all_dst_buf_wr_ready;

    assign busy = run_req
               || run_active
               || l3_addr_busy
               || rd_pending
               || pix_valid_reg
               || any_outcore_busy
               || any_outcore_out_valid;

    assign launch_cond = run_req
                      && all_src_frame_valid
                      && weight_loaded
                      && !l3_addr_busy
                      && !rd_pending
                      && !pix_valid_reg
                      && !any_outcore_busy
                      && !any_outcore_out_valid
                      && all_dst_buf_wr_ready;

    assign l3_rd_addr_ready = run_active
                           && all_src_frame_valid
                           && !rd_pending
                           && !pix_valid_reg
                           && all_outcore_in_ready
                           && !any_outcore_out_valid;

    assign rd_issue_fire = l3_rd_addr_valid && l3_rd_addr_ready;
    assign src_rd_en = {SRC_NUM{rd_issue_fire}};

    // 12 路输出核和 12 路输出缓存必须同拍全部准备好, 才推进到下一个输出点
    assign all_outcore_commit_fire = l3_wr_addr_valid
                                  && all_outcore_out_valid
                                  && all_dst_buf_wr_ready;

    assign dst_frame_valid = dst_frame_valid_vec;
    assign dst_rd_data = dst_rd_data_bus;
    assign dst_rd_valid = dst_rd_valid_vec;

    always @(*)
    begin
        cfg_weight_out_hit = {OUT_NUM{1'b0}};
        if(cfg_weight_out < OUT_NUM)
        begin
            cfg_weight_out_hit[cfg_weight_out] = 1'b1;
        end
    end

    always @(*)
    begin
        cfg_weight_ready_reg = 1'b0;
        if(cfg_weight_out < OUT_NUM)
        begin
            cfg_weight_ready_reg = outcore_cfg_weight_ready_vec[cfg_weight_out];
        end
    end

    win_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) u_l3_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .start(launch_pulse),
        .rd_addr_ready(l3_rd_addr_ready),
        .out_fire(all_outcore_commit_fire),
        .rd_addr_valid(l3_rd_addr_valid),
        .rd_addr2d(l3_rd_addr2d),
        .rd_addr_last(l3_rd_addr_last),
        .wr_addr_valid(l3_wr_addr_valid),
        .wr_addr2d(l3_wr_addr2d),
        .wr_last(l3_wr_last),
        .busy(l3_addr_busy),
        .win_done(),
        .map_done(l3_map_done),
        .cur_base_row(),
        .cur_base_col(),
        .cur_krow(),
        .cur_kcol()
    );

    genvar si;
    generate
        for(si = 0; si < SRC_NUM; si = si + 1)
        begin: g_src_addr
            assign src_rd_addr2d[((si + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = l3_rd_addr2d;
        end
    endgenerate

    genvar gi;
    generate
        for(gi = 0; gi < OUT_NUM; gi = gi + 1)
        begin: g_l3_out
            wire out_cfg_weight_valid_i;
            wire out_cfg_weight_last_i;
            wire out_in_valid_i;
            wire [ADDR2D_WIDTH-1:0] dst_rd_addr2d_i;
            wire signed [OUT_WIDTH-1:0] outcore_out_data_i;
            wire signed [OUT_WIDTH-1:0] dst_rd_data_i;

            assign out_cfg_weight_valid_i = cfg_weight_valid && cfg_weight_out_hit[gi];
            assign out_cfg_weight_last_i = cfg_weight_last && cfg_weight_out_hit[gi];
            assign out_in_valid_i = pix_valid_reg && all_outcore_in_ready;
            assign dst_rd_addr2d_i = dst_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign outcore_out_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = outcore_out_data_i;
            assign dst_rd_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = dst_rd_data_i;

            l3_out_core #(
                .CIN_NUM(SRC_NUM),
                .CIN_SEL_WIDTH(SRC_SEL_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .K(K),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_l3_out_core (
                .clk(clk),
                .rstn(rstn),
                .cfg_weight_valid(out_cfg_weight_valid_i),
                .cfg_weight_data(cfg_weight_data),
                .cfg_weight_last(out_cfg_weight_last_i),
                .cfg_weight_cin(cfg_weight_cin),
                .in_valid(out_in_valid_i),
                .in_data(pix_data_reg),
                .in_last(pix_last_reg),
                .out_ready(all_outcore_commit_fire),
                .cfg_weight_ready(outcore_cfg_weight_ready_vec[gi]),
                .cfg_weight_done(outcore_cfg_weight_done_vec[gi]),
                .in_ready(outcore_in_ready_vec[gi]),
                .out_valid(outcore_out_valid_vec[gi]),
                .out_data(outcore_out_data_i),
                .busy(outcore_busy_vec[gi]),
                .weight_loaded(outcore_weight_loaded_vec[gi])
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
            ) u_l3_ofmap_buf (
                .clk(clk),
                .rstn(rstn),
                .wr_valid(all_outcore_commit_fire),
                .wr_data(outcore_out_data_i),
                .wr_addr2d(l3_wr_addr2d),
                .wr_last(l3_wr_last),
                .rd_en(dst_rd_en[gi]),
                .rd_addr2d(dst_rd_addr2d_i),
                .rd_done(dst_rd_done[gi]),
                .wr_ready(dst_buf_wr_ready_vec[gi]),
                .wr_done(),
                .rd_data(dst_rd_data_i),
                .rd_valid(dst_rd_valid_vec[gi]),
                .rd_frame_valid(dst_frame_valid_vec[gi])
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            run_req <= 1'b0;
            run_active <= 1'b0;
            launch_pulse <= 1'b0;
            rd_pending <= 1'b0;
            rd_last_pending <= 1'b0;
            pix_valid_reg <= 1'b0;
            pix_last_reg <= 1'b0;
            pix_data_reg <= {SRC_NUM*DATA_WIDTH{1'b0}};
            done <= 1'b0;
            src_rd_done <= {SRC_NUM{1'b0}};
        end
        else
        begin
            launch_pulse <= 1'b0;
            done <= 1'b0;
            src_rd_done <= {SRC_NUM{1'b0}};

            if(start)
            begin
                run_req <= 1'b1;
            end

            if(launch_cond)
            begin
                run_req <= 1'b0;
                run_active <= 1'b1;
                launch_pulse <= 1'b1;
            end

            if(rd_issue_fire)
            begin
                rd_pending <= 1'b1;
                rd_last_pending <= l3_rd_addr_last;
            end

            // 6 路输入缓存返回同一窗口的 6 个像素后, 顶层先整体锁存再广播
            if(all_src_rd_valid && rd_pending)
            begin
                rd_pending <= 1'b0;
                pix_valid_reg <= 1'b1;
                pix_data_reg <= src_rd_data;
                pix_last_reg <= rd_last_pending;
            end

            if(pix_valid_reg && all_outcore_in_ready)
            begin
                pix_valid_reg <= 1'b0;
            end

            if(l3_map_done)
            begin
                run_active <= 1'b0;
                done <= 1'b1;
                src_rd_done <= {SRC_NUM{1'b1}};
            end
        end
    end

endmodule
