`timescale 1ns / 1ps

module compare_conv2_fifo_path_tb;

    reg clk;
    reg rstn;
    reg start;
    reg start_window;
    reg rd_en;

    reg signed [7:0] weight;
    reg [5:0] weight_en;

    wire [7:0] fifo_dout_0;
    wire [7:0] fifo_dout_1;
    wire [39:0] taps_0;
    wire [39:0] taps_1;

    wire signed [31:0] stream_dout [0:5];
    wire [5:0] stream_ovalid;
    wire [5:0] stream_done;

    reg valid_d1;
    reg valid_d2;
    reg valid_d3;

    wire direct_ovalid;
    wire direct_done;
    wire signed [31:0] direct_dout_0;
    wire signed [31:0] direct_dout_1;
    wire signed [31:0] direct_dout_2;
    wire signed [31:0] direct_dout_3;
    wire signed [31:0] direct_dout_4;
    wire signed [31:0] direct_dout_5;

    reg signed [7:0] fmap0_mem [0:143];
    reg signed [7:0] fmap1_mem [0:143];
    reg signed [7:0] w0_mem [0:49];
    reg signed [7:0] w1_mem [0:49];
    reg signed [7:0] w2_mem [0:49];
    reg signed [7:0] w3_mem [0:49];
    reg signed [7:0] w4_mem [0:49];
    reg signed [7:0] w5_mem [0:49];

    reg signed [31:0] stream0_store [0:63];
    reg signed [31:0] stream1_store [0:63];
    reg signed [31:0] stream2_store [0:63];
    reg signed [31:0] stream3_store [0:63];
    reg signed [31:0] stream4_store [0:63];
    reg signed [31:0] stream5_store [0:63];

    reg signed [31:0] direct0_store [0:63];
    reg signed [31:0] direct1_store [0:63];
    reg signed [31:0] direct2_store [0:63];
    reg signed [31:0] direct3_store [0:63];
    reg signed [31:0] direct4_store [0:63];
    reg signed [31:0] direct5_store [0:63];

    integer i;
    integer bank_idx;
    integer stream_count;
    integer direct_count;
    integer err_count;

    localparam integer CLK_PERIOD_NS = 20;
    localparam integer WINDOW_START_DELAY = 241;
    localparam integer TIMEOUT_NS = 2000000;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    FIFO_fmap u_fifo_0(
        .clk(clk),
        .rstn(rstn),
        .din(8'd0),
        .wr_en(1'b0),
        .rd_en(rd_en),
        .rd_rst(1'b0),
        .empty(),
        .full(),
        .dout(fifo_dout_0)
    );

    FIFO_fmap u_fifo_1(
        .clk(clk),
        .rstn(rstn),
        .din(8'd0),
        .wr_en(1'b0),
        .rd_en(rd_en),
        .rd_rst(1'b0),
        .empty(),
        .full(),
        .dout(fifo_dout_1)
    );

    window u_window_0(
        .clk(clk),
        .rstn(rstn),
        .start(start_window),
        .state(1'b1),
        .din(fifo_dout_0),
        .taps(taps_0)
    );

    window u_window_1(
        .clk(clk),
        .rstn(rstn),
        .start(start_window),
        .state(1'b1),
        .din(fifo_dout_1),
        .taps(taps_1)
    );

    genvar gi;
    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_stream_conv
            conv_pin2 u_stream_conv(
                .clk(clk),
                .rstn(rstn),
                .start(start),
                .weight_en(weight_en[gi]),
                .weight(weight),
                .taps_0(taps_0),
                .taps_1(taps_1),
                .state(1'b1),
                .dout(stream_dout[gi]),
                .ovalid(stream_ovalid[gi]),
                .done(stream_done[gi])
            );
        end
    endgenerate

    conv2_pin2_pout6_pk1 u_direct_conv(
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .fmap_valid(valid_d3),
        .fmap_0(fifo_dout_0),
        .fmap_1(fifo_dout_1),
        .weight(weight),
        .weight_en(weight_en),
        .ovalid(direct_ovalid),
        .done(direct_done),
        .dout_0(direct_dout_0),
        .dout_1(direct_dout_1),
        .dout_2(direct_dout_2),
        .dout_3(direct_dout_3),
        .dout_4(direct_dout_4),
        .dout_5(direct_dout_5)
    );

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;
            valid_d3 <= 1'b0;
        end
        else begin
            valid_d1 <= rd_en;
            valid_d2 <= valid_d1;
            valid_d3 <= valid_d2;
        end
    end

    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        start_window = 1'b0;
        rd_en = 1'b0;
        weight = 8'sd0;
        weight_en = 6'b000000;
        stream_count = 0;
        direct_count = 0;
        err_count = 0;

        for (i = 0; i < 144; i = i + 1) begin
            fmap0_mem[i] = ((i * 3) % 17) - 8;
            fmap1_mem[i] = ((i * 5) % 19) - 9;
        end

        for (i = 0; i < 50; i = i + 1) begin
            w0_mem[i] = (i % 5) - 2;
            w1_mem[i] = (i % 7) - 3;
            w2_mem[i] = (i % 4) - 1;
            w3_mem[i] = (i % 6) - 2;
            w4_mem[i] = (i % 3) - 1;
            w5_mem[i] = (i % 8) - 4;
        end

        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        for (i = 0; i < 144; i = i + 1) begin
            u_fifo_0.mem[i] = fmap0_mem[i];
            u_fifo_1.mem[i] = fmap1_mem[i];
        end
        u_fifo_0.wr_ptr = 8'd144;
        u_fifo_0.rd_ptr = 8'd0;
        u_fifo_0.dout_r = 8'd0;
        u_fifo_1.wr_ptr = 8'd144;
        u_fifo_1.rd_ptr = 8'd0;
        u_fifo_1.dout_r = 8'd0;

        start = 1'b1;

        for (i = 0; i < 520; i = i + 1) begin
            @(negedge clk);

            if (i == WINDOW_START_DELAY)
                start_window = 1'b1;

            rd_en = start_window;

            if (i < 300) begin
                bank_idx = i / 50;
                case (bank_idx)
                    0: begin weight = w0_mem[i % 50]; weight_en = 6'b000001; end
                    1: begin weight = w1_mem[i % 50]; weight_en = 6'b000010; end
                    2: begin weight = w2_mem[i % 50]; weight_en = 6'b000100; end
                    3: begin weight = w3_mem[i % 50]; weight_en = 6'b001000; end
                    4: begin weight = w4_mem[i % 50]; weight_en = 6'b010000; end
                    5: begin weight = w5_mem[i % 50]; weight_en = 6'b100000; end
                    default: begin weight = 8'sd0; weight_en = 6'b000000; end
                endcase
            end
            else begin
                weight = 8'sd0;
                weight_en = 6'b000000;
            end
        end

        wait ((stream_count == 64) && (direct_count == 64));
        repeat (5) @(posedge clk);

        for (i = 0; i < 64; i = i + 1) begin
            if ((stream0_store[i] !== direct0_store[i]) ||
                (stream1_store[i] !== direct1_store[i]) ||
                (stream2_store[i] !== direct2_store[i]) ||
                (stream3_store[i] !== direct3_store[i]) ||
                (stream4_store[i] !== direct4_store[i]) ||
                (stream5_store[i] !== direct5_store[i])) begin
                err_count = err_count + 1;
                $display("MISMATCH out=%0d", i);
                $display("  stream = %0d %0d %0d %0d %0d %0d",
                    stream0_store[i], stream1_store[i], stream2_store[i],
                    stream3_store[i], stream4_store[i], stream5_store[i]);
                $display("  direct = %0d %0d %0d %0d %0d %0d",
                    direct0_store[i], direct1_store[i], direct2_store[i],
                    direct3_store[i], direct4_store[i], direct5_store[i]);
            end
        end

        if (err_count == 0)
            $display("FIFO-PATH COMPARE PASS");
        else
            $display("FIFO-PATH COMPARE FAIL, err_count=%0d", err_count);

        $finish;
    end

    always @(posedge clk) begin
        if (stream_ovalid[0]) begin
            stream0_store[stream_count] = stream_dout[0];
            stream1_store[stream_count] = stream_dout[1];
            stream2_store[stream_count] = stream_dout[2];
            stream3_store[stream_count] = stream_dout[3];
            stream4_store[stream_count] = stream_dout[4];
            stream5_store[stream_count] = stream_dout[5];
            stream_count = stream_count + 1;
        end

        if (direct_ovalid) begin
            direct0_store[direct_count] = direct_dout_0;
            direct1_store[direct_count] = direct_dout_1;
            direct2_store[direct_count] = direct_dout_2;
            direct3_store[direct_count] = direct_dout_3;
            direct4_store[direct_count] = direct_dout_4;
            direct5_store[direct_count] = direct_dout_5;
            direct_count = direct_count + 1;
        end
    end

    initial begin
        #TIMEOUT_NS;
        $display("TIMEOUT stream_count=%0d direct_count=%0d", stream_count, direct_count);
        $finish;
    end

endmodule
