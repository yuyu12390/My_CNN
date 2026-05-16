`timescale 1ns / 1ns

// 全局权重分发模块
// 1. 接收一条串行权重流
// 2. 按固定顺序输出逻辑目标 {layer_id, kernel_id}
// 3. 内部计数独立于外部 last, 可报告时序错误
// 4. 当前版本顺序固定为:
//    (0,0) ~ (0,5), 每核 25 个权重
//    (1,0) ~ (1,11), 每核 150 个权重
module wgt_dist_global
#(
    parameter WEIGHT_WIDTH    = 8,
    parameter LAYER_ID_WIDTH  = 1,
    parameter KERNEL_ID_WIDTH = 4,
    parameter WEIGHT_IDX_WIDTH = 8,
    parameter L0_KERNEL_NUM   = 6,
    parameter L0_WEIGHT_NUM   = 25,
    parameter L1_KERNEL_NUM   = 12,
    parameter L1_WEIGHT_NUM   = 150,
    parameter DST2D_WIDTH     = LAYER_ID_WIDTH + KERNEL_ID_WIDTH
)
(
    input  clk,                                              // 时钟
    input  rstn,                                             // 低有效复位
    input  cfg_weight_valid,                                 // 上级权重有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,        // 上级权重数据
    input  cfg_weight_last,                                  // 整体流最后一拍
    input  weight_ready,                                     // 下游准备好

    output cfg_weight_ready,                                 // 上级准备好
    output weight_valid,                                     // 下发权重有效
    output signed [WEIGHT_WIDTH-1:0] weight_data,            // 下发权重数据
    output [DST2D_WIDTH-1:0] weight_dst2d,                   // 逻辑目标编号
    output [WEIGHT_IDX_WIDTH-1:0] weight_idx,                // 组内权重编号
    output dst_last,                                         // 当前目标最后一拍
    output reg load_busy,                                    // 当前装载忙
    output reg load_done,                                    // 整体装载完成脉冲
    output reg cfg_last_err                                  // 外部 last 错误脉冲
);

    localparam [LAYER_ID_WIDTH-1:0] LAYER0_ID = {LAYER_ID_WIDTH{1'b0}};
    localparam [LAYER_ID_WIDTH-1:0] LAYER1_ID = {{(LAYER_ID_WIDTH-1){1'b0}}, 1'b1};

    reg [LAYER_ID_WIDTH-1:0] cur_layer_id;
    reg [KERNEL_ID_WIDTH-1:0] cur_kernel_id;
    reg [WEIGHT_IDX_WIDTH-1:0] cur_weight_idx;

    wire cfg_fire;
    wire cur_is_layer0;
    wire [WEIGHT_IDX_WIDTH-1:0] cur_last_idx;
    wire dst_last_exp;
    wire stream_last_exp;
    wire last_kernel_in_layer;

    assign cfg_weight_ready = weight_ready;
    assign weight_valid = cfg_weight_valid;
    assign weight_data = cfg_weight_data;
    assign weight_dst2d = {cur_layer_id, cur_kernel_id};
    assign weight_idx = cur_weight_idx;

    // 只有真正握手成功后, 目标号和组内计数才推进
    assign cfg_fire = cfg_weight_valid && cfg_weight_ready;
    assign cur_is_layer0 = (cur_layer_id == LAYER0_ID);
    assign cur_last_idx = cur_is_layer0 ? (L0_WEIGHT_NUM - 1) : (L1_WEIGHT_NUM - 1);
    assign dst_last_exp = (cur_weight_idx == cur_last_idx);
    assign last_kernel_in_layer = cur_is_layer0
                                ? (cur_kernel_id == (L0_KERNEL_NUM - 1))
                                : (cur_kernel_id == (L1_KERNEL_NUM - 1));
    assign stream_last_exp = (!cur_is_layer0) && last_kernel_in_layer && dst_last_exp;
    assign dst_last = weight_valid && dst_last_exp;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            cur_layer_id  <= {LAYER_ID_WIDTH{1'b0}};
            cur_kernel_id <= {KERNEL_ID_WIDTH{1'b0}};
            cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};
            load_busy <= 1'b0;
            load_done <= 1'b0;
            cfg_last_err <= 1'b0;
        end
        else
        begin
            load_done <= 1'b0;
            cfg_last_err <= 1'b0;

            if(cfg_fire)
            begin
                // 外部 last 只做校验, 不参与内部计数推进
                if(cfg_weight_last != stream_last_exp)
                begin
                    cfg_last_err <= 1'b1;
                end

                if(stream_last_exp)
                begin
                    // 整包结束后回到初始目标, 等待下一轮预装载
                    cur_layer_id <= {LAYER_ID_WIDTH{1'b0}};
                    cur_kernel_id <= {KERNEL_ID_WIDTH{1'b0}};
                    cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};
                    load_busy <= 1'b0;
                    load_done <= 1'b1;
                end
                else
                begin
                    load_busy <= 1'b1;

                    if(dst_last_exp)
                    begin
                        cur_weight_idx <= {WEIGHT_IDX_WIDTH{1'b0}};

                        if(cur_is_layer0)
                        begin
                            // 第一层最后一个卷积核结束后切到第二层
                            if(last_kernel_in_layer)
                            begin
                                cur_layer_id <= LAYER1_ID;
                                cur_kernel_id <= {KERNEL_ID_WIDTH{1'b0}};
                            end
                            else
                            begin
                                cur_kernel_id <= cur_kernel_id + 1'b1;
                            end
                        end
                        else
                        begin
                            cur_kernel_id <= cur_kernel_id + 1'b1;
                        end
                    end
                    else
                    begin
                        cur_weight_idx <= cur_weight_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
