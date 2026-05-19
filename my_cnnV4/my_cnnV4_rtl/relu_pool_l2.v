`timescale 1ns / 1ns
// 第二级 relu+pool 单通道封装模块
// 1. 负责管理上一级 24x24 特征图的 2x2 池化窗口读地址
// 2. 例化纯 relu+pool 计算核, 串行处理每个 2x2 窗口
// 3. 把 12x12 的 8bit 结果写入本级输出乒乓缓存
module relu_pool_l2
#(
    parameter IN_WIDTH = 32,
    parameter OUT_WIDTH = 8,
    parameter IMG_W = 24,
    parameter IMG_H = 24,
    parameter K = 2,
    parameter STRIDE = 2,
    parameter SHIFT_BITS = 10,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter OUT_W = ((IMG_W - K) / STRIDE) + 1,
    parameter OUT_H = ((IMG_H - K) / STRIDE) + 1,
    parameter OUT_ADDR_WIDTH = 8
)
(
    input  clk,                                             // 时钟
    input  rstn,                                            // 低有效复位
    input  start,                                           // 启动一次完整 relu+pool
    input  src_frame_valid,                                 // 上一级输入帧有效
    input  signed [IN_WIDTH-1:0] src_rd_data,               // 上一级读回 32bit 数据
    input  src_rd_valid,                                    // 上一级读回有效
    input  dst_rd_en,                                       // 下一级读本模块输出使能
    input  [ADDR2D_WIDTH-1:0] dst_rd_addr2d,                // 下一级读本模块输出地址
    input  dst_rd_done,                                     // 下一级读完整帧

    output ready,                                           // 可启动
    output busy,                                            // 模块忙
    output reg done,                                        // 本轮处理完成脉冲
    output src_rd_en,                                       // 读上一级缓存使能
    output [ADDR2D_WIDTH-1:0] src_rd_addr2d,                // 读上一级缓存地址
    output reg src_rd_done,                                 // 释放上一级输入帧
    output dst_frame_valid,                                 // 本模块输出帧有效
    output signed [OUT_WIDTH-1:0] dst_rd_data,              // 本模块输出读数据
    output dst_rd_valid                                     // 本模块输出读有效
);

    reg run_req;
    reg run_active;
    reg launch_pulse;
    reg rd_pending;
    reg rd_last_pending;
    reg pix_valid_reg;
    reg pix_last_reg;
    reg signed [IN_WIDTH-1:0] pix_data_reg;

    wire pool_rd_addr_valid;
    wire pool_rd_addr_ready;
    wire [ADDR2D_WIDTH-1:0] pool_rd_addr2d;
    wire pool_rd_addr_last;
    wire pool_wr_addr_valid;
    wire pool_wr_last;
    wire pool_addr_busy;
    wire pool_map_done;
    wire [ROW_ADDR_WIDTH-1:0] pool_base_row;
    wire [COL_ADDR_WIDTH-1:0] pool_base_col;
    wire [ROW_ADDR_WIDTH-1:0] pool_wr_row;
    wire [COL_ADDR_WIDTH-1:0] pool_wr_col;
    wire [ADDR2D_WIDTH-1:0] pool_wr_addr2d;

    wire dst_buf_wr_ready;
    wire dst_buf_rd_valid;
    wire dst_buf_frame_valid;
    wire signed [OUT_WIDTH-1:0] dst_buf_rd_data;

    wire launch_cond;
    wire rd_issue_fire;
    wire core_in_fire;
    wire core_in_ready;
    wire core_out_valid;
    wire signed [OUT_WIDTH-1:0] core_out_data;
    wire core_busy;
    wire pool_out_fire;

    assign ready = src_frame_valid
                && !run_req
                && !run_active
                && !rd_pending
                && !pix_valid_reg
                && !core_out_valid
                && dst_buf_wr_ready;

    assign busy = run_req
               || run_active
               || pool_addr_busy
               || rd_pending
               || pix_valid_reg
               || core_busy
               || core_out_valid;

    assign launch_cond = run_req
                      && src_frame_valid
                      && !pool_addr_busy
                      && !rd_pending
                      && !pix_valid_reg
                      && !core_out_valid
                      && dst_buf_wr_ready;

    assign pool_rd_addr_ready = run_active
                             && src_frame_valid
                             && !rd_pending
                             && !pix_valid_reg
                             && core_in_ready
                             && !core_out_valid;

    assign rd_issue_fire = pool_rd_addr_valid && pool_rd_addr_ready;
    assign src_rd_en = rd_issue_fire;
    assign src_rd_addr2d = pool_rd_addr2d;

    assign core_in_fire = pix_valid_reg && core_in_ready;

    // 池化窗口左上角坐标每次按 stride 前进, 写地址改成 12x12 输出坐标
    assign pool_wr_row = pool_base_row / STRIDE;
    assign pool_wr_col = pool_base_col / STRIDE;
    assign pool_wr_addr2d = {pool_wr_row, pool_wr_col};

    assign pool_out_fire = core_out_valid && pool_wr_addr_valid && dst_buf_wr_ready;

    assign dst_frame_valid = dst_buf_frame_valid;
    assign dst_rd_data = dst_buf_rd_data;
    assign dst_rd_valid = dst_buf_rd_valid;

    win_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) u_pool_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .start(launch_pulse),
        .rd_addr_ready(pool_rd_addr_ready),
        .out_fire(pool_out_fire),
        .rd_addr_valid(pool_rd_addr_valid),
        .rd_addr2d(pool_rd_addr2d),
        .rd_addr_last(pool_rd_addr_last),
        .wr_addr_valid(pool_wr_addr_valid),
        .wr_addr2d(),
        .wr_last(pool_wr_last),
        .busy(pool_addr_busy),
        .win_done(),
        .map_done(pool_map_done),
        .cur_base_row(pool_base_row),
        .cur_base_col(pool_base_col),
        .cur_krow(),
        .cur_kcol()
    );

    relu_pool_core #(
        .IN_WIDTH(IN_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .K(K),
        .SHIFT_BITS(SHIFT_BITS)
    ) u_relu_pool_core (
        .clk(clk),
        .rstn(rstn),
        .in_valid(pix_valid_reg),
        .in_data(pix_data_reg),
        .in_last(pix_last_reg),
        .out_ready(dst_buf_wr_ready && pool_wr_addr_valid),
        .in_ready(core_in_ready),
        .out_valid(core_out_valid),
        .out_data(core_out_data),
        .busy(core_busy)
    );

    pingpong_img_buf #(
        .DATA_WIDTH(OUT_WIDTH),
        .IMG_W(OUT_W),
        .IMG_H(OUT_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .DEPTH(OUT_W * OUT_H),
        .ADDR_WIDTH(OUT_ADDR_WIDTH)
    ) u_pool_out_buf (
        .clk(clk),
        .rstn(rstn),
        .wr_valid(core_out_valid),
        .wr_data(core_out_data),
        .wr_addr2d(pool_wr_addr2d),
        .wr_last(pool_wr_last),
        .rd_en(dst_rd_en),
        .rd_addr2d(dst_rd_addr2d),
        .rd_done(dst_rd_done),
        .wr_ready(dst_buf_wr_ready),
        .wr_done(),
        .rd_data(dst_buf_rd_data),
        .rd_valid(dst_buf_rd_valid),
        .rd_frame_valid(dst_buf_frame_valid)
    );

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
            pix_data_reg <= {IN_WIDTH{1'b0}};
            done <= 1'b0;
            src_rd_done <= 1'b0;
        end
        else
        begin
            launch_pulse <= 1'b0;
            done <= 1'b0;
            src_rd_done <= 1'b0;

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
                rd_last_pending <= pool_rd_addr_last;
            end

            if(src_rd_valid)
            begin
                rd_pending <= 1'b0;
                pix_valid_reg <= 1'b1;
                pix_data_reg <= src_rd_data;
                pix_last_reg <= rd_last_pending;
            end

            if(core_in_fire)
            begin
                pix_valid_reg <= 1'b0;
            end

            if(pool_map_done)
            begin
                run_active <= 1'b0;
                done <= 1'b1;
                src_rd_done <= 1'b1;
            end
        end
    end

endmodule
