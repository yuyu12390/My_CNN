`timescale 1ns / 1ns

// FC neuron INT4 experiment core
// 1. Keep weight load and 32-beat accumulation flow
// 2. Select reference or packed 6-lane beat datapath by parameter
// 3. This experiment is fixed to 6 lanes and 2 groups
module fc_neuron_sint4_core
#(
    parameter USE_PACKED       = 0,
    parameter LANE_NUM         = 6,
    parameter DATA_WIDTH       = 4,
    parameter WEIGHT_WIDTH     = 4,
    parameter GROUP_NUM        = 2,
    parameter BEATS_PER_GROUP  = 16,
    parameter TOTAL_WEIGHT_NUM = LANE_NUM * GROUP_NUM * BEATS_PER_GROUP,
    parameter OUT_WIDTH        = 20
)
(
    input  clk,                                                 // clock
    input  rstn,                                                // active-low reset
    input  cfg_weight_valid,                                    // weight valid
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,           // weight data
    input  cfg_weight_last,                                     // last weight beat
    input  in_valid,                                            // 6-lane input valid
    input  signed [LANE_NUM*DATA_WIDTH-1:0] in_data,            // 6-lane input bus
    input  in_last,                                             // last input beat
    input  out_ready,                                           // result ready

    output cfg_weight_ready,                                    // weight ready
    output reg cfg_weight_done,                                 // weight load done pulse
    output in_ready,                                            // input ready
    output reg out_valid,                                       // result valid
    output reg signed [OUT_WIDTH-1:0] out_data,                 // result data
    output reg busy,                                            // busy flag
    output reg weight_loaded                                    // weight loaded flag
);

    localparam integer BEAT_NUM         = GROUP_NUM * BEATS_PER_GROUP;
    localparam integer WEIGHT_IDX_WIDTH = (TOTAL_WEIGHT_NUM <= 1) ? 1 : $clog2(TOTAL_WEIGHT_NUM);
    localparam integer BEAT_IDX_WIDTH   = (BEAT_NUM <= 1) ? 1 : $clog2(BEAT_NUM);
    localparam integer GROUP_IDX_WIDTH  = (GROUP_NUM <= 1) ? 1 : $clog2(GROUP_NUM);
    localparam integer BEAT_SUM_WIDTH   = 12;

    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:TOTAL_WEIGHT_NUM-1];
    reg [WEIGHT_IDX_WIDTH-1:0] weight_wr_cnt;
    reg [BEAT_IDX_WIDTH-1:0] beat_cnt;
    reg weight_loading;
    reg signed [OUT_WIDTH-1:0] acc_reg;

    reg signed [OUT_WIDTH-1:0] acc_next_comb;

    wire [GROUP_IDX_WIDTH-1:0] group_idx_w;
    wire [BEAT_IDX_WIDTH-1:0] beat_pos_w;
    wire [WEIGHT_IDX_WIDTH-1:0] lane_weight_idx_w [0:LANE_NUM-1];
    wire signed [LANE_NUM*WEIGHT_WIDTH-1:0] cur_weight_bus_w;
    wire signed [BEAT_SUM_WIDTH-1:0] beat_sum_raw_w;

    wire idle_no_result;
    wire cfg_fire;
    wire in_fire;

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
        begin: g_weight_pick
            assign lane_weight_idx_w[gi] = (group_idx_w * (LANE_NUM * BEATS_PER_GROUP))
                                         + (gi * BEATS_PER_GROUP)
                                         + beat_pos_w;
            assign cur_weight_bus_w[((gi + 1) * WEIGHT_WIDTH) - 1 -: WEIGHT_WIDTH]
                = weight_mem[lane_weight_idx_w[gi]];
        end
    endgenerate

    generate
        if(USE_PACKED)
        begin: g_pack
            fc_lane6_pack_sint4 u_lane6_pack (
                .in_data(in_data),
                .weight_data(cur_weight_bus_w),
                .out_sum(beat_sum_raw_w)
            );
        end
        else
        begin: g_ref
            fc_lane6_ref_sint4 u_lane6_ref (
                .in_data(in_data),
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
