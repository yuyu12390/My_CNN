`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/08/10 15:41:35
// Design Name: 
// Module Name: CNN
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module FIFO_weight
( 	
    input clk,
	input rstn,
	input [7:0] s_axis_tdata,
	input s_axis_tvalid,
	output s_axis_tready,
	input rd_rst,
	input m_axis_tready,
	output m_axis_tvalid,
	output reg [7:0] m_axis_tdata
);
reg [10:0] rd_ptr, wr_ptr;
reg [10:0] mem [0:1949];
integer i;
reg s_axis_ready;
reg m_axis_valid;

assign empty = (wr_ptr == rd_ptr);
assign full = ((wr_ptr - rd_ptr) == 11'd1950);

always@(*)
begin
if(!full)
    s_axis_ready <= 1'b1;
else
    s_axis_ready <= 1'b0;
end

always@(*)
begin
if(!empty)
    m_axis_valid <= 1'b1;
else
    m_axis_valid <= 1'b0;
end

    
always @(posedge clk or negedge rstn)
begin
    if(!rstn)
        m_axis_tdata <= 0;
	else if(m_axis_tready && m_axis_valid)
		m_axis_tdata <= mem[rd_ptr];
	end
	
always @(posedge clk or negedge rstn) 
begin
    if(rstn && s_axis_ready && s_axis_tvalid)
	   mem[wr_ptr] <= s_axis_tdata;
end
	
always @(posedge clk or negedge rstn) 
begin
    if(!rstn) 
        wr_ptr <= 0;
	else if(!full && s_axis_tvalid)
		wr_ptr <= wr_ptr + 1;
end

always @(posedge clk or negedge rstn) 
begin
    if(!rstn)
        rd_ptr <= 0;
    else
        if(rd_rst)	
            rd_ptr <= 0;
        else if(!empty && m_axis_tready)
			rd_ptr <= rd_ptr + 1;
	end

assign s_axis_tready = s_axis_ready;
assign m_axis_tvalid = m_axis_valid;
endmodule 