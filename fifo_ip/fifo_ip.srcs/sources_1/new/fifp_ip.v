`timescale 1ns / 1ps

module fifp_ip
(
    input sys_clk,
    input BTN0
);

wire sys_rst_n;
wire almost_empty;
wire almost_full;
wire fifo_wr_en;
wire [7:0] fifo_wr_data;
wire fifo_rd_en;
wire [7:0] dout;
wire empty;
wire full;
wire [7:0] wr_data_count;
wire [7:0] rd_data_count;

assign sys_rst_n = ~BTN0;

fifo_write fifo_write_u
(
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    .almost_empty(almost_empty),
    .almost_full(almost_full),
    
    .fifo_wr_en(fifo_wr_en),
    .fifo_wr_data(fifo_wr_data)   
);

fifo_rd fifo_rd_u
(
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    .almost_empty(almost_empty),
    .almost_full(almost_full),
    .fifo_rd_data(fifo_rd_data),
    
    .fifo_rd_en(fifo_rd_en)
);

fifo_generator_0 fifo_ip_u (
  .wr_clk(sys_clk),                
  .rd_clk(sys_clk),               
  .din(fifo_wr_data),                     
  .wr_en(fifo_wr_en),                 
  .rd_en(fifo_rd_en),                 
  .dout(dout),                   
  .full(full),                   
  .almost_full(almost_full),     
  .empty(empty),                 
  .almost_empty(almost_empty),   
  .rd_data_count(rd_data_count), 
  .wr_data_count(wr_data_count)  
);


ila_0 ila_0_u (
	.clk(sys_clk), // input wire clk

	.probe0(fifo_wr_data), // input wire [7:0]  probe0  
	.probe1(dout), // input wire [7:0]  probe1 
	.probe2(wr_data_count), // input wire [7:0]  probe2 
	.probe3(rd_data_count), // input wire [7:0]  probe3 
	.probe4(empty), // input wire [0:0]  probe4 
	.probe5(almost_empty), // input wire [0:0]  probe5 
	.probe6(full), // input wire [0:0]  probe6 
	.probe7(almost_full), // input wire [0:0]  probe7 
	.probe8(fifo_wr_ene8), // input wire [0:0]  probe8 
	.probe9(fifo_rd_en) // input wire [0:0]  probe9
);



endmodule
