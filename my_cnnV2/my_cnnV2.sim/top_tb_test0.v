`timescale 1ns / 1ps

module top_tb_test0;

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

    integer fp_img;
    integer fp_cw;
    integer fp_fcw;
    integer rc_img;
    integer rc_cw;
    integer rc_fcw;

    integer img_line_cnt;
    integer cw_line_cnt;
    integer fcw_line_cnt;
    integer result_cnt;
    integer pred_idx;

    reg signed [31:0] best_score;

    reg image_eof;
    reg cw_eof;
    reg fcw_eof;
    reg img_advance;
    reg cw_advance;
    reg fcw_advance;

    localparam integer CLK_PERIOD_NS  = 20;
    localparam integer RESET_HOLD_NS  = 40;
    localparam integer START_DELAY_NS = 40000;
    localparam integer TIMEOUT_NS     = 1000000;

    localparam IMG_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";
    localparam CW_FILE  = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnn/my_cnn_test/cw.txt";
    localparam FCW_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnn/my_cnn_test/fcw.txt";

    task load_next_image;
        begin
            rc_img = $fscanf(fp_img, "%b", image_tdata);
            if (rc_img != 1) begin
                image_eof = 1'b1;
                image_tvalid = 1'b0;
                $display("image read stop at line %0d, rc_img=%0d, time=%0t", img_line_cnt, rc_img, $time);
            end
        end
    endtask

    task load_next_cw;
        begin
            rc_cw = $fscanf(fp_cw, "%d", weight_tdata);
            if (rc_cw != 1) begin
                cw_eof = 1'b1;
                weight_tvalid = 1'b0;
                $display("conv weight read stop at line %0d, rc_cw=%0d, time=%0t", cw_line_cnt, rc_cw, $time);
            end
        end
    endtask

    task load_next_fcw;
        begin
            rc_fcw = $fscanf(fp_fcw, "%d", weightfc_tdata);
            if (rc_fcw != 1) begin
                fcw_eof = 1'b1;
                weightfc_tvalid = 1'b0;
                $display("fc weight read stop at line %0d, rc_fcw=%0d, time=%0t", fcw_line_cnt, rc_fcw, $time);
            end
        end
    endtask

    task finish_tb;
        begin
            if (fp_img != 0) begin
                $fclose(fp_img);
            end
            if (fp_cw != 0) begin
                $fclose(fp_cw);
            end
            if (fp_fcw != 0) begin
                $fclose(fp_fcw);
            end
            $finish;
        end
    endtask

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

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

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

        img_line_cnt = 0;
        cw_line_cnt = 0;
        fcw_line_cnt = 0;
        result_cnt = 0;
        pred_idx = -1;
        best_score = 32'sd0;

        image_eof = 1'b0;
        cw_eof = 1'b0;
        fcw_eof = 1'b0;
        img_advance = 1'b0;
        cw_advance = 1'b0;
        fcw_advance = 1'b0;

        $display("IMG_FILE = %s", IMG_FILE);
        $display("CW_FILE  = %s", CW_FILE);
        $display("FCW_FILE = %s", FCW_FILE);

        fp_img = $fopen(IMG_FILE, "r");
        fp_cw  = $fopen(CW_FILE, "r");
        fp_fcw = $fopen(FCW_FILE, "r");

        if (fp_img == 0) begin
            $display("ERROR: failed to open image file");
            finish_tb();
        end
        if (fp_cw == 0) begin
            $display("ERROR: failed to open conv weight file");
            finish_tb();
        end
        if (fp_fcw == 0) begin
            $display("ERROR: failed to open fc weight file");
            finish_tb();
        end

        load_next_image();
        load_next_cw();
        load_next_fcw();

        #RESET_HOLD_NS;
        resetn = 1'b1;
        image_tvalid = 1'b1;
        weight_tvalid = 1'b1;
        weightfc_tvalid = 1'b1;

        #START_DELAY_NS;
        start_cnn = 1'b1;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            img_line_cnt <= 0;
            img_advance <= 1'b0;
        end else begin
            img_advance <= 1'b0;
            if (image_tvalid && image_tready && !image_eof) begin
                img_line_cnt <= img_line_cnt + 1;
                img_advance <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            cw_line_cnt <= 0;
            cw_advance <= 1'b0;
        end else begin
            cw_advance <= 1'b0;
            if (weight_tvalid && weight_tready && !cw_eof) begin
                cw_line_cnt <= cw_line_cnt + 1;
                cw_advance <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            fcw_line_cnt <= 0;
            fcw_advance <= 1'b0;
        end else begin
            fcw_advance <= 1'b0;
            if (weightfc_tvalid && weightfc_tready && !fcw_eof) begin
                fcw_line_cnt <= fcw_line_cnt + 1;
                fcw_advance <= 1'b1;
            end
        end
    end

    always @(negedge clk) begin
        if (resetn && img_advance && !image_eof) begin
            load_next_image();
        end
        if (resetn && cw_advance && !cw_eof) begin
            load_next_cw();
        end
        if (resetn && fcw_advance && !fcw_eof) begin
            load_next_fcw();
        end
    end

    always @(posedge clk) begin
        if (result_tvalid && result_tready) begin
            $display("result[%0d] = %0d, last=%0d, time=%0t", result_cnt, $signed(result_tdata), result_tlast, $time);

            if (result_cnt == 0 || $signed(result_tdata) > best_score) begin
                best_score <= $signed(result_tdata);
                pred_idx <= result_cnt;
            end

            result_cnt <= result_cnt + 1;

            if (result_tlast) begin
                #1;
                $display("final pred = %0d", pred_idx);
                $display("img_line_cnt=%0d, cw_line_cnt=%0d, fcw_line_cnt=%0d", img_line_cnt, cw_line_cnt, fcw_line_cnt);
                #50;
                finish_tb();
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
        finish_tb();
    end

endmodule
