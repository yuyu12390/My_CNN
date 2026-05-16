`timescale 1ns / 1ns

// 图像乒乓缓存模块
module pingpong_img_buf
#(
    parameter DATA_WIDTH = 8,
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter DEPTH = IMG_W * IMG_H,
    parameter ADDR_WIDTH = 10
)
(
    input clk,                               // 时钟
    input rstn,                              // 低有效复位
    input wr_valid,                          // 写有效
    input [DATA_WIDTH-1:0] wr_data,          // 写数据
    input [ADDR2D_WIDTH-1:0] wr_addr2d,      // 写二维地址
    input wr_last,                           // 一帧最后一个写数据
    input rd_en,                             // 读使能
    input [ADDR2D_WIDTH-1:0] rd_addr2d,      // 读二维地址
    input rd_done,                           // 当前读帧结束

    output wr_ready,                         // 写准备好
    output reg wr_done,                      // 当前写帧结束脉冲
    output reg [DATA_WIDTH-1:0] rd_data,     // 读数据
    output reg rd_valid,                     // 读数据有效
    output reg rd_frame_valid,               // 当前读bank有效
    output reg wr_bank_sel,                  // 当前写bank选择
    output reg rd_bank_sel,                  // 当前读bank选择
    output reg bank0_valid,                  // bank0有效标志
    output reg bank1_valid                   // bank1有效标志
);

    reg [DATA_WIDTH-1:0] bank0 [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] bank1 [0:DEPTH-1];
    reg wr_busy;

    wire [ROW_ADDR_WIDTH-1:0] wr_row;
    wire [COL_ADDR_WIDTH-1:0] wr_col;
    wire [ROW_ADDR_WIDTH-1:0] rd_row;
    wire [COL_ADDR_WIDTH-1:0] rd_col;
    wire [ADDR_WIDTH-1:0] wr_addr_1d;
    wire [ADDR_WIDTH-1:0] rd_addr_1d;
    wire cur_wr_bank_valid;
    wire cur_wr_bank_reading;
    wire wr_fire;
    wire wr_frame_done;
    wire bank0_reading;
    wire bank1_reading;
    wire bank0_free;
    wire bank1_free;

    // 外部发来的地址是拼接后的二维地址, 本模块内部再拆包
    assign wr_row = wr_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
    assign wr_col = wr_addr2d[COL_ADDR_WIDTH-1:0];
    assign rd_row = rd_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
    assign rd_col = rd_addr2d[COL_ADDR_WIDTH-1:0];

    // bank实际存储是一维地址, 所以这里做二维到一维的转换
    assign wr_addr_1d = (wr_row * IMG_W) + wr_col;
    assign rd_addr_1d = (rd_row * IMG_W) + rd_col;

    assign cur_wr_bank_valid = (wr_bank_sel == 1'b0) ? bank0_valid : bank1_valid;
    assign cur_wr_bank_reading = rd_frame_valid && (wr_bank_sel == rd_bank_sel);
    assign wr_ready = !cur_wr_bank_valid && !cur_wr_bank_reading;
    assign wr_fire = wr_valid && wr_ready;
    assign wr_frame_done = wr_fire && wr_last;

    assign bank0_reading = rd_frame_valid && (rd_bank_sel == 1'b0);
    assign bank1_reading = rd_frame_valid && (rd_bank_sel == 1'b1);
    assign bank0_free = !bank0_valid && !bank0_reading;
    assign bank1_free = !bank1_valid && !bank1_reading;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            wr_done <= 1'b0;
            rd_data <= {DATA_WIDTH{1'b0}};
            rd_valid <= 1'b0;
            rd_frame_valid <= 1'b0;
            wr_bank_sel <= 1'b0;
            rd_bank_sel <= 1'b0;
            bank0_valid <= 1'b0;
            bank1_valid <= 1'b0;
            wr_busy <= 1'b0;
        end
        else begin
            wr_done <= 1'b0;
            rd_valid <= 1'b0;

            // 空闲时, 把写bank尽量指向真正空闲的一块
            if(!wr_busy) begin
                if((wr_bank_sel == 1'b0) && !bank0_free && bank1_free) begin
                    wr_bank_sel <= 1'b1;
                end
                else if((wr_bank_sel == 1'b1) && !bank1_free && bank0_free) begin
                    wr_bank_sel <= 1'b0;
                end
            end

            // 整帧读完后, 释放当前读bank, 并尝试切到另一块完整bank
            if(rd_done && rd_frame_valid) begin
                if(rd_bank_sel == 1'b0) begin
                    bank0_valid <= 1'b0;
                    if(bank1_valid || (wr_frame_done && (wr_bank_sel == 1'b1))) begin
                        rd_bank_sel <= 1'b1;
                        rd_frame_valid <= 1'b1;
                    end
                    else begin
                        rd_frame_valid <= 1'b0;
                    end
                end
                else begin
                    bank1_valid <= 1'b0;
                    if(bank0_valid || (wr_frame_done && (wr_bank_sel == 1'b0))) begin
                        rd_bank_sel <= 1'b0;
                        rd_frame_valid <= 1'b1;
                    end
                    else begin
                        rd_frame_valid <= 1'b0;
                    end
                end
            end

            // 写地址完全由外部给出, wr_last声明一整帧结束
            if(wr_fire) begin
                if(wr_bank_sel == 1'b0) begin
                    bank0[wr_addr_1d] <= wr_data;
                end
                else begin
                    bank1[wr_addr_1d] <= wr_data;
                end

                if(wr_frame_done) begin
                    wr_done <= 1'b1;
                    wr_busy <= 1'b0;

                    if(wr_bank_sel == 1'b0) begin
                        bank0_valid <= 1'b1;
                        if(!rd_frame_valid) begin
                            rd_bank_sel <= 1'b0;
                            rd_frame_valid <= 1'b1;
                        end
                        if(bank1_free) begin
                            wr_bank_sel <= 1'b1;
                        end
                    end
                    else begin
                        bank1_valid <= 1'b1;
                        if(!rd_frame_valid) begin
                            rd_bank_sel <= 1'b1;
                            rd_frame_valid <= 1'b1;
                        end
                        if(bank0_free) begin
                            wr_bank_sel <= 1'b0;
                        end
                    end
                end
                else begin
                    wr_busy <= 1'b1;
                end
            end

            // 单点读: 外部给拼接二维地址, 本模块返回当前读bank里的对应像素
            if(rd_en && rd_frame_valid) begin
                if(rd_bank_sel == 1'b0) begin
                    rd_data <= bank0[rd_addr_1d];
                end
                else begin
                    rd_data <= bank1[rd_addr_1d];
                end
                rd_valid <= 1'b1;
            end
        end
    end

endmodule