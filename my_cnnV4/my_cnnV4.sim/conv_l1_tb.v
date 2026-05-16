`timescale 1ns / 1ns

module conv_l1_tb;

    localparam integer CLK_PERIOD   = 20;
    localparam integer DATA_WIDTH   = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer K            = 5;
    localparam integer OUT_WIDTH    = 32;
    localparam integer WIN_SIZE     = K * K;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";
    localparam WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/conv_l1_case0_weights.txt";
    localparam RESULT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/conv_l1_case0_result.txt";

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg in_valid;
    reg [DATA_WIDTH-1:0] in_data;
    reg in_last;
    reg out_ready;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire in_ready;
    wire out_valid;
    wire signed [OUT_WIDTH-1:0] out_data;
    wire busy;
    wire weight_loaded;

    reg [7:0] img_mem [0:783];
    reg [7:0] window_pix [0:WIN_SIZE-1];
    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:WIN_SIZE-1];

    integer fp_img;
    integer fp_weight;
    integer fp_result;
    integer rc;
    integer i;
    integer idx;
    integer err_cnt;
    integer exp_sum;
    integer hold_cycle;

    conv_l1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .K(K),
        .OUT_WIDTH(OUT_WIDTH)
    ) u_conv_l1 (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .busy(busy),
        .weight_loaded(weight_loaded)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    initial begin
        clk              = 1'b0;
        rstn             = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data  = 'd0;
        cfg_weight_last  = 1'b0;
        in_valid         = 1'b0;
        in_data          = 'd0;
        in_last          = 1'b0;
        out_ready        = 1'b0;
        err_cnt          = 0;
        exp_sum          = 0;

        fp_img = $fopen(IMAGE_FILE, "r");
        if(fp_img == 0) begin
            $display("ERROR: failed to open %s", IMAGE_FILE);
            $finish;
        end

        fp_weight = $fopen(WEIGHT_FILE, "r");
        if(fp_weight == 0) begin
            $display("ERROR: failed to open %s", WEIGHT_FILE);
            $finish;
        end

        fp_result = $fopen(RESULT_FILE, "r");
        if(fp_result == 0) begin
            $display("ERROR: failed to open %s", RESULT_FILE);
            $finish;
        end

        for(i = 0; i < 784; i = i + 1) begin
            rc = $fscanf(fp_img, "%b", img_mem[i]);
            if(rc != 1) begin
                $display("ERROR: image preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_img);

        // 选取图像中的一个非零 5x5 窗口用于卷积验证
        window_pix[0]  = img_mem[(4*28)+12];
        window_pix[1]  = img_mem[(4*28)+13];
        window_pix[2]  = img_mem[(4*28)+14];
        window_pix[3]  = img_mem[(4*28)+15];
        window_pix[4]  = img_mem[(4*28)+16];
        window_pix[5]  = img_mem[(5*28)+12];
        window_pix[6]  = img_mem[(5*28)+13];
        window_pix[7]  = img_mem[(5*28)+14];
        window_pix[8]  = img_mem[(5*28)+15];
        window_pix[9]  = img_mem[(5*28)+16];
        window_pix[10] = img_mem[(6*28)+12];
        window_pix[11] = img_mem[(6*28)+13];
        window_pix[12] = img_mem[(6*28)+14];
        window_pix[13] = img_mem[(6*28)+15];
        window_pix[14] = img_mem[(6*28)+16];
        window_pix[15] = img_mem[(7*28)+12];
        window_pix[16] = img_mem[(7*28)+13];
        window_pix[17] = img_mem[(7*28)+14];
        window_pix[18] = img_mem[(7*28)+15];
        window_pix[19] = img_mem[(7*28)+16];
        window_pix[20] = img_mem[(8*28)+12];
        window_pix[21] = img_mem[(8*28)+13];
        window_pix[22] = img_mem[(8*28)+14];
        window_pix[23] = img_mem[(8*28)+15];
        window_pix[24] = img_mem[(8*28)+16];

        // 从 PC 黄金文件读权重和期望卷积结果
        for(i = 0; i < WIN_SIZE; i = i + 1) begin
            rc = $fscanf(fp_weight, "%d", weight_mem[i]);
            if(rc != 1) begin
                $display("ERROR: weight preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_weight);

        rc = $fscanf(fp_result, "%d", exp_sum);
        if(rc != 1) begin
            $display("ERROR: result preload failed");
            $finish;
        end
        $fclose(fp_result);

        #60;
        rstn = 1'b1;

        check_before_weight_loaded;
        load_weight_group;
        feed_one_window;
        hold_output_and_release;

        $display("SUMMARY: err_cnt=%0d expected_sum=%0d out_data=%0d",
                 err_cnt, exp_sum, out_data);
        #80;
        $finish;
    end

    task check_before_weight_loaded;
        begin
            @(posedge clk);
            #1;
            if(in_ready !== 1'b0) begin
                $display("ERROR: in_ready should stay low before weight load");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task load_weight_group;
        begin
            for(idx = 0; idx < WIN_SIZE; idx = idx + 1) begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data  = weight_mem[idx];
                cfg_weight_last  = (idx == WIN_SIZE - 1);
                #1;

                if(!cfg_weight_ready) begin
                    $display("ERROR: cfg_weight_ready low before handshake idx=%0d", idx);
                    err_cnt = err_cnt + 1;
                end

                @(posedge clk);
                #1;
                if(idx < 5) begin
                    $display("LOAD_W idx=%0d weight=%0d last=%b",
                             idx, cfg_weight_data, cfg_weight_last);
                end

                if(idx == WIN_SIZE - 1) begin
                    if(!cfg_weight_done) begin
                        $display("ERROR: cfg_weight_done not asserted on last weight beat");
                        err_cnt = err_cnt + 1;
                    end
                    if(!weight_loaded) begin
                        $display("ERROR: weight_loaded should go high on last weight beat");
                        err_cnt = err_cnt + 1;
                    end
                end
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data  = 'd0;
            cfg_weight_last  = 1'b0;
        end
    endtask

    task feed_one_window;
        begin
            out_ready = 1'b0;

            for(idx = 0; idx < WIN_SIZE; idx = idx + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_data  = window_pix[idx];
                in_last  = (idx == WIN_SIZE - 1);
                #1;

                if(!in_ready) begin
                    $display("ERROR: in_ready low before handshake pixel idx=%0d", idx);
                    err_cnt = err_cnt + 1;
                end

                @(posedge clk);
                #1;
                if(idx < 5) begin
                    $display("FEED_P idx=%0d pixel=%0d last=%b busy=%b",
                             idx, in_data, in_last, busy);
                end
            end

            @(negedge clk);
            in_valid = 1'b0;
            in_data  = 'd0;
            in_last  = 1'b0;
        end
    endtask

    task hold_output_and_release;
        reg signed [OUT_WIDTH-1:0] held_data;
        begin
            hold_cycle = 0;
            while(!out_valid && hold_cycle < 50) begin
                @(posedge clk);
                hold_cycle = hold_cycle + 1;
            end

            if(!out_valid) begin
                $display("ERROR: out_valid timeout");
                err_cnt = err_cnt + 1;
                disable hold_output_and_release;
            end

            #1;
            held_data = out_data;
            if(out_data !== exp_sum) begin
                $display("ERROR: out_data=%0d expect=%0d", out_data, exp_sum);
                err_cnt = err_cnt + 1;
            end

            if(in_ready !== 1'b0) begin
                $display("ERROR: in_ready should be low while out_valid holds result");
                err_cnt = err_cnt + 1;
            end

            $display("OUT_HOLD data=%0d busy=%b out_valid=%b", out_data, busy, out_valid);

            repeat(3) begin
                @(posedge clk);
                #1;
                if(out_data !== held_data) begin
                    $display("ERROR: out_data changed while out_ready=0");
                    err_cnt = err_cnt + 1;
                end
                if(out_valid !== 1'b1) begin
                    $display("ERROR: out_valid dropped before out_ready");
                    err_cnt = err_cnt + 1;
                end
            end

            @(negedge clk);
            out_ready = 1'b1;
            @(posedge clk);
            #1;
            @(posedge clk);
            #1;

            if(out_valid !== 1'b0) begin
                $display("ERROR: out_valid should clear after handshake");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

endmodule

