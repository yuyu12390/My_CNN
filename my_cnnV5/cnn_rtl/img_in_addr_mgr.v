`timescale 1ns / 1ns

// 图像输入地址管理模块
module img_in_addr_mgr
#(
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH
)
(
    input clk,                               // 时钟
    input rstn,                              // 低有效复位
    input frame_start,                       // 一帧开始
    input addr_ready,                        // 下游地址接收

    output addr_valid,                       // 地址有效
    output [ADDR2D_WIDTH-1:0] addr2d,        // 拼接二维地址
    output addr_last,                        // 最后一个地址
    output reg frame_busy,                   // 当前帧进行中
    output reg frame_done,                   // 当前帧结束脉冲
    output reg [ROW_ADDR_WIDTH-1:0] cur_row, // 当前行
    output reg [COL_ADDR_WIDTH-1:0] cur_col  // 当前列
);

    reg frame_active;
    wire addr_fire;
    wire last_addr;

    assign addr_valid = frame_active;
    assign addr2d = {cur_row, cur_col};
    assign last_addr = (cur_row == IMG_H - 1) && (cur_col == IMG_W - 1);
    assign addr_last = frame_active && last_addr;
    assign addr_fire = addr_valid && addr_ready;

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            frame_active <= 1'b0;
            frame_busy <= 1'b0;
            frame_done <= 1'b0;
            cur_row <= {ROW_ADDR_WIDTH{1'b0}};
            cur_col <= {COL_ADDR_WIDTH{1'b0}};
        end
        else
        begin
            frame_done <= 1'b0;
            frame_busy <= frame_active;

            // 空闲时接收一帧开始, 地址从(0,0)起步
            if(frame_start && !frame_active)
            begin
                frame_active <= 1'b1;
                frame_busy <= 1'b1;
                cur_row <= {ROW_ADDR_WIDTH{1'b0}};
                cur_col <= {COL_ADDR_WIDTH{1'b0}};
            end
            else if(addr_fire)
            begin
                // 只有地址被下游接收, 才推进到下一个地址
                if(last_addr)
                begin
                    frame_active <= 1'b0;
                    frame_busy <= 1'b0;
                    frame_done <= 1'b1;
                    cur_row <= {ROW_ADDR_WIDTH{1'b0}};
                    cur_col <= {COL_ADDR_WIDTH{1'b0}};
                end
                else if(cur_col == IMG_W - 1)
                begin
                    cur_col <= {COL_ADDR_WIDTH{1'b0}};
                    cur_row <= cur_row + 1'b1;
                end
                else
                begin
                    cur_col <= cur_col + 1'b1;
                end
            end
        end
    end

endmodule