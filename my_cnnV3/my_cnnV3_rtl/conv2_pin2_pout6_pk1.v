module conv2_pin2_pout6_pk1
(
    input clk,
    input rstn,
    input start,

    input fmap_valid,
    input signed [7:0] fmap_0,
    input signed [7:0] fmap_1,

    input signed [7:0] weight,
    input [5:0] weight_en,

    output reg ovalid,
    output reg done,
    output reg signed [31:0] dout_0,
    output reg signed [31:0] dout_1,
    output reg signed [31:0] dout_2,
    output reg signed [31:0] dout_3,
    output reg signed [31:0] dout_4,
    output reg signed [31:0] dout_5
);

    localparam FMAP_SIZE   = 8'd144;
    localparam WEIGHT_SIZE = 6'd50;
    localparam integer OUT_SIZE = 64;
    localparam TAP_LAST    = 5'd24;

    reg signed [7:0] fmap_mem_0 [0:143];
    reg signed [7:0] fmap_mem_1 [0:143];

    reg signed [7:0] w0 [0:49];
    reg signed [7:0] w1 [0:49];
    reg signed [7:0] w2 [0:49];
    reg signed [7:0] w3 [0:49];
    reg signed [7:0] w4 [0:49];
    reg signed [7:0] w5 [0:49];

    reg signed [31:0] out_mem_0 [0:63];
    reg signed [31:0] out_mem_1 [0:63];
    reg signed [31:0] out_mem_2 [0:63];
    reg signed [31:0] out_mem_3 [0:63];
    reg signed [31:0] out_mem_4 [0:63];
    reg signed [31:0] out_mem_5 [0:63];

    reg [7:0] fmap_load_cnt;
    reg [5:0] waddr_0;
    reg [5:0] waddr_1;
    reg [5:0] waddr_2;
    reg [5:0] waddr_3;
    reg [5:0] waddr_4;
    reg [5:0] waddr_5;

    reg compute_en;
    reg emit_en;
    reg [5:0] out_idx;
    reg [4:0] tap_idx;
    reg [2:0] emit_row;
    reg [3:0] emit_col;

    reg [2:0] out_row;
    reg [2:0] out_col;
    reg [2:0] tap_row;
    reg [2:0] tap_col;
    reg [7:0] fmap_idx;
    reg [5:0] tap_idx_ch1;

    reg signed [31:0] acc_0;
    reg signed [31:0] acc_1;
    reg signed [31:0] acc_2;
    reg signed [31:0] acc_3;
    reg signed [31:0] acc_4;
    reg signed [31:0] acc_5;

    reg signed [17:0] mac_0;
    reg signed [17:0] mac_1;
    reg signed [17:0] mac_2;
    reg signed [17:0] mac_3;
    reg signed [17:0] mac_4;
    reg signed [17:0] mac_5;

    wire fmap_loaded;
    wire weight_loaded;
    wire ready_to_compute;

    integer i;

    assign fmap_loaded = (fmap_load_cnt == FMAP_SIZE);
    assign weight_loaded = (waddr_0 == WEIGHT_SIZE) &&
                           (waddr_1 == WEIGHT_SIZE) &&
                           (waddr_2 == WEIGHT_SIZE) &&
                           (waddr_3 == WEIGHT_SIZE) &&
                           (waddr_4 == WEIGHT_SIZE) &&
                           (waddr_5 == WEIGHT_SIZE);
    assign ready_to_compute = fmap_loaded && weight_loaded;

    always @(*) begin
        out_row = out_idx[5:3];
        out_col = out_idx[2:0];
        tap_row = tap_idx / 5;
        tap_col = tap_idx % 5;
        tap_idx_ch1 = {1'b0, tap_idx} + 6'd25;
        fmap_idx = ({5'd0, out_row} * 8'd12) +
                   {5'd0, out_col} +
                   ({5'd0, tap_row} * 8'd12) +
                   {5'd0, tap_col};

        mac_0 = $signed(fmap_mem_0[fmap_idx]) * $signed(w0[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w0[tap_idx_ch1]);
        mac_1 = $signed(fmap_mem_0[fmap_idx]) * $signed(w1[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w1[tap_idx_ch1]);
        mac_2 = $signed(fmap_mem_0[fmap_idx]) * $signed(w2[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w2[tap_idx_ch1]);
        mac_3 = $signed(fmap_mem_0[fmap_idx]) * $signed(w3[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w3[tap_idx_ch1]);
        mac_4 = $signed(fmap_mem_0[fmap_idx]) * $signed(w4[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w4[tap_idx_ch1]);
        mac_5 = $signed(fmap_mem_0[fmap_idx]) * $signed(w5[tap_idx]) +
                $signed(fmap_mem_1[fmap_idx]) * $signed(w5[tap_idx_ch1]);
    end

    always @(posedge clk or negedge rstn) begin
        if(!rstn || !start) begin
            fmap_load_cnt <= 8'd0;
        end
        else if(fmap_valid && !fmap_loaded) begin
            fmap_mem_0[fmap_load_cnt] <= fmap_0;
            fmap_mem_1[fmap_load_cnt] <= fmap_1;
            fmap_load_cnt <= fmap_load_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if(!rstn || !start) begin
            waddr_0 <= 6'd0;
            waddr_1 <= 6'd0;
            waddr_2 <= 6'd0;
            waddr_3 <= 6'd0;
            waddr_4 <= 6'd0;
            waddr_5 <= 6'd0;
        end
        else begin
            if(weight_en[0] && (waddr_0 < WEIGHT_SIZE)) begin
                w0[waddr_0] <= weight;
                waddr_0 <= waddr_0 + 1'b1;
            end
            if(weight_en[1] && (waddr_1 < WEIGHT_SIZE)) begin
                w1[waddr_1] <= weight;
                waddr_1 <= waddr_1 + 1'b1;
            end
            if(weight_en[2] && (waddr_2 < WEIGHT_SIZE)) begin
                w2[waddr_2] <= weight;
                waddr_2 <= waddr_2 + 1'b1;
            end
            if(weight_en[3] && (waddr_3 < WEIGHT_SIZE)) begin
                w3[waddr_3] <= weight;
                waddr_3 <= waddr_3 + 1'b1;
            end
            if(weight_en[4] && (waddr_4 < WEIGHT_SIZE)) begin
                w4[waddr_4] <= weight;
                waddr_4 <= waddr_4 + 1'b1;
            end
            if(weight_en[5] && (waddr_5 < WEIGHT_SIZE)) begin
                w5[waddr_5] <= weight;
                waddr_5 <= waddr_5 + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            compute_en <= 1'b0;
            emit_en <= 1'b0;
            out_idx <= 6'd0;
            tap_idx <= 5'd0;
            emit_row <= 3'd0;
            emit_col <= 4'd0;
            acc_0 <= 32'sd0;
            acc_1 <= 32'sd0;
            acc_2 <= 32'sd0;
            acc_3 <= 32'sd0;
            acc_4 <= 32'sd0;
            acc_5 <= 32'sd0;
            dout_0 <= 32'sd0;
            dout_1 <= 32'sd0;
            dout_2 <= 32'sd0;
            dout_3 <= 32'sd0;
            dout_4 <= 32'sd0;
            dout_5 <= 32'sd0;
            ovalid <= 1'b0;
            done <= 1'b0;
            for(i=0; i<64; i=i+1) begin
                out_mem_0[i] <= 32'sd0;
                out_mem_1[i] <= 32'sd0;
                out_mem_2[i] <= 32'sd0;
                out_mem_3[i] <= 32'sd0;
                out_mem_4[i] <= 32'sd0;
                out_mem_5[i] <= 32'sd0;
            end
        end
        else if(!start) begin
            compute_en <= 1'b0;
            emit_en <= 1'b0;
            out_idx <= 6'd0;
            tap_idx <= 5'd0;
            emit_row <= 3'd0;
            emit_col <= 4'd0;
            acc_0 <= 32'sd0;
            acc_1 <= 32'sd0;
            acc_2 <= 32'sd0;
            acc_3 <= 32'sd0;
            acc_4 <= 32'sd0;
            acc_5 <= 32'sd0;
            ovalid <= 1'b0;
            done <= 1'b0;
        end
        else begin
            ovalid <= 1'b0;
            done <= 1'b0;

            if(!compute_en && !emit_en && ready_to_compute) begin
                compute_en <= 1'b1;
                out_idx <= 6'd0;
                tap_idx <= 5'd0;
                acc_0 <= 32'sd0;
                acc_1 <= 32'sd0;
                acc_2 <= 32'sd0;
                acc_3 <= 32'sd0;
                acc_4 <= 32'sd0;
                acc_5 <= 32'sd0;
            end
            else if(compute_en) begin
                if(tap_idx == TAP_LAST) begin
                    out_mem_0[out_idx] <= acc_0 + $signed(mac_0);
                    out_mem_1[out_idx] <= acc_1 + $signed(mac_1);
                    out_mem_2[out_idx] <= acc_2 + $signed(mac_2);
                    out_mem_3[out_idx] <= acc_3 + $signed(mac_3);
                    out_mem_4[out_idx] <= acc_4 + $signed(mac_4);
                    out_mem_5[out_idx] <= acc_5 + $signed(mac_5);

                    acc_0 <= 32'sd0;
                    acc_1 <= 32'sd0;
                    acc_2 <= 32'sd0;
                    acc_3 <= 32'sd0;
                    acc_4 <= 32'sd0;
                    acc_5 <= 32'sd0;
                    tap_idx <= 5'd0;

                    if(out_idx == OUT_SIZE - 1'b1) begin
                        compute_en <= 1'b0;
                        emit_en <= 1'b1;
                        emit_row <= 3'd0;
                        emit_col <= 4'd0;
                        out_idx <= 6'd0;
                    end
                    else begin
                        out_idx <= out_idx + 1'b1;
                    end
                end
                else begin
                    acc_0 <= acc_0 + $signed(mac_0);
                    acc_1 <= acc_1 + $signed(mac_1);
                    acc_2 <= acc_2 + $signed(mac_2);
                    acc_3 <= acc_3 + $signed(mac_3);
                    acc_4 <= acc_4 + $signed(mac_4);
                    acc_5 <= acc_5 + $signed(mac_5);
                    tap_idx <= tap_idx + 1'b1;
                end
            end
            else if(emit_en) begin
                // Replay the stored 8x8 outputs over a 12-column scan so the
                // downstream pipeline still sees the original 8-valid/4-idle pattern.
                if(emit_col < 4'd8) begin
                    dout_0 <= out_mem_0[{emit_row, emit_col[2:0]}];
                    dout_1 <= out_mem_1[{emit_row, emit_col[2:0]}];
                    dout_2 <= out_mem_2[{emit_row, emit_col[2:0]}];
                    dout_3 <= out_mem_3[{emit_row, emit_col[2:0]}];
                    dout_4 <= out_mem_4[{emit_row, emit_col[2:0]}];
                    dout_5 <= out_mem_5[{emit_row, emit_col[2:0]}];
                    ovalid <= 1'b1;
                end

                // Match the V2 tail timing: stop on the first idle slot after
                // the last valid sample so downstream add-count restart logic
                // still sees the final 64th add result before the counter clears.
                if((emit_row == 3'd7) && (emit_col == 4'd8)) begin
                    emit_en <= 1'b0;
                    done <= 1'b1;
                    emit_row <= 3'd0;
                    emit_col <= 4'd0;
                end
                else begin
                    if(emit_col == 4'd11) begin
                        emit_col <= 4'd0;
                        emit_row <= emit_row + 1'b1;
                    end
                    else begin
                        emit_col <= emit_col + 1'b1;
                    end
                end
            end
        end
    end

endmodule
