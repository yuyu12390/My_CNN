`timescale 1ns / 1ns

// 第二级 relu+pool 单通道仿真
// 1. 使用真实 0.txt 和 cw.txt 计算单路第一层卷积结果
// 2. 通过上一级乒乓缓存把 24x24 的 32bit 特征图送给 relu_pool_l2
// 3. 检查 12x12 的 relu+pool 输出是否正确
module relu_pool_l2_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IMAGE_W = 28;
    localparam integer IMAGE_H = 28;
    localparam integer CONV_K = 5;
    localparam integer SRC_W = ((IMAGE_W - CONV_K) / 1) + 1;
    localparam integer SRC_H = ((IMAGE_H - CONV_K) / 1) + 1;
    localparam integer POOL_K = 2;
    localparam integer POOL_STRIDE = 2;
    localparam integer DST_W = ((SRC_W - POOL_K) / POOL_STRIDE) + 1;
    localparam integer DST_H = ((SRC_H - POOL_K) / POOL_STRIDE) + 1;
    localparam integer IMAGE_LEN = IMAGE_W * IMAGE_H;
    localparam integer SRC_LEN = SRC_W * SRC_H;
    localparam integer DST_LEN = DST_W * DST_H;
    localparam integer WEIGHT_NUM = 25;
    localparam integer TEST_LANE = 1;
    localparam integer SHIFT_BITS = 10;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer SRC_ADDR_WIDTH = 10;
    localparam integer DST_ADDR_WIDTH = 8;
    localparam integer IN_WIDTH = 32;
    localparam integer OUT_WIDTH = 8;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";
    localparam WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt";

    reg clk;
    reg rstn;
    reg start;

    reg src_wr_valid;
    reg signed [IN_WIDTH-1:0] src_wr_data;
    reg [ADDR2D_WIDTH-1:0] src_wr_addr2d;
    reg src_wr_last;

    reg dst_rd_en;
    reg [ADDR2D_WIDTH-1:0] dst_rd_addr2d;
    reg dst_rd_done;

    wire src_wr_ready;
    wire src_wr_done;
    wire signed [IN_WIDTH-1:0] src_buf_rd_data;
    wire src_buf_rd_valid;
    wire src_buf_frame_valid;
    wire rp_ready;
    wire rp_busy;
    wire rp_done;
    wire src_rd_en;
    wire [ADDR2D_WIDTH-1:0] src_rd_addr2d;
    wire src_rd_done;
    wire dst_frame_valid;
    wire signed [OUT_WIDTH-1:0] dst_rd_data;
    wire dst_rd_valid;

    reg [7:0] img_mem [0:IMAGE_LEN-1];
    reg signed [7:0] lane_weight_mem [0:WEIGHT_NUM-1];
    reg signed [IN_WIDTH-1:0] src_feature_map [0:SRC_LEN-1];
    reg signed [OUT_WIDTH-1:0] relu_map [0:SRC_LEN-1];
    reg signed [OUT_WIDTH-1:0] exp_pool_map [0:DST_LEN-1];

    integer fp_img;
    integer fp_weight;
    integer rc;
    integer i;
    integer idx;
    integer row_id;
    integer col_id;
    integer krow;
    integer kcol;
    integer img_idx;
    integer sum_val;
    integer err_cnt;
    integer wait_cycle;
    integer pool_idx;
    integer weight_skip;
    integer max_val;
    integer done_seen;
    integer src_done_seen;
    reg signed [OUT_WIDTH-1:0] rd_value;

    pingpong_img_buf #(
        .DATA_WIDTH(IN_WIDTH),
        .IMG_W(SRC_W),
        .IMG_H(SRC_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .DEPTH(SRC_W * SRC_H),
        .ADDR_WIDTH(SRC_ADDR_WIDTH)
    ) u_src_buf (
        .clk(clk),
        .rstn(rstn),
        .wr_valid(src_wr_valid),
        .wr_data(src_wr_data),
        .wr_addr2d(src_wr_addr2d),
        .wr_last(src_wr_last),
        .rd_en(src_rd_en),
        .rd_addr2d(src_rd_addr2d),
        .rd_done(src_rd_done),
        .wr_ready(src_wr_ready),
        .wr_done(src_wr_done),
        .rd_data(src_buf_rd_data),
        .rd_valid(src_buf_rd_valid),
        .rd_frame_valid(src_buf_frame_valid)
    );

    relu_pool_l2 #(
        .IN_WIDTH(IN_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .IMG_W(SRC_W),
        .IMG_H(SRC_H),
        .K(POOL_K),
        .STRIDE(POOL_STRIDE),
        .SHIFT_BITS(SHIFT_BITS),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .OUT_W(DST_W),
        .OUT_H(DST_H),
        .OUT_ADDR_WIDTH(DST_ADDR_WIDTH)
    ) u_relu_pool_l2 (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_buf_frame_valid),
        .src_rd_data(src_buf_rd_data),
        .src_rd_valid(src_buf_rd_valid),
        .dst_rd_en(dst_rd_en),
        .dst_rd_addr2d(dst_rd_addr2d),
        .dst_rd_done(dst_rd_done),
        .ready(rp_ready),
        .busy(rp_busy),
        .done(rp_done),
        .src_rd_en(src_rd_en),
        .src_rd_addr2d(src_rd_addr2d),
        .src_rd_done(src_rd_done),
        .dst_frame_valid(dst_frame_valid),
        .dst_rd_data(dst_rd_data),
        .dst_rd_valid(dst_rd_valid)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
    begin
        #1;

        if(rp_done)
        begin
            done_seen = 1;
        end

        if(src_rd_done)
        begin
            src_done_seen = 1;
        end

        if(src_buf_rd_valid)
        begin
            $display("SRC_RET data=%0d last=%b core_cnt=%0d",
                     src_buf_rd_data,
                     u_relu_pool_l2.pix_last_reg,
                     u_relu_pool_l2.u_relu_pool_core.sample_cnt);
        end

        if(u_relu_pool_l2.u_relu_pool_core.out_valid)
        begin
            $display("POOL_WR addr=%0h data=%0d wr_ready=%b",
                     u_relu_pool_l2.pool_wr_addr2d,
                     u_relu_pool_l2.u_relu_pool_core.out_data,
                     u_relu_pool_l2.dst_buf_wr_ready);
        end
    end

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        src_wr_valid = 1'b0;
        src_wr_data = {IN_WIDTH{1'b0}};
        src_wr_addr2d = {ADDR2D_WIDTH{1'b0}};
        src_wr_last = 1'b0;
        dst_rd_en = 1'b0;
        dst_rd_addr2d = {ADDR2D_WIDTH{1'b0}};
        dst_rd_done = 1'b0;
        err_cnt = 0;
        done_seen = 0;
        src_done_seen = 0;

        fp_img = $fopen(IMAGE_FILE, "r");
        if(fp_img == 0)
        begin
            $display("ERROR: failed to open %s", IMAGE_FILE);
            $finish;
        end

        fp_weight = $fopen(WEIGHT_FILE, "r");
        if(fp_weight == 0)
        begin
            $display("ERROR: failed to open %s", WEIGHT_FILE);
            $finish;
        end

        for(i = 0; i < IMAGE_LEN; i = i + 1)
        begin
            rc = $fscanf(fp_img, "%b", img_mem[i]);
            if(rc != 1)
            begin
                $display("ERROR: image preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_img);

        weight_skip = TEST_LANE * WEIGHT_NUM;
        for(i = 0; i < weight_skip; i = i + 1)
        begin
            rc = $fscanf(fp_weight, "%d", sum_val);
            if(rc != 1)
            begin
                $display("ERROR: weight skip failed at line %0d", i);
                $finish;
            end
        end

        for(i = 0; i < WEIGHT_NUM; i = i + 1)
        begin
            rc = $fscanf(fp_weight, "%d", lane_weight_mem[i]);
            if(rc != 1)
            begin
                $display("ERROR: lane weight preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_weight);

        for(row_id = 0; row_id < SRC_H; row_id = row_id + 1)
        begin
            for(col_id = 0; col_id < SRC_W; col_id = col_id + 1)
            begin
                sum_val = 0;

                for(krow = 0; krow < CONV_K; krow = krow + 1)
                begin
                    for(kcol = 0; kcol < CONV_K; kcol = kcol + 1)
                    begin
                        img_idx = ((row_id + krow) * IMAGE_W) + (col_id + kcol);
                        sum_val = sum_val
                                + ($signed({1'b0, img_mem[img_idx]})
                                * $signed(lane_weight_mem[(krow * CONV_K) + kcol]));
                    end
                end

                src_feature_map[(row_id * SRC_W) + col_id] = sum_val;
                relu_map[(row_id * SRC_W) + col_id] = relu_quant_func(sum_val);
            end
        end

        for(row_id = 0; row_id < DST_H; row_id = row_id + 1)
        begin
            for(col_id = 0; col_id < DST_W; col_id = col_id + 1)
            begin
                max_val = relu_map[((row_id * 2) * SRC_W) + (col_id * 2)];

                for(krow = 0; krow < POOL_K; krow = krow + 1)
                begin
                    for(kcol = 0; kcol < POOL_K; kcol = kcol + 1)
                    begin
                        pool_idx = (((row_id * 2) + krow) * SRC_W) + ((col_id * 2) + kcol);
                        if(relu_map[pool_idx] > max_val)
                        begin
                            max_val = relu_map[pool_idx];
                        end
                    end
                end

                exp_pool_map[(row_id * DST_W) + col_id] = max_val[OUT_WIDTH-1:0];
            end
        end

        #60;
        rstn = 1'b1;

        $display("SRC_EXP first4 = %0d %0d %0d %0d",
                 src_feature_map[0],
                 src_feature_map[1],
                 src_feature_map[SRC_W],
                 src_feature_map[SRC_W + 1]);
        $display("POOL_EXP first = %0d", exp_pool_map[0]);

        preload_src_feature_map;
        run_relu_pool_once;
        read_back_dst_feature_map;
        release_dst_feature_map;

        if(!done_seen)
        begin
            $display("ERROR: rp_done pulse was not observed");
            err_cnt = err_cnt + 1;
        end

        if(!src_done_seen)
        begin
            $display("ERROR: src_rd_done pulse was not observed");
            err_cnt = err_cnt + 1;
        end

        if(src_buf_frame_valid)
        begin
            $display("ERROR: source frame should be released after processing");
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d done_seen=%0d src_done_seen=%0d",
                 err_cnt, done_seen, src_done_seen);
        #80;
        $finish;
    end

    task preload_src_feature_map;
        reg [ADDR2D_WIDTH-1:0] pack_addr;
        integer pack_row;
        integer pack_col;
        begin
            idx = 0;
            wait_cycle = 0;

            while(idx < SRC_LEN)
            begin
                pack_row = idx / SRC_W;
                pack_col = idx % SRC_W;
                pack_addr = (pack_row << COL_ADDR_WIDTH) | pack_col;

                @(negedge clk);
                src_wr_valid = 1'b1;
                src_wr_data = src_feature_map[idx];
                src_wr_addr2d = pack_addr;
                src_wr_last = (idx == SRC_LEN - 1);

                @(posedge clk);
                #1;

                if(src_wr_valid && src_wr_ready)
                begin
                    idx = idx + 1;
                    wait_cycle = 0;
                end
                else
                begin
                    wait_cycle = wait_cycle + 1;
                    if(wait_cycle > 2000)
                    begin
                        $display("ERROR: source preload timeout idx=%0d", idx);
                        err_cnt = err_cnt + 1;
                        disable preload_src_feature_map;
                    end
                end
            end

            @(negedge clk);
            src_wr_valid = 1'b0;
            src_wr_data = {IN_WIDTH{1'b0}};
            src_wr_addr2d = {ADDR2D_WIDTH{1'b0}};
            src_wr_last = 1'b0;

            repeat(2) @(posedge clk);
            #1;
            if(!src_buf_frame_valid)
            begin
                $display("ERROR: source frame should be valid after preload");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task run_relu_pool_once;
        begin
            wait(rp_ready == 1'b1);

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait_cycle = 0;
            while(!rp_done)
            begin
                @(posedge clk);
                #1;
                wait_cycle = wait_cycle + 1;

                if(wait_cycle > 200000)
                begin
                    $display("ERROR: relu_pool timeout");
                    err_cnt = err_cnt + 1;
                    disable run_relu_pool_once;
                end
            end

            repeat(2) @(posedge clk);
            #1;
            if(!dst_frame_valid)
            begin
                $display("ERROR: destination frame should be valid after relu_pool");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task read_back_dst_feature_map;
        reg [ADDR2D_WIDTH-1:0] pack_addr;
        integer pack_row;
        integer pack_col;
        begin
            for(idx = 0; idx < DST_LEN; idx = idx + 1)
            begin
                pack_row = idx / DST_W;
                pack_col = idx % DST_W;
                pack_addr = (pack_row << COL_ADDR_WIDTH) | pack_col;

                @(negedge clk);
                dst_rd_en = 1'b1;
                dst_rd_addr2d = pack_addr;

                @(posedge clk);
                #1;

                if(!dst_rd_valid)
                begin
                    $display("ERROR: dst_rd_valid low at idx=%0d", idx);
                    err_cnt = err_cnt + 1;
                    disable read_back_dst_feature_map;
                end

                rd_value = dst_rd_data;
                $display("POOL_OUT idx=%0d row=%0d col=%0d data=%0d",
                         idx,
                         idx / DST_W,
                         idx % DST_W,
                         rd_value);

                if(rd_value !== exp_pool_map[idx])
                begin
                    $display("ERROR: pool idx=%0d data=%0d expect=%0d",
                             idx,
                             rd_value,
                             exp_pool_map[idx]);
                    err_cnt = err_cnt + 1;
                    disable read_back_dst_feature_map;
                end
            end

            @(negedge clk);
            dst_rd_en = 1'b0;
            dst_rd_addr2d = {ADDR2D_WIDTH{1'b0}};
        end
    endtask

    task release_dst_feature_map;
        begin
            @(negedge clk);
            dst_rd_done = 1'b1;
            @(negedge clk);
            dst_rd_done = 1'b0;

            repeat(2) @(posedge clk);
            #1;
            if(dst_frame_valid)
            begin
                $display("ERROR: destination frame should clear after dst_rd_done");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    function signed [OUT_WIDTH-1:0] relu_quant_func;
        input signed [IN_WIDTH-1:0] conv_val;
        reg signed [IN_WIDTH-1:0] clip_val;
        reg signed [IN_WIDTH-1:0] shift_val;
        begin
            if(conv_val[IN_WIDTH-1])
            begin
                clip_val = {IN_WIDTH{1'b0}};
            end
            else
            begin
                clip_val = conv_val;
            end

            shift_val = clip_val >>> SHIFT_BITS;
            relu_quant_func = shift_val[OUT_WIDTH-1:0];
        end
    endfunction

endmodule
