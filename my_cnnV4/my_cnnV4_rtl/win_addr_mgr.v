`timescale 1ns / 1ns

// 通用窗口地址管理模块
// 1. 同时管理窗口读地址和卷积结果写地址
// 2. 一个窗口输出 25 个读地址, 对应 1 个写地址
// 3. 只有卷积结果真正写成功后, 才推进到下一个输出点
module win_addr_mgr
#(
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter K = 5,
    parameter STRIDE = 1,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH
)
(
    input  clk,                                     // 时钟
    input  rstn,                                    // 低有效复位
    input  start,                                   // 启动一次完整扫描
    input  rd_addr_ready,                           // 读地址接收准备好
    input  out_fire,                                // 本窗口卷积结果成功写入

    output rd_addr_valid,                           // 读地址有效
    output [ADDR2D_WIDTH-1:0] rd_addr2d,            // 当前读二维地址
    output rd_addr_last,                            // 当前窗口最后一个读地址
    output wr_addr_valid,                           // 写地址有效
    output [ADDR2D_WIDTH-1:0] wr_addr2d,            // 当前写二维地址
    output wr_last,                                 // 整幅输出最后一个写地址
    output busy,                                    // 管理器忙
    output reg win_done,                            // 一个窗口读完脉冲
    output reg map_done,                            // 整幅输出写完脉冲
    output reg [ROW_ADDR_WIDTH-1:0] cur_base_row,   // 当前窗口左上角行
    output reg [COL_ADDR_WIDTH-1:0] cur_base_col,   // 当前窗口左上角列
    output reg [ROW_ADDR_WIDTH-1:0] cur_krow,       // 当前窗口内部行偏移
    output reg [COL_ADDR_WIDTH-1:0] cur_kcol        // 当前窗口内部列偏移
);

    localparam integer OUT_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer OUT_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer LAST_BASE_COL = (OUT_W - 1) * STRIDE;
    localparam integer LAST_BASE_ROW = (OUT_H - 1) * STRIDE;

    reg active;
    reg window_done_wait;

    wire rd_fire;
    wire inner_last;
    wire scan_last;
    wire [ROW_ADDR_WIDTH-1:0] rd_row;
    wire [COL_ADDR_WIDTH-1:0] rd_col;

    assign busy = active;
    assign inner_last = (cur_krow == K - 1) && (cur_kcol == K - 1);
    assign scan_last = (cur_base_row == LAST_BASE_ROW) && (cur_base_col == LAST_BASE_COL);

    assign rd_addr_valid = active && !window_done_wait;
    assign rd_row = cur_base_row + cur_krow;
    assign rd_col = cur_base_col + cur_kcol;
    assign rd_addr2d = {rd_row, rd_col};
    assign rd_addr_last = rd_addr_valid && inner_last;
    assign rd_fire = rd_addr_valid && rd_addr_ready;

    assign wr_addr_valid = active && window_done_wait;
    assign wr_addr2d = {cur_base_row, cur_base_col};
    assign wr_last = wr_addr_valid && scan_last;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            active <= 1'b0;
            window_done_wait <= 1'b0;
            win_done <= 1'b0;
            map_done <= 1'b0;
            cur_base_row <= {ROW_ADDR_WIDTH{1'b0}};
            cur_base_col <= {COL_ADDR_WIDTH{1'b0}};
            cur_krow <= {ROW_ADDR_WIDTH{1'b0}};
            cur_kcol <= {COL_ADDR_WIDTH{1'b0}};
        end
        else
        begin
            win_done <= 1'b0;
            map_done <= 1'b0;

            if(start && !active)
            begin
                active <= 1'b1;
                window_done_wait <= 1'b0;
                cur_base_row <= {ROW_ADDR_WIDTH{1'b0}};
                cur_base_col <= {COL_ADDR_WIDTH{1'b0}};
                cur_krow <= {ROW_ADDR_WIDTH{1'b0}};
                cur_kcol <= {COL_ADDR_WIDTH{1'b0}};
            end
            else if(rd_fire)
            begin
                if(inner_last)
                begin
                    window_done_wait <= 1'b1;
                    win_done <= 1'b1;
                    cur_krow <= {ROW_ADDR_WIDTH{1'b0}};
                    cur_kcol <= {COL_ADDR_WIDTH{1'b0}};
                end
                else if(cur_kcol == K - 1)
                begin
                    cur_kcol <= {COL_ADDR_WIDTH{1'b0}};
                    cur_krow <= cur_krow + 1'b1;
                end
                else
                begin
                    cur_kcol <= cur_kcol + 1'b1;
                end
            end

            if(out_fire && window_done_wait)
            begin
                window_done_wait <= 1'b0;

                if(scan_last)
                begin
                    active <= 1'b0;
                    map_done <= 1'b1;
                    cur_base_row <= {ROW_ADDR_WIDTH{1'b0}};
                    cur_base_col <= {COL_ADDR_WIDTH{1'b0}};
                end
                else if(cur_base_col == LAST_BASE_COL)
                begin
                    cur_base_col <= {COL_ADDR_WIDTH{1'b0}};
                    cur_base_row <= cur_base_row + STRIDE;
                end
                else
                begin
                    cur_base_col <= cur_base_col + STRIDE;
                end
            end
        end
    end

endmodule
