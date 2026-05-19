`timescale 1ns / 1ns

// 第五层全连接读地址管理模块
// 1. 管理上一级 12 路 4x4 特征图缓存的读取
// 2. 先输出第 0 组 6 路 16 拍, 再输出第 1 组 6 路 16 拍
// 3. 每拍同一组 6 路共享同一个二维地址
// 4. 只有地址握手成功后, 才推进到下一拍
module fc_addr_mgr
#(
    parameter IN_CH_NUM       = 12,
    parameter LANE_NUM        = 6,
    parameter IMG_W           = 4,
    parameter IMG_H           = 4,
    parameter ROW_ADDR_WIDTH  = 5,
    parameter COL_ADDR_WIDTH  = 5,
    parameter ADDR2D_WIDTH    = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter GROUP_NUM       = IN_CH_NUM / LANE_NUM,
    parameter GROUP_SEL_WIDTH = (GROUP_NUM <= 2) ? 1 : $clog2(GROUP_NUM)
)
(
    input  clk,                                                 // 时钟
    input  rstn,                                                // 低有效复位
    input  start,                                               // 启动一次完整 FC 读取
    input  rd_addr_ready,                                       // 地址接收准备好

    output rd_addr_valid,                                       // 读地址有效
    output reg [IN_CH_NUM-1:0] rd_en,                           // 12 路读使能
    output reg [IN_CH_NUM*ADDR2D_WIDTH-1:0] rd_addr2d,          // 12 路读二维地址
    output rd_addr_last,                                        // 最后一拍读地址
    output busy,                                                // 地址管理器忙
    output reg done,                                            // 一次完整读取结束脉冲
    output reg [GROUP_SEL_WIDTH-1:0] cur_group,                 // 当前组号
    output reg [ROW_ADDR_WIDTH-1:0] cur_row,                    // 当前行坐标
    output reg [COL_ADDR_WIDTH-1:0] cur_col                     // 当前列坐标
);

    localparam integer LAST_GROUP = GROUP_NUM - 1;
    localparam integer LAST_ROW   = IMG_H - 1;
    localparam integer LAST_COL   = IMG_W - 1;

    reg active;

    integer ch_idx;
    integer lane_lo_int;
    integer lane_hi_int;

    wire rd_fire;

    assign busy = active;
    assign rd_addr_valid = active;
    assign rd_addr_last = rd_addr_valid
                       && (cur_group == LAST_GROUP)
                       && (cur_row == LAST_ROW)
                       && (cur_col == LAST_COL);
    assign rd_fire = rd_addr_valid && rd_addr_ready;

    always @(*)
    begin
        rd_en = {IN_CH_NUM{1'b0}};
        rd_addr2d = {(IN_CH_NUM * ADDR2D_WIDTH){1'b0}};

        lane_lo_int = cur_group * LANE_NUM;
        lane_hi_int = lane_lo_int + LANE_NUM;

        if(active)
        begin
            for(ch_idx = 0; ch_idx < IN_CH_NUM; ch_idx = ch_idx + 1)
            begin
                rd_addr2d[((ch_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = {cur_row, cur_col};

                if((ch_idx >= lane_lo_int) && (ch_idx < lane_hi_int))
                begin
                    rd_en[ch_idx] = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            active    <= 1'b0;
            done      <= 1'b0;
            cur_group <= {GROUP_SEL_WIDTH{1'b0}};
            cur_row   <= {ROW_ADDR_WIDTH{1'b0}};
            cur_col   <= {COL_ADDR_WIDTH{1'b0}};
        end
        else
        begin
            done <= 1'b0;

            if(start && !active)
            begin
                active    <= 1'b1;
                cur_group <= {GROUP_SEL_WIDTH{1'b0}};
                cur_row   <= {ROW_ADDR_WIDTH{1'b0}};
                cur_col   <= {COL_ADDR_WIDTH{1'b0}};
            end
            else if(rd_fire)
            begin
                if(rd_addr_last)
                begin
                    active    <= 1'b0;
                    done      <= 1'b1;
                    cur_group <= {GROUP_SEL_WIDTH{1'b0}};
                    cur_row   <= {ROW_ADDR_WIDTH{1'b0}};
                    cur_col   <= {COL_ADDR_WIDTH{1'b0}};
                end
                else if(cur_col == LAST_COL)
                begin
                    cur_col <= {COL_ADDR_WIDTH{1'b0}};

                    if(cur_row == LAST_ROW)
                    begin
                        cur_row <= {ROW_ADDR_WIDTH{1'b0}};
                        cur_group <= cur_group + 1'b1;
                    end
                    else
                    begin
                        cur_row <= cur_row + 1'b1;
                    end
                end
                else
                begin
                    cur_col <= cur_col + 1'b1;
                end
            end
        end
    end

endmodule
