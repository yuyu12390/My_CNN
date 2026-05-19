`timescale 1ns / 1ns

// 特征图乒乓缓存模块
// 1. 两个bank都按BRAM推断友好方式实现
// 2. 外部给二维地址, 模块内部转成一维地址
// 3. 读口保持单拍同步读, 接口时序不变
module pingpong_img_buf
#(
    parameter DATA_WIDTH = 32,
    parameter IMG_W = 24,
    parameter IMG_H = 24,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter DEPTH = IMG_W * IMG_H,
    parameter ADDR_WIDTH = 10
)
(
    input  clk,                                  // 时钟
    input  rstn,                                 // 低有效复位
    input  wr_valid,                             // 写有效
    input  signed [DATA_WIDTH-1:0] wr_data,      // 写数据
    input  [ADDR2D_WIDTH-1:0] wr_addr2d,         // 写二维地址
    input  wr_last,                              // 一帧最后一个写数据
    input  rd_en,                                // 读使能
    input  [ADDR2D_WIDTH-1:0] rd_addr2d,         // 读二维地址
    input  rd_done,                              // 当前读帧结束

    output wr_ready,                             // 写准备好
    output reg wr_done,                          // 当前写帧结束脉冲
    output signed [DATA_WIDTH-1:0] rd_data,      // 读数据
    output reg rd_valid,                         // 读数据有效
    output reg rd_frame_valid                    // 当前读bank有效
);

    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] bank0 [0:DEPTH-1];
    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] bank1 [0:DEPTH-1];

    reg wr_bank_sel;
    reg rd_bank_sel;
    reg bank0_valid;
    reg bank1_valid;
    reg wr_busy;
    reg rd_bank_sel_hold;
    reg signed [DATA_WIDTH-1:0] bank0_rd_data;
    reg signed [DATA_WIDTH-1:0] bank1_rd_data;

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
    wire rd_fire;
    wire bank0_wr_fire;
    wire bank1_wr_fire;
    wire bank0_rd_fire;
    wire bank1_rd_fire;

    assign wr_row = wr_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
    assign wr_col = wr_addr2d[COL_ADDR_WIDTH-1:0];
    assign rd_row = rd_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
    assign rd_col = rd_addr2d[COL_ADDR_WIDTH-1:0];

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

    assign rd_fire = rd_en && rd_frame_valid;
    assign bank0_wr_fire = wr_fire && (wr_bank_sel == 1'b0);
    assign bank1_wr_fire = wr_fire && (wr_bank_sel == 1'b1);
    assign bank0_rd_fire = rd_fire && (rd_bank_sel == 1'b0);
    assign bank1_rd_fire = rd_fire && (rd_bank_sel == 1'b1);

    assign rd_data = rd_bank_sel_hold ? bank1_rd_data : bank0_rd_data;

    // bank0独立读写口, 便于综合推断成块RAM
    always @(posedge clk)
    begin
        if(bank0_wr_fire)
        begin
            bank0[wr_addr_1d] <= wr_data;
        end

        if(bank0_rd_fire)
        begin
            bank0_rd_data <= bank0[rd_addr_1d];
        end
    end

    // bank1独立读写口, 便于综合推断成块RAM
    always @(posedge clk)
    begin
        if(bank1_wr_fire)
        begin
            bank1[wr_addr_1d] <= wr_data;
        end

        if(bank1_rd_fire)
        begin
            bank1_rd_data <= bank1[rd_addr_1d];
        end
    end

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            wr_done <= 1'b0;
            rd_valid <= 1'b0;
            rd_frame_valid <= 1'b0;
            wr_bank_sel <= 1'b0;
            rd_bank_sel <= 1'b0;
            rd_bank_sel_hold <= 1'b0;
            bank0_valid <= 1'b0;
            bank1_valid <= 1'b0;
            wr_busy <= 1'b0;
        end
        else
        begin
            wr_done <= 1'b0;
            rd_valid <= rd_fire;

            if(rd_fire)
            begin
                rd_bank_sel_hold <= rd_bank_sel;
            end

            // 空闲时, 把写bank尽量指向真正空闲的一块
            if(!wr_busy)
            begin
                if((wr_bank_sel == 1'b0) && !bank0_free && bank1_free)
                begin
                    wr_bank_sel <= 1'b1;
                end
                else if((wr_bank_sel == 1'b1) && !bank1_free && bank0_free)
                begin
                    wr_bank_sel <= 1'b0;
                end
            end

            // 整帧读完后, 释放当前读bank, 并尝试切到另一块完整bank
            if(rd_done && rd_frame_valid)
            begin
                if(rd_bank_sel == 1'b0)
                begin
                    bank0_valid <= 1'b0;
                    if(bank1_valid || (wr_frame_done && (wr_bank_sel == 1'b1)))
                    begin
                        rd_bank_sel <= 1'b1;
                        rd_frame_valid <= 1'b1;
                    end
                    else
                    begin
                        rd_frame_valid <= 1'b0;
                    end
                end
                else
                begin
                    bank1_valid <= 1'b0;
                    if(bank0_valid || (wr_frame_done && (wr_bank_sel == 1'b0)))
                    begin
                        rd_bank_sel <= 1'b0;
                        rd_frame_valid <= 1'b1;
                    end
                    else
                    begin
                        rd_frame_valid <= 1'b0;
                    end
                end
            end

            // 写地址完全由外部给出, wr_last声明一整帧结束
            if(wr_fire)
            begin
                if(wr_frame_done)
                begin
                    wr_done <= 1'b1;
                    wr_busy <= 1'b0;

                    if(wr_bank_sel == 1'b0)
                    begin
                        bank0_valid <= 1'b1;
                        if(!rd_frame_valid)
                        begin
                            rd_bank_sel <= 1'b0;
                            rd_frame_valid <= 1'b1;
                        end
                        if(bank1_free)
                        begin
                            wr_bank_sel <= 1'b1;
                        end
                    end
                    else
                    begin
                        bank1_valid <= 1'b1;
                        if(!rd_frame_valid)
                        begin
                            rd_bank_sel <= 1'b1;
                            rd_frame_valid <= 1'b1;
                        end
                        if(bank0_free)
                        begin
                            wr_bank_sel <= 1'b0;
                        end
                    end
                end
                else
                begin
                    wr_busy <= 1'b1;
                end
            end
        end
    end

endmodule
