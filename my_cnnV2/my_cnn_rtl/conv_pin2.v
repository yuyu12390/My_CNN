module conv_pin2
#(
    parameter K = 5,
    parameter S = 1
)
(
    input clk,
    input rstn,
    input start,
    input weight_en,
    input signed [7:0] weight,
    input [39:0] taps_0,
    input [39:0] taps_1,
    input state,
    output signed [31:0] dout,
    output ovalid,
    output done
);

    reg [7:0] weight_addr;
    reg [19:0] cnt1;
    reg [9:0] cnt2;
    reg [9:0] cnt2s;
    reg [9:0] cnt3s;
    reg wren;
    reg sum_valid;
    reg sum_valid_ff;

    reg [4:0] Ni;
    reg [7:0] weight_total;
    reg [9:0] valid_start_cnt;
    reg [9:0] valid_end_cnt;

    reg signed [7:0] k0 [0:24];
    reg signed [7:0] k1 [0:24];
    reg signed [7:0] m0 [0:24];
    reg signed [7:0] m1 [0:24];
    reg signed [15:0] p0 [0:24];
    reg signed [15:0] p1 [0:24];

    reg signed [16:0] sum_s2_0 [0:14];
    reg signed [16:0] sum_s2_1 [0:14];
    reg signed [17:0] sum_s3_0 [0:9];
    reg signed [17:0] sum_s3_1 [0:9];
    reg signed [18:0] sum_s4_0 [0:4];
    reg signed [18:0] sum_s4_1 [0:4];
    reg signed [19:0] sum_s5_0 [0:2];
    reg signed [19:0] sum_s5_1 [0:2];
    reg signed [20:0] sum_s6_0 [0:1];
    reg signed [20:0] sum_s6_1 [0:1];
    reg signed [31:0] wr_data_0;
    reg signed [31:0] wr_data_1;

    integer i;
    integer col_idx;

    wire signed [7:0] taps0_r0;
    wire signed [7:0] taps0_r1;
    wire signed [7:0] taps0_r2;
    wire signed [7:0] taps0_r3;
    wire signed [7:0] taps0_r4;
    wire signed [7:0] taps1_r0;
    wire signed [7:0] taps1_r1;
    wire signed [7:0] taps1_r2;
    wire signed [7:0] taps1_r3;
    wire signed [7:0] taps1_r4;

    assign taps0_r0 = taps_0[39:32];
    assign taps0_r1 = taps_0[31:24];
    assign taps0_r2 = taps_0[23:16];
    assign taps0_r3 = taps_0[15:8];
    assign taps0_r4 = taps_0[7:0];
    assign taps1_r0 = taps_1[39:32];
    assign taps1_r1 = taps_1[31:24];
    assign taps1_r2 = taps_1[23:16];
    assign taps1_r3 = taps_1[15:8];
    assign taps1_r4 = taps_1[7:0];

    always @(*)
    begin
        if(!state) begin
            Ni = 5'd28;
            weight_total = 8'd25;
            valid_start_cnt = 10'd162;
            valid_end_cnt = 10'd830;
        end
        else begin
            Ni = 5'd12;
            weight_total = 8'd50;
            valid_start_cnt = 10'd313;
            valid_end_cnt = 10'd405;
        end
    end

    always @(posedge clk)
    begin
        m0[0]  <= m0[1];
        m0[1]  <= m0[2];
        m0[2]  <= m0[3];
        m0[3]  <= taps0_r0;
        m0[5]  <= m0[6];
        m0[6]  <= m0[7];
        m0[7]  <= m0[8];
        m0[8]  <= taps0_r1;
        m0[10] <= m0[11];
        m0[11] <= m0[12];
        m0[12] <= m0[13];
        m0[13] <= taps0_r2;
        m0[15] <= m0[16];
        m0[16] <= m0[17];
        m0[17] <= m0[18];
        m0[18] <= taps0_r3;
        m0[20] <= m0[21];
        m0[21] <= m0[22];
        m0[22] <= m0[23];
        m0[23] <= taps0_r4;

        m1[0]  <= m1[1];
        m1[1]  <= m1[2];
        m1[2]  <= m1[3];
        m1[3]  <= taps1_r0;
        m1[5]  <= m1[6];
        m1[6]  <= m1[7];
        m1[7]  <= m1[8];
        m1[8]  <= taps1_r1;
        m1[10] <= m1[11];
        m1[11] <= m1[12];
        m1[12] <= m1[13];
        m1[13] <= taps1_r2;
        m1[15] <= m1[16];
        m1[16] <= m1[17];
        m1[17] <= m1[18];
        m1[18] <= taps1_r3;
        m1[20] <= m1[21];
        m1[21] <= m1[22];
        m1[22] <= m1[23];
        m1[23] <= taps1_r4;
    end

    always @(posedge clk or negedge rstn)
    begin
        if(!rstn || !start) begin
            weight_addr <= 8'd0;
            for(i=0; i<25; i=i+1) begin
                k0[i] <= 8'sd0;
                k1[i] <= 8'sd0;
            end
        end
        else begin
            if(weight_en && weight_addr < weight_total) begin
                if(weight_addr < 8'd25)
                    k0[weight_addr] <= weight;
                else
                    k1[weight_addr-8'd25] <= weight;
                weight_addr <= weight_addr + 1'b1;
            end
            else begin
                weight_addr <= weight_addr;
            end
        end
    end

    always @(posedge clk)
    begin
        p0[0]  <= k0[0]  * m0[0];
        p0[1]  <= k0[1]  * m0[1];
        p0[2]  <= k0[2]  * m0[2];
        p0[3]  <= k0[3]  * m0[3];
        p0[4]  <= k0[4]  * taps0_r0;
        p0[5]  <= k0[5]  * m0[5];
        p0[6]  <= k0[6]  * m0[6];
        p0[7]  <= k0[7]  * m0[7];
        p0[8]  <= k0[8]  * m0[8];
        p0[9]  <= k0[9]  * taps0_r1;
        p0[10] <= k0[10] * m0[10];
        p0[11] <= k0[11] * m0[11];
        p0[12] <= k0[12] * m0[12];
        p0[13] <= k0[13] * m0[13];
        p0[14] <= k0[14] * taps0_r2;
        p0[15] <= k0[15] * m0[15];
        p0[16] <= k0[16] * m0[16];
        p0[17] <= k0[17] * m0[17];
        p0[18] <= k0[18] * m0[18];
        p0[19] <= k0[19] * taps0_r3;
        p0[20] <= k0[20] * m0[20];
        p0[21] <= k0[21] * m0[21];
        p0[22] <= k0[22] * m0[22];
        p0[23] <= k0[23] * m0[23];
        p0[24] <= k0[24] * taps0_r4;

        p1[0]  <= k1[0]  * m1[0];
        p1[1]  <= k1[1]  * m1[1];
        p1[2]  <= k1[2]  * m1[2];
        p1[3]  <= k1[3]  * m1[3];
        p1[4]  <= k1[4]  * taps1_r0;
        p1[5]  <= k1[5]  * m1[5];
        p1[6]  <= k1[6]  * m1[6];
        p1[7]  <= k1[7]  * m1[7];
        p1[8]  <= k1[8]  * m1[8];
        p1[9]  <= k1[9]  * taps1_r1;
        p1[10] <= k1[10] * m1[10];
        p1[11] <= k1[11] * m1[11];
        p1[12] <= k1[12] * m1[12];
        p1[13] <= k1[13] * m1[13];
        p1[14] <= k1[14] * taps1_r2;
        p1[15] <= k1[15] * m1[15];
        p1[16] <= k1[16] * m1[16];
        p1[17] <= k1[17] * m1[17];
        p1[18] <= k1[18] * m1[18];
        p1[19] <= k1[19] * taps1_r3;
        p1[20] <= k1[20] * m1[20];
        p1[21] <= k1[21] * m1[21];
        p1[22] <= k1[22] * m1[22];
        p1[23] <= k1[23] * m1[23];
        p1[24] <= k1[24] * taps1_r4;
    end

    always @(posedge clk)
    begin
        for(col_idx=0; col_idx<5; col_idx=col_idx+1) begin
            sum_s2_0[col_idx*3+0] <= p0[col_idx] + p0[5+col_idx];
            sum_s2_0[col_idx*3+1] <= p0[10+col_idx] + p0[15+col_idx];
            sum_s2_0[col_idx*3+2] <= p0[20+col_idx];

            sum_s2_1[col_idx*3+0] <= p1[col_idx] + p1[5+col_idx];
            sum_s2_1[col_idx*3+1] <= p1[10+col_idx] + p1[15+col_idx];
            sum_s2_1[col_idx*3+2] <= p1[20+col_idx];
        end
    end

    always @(posedge clk)
    begin
        for(col_idx=0; col_idx<5; col_idx=col_idx+1) begin
            sum_s3_0[col_idx*2+0] <= sum_s2_0[col_idx*3+0] + sum_s2_0[col_idx*3+1];
            sum_s3_0[col_idx*2+1] <= sum_s2_0[col_idx*3+2];

            sum_s3_1[col_idx*2+0] <= sum_s2_1[col_idx*3+0] + sum_s2_1[col_idx*3+1];
            sum_s3_1[col_idx*2+1] <= sum_s2_1[col_idx*3+2];
        end
    end

    always @(posedge clk)
    begin
        for(col_idx=0; col_idx<5; col_idx=col_idx+1) begin
            sum_s4_0[col_idx] <= sum_s3_0[col_idx*2+0] + sum_s3_0[col_idx*2+1];
            sum_s4_1[col_idx] <= sum_s3_1[col_idx*2+0] + sum_s3_1[col_idx*2+1];
        end
    end

    always @(posedge clk)
    begin
        sum_s5_0[0] <= sum_s4_0[0] + sum_s4_0[1];
        sum_s5_0[1] <= sum_s4_0[2] + sum_s4_0[3];
        sum_s5_0[2] <= sum_s4_0[4];

        sum_s5_1[0] <= sum_s4_1[0] + sum_s4_1[1];
        sum_s5_1[1] <= sum_s4_1[2] + sum_s4_1[3];
        sum_s5_1[2] <= sum_s4_1[4];
    end

    always @(posedge clk)
    begin
        sum_s6_0[0] <= sum_s5_0[0] + sum_s5_0[1];
        sum_s6_0[1] <= sum_s5_0[2];

        sum_s6_1[0] <= sum_s5_1[0] + sum_s5_1[1];
        sum_s6_1[1] <= sum_s5_1[2];
    end

    always @(posedge clk)
    begin
        wr_data_0 <= sum_s6_0[0] + sum_s6_0[1];
        wr_data_1 <= sum_s6_1[0] + sum_s6_1[1];
    end

    always @(posedge clk)
    begin
        if(start)
            cnt1 <= cnt1 + 1'd1;
        else
            cnt1 <= 19'd0;
    end

    always @(posedge clk)
    begin
        if(sum_valid) begin
            if(cnt2 == Ni-1)
                cnt2 <= 10'd0;
            else
                cnt2 <= cnt2 + 10'd1;
        end
        else begin
            cnt2 <= 10'd0;
        end
    end

    always @(posedge clk)
    begin
        if(sum_valid) begin
            if(cnt2 == Ni-1) begin
                if(cnt3s == S-1)
                    cnt3s <= 10'd0;
                else
                    cnt3s <= cnt3s + 1'd1;
            end
            else begin
                cnt3s <= cnt3s;
            end
        end
        else begin
            cnt3s <= 10'd0;
        end
    end

    always @(posedge clk)
    begin
        if(sum_valid) begin
            if(cnt2 == Ni-1 || cnt2s == S-1)
                cnt2s <= 10'd0;
            else
                cnt2s <= cnt2s + 10'd1;
        end
        else begin
            cnt2s <= 10'd0;
        end
    end

    always @(posedge clk)
    begin
        if(sum_valid && cnt2 < Ni-K+1 && cnt2s == 0 && cnt3s == 0)
            wren <= 1'b1;
        else
            wren <= 1'b0;
    end

    always @(posedge clk)
    begin
        if(!start)
            sum_valid <= 1'b0;
        else if(cnt1 == valid_end_cnt)
            sum_valid <= 1'b0;
        else if(cnt1 == valid_start_cnt)
            sum_valid <= 1'b1;
    end

    always @(posedge clk)
    begin
        sum_valid_ff <= sum_valid;
    end

    assign done = ~sum_valid && sum_valid_ff;
    assign ovalid = wren;
    assign dout = (!state) ? wr_data_0 : ($signed(wr_data_0) + $signed(wr_data_1));

endmodule
