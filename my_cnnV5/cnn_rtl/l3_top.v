`timescale 1ns / 1ns
// 第三层对外顶层
// 1. 接收全局权重分发器输出的逻辑目标 {layer_id, kernel_id}
// 2. 只把第三层目标 (1,0) ~ (1,11) 翻译给 l3_core
// 3. 每个第三层输出核的 150 个权重拆成 6 组 25 个切片权重
// 4. 第三层权重原始顺序固定为: cin 优先, 再到 12 个输出核, 最后 5x5 tap
// 5. 本版使用本地计数器翻译权重目标, 避免组合除法取模造成时序热点
module l3_top
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
    parameter ADDR1D_WIDTH = 8,
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
    input  clk,                                                // 时钟
    input  rstn,                                               // 低有效复位
    input  start,                                              // 启动一次完整第三层扫描
    input  [SRC_NUM-1:0] src_frame_valid,                      // 上一级 6 路输入帧有效
    input  [SRC_NUM*DATA_WIDTH-1:0] src_rd_data,               // 上一级 6 路读回像素
    input  [SRC_NUM-1:0] src_rd_valid,                         // 上一级 6 路读回有效
    input  cfg_weight_valid,                                   // 全局串行权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,          // 全局串行权重数据
    input  cfg_weight_last,                                    // 全局串行权重最后一拍
    input  [OUT_NUM-1:0] dst_rd_en,                            // 下一级读 12 路输出使能
    input  [OUT_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d,           // 下一级读 12 路输出地址
    input  [OUT_NUM-1:0] dst_rd_done,                          // 下一级读完整帧

    output cfg_weight_ready,                                   // 全局串行权重准备好
    output cfg_weight_done,                                    // 全局预装载完成脉冲
    output cfg_last_err,                                       // 全局 last 时序错误
    output ready,                                              // 第三层可启动
    output busy,                                               // 第三层忙
    output done,                                               // 第三层处理完成脉冲
    output weight_loaded,                                      // 第三层 12 路权重全部装好
    output [SRC_NUM-1:0] src_rd_en,                            // 读上一级 6 路缓存使能
    output [SRC_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d,           // 读上一级 6 路缓存地址
    output [SRC_NUM-1:0] src_rd_done,                          // 释放上一级 6 路输入帧
    output [OUT_NUM-1:0] dst_frame_valid,                      // 12 路输出帧有效
    output signed [OUT_NUM*OUT_WIDTH-1:0] dst_rd_data,         // 12 路输出读数据
    output [OUT_NUM-1:0] dst_rd_valid                          // 12 路输出读有效
);

    localparam [LAYER_ID_WIDTH-1:0] LAYER1_ID = {{(LAYER_ID_WIDTH-1){1'b0}}, 1'b1};
    localparam integer L3_TAP_CNT_WIDTH = (L0_WEIGHT_NUM <= 2) ? 1 : $clog2(L0_WEIGHT_NUM);

    reg preload_done_reg;
    reg l3_weight_decode_valid_reg;
    reg signed [WEIGHT_WIDTH-1:0] l3_weight_decode_data_reg;
    reg l3_weight_pipe_valid_reg;
    reg signed [WEIGHT_WIDTH-1:0] l3_weight_pipe_data_reg;
    reg l3_weight_pipe_last_reg;
    reg [OUT_SEL_WIDTH-1:0] l3_weight_pipe_out_reg;
    reg [SRC_SEL_WIDTH-1:0] l3_weight_pipe_cin_reg;
    reg [SRC_SEL_WIDTH-1:0] l3_route_cin_reg;
    reg [OUT_SEL_WIDTH-1:0] l3_route_out_reg;
    reg [L3_TAP_CNT_WIDTH-1:0] l3_route_tap_reg;

    wire gw_cfg_weight_ready_up;
    wire gw_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] gw_weight_data;
    wire [DST2D_WIDTH-1:0] gw_weight_dst2d;
    wire [WEIGHT_IDX_WIDTH-1:0] gw_weight_idx;
    wire gw_dst_last;
    wire gw_load_busy;
    wire gw_load_done;
    wire gw_cfg_last_err;
    wire gw_weight_ready;
    wire [LAYER_ID_WIDTH-1:0] gw_layer_id;
    wire [KERNEL_ID_WIDTH-1:0] gw_kernel_id;
    wire gw_is_l3_target;

    wire l3_cfg_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] l3_cfg_weight_data;
    wire l3_cfg_weight_last;
    wire [OUT_SEL_WIDTH-1:0] l3_cfg_weight_out;
    wire [SRC_SEL_WIDTH-1:0] l3_cfg_weight_cin;
    wire l3_cfg_weight_ready;
    wire l3_ready;
    wire l3_busy;
    wire l3_done;
    wire l3_weight_loaded;
    wire l3_decode_accept;
    wire l3_pipe_accept;
    wire gw_weight_hold_ready;

    assign cfg_weight_ready = gw_cfg_weight_ready_up;
    assign cfg_weight_done = gw_load_done;
    assign cfg_last_err = gw_cfg_last_err;

    assign gw_layer_id = gw_weight_dst2d[DST2D_WIDTH-1:KERNEL_ID_WIDTH];
    assign gw_kernel_id = gw_weight_dst2d[KERNEL_ID_WIDTH-1:0];
    assign gw_is_l3_target = (gw_layer_id == LAYER1_ID) && (gw_kernel_id < L1_KERNEL_NUM);

    // 第三层目标先进入译码缓冲, 再进入下发缓冲, 用于切断长组合控制路径
    assign l3_decode_accept = !l3_weight_decode_valid_reg || (!l3_weight_pipe_valid_reg || l3_cfg_weight_ready);
    assign l3_pipe_accept = !l3_weight_pipe_valid_reg || l3_cfg_weight_ready;
    assign gw_weight_hold_ready = !gw_is_l3_target || l3_decode_accept;
    // 第三层目标走本地权重缓冲握手, 其他目标当前阶段直接吞掉
    assign gw_weight_ready = gw_weight_hold_ready;

    assign l3_cfg_weight_valid = l3_weight_pipe_valid_reg;
    assign l3_cfg_weight_data = l3_weight_pipe_data_reg;
    assign l3_cfg_weight_last = l3_weight_pipe_last_reg;
    assign l3_cfg_weight_out = l3_weight_pipe_out_reg;
    assign l3_cfg_weight_cin = l3_weight_pipe_cin_reg;

    // 当前阶段要求全局预装载完成后再允许启动第三层扫描
    assign ready = l3_ready && preload_done_reg;
    assign busy = l3_busy || gw_load_busy;
    assign done = l3_done;
    assign weight_loaded = l3_weight_loaded;

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
        .cfg_weight_ready(gw_cfg_weight_ready_up),
        .weight_valid(gw_weight_valid),
        .weight_data(gw_weight_data),
        .weight_dst2d(gw_weight_dst2d),
        .weight_idx(gw_weight_idx),
        .dst_last(gw_dst_last),
        .load_busy(gw_load_busy),
        .load_done(gw_load_done),
        .cfg_last_err(gw_cfg_last_err)
    );

    l3_core #(
        .SRC_NUM(SRC_NUM),
        .OUT_NUM(OUT_NUM),
        .SRC_SEL_WIDTH(SRC_SEL_WIDTH),
        .OUT_SEL_WIDTH(OUT_SEL_WIDTH),
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
    ) u_l3_core (
        .clk(clk),
        .rstn(rstn),
        .start(start && preload_done_reg),
        .src_frame_valid(src_frame_valid),
        .src_rd_data(src_rd_data),
        .src_rd_valid(src_rd_valid),
        .cfg_weight_valid(l3_cfg_weight_valid),
        .cfg_weight_data(l3_cfg_weight_data),
        .cfg_weight_last(l3_cfg_weight_last),
        .cfg_weight_out(l3_cfg_weight_out),
        .cfg_weight_cin(l3_cfg_weight_cin),
        .dst_rd_en(dst_rd_en),
        .dst_rd_addr2d(dst_rd_addr2d),
        .dst_rd_done(dst_rd_done),
        .ready(l3_ready),
        .busy(l3_busy),
        .done(l3_done),
        .cfg_weight_ready(l3_cfg_weight_ready),
        .cfg_weight_done(),
        .weight_loaded(l3_weight_loaded),
        .src_rd_en(src_rd_en),
        .src_rd_addr2d(src_rd_addr2d),
        .src_rd_done(src_rd_done),
        .dst_frame_valid(dst_frame_valid),
        .dst_rd_data(dst_rd_data),
        .dst_rd_valid(dst_rd_valid)
    );

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            preload_done_reg <= 1'b0;
            l3_weight_decode_valid_reg <= 1'b0;
            l3_weight_decode_data_reg <= {WEIGHT_WIDTH{1'b0}};
            l3_weight_pipe_valid_reg <= 1'b0;
            l3_weight_pipe_data_reg <= {WEIGHT_WIDTH{1'b0}};
            l3_weight_pipe_last_reg <= 1'b0;
            l3_weight_pipe_out_reg <= {OUT_SEL_WIDTH{1'b0}};
            l3_weight_pipe_cin_reg <= {SRC_SEL_WIDTH{1'b0}};
            l3_route_cin_reg <= {SRC_SEL_WIDTH{1'b0}};
            l3_route_out_reg <= {OUT_SEL_WIDTH{1'b0}};
            l3_route_tap_reg <= {L3_TAP_CNT_WIDTH{1'b0}};
        end
        else
        begin
            if(gw_load_done)
            begin
                preload_done_reg <= 1'b1;
            end

            if(l3_weight_pipe_valid_reg && l3_cfg_weight_ready)
            begin
                l3_weight_pipe_valid_reg <= 1'b0;
            end

            if(l3_weight_decode_valid_reg && l3_pipe_accept)
            begin
                l3_weight_decode_valid_reg <= 1'b0;
                l3_weight_pipe_valid_reg <= 1'b1;
                l3_weight_pipe_data_reg <= l3_weight_decode_data_reg;
                l3_weight_pipe_last_reg <= (l3_route_tap_reg == (L0_WEIGHT_NUM - 1));
                l3_weight_pipe_out_reg <= l3_route_out_reg;
                l3_weight_pipe_cin_reg <= l3_route_cin_reg;

                // 本地计数器严格复现第三层原始权重顺序
                // 顺序为: cin 0~5 -> out 0~11 -> tap 0~24
                if(l3_route_tap_reg == (L0_WEIGHT_NUM - 1))
                begin
                    l3_route_tap_reg <= {L3_TAP_CNT_WIDTH{1'b0}};
                    if(l3_route_out_reg == (OUT_NUM - 1))
                    begin
                        l3_route_out_reg <= {OUT_SEL_WIDTH{1'b0}};
                        if(l3_route_cin_reg == (SRC_NUM - 1))
                        begin
                            l3_route_cin_reg <= {SRC_SEL_WIDTH{1'b0}};
                        end
                        else
                        begin
                            l3_route_cin_reg <= l3_route_cin_reg + 1'b1;
                        end
                    end
                    else
                    begin
                        l3_route_out_reg <= l3_route_out_reg + 1'b1;
                    end
                end
                else
                begin
                    l3_route_tap_reg <= l3_route_tap_reg + 1'b1;
                end
            end

            if(gw_weight_valid && gw_weight_hold_ready && gw_is_l3_target)
            begin
                l3_weight_decode_valid_reg <= 1'b1;
                l3_weight_decode_data_reg <= gw_weight_data;
            end
        end
    end

endmodule