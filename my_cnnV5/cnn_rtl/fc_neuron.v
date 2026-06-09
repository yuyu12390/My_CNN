`timescale 1ns / 1ns

// 第五层单神经元全连接模块
// 1. 上电后先统一装载 1 个神经元的全部权重
// 2. 运行期每拍并行接收 6 路 8bit 输入数据
// 3. 共接收 32 拍, 对应 12x4x4 的 192 个乘加
// 4. 当前把 6 路乘法显式映射到 DSP, 加法树仍保留在逻辑中
module fc_neuron
#(
    parameter LANE_NUM         = 6,
    parameter DATA_WIDTH       = 8,
    parameter WEIGHT_WIDTH     = 8,
    parameter GROUP_NUM        = 2,
    parameter BEATS_PER_GROUP  = 16,
    parameter TOTAL_WEIGHT_NUM = LANE_NUM * GROUP_NUM * BEATS_PER_GROUP,
    parameter OUT_WIDTH        = 32
)
(
    input  clk,                                                  // 时钟
    input  rstn,                                                 // 低有效复位
    input  cfg_weight_valid,                                     // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,            // 权重输入数据
    input  cfg_weight_last,                                      // 当前神经元权重最后一拍
    input  in_valid,                                             // 6 路输入同拍有效
    input  signed [LANE_NUM*DATA_WIDTH-1:0] in_data,             // 6 路输入数据
    input  in_last,                                              // 当前输入向量最后一拍
    input  out_ready,                                            // 下游结果接收准备好

    output cfg_weight_ready,                                     // 权重输入准备好
    output reg cfg_weight_done,                                  // 权重装载完成脉冲
    output in_ready,                                             // 输入数据准备好
    output reg out_valid,                                        // 输出结果有效
    output reg signed [OUT_WIDTH-1:0] out_data,                  // 输出结果数据
    output reg busy,                                             // 当前神经元忙
    output reg weight_loaded                                     // 已装好完整权重
);

    localparam integer BEAT_NUM          = GROUP_NUM * BEATS_PER_GROUP;
    localparam integer WEIGHT_IDX_WIDTH  = (TOTAL_WEIGHT_NUM <= 1) ? 1 : $clog2(TOTAL_WEIGHT_NUM);
    localparam integer BEAT_IDX_WIDTH    = (BEAT_NUM <= 1) ? 1 : $clog2(BEAT_NUM);
    localparam integer GROUP_IDX_WIDTH   = (GROUP_NUM <= 1) ? 1 : $clog2(GROUP_NUM);
    localparam integer PROD_WIDTH        = DATA_WIDTH + WEIGHT_WIDTH;

    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:TOTAL_WEIGHT_NUM-1];
    reg [WEIGHT_IDX_WIDTH-1:0] weight_wr_cnt;
    reg [BEAT_IDX_WIDTH-1:0] beat_cnt;
    reg weight_loading;
    reg signed [OUT_WIDTH-1:0] acc_reg;

    reg signed [OUT_WIDTH-1:0] beat_sum_comb;
    reg signed [OUT_WIDTH-1:0] acc_next_comb;

    wire signed [DATA_WIDTH-1:0] lane_in_data_w [0:LANE_NUM-1];
    wire [WEIGHT_IDX_WIDTH-1:0] lane_weight_idx_w [0:LANE_NUM-1];
    wire signed [WEIGHT_WIDTH-1:0] lane_weight_w [0:LANE_NUM-1];
    wire signed [15:0] lane_mul_w [0:LANE_NUM-1];
    wire [GROUP_IDX_WIDTH-1:0] group_idx_w;
    wire [BEAT_IDX_WIDTH-1:0] beat_pos_w;

    integer lane_idx;

    wire idle_no_result;
    wire cfg_fire;
    wire in_fire;

    // 统一初始化阶段先装权重
    // 只有完整权重装好后, 才允许进入全连接计算阶段
    assign idle_no_result   = !busy && !out_valid;
    assign cfg_weight_ready = weight_loading || (idle_no_result && (!weight_loaded || !in_valid));
    assign in_ready         = weight_loaded && !weight_loading && !out_valid;

    assign cfg_fire = cfg_weight_valid && cfg_weight_ready;
    assign in_fire  = in_valid && in_ready;

    assign group_idx_w = beat_cnt / BEATS_PER_GROUP;
    assign beat_pos_w  = beat_cnt - (group_idx_w * BEATS_PER_GROUP);

    genvar gi;
    generate
        for(gi = 0; gi < LANE_NUM; gi = gi + 1)
        begin: g_fc_mul
            assign lane_in_data_w[gi] = in_data[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH];
            assign lane_weight_idx_w[gi] = (group_idx_w * (LANE_NUM * BEATS_PER_GROUP))
                                         + (gi * BEATS_PER_GROUP)
                                         + beat_pos_w;
            assign lane_weight_w[gi] = weight_mem[lane_weight_idx_w[gi]];

            fc_mul_dsp_s8 u_fc_mul_dsp_s8 (
                .a(lane_in_data_w[gi]),
                .b(lane_weight_w[gi]),
                .p(lane_mul_w[gi])
            );
        end
    endgenerate

    // 权重存储顺序约定:
    // group0: cin0~cin5, 每个通道 16 个空间点
    // group1: cin6~cin11, 每个通道 16 个空间点
    always @(*)
    begin
        beat_sum_comb = {OUT_WIDTH{1'b0}};

        for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
        begin
            beat_sum_comb = beat_sum_comb
                          + $signed({{(OUT_WIDTH-PROD_WIDTH){lane_mul_w[lane_idx][PROD_WIDTH-1]}},
                                     lane_mul_w[lane_idx][PROD_WIDTH-1:0]});
        end

        if(beat_cnt == {BEAT_IDX_WIDTH{1'b0}})
        begin
            acc_next_comb = beat_sum_comb;
        end
        else
        begin
            acc_next_comb = acc_reg + beat_sum_comb;
        end
    end

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            cfg_weight_done <= 1'b0;
            out_valid       <= 1'b0;
            out_data        <= {OUT_WIDTH{1'b0}};
            busy            <= 1'b0;
            weight_loaded   <= 1'b0;
            weight_loading  <= 1'b0;
            weight_wr_cnt   <= {WEIGHT_IDX_WIDTH{1'b0}};
            beat_cnt        <= {BEAT_IDX_WIDTH{1'b0}};
            acc_reg         <= {OUT_WIDTH{1'b0}};
        end
        else
        begin
            cfg_weight_done <= 1'b0;

            // 结果被下游接收后, 再清掉 out_valid
            if(out_valid && out_ready)
            begin
                out_valid <= 1'b0;
            end

            // 上电初始化阶段串行装入全部权重
            if(cfg_fire)
            begin
                if(!weight_loading)
                begin
                    weight_loading <= 1'b1;
                    weight_loaded  <= 1'b0;
                    weight_wr_cnt  <= {{(WEIGHT_IDX_WIDTH-1){1'b0}}, 1'b1};
                    weight_mem[0]  <= cfg_weight_data;

                    if(cfg_weight_last || (TOTAL_WEIGHT_NUM == 1))
                    begin
                        weight_loading  <= 1'b0;
                        weight_loaded   <= 1'b1;
                        weight_wr_cnt   <= {WEIGHT_IDX_WIDTH{1'b0}};
                        cfg_weight_done <= 1'b1;
                    end
                end
                else
                begin
                    weight_mem[weight_wr_cnt] <= cfg_weight_data;

                    if(cfg_weight_last || (weight_wr_cnt == TOTAL_WEIGHT_NUM - 1))
                    begin
                        weight_loading  <= 1'b0;
                        weight_loaded   <= 1'b1;
                        weight_wr_cnt   <= {WEIGHT_IDX_WIDTH{1'b0}};
                        cfg_weight_done <= 1'b1;
                    end
                    else
                    begin
                        weight_wr_cnt <= weight_wr_cnt + 1'b1;
                    end
                end
            end

            // 权重装好后, 每拍吃 6 路输入并累加
            if(in_fire)
            begin
                busy <= 1'b1;

                if((beat_cnt == BEAT_NUM - 1) || in_last)
                begin
                    out_data  <= acc_next_comb;
                    out_valid <= 1'b1;
                    busy      <= 1'b0;
                    beat_cnt  <= {BEAT_IDX_WIDTH{1'b0}};
                    acc_reg   <= {OUT_WIDTH{1'b0}};
                end
                else
                begin
                    acc_reg  <= acc_next_comb;
                    beat_cnt <= beat_cnt + 1'b1;
                end
            end
        end
    end

endmodule