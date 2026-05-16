`timescale 1ns / 1ns

// 第一层单核串行卷积模块
// 1. 上电后先统一装载 1 组 5x5 权重
// 2. 权重装完之前, 卷积核不接收窗口像素
// 3. 运行期串行接收 1 个 5x5 窗口的 25 个像素
// 4. 输出 1 个 32bit 有符号卷积结果
module conv_l1
#(
    parameter DATA_WIDTH   = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter K            = 5,
    parameter OUT_WIDTH    = 32
)
(
    input  clk,                                           // 时钟
    input  rstn,                                          // 低有效复位
    input  cfg_weight_valid,                              // 权重输入有效
    input  signed [WEIGHT_WIDTH-1:0] cfg_weight_data,     // 权重输入数据
    input  cfg_weight_last,                               // 当前权重组最后一拍
    input  in_valid,                                      // 窗口像素有效
    input  [DATA_WIDTH-1:0] in_data,                      // 窗口像素数据
    input  in_last,                                       // 当前窗口最后一拍
    input  out_ready,                                     // 下游结果接收准备好

    output cfg_weight_ready,                              // 权重输入准备好
    output reg cfg_weight_done,                           // 权重装载完成脉冲
    output in_ready,                                      // 像素输入准备好
    output reg out_valid,                                 // 卷积结果有效
    output reg signed [OUT_WIDTH-1:0] out_data,           // 卷积结果数据
    output reg busy,                                      // 当前窗口计算中
    output reg weight_loaded                              // 已装好完整权重
);

    localparam integer WIN_SIZE  = K * K;
    localparam integer IDX_WIDTH = (WIN_SIZE <= 1) ? 1 : $clog2(WIN_SIZE);

    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:WIN_SIZE-1];
    reg [IDX_WIDTH-1:0] weight_wr_cnt;
    reg [IDX_WIDTH-1:0] sample_cnt;
    reg weight_loading;
    reg signed [OUT_WIDTH-1:0] acc_reg;

    wire idle_no_result;
    wire cfg_fire;
    wire in_fire;
    wire signed [WEIGHT_WIDTH-1:0] cur_weight;
    wire signed [DATA_WIDTH:0] in_data_ext;
    wire signed [DATA_WIDTH+WEIGHT_WIDTH:0] mult_term;
    wire signed [OUT_WIDTH-1:0] mult_term_ext;
    wire signed [OUT_WIDTH-1:0] acc_next;

    // 统一初始化阶段先装权重
    // 只有完整权重装好后, 才允许进入窗口卷积阶段
    assign idle_no_result   = !busy && !out_valid;
    assign cfg_weight_ready = weight_loading || (idle_no_result && (!weight_loaded || !in_valid));
    assign in_ready         = weight_loaded && !weight_loading && !out_valid;

    assign cfg_fire = cfg_weight_valid && cfg_weight_ready;
    assign in_fire  = in_valid && in_ready;

    assign cur_weight    = weight_mem[sample_cnt];
    assign in_data_ext   = $signed({1'b0, in_data});
    assign mult_term     = in_data_ext * cur_weight;
    assign mult_term_ext = $signed(mult_term);
    assign acc_next      = (sample_cnt == {IDX_WIDTH{1'b0}}) ? mult_term_ext
                                                              : (acc_reg + mult_term_ext);

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
            weight_wr_cnt   <= {IDX_WIDTH{1'b0}};
            sample_cnt      <= {IDX_WIDTH{1'b0}};
            acc_reg         <= {OUT_WIDTH{1'b0}};
        end
        else
        begin
            cfg_weight_done <= 1'b0;

            // 结果被下游接收后, 释放结果保持寄存器
            if(out_valid && out_ready)
            begin
                out_valid <= 1'b0;
            end

            // 上电初始化阶段串行装入 25 个权重
            if(cfg_fire)
            begin
                if(!weight_loading)
                begin
                    weight_loading <= 1'b1;
                    weight_loaded  <= 1'b0;
                    weight_wr_cnt  <= {{(IDX_WIDTH-1){1'b0}}, 1'b1};
                    weight_mem[0]  <= cfg_weight_data;

                    if(cfg_weight_last || (WIN_SIZE == 1))
                    begin
                        weight_loading  <= 1'b0;
                        weight_loaded   <= 1'b1;
                        weight_wr_cnt   <= {IDX_WIDTH{1'b0}};
                        cfg_weight_done <= 1'b1;
                    end
                end
                else
                begin
                    weight_mem[weight_wr_cnt] <= cfg_weight_data;

                    if(cfg_weight_last || (weight_wr_cnt == WIN_SIZE - 1))
                    begin
                        weight_loading  <= 1'b0;
                        weight_loaded   <= 1'b1;
                        weight_wr_cnt   <= {IDX_WIDTH{1'b0}};
                        cfg_weight_done <= 1'b1;
                    end
                    else
                    begin
                        weight_wr_cnt <= weight_wr_cnt + 1'b1;
                    end
                end
            end

            // 权重就绪后, 串行吃入 25 个窗口像素
            if(in_fire)
            begin
                busy <= 1'b1;

                if((sample_cnt == WIN_SIZE - 1) || in_last)
                begin
                    out_data   <= acc_next;
                    out_valid  <= 1'b1;
                    busy       <= 1'b0;
                    sample_cnt <= {IDX_WIDTH{1'b0}};
                    acc_reg    <= {OUT_WIDTH{1'b0}};
                end
                else
                begin
                    acc_reg    <= acc_next;
                    sample_cnt <= sample_cnt + 1'b1;
                end
            end
        end
    end

endmodule
