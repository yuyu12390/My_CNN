`timescale 1ns / 1ps

module top_tb_buffered_v2;

    localparam integer IMG_LEN = 784;
    localparam integer CW_LEN  = 1950;
    localparam integer FCW_LEN = 1920;

    localparam integer CLK_PERIOD_NS  = 20;
    localparam integer RESET_HOLD_NS  = 40;
    localparam integer START_DELAY_NS = 40000;
    localparam integer TIMEOUT_NS     = 300000;

    localparam IMG_FILE = "C:/Users/28010/Desktop/my_cnn/test_number4/4b.txt";
    localparam CW_FILE  = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt";
    localparam FCW_FILE = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/fcw.txt";

    reg clk;
    reg resetn;
    reg start_cnn;

    reg image_tvalid;
    reg signed [7:0] image_tdata;
    wire image_tready;

    reg weight_tvalid;
    reg signed [7:0] weight_tdata;
    wire weight_tready;

    reg weightfc_tvalid;
    reg signed [7:0] weightfc_tdata;
    wire weightfc_tready;

    reg result_tready;
    wire result_tvalid;
    wire result_tlast;
    wire signed [31:0] result_tdata;

    wire cnn_done;
    wire [3:0] conv_cnt;

    reg [7:0] image_mem [0:IMG_LEN-1];
    reg signed [7:0] cw_mem_raw [0:CW_LEN-1];
    reg signed [7:0] cw_mem [0:CW_LEN-1];
    reg signed [7:0] fcw_mem [0:FCW_LEN-1];

    integer fp_img;
    integer fp_cw;
    integer fp_fcw;
    integer rc;
    integer i;

    integer img_idx;
    integer cw_idx;
    integer fcw_idx;
    integer result_idx;
    integer pred_idx;
    integer img_sent_count;
    integer cw_sent_count;
    integer fcw_sent_count;
    integer pair_idx;
    integer out_grp_idx;
    integer out_mod_idx;
    integer k_idx;
    integer old_base;
    integer new_base;

    reg signed [31:0] best_score;

    CNN dut (
        .clk(clk),
        .resetn(resetn),
        .start_cnn(start_cnn),
        .image_tvalid(image_tvalid),
        .image_tready(image_tready),
        .image_tdata(image_tdata),
        .weight_tvalid(weight_tvalid),
        .weight_tready(weight_tready),
        .weight_tdata(weight_tdata),
        .weightfc_tvalid(weightfc_tvalid),
        .weightfc_tready(weightfc_tready),
        .weightfc_tdata(weightfc_tdata),
        .cnn_done(cnn_done),
        .result_tready(result_tready),
        .result_tvalid(result_tvalid),
        .result_tlast(result_tlast),
        .result_tdata(result_tdata),
        .conv_cnt(conv_cnt)
    );

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        start_cnn = 1'b0;
        image_tvalid = 1'b0;
        image_tdata = 8'sd0;
        weight_tvalid = 1'b0;
        weight_tdata = 8'sd0;
        weightfc_tvalid = 1'b0;
        weightfc_tdata = 8'sd0;
        result_tready = 1'b1;

        img_idx = 0;
        cw_idx = 0;
        fcw_idx = 0;
        result_idx = 0;
        pred_idx = -1;
        img_sent_count = 0;
        cw_sent_count = 0;
        fcw_sent_count = 0;
        best_score = 32'sd0;

        $display("IMG_FILE = %s", IMG_FILE);
        $display("CW_FILE  = %s", CW_FILE);
        $display("FCW_FILE = %s", FCW_FILE);

        fp_img = $fopen(IMG_FILE, "r");
        fp_cw  = $fopen(CW_FILE, "r");
        fp_fcw = $fopen(FCW_FILE, "r");

        if (fp_img == 0 || fp_cw == 0 || fp_fcw == 0) begin
            $display("ERROR: failed to open one or more input files");
            $finish;
        end

        for (i = 0; i < IMG_LEN; i = i + 1) begin
            rc = $fscanf(fp_img, "%b", image_mem[i]);
            if (rc != 1) begin
                $display("ERROR: image preload failed at line %0d", i);
                $finish;
            end
        end

        for (i = 0; i < CW_LEN; i = i + 1) begin
            rc = $fscanf(fp_cw, "%d", cw_mem_raw[i]);
            if (rc != 1) begin
                $display("ERROR: conv weight preload failed at line %0d", i);
                $finish;
            end
        end

        for (i = 0; i < FCW_LEN; i = i + 1) begin
            rc = $fscanf(fp_fcw, "%d", fcw_mem[i]);
            if (rc != 1) begin
                $display("ERROR: fc weight preload failed at line %0d", i);
                $finish;
            end
        end

        $fclose(fp_img);
        $fclose(fp_cw);
        $fclose(fp_fcw);

        // Reorder conv2 weights for Pin=2:
        // old order:  in0-g0, in0-g1, in1-g0, in1-g1, ...
        // new order: (in0,in1)-g0, (in0,in1)-g1, (in2,in3)-g0, ...
        for (i = 0; i < 150; i = i + 1) begin
            cw_mem[i] = cw_mem_raw[i];
        end

        for (pair_idx = 0; pair_idx < 3; pair_idx = pair_idx + 1) begin
            for (out_grp_idx = 0; out_grp_idx < 2; out_grp_idx = out_grp_idx + 1) begin
                for (out_mod_idx = 0; out_mod_idx < 6; out_mod_idx = out_mod_idx + 1) begin
                    old_base = 150 + (((pair_idx * 2) * 2 + out_grp_idx) * 150) + out_mod_idx * 25;
                    new_base = 150 + ((pair_idx * 2 + out_grp_idx) * 300) + out_mod_idx * 50;
                    for (k_idx = 0; k_idx < 25; k_idx = k_idx + 1) begin
                        cw_mem[new_base + k_idx] = cw_mem_raw[old_base + k_idx];
                        cw_mem[new_base + 25 + k_idx] = cw_mem_raw[old_base + 300 + k_idx];
                    end
                end
            end
        end

        image_tdata = image_mem[0];
        weight_tdata = cw_mem[0];
        weightfc_tdata = fcw_mem[0];

        #RESET_HOLD_NS;
        resetn = 1'b1;
        image_tvalid = 1'b1;
        weight_tvalid = 1'b1;
        weightfc_tvalid = 1'b1;

        #START_DELAY_NS;
        start_cnn = 1'b1;
        $display("start_cnn asserted at time=%0t", $time);
    end

    always @(posedge clk) begin
        if (!resetn) begin
            img_idx <= 0;
        end else if (image_tvalid && image_tready) begin
            img_sent_count <= img_sent_count + 1;
            if (img_idx == IMG_LEN - 1) begin
                image_tvalid <= 1'b0;
            end else begin
                img_idx <= img_idx + 1;
                image_tdata <= image_mem[img_idx + 1];
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            cw_idx <= 0;
        end else if (weight_tvalid && weight_tready) begin
            cw_sent_count <= cw_sent_count + 1;
            if (cw_idx == CW_LEN - 1) begin
                weight_tvalid <= 1'b0;
            end else begin
                cw_idx <= cw_idx + 1;
                weight_tdata <= cw_mem[cw_idx + 1];
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            fcw_idx <= 0;
        end else if (weightfc_tvalid && weightfc_tready) begin
            fcw_sent_count <= fcw_sent_count + 1;
            if (fcw_idx == FCW_LEN - 1) begin
                weightfc_tvalid <= 1'b0;
            end else begin
                fcw_idx <= fcw_idx + 1;
                weightfc_tdata <= fcw_mem[fcw_idx + 1];
            end
        end
    end

    always @(posedge clk) begin
        if (result_tvalid && result_tready) begin
            $display("result[%0d] = %0d, last=%0d, time=%0t", result_idx, $signed(result_tdata), result_tlast, $time);
            if (result_idx == 0 || $signed(result_tdata) > best_score) begin
                best_score <= $signed(result_tdata);
                pred_idx <= result_idx;
            end
            result_idx <= result_idx + 1;
            if (result_tlast || result_idx == 9) begin
                if ($signed(result_tdata) > best_score)
                    $display("final pred = %0d", result_idx);
                else
                    $display("final pred = %0d", pred_idx);
                $display("img_sent=%0d, cw_sent=%0d, fcw_sent=%0d", img_sent_count, cw_sent_count, fcw_sent_count);
                #100;
                $finish;
            end
        end
    end

    always @(posedge clk) begin
        if (cnn_done) begin
            $display("cnn_done asserted, conv_cnt=%0d, time=%0t", conv_cnt, $time);
        end
    end

    initial begin
        #TIMEOUT_NS;
        $display("TIMEOUT at %0t", $time);
        $finish;
    end

endmodule
