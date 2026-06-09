`timescale 1ns / 1ns

// 第五层原始FC权重顶层
// 1. 直接接收fcw.txt这种原始FC串行权重流
// 2. 每192个权重分给1个神经元
// 3. 复用fc_addr_mgr, 从上一级12路4x4缓存顺序读出32拍输入
// 4. 10个神经元并行计算, 一次输出10个分类分数
module l5_top_raw
#(
    parameter IN_CH_NUM = 12,
    parameter LANE_NUM = 6,
    parameter OUT_NUM = 10,
    parameter GROUP_NUM = IN_CH_NUM / LANE_NUM,
    parameter GROUP_SEL_WIDTH = (GROUP_NUM <= 2) ? 1 : $clog2(GROUP_NUM),
    parameter OUT_SEL_WIDTH = (OUT_NUM <= 2) ? 1 : $clog2(OUT_NUM),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
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
    input  clk,                                                // 时钟
    input  rstn,                                               // 低有效复位
    input  start,                                              // 启动一次完整第五层计算
    input  [IN_CH_NUM-1:0] src_frame_valid,                    // 上一级12路输入帧有效
    input  signed [IN_CH_NUM*DATA_WIDTH-1:0] src_rd_data,      // 上一级12路读回数据
    input  [IN_CH_NUM-1:0] src_rd_valid,                       // 上一级12路读回有效
    input  cfg_weight_valid,                                   // FC串行权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,          // FC串行权重数据
    input  cfg_weight_last,                                    // FC串行权重最后一拍
    input  score_ready,                                        // 外部结果接收准备好

    output cfg_weight_ready,                                   // FC串行权重准备好
    output cfg_weight_done,                                    // FC预装载完成脉冲
    output cfg_last_err,                                       // FC last时序错误
    output ready,                                              // 第五层可启动
    output busy,                                               // 第五层忙
    output reg done,                                           // 第五层结果就绪脉冲
    output weight_loaded,                                      // 10个神经元权重全部装好
    output [IN_CH_NUM-1:0] src_rd_en,                          // 读上一级12路缓存使能
    output [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d,         // 读上一级12路缓存地址
    output reg [IN_CH_NUM-1:0] src_rd_done,                    // 释放上一级12路输入帧
    output score_valid,                                        // 10路结果整体有效
    output signed [OUT_NUM*OUT_WIDTH-1:0] score_data           // 10路分类分数
);

    reg preload_done_reg;
    reg rd_pending;
    reg [GROUP_SEL_WIDTH-1:0] rd_pending_group;
    reg rd_pending_last;
    reg rsp_valid_reg;
    reg rsp_last_reg;
    reg signed [LANE_NUM*DATA_WIDTH-1:0] rsp_data_reg;
    reg score_valid_dly;

    reg signed [LANE_NUM*DATA_WIDTH-1:0] rsp_data_next_comb;
    reg rsp_all_valid_comb;
    reg [OUT_SEL_WIDTH-1:0] l5_cfg_weight_out_reg;

    integer lane_idx;
    integer base_ch_idx;

    wire gw_cfg_weight_ready_up;
    wire gw_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] gw_weight_data;
    wire [OUT_SEL_WIDTH-1:0] gw_weight_out;
    wire gw_dst_last;
    wire gw_load_busy;
    wire gw_load_done;
    wire gw_cfg_last_err;
    wire gw_weight_ready;

    wire addr_rd_valid;
    wire [IN_CH_NUM-1:0] addr_rd_en;
    wire [IN_CH_NUM*ADDR2D_WIDTH-1:0] addr_rd_addr2d;
    wire addr_rd_last;
    wire addr_busy;
    wire addr_done;
    wire [GROUP_SEL_WIDTH-1:0] addr_cur_group;
    wire [ROW_ADDR_WIDTH-1:0] addr_cur_row;
    wire [COL_ADDR_WIDTH-1:0] addr_cur_col;
    wire addr_rd_ready;
    wire addr_rd_fire;

    wire l5_cfg_weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] l5_cfg_weight_data;
    wire l5_cfg_weight_last;
    wire [OUT_SEL_WIDTH-1:0] l5_cfg_weight_out;

    wire [OUT_NUM-1:0] neuron_cfg_weight_ready_vec;
    wire [OUT_NUM-1:0] neuron_cfg_weight_done_vec;
    wire [OUT_NUM-1:0] neuron_in_ready_vec;
    wire [OUT_NUM-1:0] neuron_out_valid_vec;
    wire [OUT_NUM-1:0] neuron_busy_vec;
    wire [OUT_NUM-1:0] neuron_weight_loaded_vec;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] neuron_out_data_bus;

    wire all_frame_valid;
    wire any_neuron_busy;
    wire all_neuron_in_ready;
    wire all_neuron_out_valid;
    wire neuron_in_valid;
    wire neuron_out_ready_fire;
    wire rsp_capture_fire;
    wire rsp_consume_fire;

    assign cfg_weight_ready = gw_cfg_weight_ready_up;
    assign cfg_weight_done = gw_load_done;
    assign cfg_last_err = gw_cfg_last_err;

    assign l5_cfg_weight_valid = gw_weight_valid;
    assign l5_cfg_weight_data = gw_weight_data;
    assign l5_cfg_weight_last = gw_dst_last;
    assign l5_cfg_weight_out = l5_cfg_weight_out_reg;

    assign gw_weight_ready = neuron_cfg_weight_ready_vec[l5_cfg_weight_out];

    assign all_frame_valid = &src_frame_valid;
    assign any_neuron_busy = |neuron_busy_vec;
    assign all_neuron_in_ready = &neuron_in_ready_vec;
    assign all_neuron_out_valid = &neuron_out_valid_vec;

    assign ready = preload_done_reg
                && weight_loaded
                && all_frame_valid
                && !gw_load_busy
                && !addr_busy
                && !rd_pending
                && !rsp_valid_reg
                && !score_valid
                && !any_neuron_busy;

    assign busy = gw_load_busy
               || addr_busy
               || rd_pending
               || rsp_valid_reg
               || any_neuron_busy
               || score_valid;

    assign weight_loaded = &neuron_weight_loaded_vec;
    assign score_valid = all_neuron_out_valid;
    assign score_data = neuron_out_data_bus;

    assign addr_rd_ready = !rd_pending && !rsp_valid_reg;
    assign addr_rd_fire = addr_rd_valid && addr_rd_ready;

    assign src_rd_en = addr_rd_en;
    assign src_rd_addr2d = addr_rd_addr2d;

    assign rsp_capture_fire = rd_pending && rsp_all_valid_comb;
    assign neuron_in_valid = rsp_valid_reg && all_neuron_in_ready;
    assign rsp_consume_fire = neuron_in_valid;
    assign neuron_out_ready_fire = score_valid && score_ready;

    always @(*)
    begin
        rsp_data_next_comb = {(LANE_NUM * DATA_WIDTH){1'b0}};
        rsp_all_valid_comb = 1'b1;

        base_ch_idx = rd_pending_group * LANE_NUM;

        for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
        begin
            rsp_all_valid_comb = rsp_all_valid_comb && src_rd_valid[base_ch_idx + lane_idx];
            rsp_data_next_comb[((lane_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]
                = src_rd_data[((base_ch_idx + lane_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH];
        end
    end

    always @(*)
    begin
        l5_cfg_weight_out_reg = {OUT_SEL_WIDTH{1'b0}};
        if(gw_weight_out < FC_KERNEL_NUM)
        begin
            l5_cfg_weight_out_reg = gw_weight_out[OUT_SEL_WIDTH-1:0];
        end
    end

    fc_wgt_dist_raw #(
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .OUT_NUM(FC_KERNEL_NUM),
        .OUT_SEL_WIDTH(OUT_SEL_WIDTH),
        .WEIGHT_NUM_PER_OUT(FC_WEIGHT_NUM)
    ) u_fc_wgt_dist_raw (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .weight_ready(gw_weight_ready),
        .cfg_weight_ready(gw_cfg_weight_ready_up),
        .weight_valid(gw_weight_valid),
        .weight_data(gw_weight_data),
        .weight_out(gw_weight_out),
        .dst_last(gw_dst_last),
        .load_busy(gw_load_busy),
        .load_done(gw_load_done),
        .cfg_last_err(gw_cfg_last_err)
    );

    fc_addr_mgr #(
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .GROUP_NUM(GROUP_NUM),
        .GROUP_SEL_WIDTH(GROUP_SEL_WIDTH)
    ) u_fc_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .start(start && ready),
        .rd_addr_ready(addr_rd_ready),
        .rd_addr_valid(addr_rd_valid),
        .rd_en(addr_rd_en),
        .rd_addr2d(addr_rd_addr2d),
        .rd_addr_last(addr_rd_last),
        .busy(addr_busy),
        .done(addr_done),
        .cur_group(addr_cur_group),
        .cur_row(addr_cur_row),
        .cur_col(addr_cur_col)
    );

    genvar gi;
    generate
        for(gi = 0; gi < OUT_NUM; gi = gi + 1)
        begin: g_fc_neuron
            wire neuron_cfg_weight_valid_i;
            wire neuron_cfg_weight_last_i;
            wire signed [OUT_WIDTH-1:0] neuron_out_data_i;

            assign neuron_cfg_weight_valid_i = l5_cfg_weight_valid && (l5_cfg_weight_out == gi);
            assign neuron_cfg_weight_last_i = l5_cfg_weight_last && (l5_cfg_weight_out == gi);
            assign neuron_out_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = neuron_out_data_i;

            fc_neuron #(
                .LANE_NUM(LANE_NUM),
                .DATA_WIDTH(DATA_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .GROUP_NUM(GROUP_NUM),
                .BEATS_PER_GROUP(IMG_W * IMG_H),
                .TOTAL_WEIGHT_NUM(FC_WEIGHT_NUM),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_fc_neuron (
                .clk(clk),
                .rstn(rstn),
                .cfg_weight_valid(neuron_cfg_weight_valid_i),
                .cfg_weight_data(l5_cfg_weight_data),
                .cfg_weight_last(neuron_cfg_weight_last_i),
                .in_valid(neuron_in_valid),
                .in_data(rsp_data_reg),
                .in_last(rsp_last_reg),
                .out_ready(neuron_out_ready_fire),
                .cfg_weight_ready(neuron_cfg_weight_ready_vec[gi]),
                .cfg_weight_done(neuron_cfg_weight_done_vec[gi]),
                .in_ready(neuron_in_ready_vec[gi]),
                .out_valid(neuron_out_valid_vec[gi]),
                .out_data(neuron_out_data_i),
                .busy(neuron_busy_vec[gi]),
                .weight_loaded(neuron_weight_loaded_vec[gi])
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            preload_done_reg <= 1'b0;
            rd_pending <= 1'b0;
            rd_pending_group <= {GROUP_SEL_WIDTH{1'b0}};
            rd_pending_last <= 1'b0;
            rsp_valid_reg <= 1'b0;
            rsp_last_reg <= 1'b0;
            rsp_data_reg <= {(LANE_NUM * DATA_WIDTH){1'b0}};
            score_valid_dly <= 1'b0;
            done <= 1'b0;
            src_rd_done <= {IN_CH_NUM{1'b0}};
        end
        else
        begin
            done <= 1'b0;
            src_rd_done <= {IN_CH_NUM{1'b0}};
            score_valid_dly <= score_valid;

            if(gw_load_done)
            begin
                preload_done_reg <= 1'b1;
            end

            if(addr_rd_fire)
            begin
                rd_pending <= 1'b1;
                rd_pending_group <= addr_cur_group;
                rd_pending_last <= addr_rd_last;
            end

            if(rsp_capture_fire)
            begin
                rd_pending <= 1'b0;
                rsp_valid_reg <= 1'b1;
                rsp_last_reg <= rd_pending_last;
                rsp_data_reg <= rsp_data_next_comb;
            end

            if(rsp_consume_fire)
            begin
                rsp_valid_reg <= 1'b0;

                if(rsp_last_reg)
                begin
                    src_rd_done <= {IN_CH_NUM{1'b1}};
                end
            end

            if(score_valid && !score_valid_dly)
            begin
                done <= 1'b1;
            end
        end
    end

endmodule
