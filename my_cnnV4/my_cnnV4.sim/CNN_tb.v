`timescale 1ns / 1ns

// CNN总顶层仿�?
// 1. 使用真实28x28图像
// 2. 使用真实cw.txt和fcw.txt
// 3. 跑完整V4五层流程
// 4. 打印10个分类分数和�?终预�?
module CNN_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IMAGE_TOTAL = 784;
    localparam integer CONV_WEIGHT_TOTAL = 1950;
    localparam integer FC_WEIGHT_TOTAL = 1920;
    localparam integer SCORE_NUM = 10;

    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test_number4/1.txt";
    localparam CONV_WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt";
    localparam FC_WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/fcw.txt";
    localparam SCORE_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/cnn_scores.txt";

    reg clk;
    reg resetn;
    reg start_cnn;
    reg image_tvalid;
    reg signed [7:0] image_tdata;
    reg weight_tvalid;
    reg signed [7:0] weight_tdata;
    reg weightfc_tvalid;
    reg signed [7:0] weightfc_tdata;
    reg result_tready;

    wire image_tready;
    wire weight_tready;
    wire weightfc_tready;
    wire cnn_done;
    wire result_tvalid;
    wire signed [31:0] result_tdata;

    reg [7:0] image_mem [0:IMAGE_TOTAL-1];
    reg signed [7:0] conv_weight_mem [0:CONV_WEIGHT_TOTAL-1];
    reg signed [7:0] fc_weight_mem [0:FC_WEIGHT_TOTAL-1];
    reg signed [31:0] rtl_scores [0:SCORE_NUM-1];
    reg signed [31:0] exp_scores [0:SCORE_NUM-1];

    integer fp_img;
    integer fp_conv;
    integer fp_fc;
    integer fp_score;
    integer rc;
    integer idx;
    integer argmax_idx;
    integer err_cnt;
    integer done_score_cnt;
    reg signed [31:0] argmax_val;

    CNN dut (
        .clk(clk),
        .resetn(resetn),
        .start_cnn(start_cnn),
        .image_tvalid(image_tvalid),
        .image_tdata(image_tdata),
        .weight_tvalid(weight_tvalid),
        .weight_tdata(weight_tdata),
        .weightfc_tvalid(weightfc_tvalid),
        .weightfc_tdata(weightfc_tdata),
        .result_tready(result_tready),
        .image_tready(image_tready),
        .weight_tready(weight_tready),
        .weightfc_tready(weightfc_tready),
        .cnn_done(cnn_done),
        .result_tvalid(result_tvalid),
        .result_tdata(result_tdata)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task load_files;
    begin
        fp_img = $fopen(IMAGE_FILE, "r");
        if(fp_img == 0)
        begin
            $display("ERROR: failed to open %s", IMAGE_FILE);
            $finish;
        end

        for(idx = 0; idx < IMAGE_TOTAL; idx = idx + 1)
        begin
            rc = $fscanf(fp_img, "%b", image_mem[idx]);
            if(rc != 1)
            begin
                $display("ERROR: image load failed at idx=%0d", idx);
                $finish;
            end
        end
        $fclose(fp_img);

        fp_conv = $fopen(CONV_WEIGHT_FILE, "r");
        if(fp_conv == 0)
        begin
            $display("ERROR: failed to open %s", CONV_WEIGHT_FILE);
            $finish;
        end

        for(idx = 0; idx < CONV_WEIGHT_TOTAL; idx = idx + 1)
        begin
            rc = $fscanf(fp_conv, "%d", conv_weight_mem[idx]);
            if(rc != 1)
            begin
                $display("ERROR: conv weight load failed at idx=%0d", idx);
                $finish;
            end
        end
        $fclose(fp_conv);

        fp_fc = $fopen(FC_WEIGHT_FILE, "r");
        if(fp_fc == 0)
        begin
            $display("ERROR: failed to open %s", FC_WEIGHT_FILE);
            $finish;
        end

        for(idx = 0; idx < FC_WEIGHT_TOTAL; idx = idx + 1)
        begin
            rc = $fscanf(fp_fc, "%d", fc_weight_mem[idx]);
            if(rc != 1)
            begin
                $display("ERROR: fc weight load failed at idx=%0d", idx);
                $finish;
            end
        end
        $fclose(fp_fc);

        fp_score = $fopen(SCORE_FILE, "r");
        if(fp_score != 0)
        begin
            for(idx = 0; idx < SCORE_NUM; idx = idx + 1)
            begin
                rc = $fscanf(fp_score, "%d", exp_scores[idx]);
                if(rc != 1)
                begin
                    $display("ERROR: score load failed at idx=%0d", idx);
                    $finish;
                end
            end
            $fclose(fp_score);
        end
        else
        begin
            for(idx = 0; idx < SCORE_NUM; idx = idx + 1)
            begin
                exp_scores[idx] = 32'sd0;
            end
        end
    end
    endtask

    task send_conv_weights;
    integer conv_idx;
    begin
        conv_idx = 0;
        @(negedge clk);
        weight_tvalid = 1'b1;
        weight_tdata = conv_weight_mem[0];

        while(conv_idx < CONV_WEIGHT_TOTAL)
        begin
            @(posedge clk);
            if(weight_tvalid && weight_tready)
            begin
                conv_idx = conv_idx + 1;
            end

            @(negedge clk);
            if(conv_idx < CONV_WEIGHT_TOTAL)
            begin
                weight_tdata = conv_weight_mem[conv_idx];
            end
        end

        weight_tvalid = 1'b0;
        weight_tdata = 8'sd0;
    end
    endtask

    task send_fc_weights;
    integer fc_idx;
    begin
        fc_idx = 0;
        @(negedge clk);
        weightfc_tvalid = 1'b1;
        weightfc_tdata = fc_weight_mem[0];

        while(fc_idx < FC_WEIGHT_TOTAL)
        begin
            @(posedge clk);
            if(weightfc_tvalid && weightfc_tready)
            begin
                fc_idx = fc_idx + 1;
            end

            @(negedge clk);
            if(fc_idx < FC_WEIGHT_TOTAL)
            begin
                weightfc_tdata = fc_weight_mem[fc_idx];
            end
        end

        weightfc_tvalid = 1'b0;
        weightfc_tdata = 8'sd0;
    end
    endtask

    task send_image;
    integer img_idx;
    begin
        img_idx = 0;
        @(negedge clk);
        image_tvalid = 1'b1;
        image_tdata = image_mem[0];

        while(img_idx < IMAGE_TOTAL)
        begin
            @(posedge clk);
            if(image_tvalid && image_tready)
            begin
                img_idx = img_idx + 1;
            end

            @(negedge clk);
            if(img_idx < IMAGE_TOTAL)
            begin
                image_tdata = image_mem[img_idx];
            end
        end

        image_tvalid = 1'b0;
        image_tdata = 8'sd0;
    end
    endtask

    initial
    begin
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
        done_score_cnt = 0;
        err_cnt = 0;
        argmax_idx = 0;
        argmax_val = -32'sd2147483647;

        for(idx = 0; idx < SCORE_NUM; idx = idx + 1)
        begin
            rtl_scores[idx] = 32'sd0;
            exp_scores[idx] = 32'sd0;
        end

        load_files();

        repeat(10) @(posedge clk);
        resetn = 1'b1;

        @(negedge clk);
        start_cnn = 1'b1;
        @(negedge clk);
        start_cnn = 1'b0;

        fork
            send_conv_weights();
            send_fc_weights();
            send_image();
        join

        wait(cnn_done == 1'b1);
        repeat(10) @(posedge clk);

        argmax_idx = 0;
        argmax_val = rtl_scores[0];
        for(idx = 1; idx < SCORE_NUM; idx = idx + 1)
        begin
            if(rtl_scores[idx] > argmax_val)
            begin
                argmax_val = rtl_scores[idx];
                argmax_idx = idx;
            end
        end

        for(idx = 0; idx < SCORE_NUM; idx = idx + 1)
        begin
            $display("RTL_SCORE idx=%0d score=%0d", idx, rtl_scores[idx]);
            $display("EXP_SCORE idx=%0d score=%0d", idx, exp_scores[idx]);
            if(rtl_scores[idx] !== exp_scores[idx])
            begin
                err_cnt = err_cnt + 1;
                $display("ERR_SCORE idx=%0d rtl=%0d exp=%0d", idx, rtl_scores[idx], exp_scores[idx]);
            end
        end
        $display("RTL_PREDICT digit=%0d score=%0d", argmax_idx, argmax_val);
        $display("SUMMARY err_cnt=%0d", err_cnt);
        $finish;
    end

    always @(posedge clk)
    begin
        if(result_tvalid && result_tready)
        begin
            rtl_scores[done_score_cnt] <= result_tdata;
            done_score_cnt <= done_score_cnt + 1;
        end
    end

endmodule
