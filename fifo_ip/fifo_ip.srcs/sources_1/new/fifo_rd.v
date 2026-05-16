`timescale 1ns / 1ps

module fifo_rd
(
    input clk,
    input rst_n,
    input almost_empty,
    input almost_full,
    input [7:0] fifo_rd_data,
    
    output reg fifo_rd_en 
);

reg almost_full_d0;
reg almost_full_syn;
reg [1:0] state;
reg [3:0] dly_cnt;
wire syn;

assign syn = ~almost_full_syn & almost_full_d0;

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        begin
            almost_full_d0 <= 1'b0;
            almost_full_syn <= 1'b0;
        end
    else
        begin
            almost_full_d0 <= almost_full;
            almost_full_syn <= almost_full_d0;
        end
end

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        begin
            fifo_rd_en <= 1'b0;
            state <= 2'b0;
            dly_cnt <= 4'b0;
        end
    else
        begin
            case(state)
            2'b0:
                begin
                    if(syn) 
                        state <= 2'd1;
                    else
                        state <= state;
                end
            2'd1:
                begin
                    if(dly_cnt == 4'd10) 
                        begin
                            dly_cnt <= 4'd0;
                            state <= 2'd2;
                        end
                    else
                        dly_cnt <= dly_cnt + 4'd1;
                end
            2'd2:
                begin
                    if(almost_empty) 
                        begin
                           fifo_rd_en <= 1'b0;
                           state <= 2'd0;
                        end
                    else
                        fifo_rd_en <=  1'b1;
                end
            endcase
       end
end     

endmodule
