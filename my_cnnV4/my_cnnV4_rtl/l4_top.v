`timescale 1ns / 1ns
// 第四层 relu+pool 12 路顶层
// 1. 接收第三层 12 路 8x8 特征图缓存读口
// 2. 复用 12 路单通道 relu+pool 封装并行处理
// 3. 输出 12 路 4x4 池化结果缓存读口给后级使用
module l4_top
#(
    parameter LANE_NUM = 12,
    parameter IN_WIDTH = 32,
    parameter OUT_WIDTH = 8,
    parameter IMG_W = 8,
    parameter IMG_H = 8,
    parameter K = 2,
    parameter STRIDE = 2,
    parameter SHIFT_BITS = 10,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter OUT_W = ((IMG_W - K) / STRIDE) + 1,
    parameter OUT_H = ((IMG_H - K) / STRIDE) + 1,
    parameter OUT_ADDR_WIDTH = 6
)
(
    input  clk,                                                        // 时钟
    input  rstn,                                                       // 低有效复位
    input  start,                                                      // 12 路同时启动
    input  [LANE_NUM-1:0] src_frame_valid,                             // 上一级各路输入帧有效
    input  signed [LANE_NUM*IN_WIDTH-1:0] src_rd_data,                 // 上一级各路读回数据
    input  [LANE_NUM-1:0] src_rd_valid,                                // 上一级各路读回有效
    input  [LANE_NUM-1:0] dst_rd_en,                                   // 下一级各路读输出使能
    input  [LANE_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d,                  // 下一级各路读输出地址
    input  [LANE_NUM-1:0] dst_rd_done,                                 // 下一级各路读完整帧

    output ready,                                                      // 12 路都可启动
    output busy,                                                       // 任一路忙
    output reg done,                                                   // 12 路全部完成脉冲
    output [LANE_NUM-1:0] src_rd_en,                                   // 读上一级缓存使能
    output [LANE_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d,                  // 读上一级缓存地址
    output [LANE_NUM-1:0] src_rd_done,                                 // 释放上一级各路输入帧
    output [LANE_NUM-1:0] dst_frame_valid,                             // 各路输出帧有效
    output signed [LANE_NUM*OUT_WIDTH-1:0] dst_rd_data,                // 各路输出读数据
    output [LANE_NUM-1:0] dst_rd_valid                                 // 各路输出读有效
);

    reg [LANE_NUM-1:0] start_req;
    reg [LANE_NUM-1:0] done_seen;

    wire [LANE_NUM-1:0] lane_ready;
    wire [LANE_NUM-1:0] lane_busy;
    wire [LANE_NUM-1:0] lane_done;
    wire [LANE_NUM-1:0] lane_src_rd_en;
    wire [LANE_NUM*ADDR2D_WIDTH-1:0] lane_src_rd_addr2d;
    wire [LANE_NUM-1:0] lane_src_rd_done;
    wire [LANE_NUM-1:0] lane_dst_frame_valid;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] lane_dst_rd_data;
    wire [LANE_NUM-1:0] lane_dst_rd_valid;

    assign ready = &lane_ready;
    assign busy = (|start_req) || (|lane_busy);
    assign src_rd_en = lane_src_rd_en;
    assign src_rd_addr2d = lane_src_rd_addr2d;
    assign src_rd_done = lane_src_rd_done;
    assign dst_frame_valid = lane_dst_frame_valid;
    assign dst_rd_data = lane_dst_rd_data;
    assign dst_rd_valid = lane_dst_rd_valid;

    genvar gi;
    generate
        for(gi = 0; gi < LANE_NUM; gi = gi + 1)
        begin: g_pool_lane
            wire start_lane;
            wire signed [IN_WIDTH-1:0] src_rd_data_i;
            wire [ADDR2D_WIDTH-1:0] dst_rd_addr2d_i;
            wire [ADDR2D_WIDTH-1:0] src_rd_addr2d_i;
            wire signed [OUT_WIDTH-1:0] dst_rd_data_i;

            assign start_lane = start && lane_ready[gi];
            assign src_rd_data_i = src_rd_data[((gi + 1) * IN_WIDTH) - 1 -: IN_WIDTH];
            assign dst_rd_addr2d_i = dst_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign lane_src_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = src_rd_addr2d_i;
            assign lane_dst_rd_data[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = dst_rd_data_i;

            relu_pool_l2 #(
                .IN_WIDTH(IN_WIDTH),
                .OUT_WIDTH(OUT_WIDTH),
                .IMG_W(IMG_W),
                .IMG_H(IMG_H),
                .K(K),
                .STRIDE(STRIDE),
                .SHIFT_BITS(SHIFT_BITS),
                .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
                .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
                .ADDR2D_WIDTH(ADDR2D_WIDTH),
                .OUT_W(OUT_W),
                .OUT_H(OUT_H),
                .OUT_ADDR_WIDTH(OUT_ADDR_WIDTH)
            ) u_relu_pool_l4 (
                .clk(clk),
                .rstn(rstn),
                .start(start_lane),
                .src_frame_valid(src_frame_valid[gi]),
                .src_rd_data(src_rd_data_i),
                .src_rd_valid(src_rd_valid[gi]),
                .dst_rd_en(dst_rd_en[gi]),
                .dst_rd_addr2d(dst_rd_addr2d_i),
                .dst_rd_done(dst_rd_done[gi]),
                .ready(lane_ready[gi]),
                .busy(lane_busy[gi]),
                .done(lane_done[gi]),
                .src_rd_en(lane_src_rd_en[gi]),
                .src_rd_addr2d(src_rd_addr2d_i),
                .src_rd_done(lane_src_rd_done[gi]),
                .dst_frame_valid(lane_dst_frame_valid[gi]),
                .dst_rd_data(dst_rd_data_i),
                .dst_rd_valid(lane_dst_rd_valid[gi])
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            start_req <= {LANE_NUM{1'b0}};
            done_seen <= {LANE_NUM{1'b0}};
            done <= 1'b0;
        end
        else
        begin
            done <= 1'b0;

            if(start)
            begin
                start_req <= {LANE_NUM{1'b1}};
                done_seen <= {LANE_NUM{1'b0}};
            end

            if(|lane_done)
            begin
                done_seen <= done_seen | lane_done;
            end

            if(&(done_seen | lane_done) && (|start_req))
            begin
                done <= 1'b1;
                start_req <= {LANE_NUM{1'b0}};
            end
        end
    end

endmodule
