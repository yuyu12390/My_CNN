`timescale 1ns / 1ns

// 第五层INT4量化单神经元核心
// 1. 对输入特征和权重先做有符号INT4量化
// 2. 单拍仍然处理6路输入, 共处理32拍
// 3. USE_PACKED=1时复用3个打包DSP乘法, USE_PACKED=0时走参考实现
(* keep_hierarchy = "yes" *)
module fc_neuron_int4_core
#(
    parameter USE_PACKED       = 0,
    parameter LANE_NUM         = 6,
    parameter DATA_WIDTH       = 8,
    parameter WEIGHT_WIDTH     = 8,
    parameter QUANT_WIDTH      = 4,
    parameter INPUT_SHIFT      = 4,
    parameter WEIGHT_SHIFT     = 4,
    parameter GROUP_NUM        = 2,
    parameter BEATS_PER_GROUP  = 16,
    parameter TOTAL_WEIGHT_NUM = LANE_NUM * GROUP_NUM * BEATS_PER_GROUP,
    parameter OUT_WIDTH        = 32
)
(
    input  clk,                                                     // 时钟
    input  rstn,                                                    // 低有效复位
    input  cfg_weight_valid,                                        // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,               // 权重输入数据
    input  cfg_weight_last,                                         // 当前神经元权重最后一拍
    input  in_valid,                                                // 6路输入同拍有效
    input  signed [LANE_NUM*DATA_WIDTH-1:0] in_data,                // 6路输入数据
    input  in_last,                                                 // 当前输入向量最后一拍
    input  out_ready,                                               // 下游结果接收准备好

    output cfg_weight_ready,                                        // 权重输入准备好
    output reg cfg_weight_done,                                     // 权重装载完成脉冲
    output in_ready,                                                // 输入数据准备好
    output reg out_valid,                                           // 输出结果有效
    output reg signed [OUT_WIDTH-1:0] out_data,                     // 输出结果数据
    output reg busy,                                                // 当前神经元忙
    output reg weight_loaded                                        // 已装好完整权重
);

    localparam integer BEAT_NUM         = GROUP_NUM * BEATS_PER_GROUP;
    localparam integer WEIGHT_IDX_WIDTH = (TOTAL_WEIGHT_NUM <= 1) ? 1 : $clog2(TOTAL_WEIGHT_NUM);
    localparam integer BEAT_IDX_WIDTH   = (BEAT_NUM <= 1) ? 1 : $clog2(BEAT_NUM);
    localparam integer GROUP_IDX_WIDTH  = (GROUP_NUM <= 1) ? 1 : $clog2(GROUP_NUM);
    localparam integer BEAT_SUM_WIDTH   = 12;
    localparam signed [DATA_WIDTH-1:0] QUANT_MAX_VAL = (1 <<< (QUANT_WIDTH - 1)) - 1;
    localparam signed [DATA_WIDTH-1:0] QUANT_MIN_VAL = -(1 <<< (QUANT_WIDTH - 1));

    reg signed [QUANT_WIDTH-1:0] weight_mem [0:TOTAL_WEIGHT_NUM-1];
    reg [WEIGHT_IDX_WIDTH-1:0] weight_wr_cnt;
    reg [BEAT_IDX_WIDTH-1:0] beat_cnt;
    reg weight_loading;
    reg signed [OUT_WIDTH-1:0] acc_reg;
    reg signed [OUT_WIDTH-1:0] acc_next_comb;

    wire signed [QUANT_WIDTH-1:0] lane_in_q_w [0:LANE_NUM-1];
    wire [WEIGHT_IDX_WIDTH-1:0] lane_weight_idx_w [0:LANE_NUM-1];
    wire signed [LANE_NUM*QUANT_WIDTH-1:0] in_data_q_bus_w;
    wire signed [LANE_NUM*QUANT_WIDTH-1:0] cur_weight_bus_w;
    wire signed [BEAT_SUM_WIDTH-1:0] beat_sum_raw_w;
    wire [GROUP_IDX_WIDTH-1:0] group_idx_w;
    wire [BEAT_IDX_WIDTH-1:0] beat_pos_w;
    wire idle_no_result;
    wire cfg_fire;
    wire in_fire;

    function signed [QUANT_WIDTH-1:0] quant_s8_to_s4;
        input signed [DATA_WIDTH-1:0] din;
        input integer shift_val;
        reg signed [DATA_WIDTH-1:0] shift_res;
        begin
            shift_res = din >>> shift_val;

            if(shift_res > QUANT_MAX_VAL)
            begin
                quant_s8_to_s4 = QUANT_MAX_VAL[QUANT_WIDTH-1:0];
            end
            else if(shift_res < QUANT_MIN_VAL)
            begin
                quant_s8_to_s4 = QUANT_MIN_VAL[QUANT_WIDTH-1:0];
            end
            else
            begin
                quant_s8_to_s4 = shift_res[QUANT_WIDTH-1:0];
            end
        end
    endfunction

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
        begin: g_q_lane
            assign lane_weight_idx_w[gi] = (group_idx_w * (LANE_NUM * BEATS_PER_GROUP))
                                         + (gi * BEATS_PER_GROUP)
                                         + beat_pos_w;
            assign cur_weight_bus_w[((gi + 1) * QUANT_WIDTH) - 1 -: QUANT_WIDTH]
                = weight_mem[lane_weight_idx_w[gi]];

            assign lane_in_q_w[gi]
                = quant_s8_to_s4(in_data[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH], INPUT_SHIFT);

            assign in_data_q_bus_w[((gi + 1) * QUANT_WIDTH) - 1 -: QUANT_WIDTH]
                = lane_in_q_w[gi];
        end
    endgenerate

    generate
        if(USE_PACKED)
        begin: g_pack
            fc_lane6_pack_sint4 u_fc_lane6_pack_sint4 (
                .in_data(in_data_q_bus_w),
                .weight_data(cur_weight_bus_w),
                .out_sum(beat_sum_raw_w)
            );
        end
        else
        begin: g_ref
            fc_lane6_ref_sint4 u_fc_lane6_ref_sint4 (
                .in_data(in_data_q_bus_w),
                .weight_data(cur_weight_bus_w),
                .out_sum(beat_sum_raw_w)
            );
        end
    endgenerate

    always @(*)
    begin
        if(beat_cnt == {BEAT_IDX_WIDTH{1'b0}})
        begin
            acc_next_comb = $signed({{(OUT_WIDTH-BEAT_SUM_WIDTH){beat_sum_raw_w[BEAT_SUM_WIDTH-1]}},
                                     beat_sum_raw_w});
        end
        else
        begin
            acc_next_comb = acc_reg
                          + $signed({{(OUT_WIDTH-BEAT_SUM_WIDTH){beat_sum_raw_w[BEAT_SUM_WIDTH-1]}},
                                     beat_sum_raw_w});
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

            if(out_valid && out_ready)
            begin
                out_valid <= 1'b0;
            end

            if(cfg_fire)
            begin
                if(!weight_loading)
                begin
                    weight_loading <= 1'b1;
                    weight_loaded  <= 1'b0;
                    weight_wr_cnt  <= {{(WEIGHT_IDX_WIDTH-1){1'b0}}, 1'b1};
                    weight_mem[0]  <= quant_s8_to_s4(cfg_weight_data, WEIGHT_SHIFT);

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
                    weight_mem[weight_wr_cnt] <= quant_s8_to_s4(cfg_weight_data, WEIGHT_SHIFT);

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
