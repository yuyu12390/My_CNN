`timescale 1ns / 1ns
// 图像输入缓存模块
module img_in_buf
#(
    parameter DATA_WIDTH = 8,
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter ROW_ADDR_WIDTH = 5,
    parameter COL_ADDR_WIDTH = 5,
    parameter ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH,
    parameter DEPTH = IMG_W * IMG_H,
    parameter ADDR1D_WIDTH = 10
)
(
    input clk,                                // 时钟
    input rstn,                               // 低有效复位
    input [DATA_WIDTH-1:0] image_tdata,       // 图像输入数据
    input image_tvalid,                       // 图像输入有效
    input addr_valid,                         // 二维地址有效
    input [ADDR2D_WIDTH-1:0] addr2d,          // 输入二维地址
    input addr_last,                          // 最后一个二维地址
    input rd_en,                              // 读使能
    input [ADDR2D_WIDTH-1:0] rd_addr2d,       // 读二维地址
    input rd_done,                            // 读完一帧

    output image_tready,                      // 图像输入准备好
    output addr_ready,                        // 地址接收完成
    output reg wr_done,                       // 写完一帧脉冲
    output reg frame_valid,                   // 当前缓存帧有效
    output [DATA_WIDTH-1:0] rd_data,          // 读数据
    output reg rd_valid                       // 读数据有效
);

    wire [ROW_ADDR_WIDTH-1:0] wr_row;
    wire [COL_ADDR_WIDTH-1:0] wr_col;
    wire [ROW_ADDR_WIDTH-1:0] rd_row;
    wire [COL_ADDR_WIDTH-1:0] rd_col;
    wire [ADDR1D_WIDTH-1:0] wr_addr1d;
    wire [ADDR1D_WIDTH-1:0] rd_addr1d;
    wire wr_fire;
    wire rd_fire;
    wire [DATA_WIDTH-1:0] bram_rd_data;

    //提取行地址和列地址
    assign wr_row = addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];//
    assign wr_col = addr2d[COL_ADDR_WIDTH-1:0];
    assign rd_row = rd_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
    assign rd_col = rd_addr2d[COL_ADDR_WIDTH-1:0];

    // 模块内部把二维地址转成一维地址后访问 BRAM IP
    assign wr_addr1d = (wr_row * IMG_W) + wr_col;
    assign rd_addr1d = (rd_row * IMG_W) + rd_col;

    assign image_tready = 1'b1;
    assign addr_ready = image_tvalid;
    assign wr_fire = image_tvalid && addr_valid;
    assign rd_fire = rd_en && frame_valid;

    assign rd_data = bram_rd_data;

    // A口写, B口读
    img_in_buf_ram u_img_in_buf_ram
    (
        .clka(clk),
        .ena(wr_fire),
        .wea({wr_fire}),
        .addra(wr_addr1d),
        .dina(image_tdata),
        .clkb(clk),
        .enb(rd_fire),
        .addrb(rd_addr1d),
        .doutb(bram_rd_data)
    );

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn)
        begin
            wr_done <= 1'b0;
            frame_valid <= 1'b0;
            rd_valid <= 1'b0;
        end
        else
        begin
            wr_done <= 1'b0;
            rd_valid <= 1'b0;

            if(wr_fire)
            begin
                if(addr_last)
                begin
                    wr_done <= 1'b1;
                    frame_valid <= 1'b1;
                end
            end

            if(rd_fire)
            begin
                rd_valid <= 1'b1;
            end

            if(rd_done)
            begin
                frame_valid <= 1'b0;
            end
        end
    end

endmodule
