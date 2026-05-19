`timescale 1ns / 1ns

// 第三层单个输出通道计算核心
// 1. 内部例化 6 个 conv_core, 每个负责 1 个输入通道切片
// 2. 权重装载阶段由 cfg_weight_cin 选择当前目标切片
// 3. 运行阶段 6 路像素同拍送入 6 个切片
// 4. 6 路切片结果全部就绪后做求和, 输出 1 个 32bit 结果
module l3_out_core
#(
    parameter CIN_NUM = 6,
    parameter CIN_SEL_WIDTH = (CIN_NUM <= 2) ? 1 : $clog2(CIN_NUM),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter K = 5,
    parameter OUT_WIDTH = 32
)
(
    input  clk,                                                // 时钟
    input  rstn,                                               // 低有效复位
    input  cfg_weight_valid,                                   // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,          // 权重输入数据
    input  cfg_weight_last,                                    // 当前切片权重最后一拍
    input  [CIN_SEL_WIDTH-1:0] cfg_weight_cin,                 // 权重目标输入通道号
    input  in_valid,                                           // 6 路像素同拍有效
    input  [CIN_NUM*DATA_WIDTH-1:0] in_data,                   // 6 路像素同拍数据
    input  in_last,                                            // 当前窗口最后一拍
    input  out_ready,                                          // 下游结果接收准备好

    output cfg_weight_ready,                                   // 当前目标切片权重准备好
    output cfg_weight_done,                                    // 当前目标切片权重装好脉冲
    output in_ready,                                           // 6 路像素同拍准备好
    output reg out_valid,                                      // 求和结果有效
    output reg signed [OUT_WIDTH-1:0] out_data,                // 求和结果数据
    output busy,                                               // 当前核心忙
    output weight_loaded                                       // 6 个切片权重全部装好
);

    localparam integer SUM_GUARD_WIDTH = (CIN_NUM <= 1) ? 1 : $clog2(CIN_NUM + 1);
    localparam integer SUM_WIDTH = OUT_WIDTH + SUM_GUARD_WIDTH;

    reg [CIN_NUM-1:0] cfg_weight_cin_hit;
    reg cfg_weight_ready_reg;
    reg cfg_weight_done_reg;
    reg signed [SUM_WIDTH-1:0] sum_data_comb;

    integer lane_idx;

    wire [CIN_NUM-1:0] lane_in_ready_vec;
    wire [CIN_NUM-1:0] lane_cfg_weight_ready_vec;
    wire [CIN_NUM-1:0] lane_cfg_weight_done_vec;
    wire [CIN_NUM-1:0] lane_out_valid_vec;
    wire [CIN_NUM-1:0] lane_busy_vec;
    wire [CIN_NUM-1:0] lane_weight_loaded_vec;
    wire signed [CIN_NUM*OUT_WIDTH-1:0] lane_out_data_bus;

    wire all_lane_in_ready;
    wire all_lane_out_valid;
    wire any_lane_busy;
    wire any_lane_out_valid;
    wire lane_commit_fire;

    assign cfg_weight_ready = cfg_weight_ready_reg;
    assign cfg_weight_done = cfg_weight_done_reg;
    assign weight_loaded = &lane_weight_loaded_vec;

    // 只有 6 个切片都能同步接收时, 才允许当前拍送入 6 路像素
    assign all_lane_in_ready = &lane_in_ready_vec;
    assign all_lane_out_valid = &lane_out_valid_vec;
    assign any_lane_busy = |lane_busy_vec;
    assign any_lane_out_valid = |lane_out_valid_vec;
    assign in_ready = weight_loaded && all_lane_in_ready && !out_valid;

    // 6 路部分和全部就绪后, 先锁存到本模块输出寄存器, 再等待下游取走
    assign lane_commit_fire = all_lane_out_valid && !out_valid;
    assign busy = any_lane_busy || any_lane_out_valid || out_valid;

    always @(*)
    begin
        cfg_weight_cin_hit = {CIN_NUM{1'b0}};
        if(cfg_weight_cin < CIN_NUM)
        begin
            cfg_weight_cin_hit[cfg_weight_cin] = 1'b1;
        end
    end

    always @(*)
    begin
        cfg_weight_ready_reg = 1'b0;
        cfg_weight_done_reg = 1'b0;

        if(cfg_weight_cin < CIN_NUM)
        begin
            cfg_weight_ready_reg = lane_cfg_weight_ready_vec[cfg_weight_cin];
            cfg_weight_done_reg = lane_cfg_weight_done_vec[cfg_weight_cin];
        end
    end

    always @(*)
    begin
        sum_data_comb = {SUM_WIDTH{1'b0}};
        for(lane_idx = 0; lane_idx < CIN_NUM; lane_idx = lane_idx + 1)
        begin
            sum_data_comb = sum_data_comb
                          + $signed(lane_out_data_bus[((lane_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH]);
        end
    end

    genvar gi;
    generate
        for(gi = 0; gi < CIN_NUM; gi = gi + 1)
        begin: g_conv_slice
            wire lane_cfg_weight_valid_i;
            wire lane_cfg_weight_last_i;
            wire lane_in_valid_i;
            wire [DATA_WIDTH-1:0] lane_in_data_i;
            wire signed [OUT_WIDTH-1:0] lane_out_data_i;

            assign lane_cfg_weight_valid_i = cfg_weight_valid && cfg_weight_cin_hit[gi];
            assign lane_cfg_weight_last_i = cfg_weight_last && cfg_weight_cin_hit[gi];
            assign lane_in_valid_i = in_valid && in_ready;
            assign lane_in_data_i = in_data[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH];
            assign lane_out_data_bus[((gi + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH] = lane_out_data_i;

            conv_core #(
                .DATA_WIDTH(DATA_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .K(K),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_conv_core (
                .clk(clk),
                .rstn(rstn),
                .cfg_weight_valid(lane_cfg_weight_valid_i),
                .cfg_weight_data(cfg_weight_data),
                .cfg_weight_last(lane_cfg_weight_last_i),
                .in_valid(lane_in_valid_i),
                .in_data(lane_in_data_i),
                .in_last(in_last),
                .out_ready(lane_commit_fire),
                .cfg_weight_ready(lane_cfg_weight_ready_vec[gi]),
                .cfg_weight_done(lane_cfg_weight_done_vec[gi]),
                .in_ready(lane_in_ready_vec[gi]),
                .out_valid(lane_out_valid_vec[gi]),
                .out_data(lane_out_data_i),
                .busy(lane_busy_vec[gi]),
                .weight_loaded(lane_weight_loaded_vec[gi])
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            out_valid <= 1'b0;
            out_data <= {OUT_WIDTH{1'b0}};
        end
        else
        begin
            if(out_valid && out_ready)
            begin
                out_valid <= 1'b0;
            end

            if(lane_commit_fire)
            begin
                out_valid <= 1'b1;
                out_data <= sum_data_comb[OUT_WIDTH-1:0];
            end
        end
    end

endmodule
