`timescale 1ns / 1ns

// 第一层卷积加第二级 relu+pool 联调仿真
// 1. 使用真实 0.txt 和 cw.txt 跑第一层 6 路卷积
// 2. 直接把 l1_top 的 6 路输出缓存接到 l2_top
// 3. 对比 6 路 12x12 relu+pool 结果和 PC 计算结果
module l1l2_top_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer LANE_NUM = 6;
    localparam integer LANE_SEL_WIDTH = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer IMG_W = 28;
    localparam integer IMG_H = 28;
    localparam integer K = 5;
    localparam integer STRIDE = 1;
    localparam integer CONV_OUT_WIDTH = 32;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer SRC_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer SRC_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer SRC_LEN = SRC_W * SRC_H;
    localparam integer POOL_K = 2;
    localparam integer POOL_STRIDE = 2;
    localparam integer POOL_OUT_WIDTH = 8;
    localparam integer DST_W = ((SRC_W - POOL_K) / POOL_STRIDE) + 1;
    localparam integer DST_H = ((SRC_H - POOL_K) / POOL_STRIDE) + 1;
    localparam integer DST_LEN = DST_W * DST_H;
    localparam integer IMAGE_LEN = IMG_W * IMG_H;
    localparam integer L0_KERNEL_NUM = 6;
    localparam integer L0_WEIGHT_NUM = 25;
    localparam integer L1_KERNEL_NUM = 12;
    localparam integer L1_WEIGHT_NUM = 150;
    localparam integer TOTAL_GLOBAL_WEIGHT = (L0_KERNEL_NUM * L0_WEIGHT_NUM)
                                           + (L1_KERNEL_NUM * L1_WEIGHT_NUM);
    localparam integer CHECK_LANE = 0;
    localparam integer SHIFT_BITS = 10;
    localparam integer LAYER_ID_WIDTH = 1;
    localparam integer KERNEL_ID_WIDTH = 4;
    localparam integer WEIGHT_IDX_WIDTH = 8;
    localparam integer DST2D_WIDTH = LAYER_ID_WIDTH + KERNEL_ID_WIDTH;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";
    localparam WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt";

    reg clk;
    reg rstn;
    reg frame_start;
    reg [DATA_WIDTH-1:0] image_tdata;
    reg image_tvalid;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg scan_start;
    reg frame_release;
    reg pool_start;
    reg [LANE_NUM-1:0] pool_dst_rd_en;
    reg [LANE_NUM*ADDR2D_WIDTH-1:0] pool_dst_rd_addr2d;
    reg [LANE_NUM-1:0] pool_dst_rd_done;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire cfg_last_err;
    wire image_tready;
    wire scan_ready;
    wire img_frame_valid;
    wire weight_loaded;
    wire scan_busy;
    wire scan_done;
    wire [LANE_NUM-1:0] l1_ofmap_frame_valid;
    wire signed [LANE_NUM*CONV_OUT_WIDTH-1:0] l1_ofmap_rd_data;
    wire [LANE_NUM-1:0] l1_ofmap_rd_valid;

    wire pool_ready;
    wire pool_busy;
    wire pool_done;
    wire [LANE_NUM-1:0] pool_src_rd_en;
    wire [LANE_NUM*ADDR2D_WIDTH-1:0] pool_src_rd_addr2d;
    wire [LANE_NUM-1:0] pool_src_rd_done;
    wire [LANE_NUM-1:0] pool_dst_frame_valid;
    wire signed [LANE_NUM*POOL_OUT_WIDTH-1:0] pool_dst_rd_data;
    wire [LANE_NUM-1:0] pool_dst_rd_valid;

    wire [LANE_NUM-1:0] l1_ofmap_rd_en;
    wire [LANE_NUM*ADDR2D_WIDTH-1:0] l1_ofmap_rd_addr2d;
    wire [LANE_NUM-1:0] l1_ofmap_rd_done;

    reg [7:0] img_mem [0:IMAGE_LEN-1];
    reg signed [WEIGHT_WIDTH-1:0] global_weight_mem [0:TOTAL_GLOBAL_WEIGHT-1];
    reg signed [WEIGHT_WIDTH-1:0] l0_weight_mem [0:(L0_KERNEL_NUM * L0_WEIGHT_NUM)-1];
    reg signed [CONV_OUT_WIDTH-1:0] exp_conv_map [0:(LANE_NUM * SRC_LEN)-1];
    reg signed [POOL_OUT_WIDTH-1:0] exp_pool_map [0:(LANE_NUM * DST_LEN)-1];

    integer fp_img;
    integer fp_weight;
    integer rc;
    integer i;
    integer idx;
    integer lane;
    integer err_cnt;
    integer wait_cycle;
    integer global_idx;
    integer calc_lane;
    integer calc_row;
    integer calc_col;
    integer calc_krow;
    integer calc_kcol;
    integer calc_img_idx;
    integer calc_w_idx;
    integer calc_sum;
    integer pool_row;
    integer pool_col;
    integer pool_idx;
    integer max_val;
    reg signed [POOL_OUT_WIDTH-1:0] rd_value;
    reg cfg_weight_done_seen;
    reg pool_done_seen;

    l1_top #(
        .LANE_NUM(LANE_NUM),
        .LANE_SEL_WIDTH(LANE_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .OUT_WIDTH(CONV_OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .ADDR1D_WIDTH(10),
        .LAYER_ID_WIDTH(LAYER_ID_WIDTH),
        .KERNEL_ID_WIDTH(KERNEL_ID_WIDTH),
        .WEIGHT_IDX_WIDTH(WEIGHT_IDX_WIDTH),
        .L0_KERNEL_NUM(L0_KERNEL_NUM),
        .L0_WEIGHT_NUM(L0_WEIGHT_NUM),
        .L1_KERNEL_NUM(L1_KERNEL_NUM),
        .L1_WEIGHT_NUM(L1_WEIGHT_NUM),
        .DST2D_WIDTH(DST2D_WIDTH)
    ) u_l1_top (
        .clk(clk),
        .rstn(rstn),
        .frame_start(frame_start),
        .image_tdata(image_tdata),
        .image_tvalid(image_tvalid),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .scan_start(scan_start),
        .frame_release(frame_release),
        .ofmap_rd_en(l1_ofmap_rd_en),
        .ofmap_rd_addr2d(l1_ofmap_rd_addr2d),
        .ofmap_rd_done(l1_ofmap_rd_done),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .cfg_last_err(cfg_last_err),
        .image_tready(image_tready),
        .scan_ready(scan_ready),
        .img_frame_valid(img_frame_valid),
        .weight_loaded(weight_loaded),
        .scan_busy(scan_busy),
        .scan_done(scan_done),
        .ofmap_frame_valid(l1_ofmap_frame_valid),
        .ofmap_rd_data(l1_ofmap_rd_data),
        .ofmap_rd_valid(l1_ofmap_rd_valid)
    );

    l2_top #(
        .LANE_NUM(LANE_NUM),
        .IN_WIDTH(CONV_OUT_WIDTH),
        .OUT_WIDTH(POOL_OUT_WIDTH),
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
        .OUT_ADDR_WIDTH(8)
    ) u_l2_top (
        .clk(clk),
        .rstn(rstn),
        .start(pool_start),
        .src_frame_valid(l1_ofmap_frame_valid),
        .src_rd_data(l1_ofmap_rd_data),
        .src_rd_valid(l1_ofmap_rd_valid),
        .dst_rd_en(pool_dst_rd_en),
        .dst_rd_addr2d(pool_dst_rd_addr2d),
        .dst_rd_done(pool_dst_rd_done),
        .ready(pool_ready),
        .busy(pool_busy),
        .done(pool_done),
        .src_rd_en(pool_src_rd_en),
        .src_rd_addr2d(pool_src_rd_addr2d),
        .src_rd_done(pool_src_rd_done),
        .dst_frame_valid(pool_dst_frame_valid),
        .dst_rd_data(pool_dst_rd_data),
        .dst_rd_valid(pool_dst_rd_valid)
    );

    assign l1_ofmap_rd_en = pool_src_rd_en;
    assign l1_ofmap_rd_addr2d = pool_src_rd_addr2d;
    assign l1_ofmap_rd_done = pool_src_rd_done;

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
    begin
        #1;

        if(cfg_weight_done)
        begin
            cfg_weight_done_seen = 1'b1;
        end

        if(pool_done)
        begin
            pool_done_seen = 1'b1;
        end
    end

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        frame_start = 1'b0;
        image_tdata = 8'd0;
        image_tvalid = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 'd0;
        cfg_weight_last = 1'b0;
        scan_start = 1'b0;
        frame_release = 1'b0;
        pool_start = 1'b0;
        pool_dst_rd_en = {LANE_NUM{1'b0}};
        pool_dst_rd_addr2d = {(LANE_NUM * ADDR2D_WIDTH){1'b0}};
        pool_dst_rd_done = {LANE_NUM{1'b0}};
        err_cnt = 0;
        cfg_weight_done_seen = 1'b0;
        pool_done_seen = 1'b0;

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

        for(i = 0; i < TOTAL_GLOBAL_WEIGHT; i = i + 1)
        begin
            rc = $fscanf(fp_weight, "%d", global_weight_mem[i]);
            if(rc != 1)
            begin
                $display("ERROR: weight preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_weight);

        for(i = 0; i < (L0_KERNEL_NUM * L0_WEIGHT_NUM); i = i + 1)
        begin
            l0_weight_mem[i] = global_weight_mem[i];
        end

        for(calc_lane = 0; calc_lane < LANE_NUM; calc_lane = calc_lane + 1)
        begin
            for(calc_row = 0; calc_row < SRC_H; calc_row = calc_row + 1)
            begin
                for(calc_col = 0; calc_col < SRC_W; calc_col = calc_col + 1)
                begin
                    calc_sum = 0;

                    for(calc_krow = 0; calc_krow < K; calc_krow = calc_krow + 1)
                    begin
                        for(calc_kcol = 0; calc_kcol < K; calc_kcol = calc_kcol + 1)
                        begin
                            calc_img_idx = ((calc_row + calc_krow) * IMG_W) + (calc_col + calc_kcol);
                            calc_w_idx = (calc_lane * L0_WEIGHT_NUM) + (calc_krow * K) + calc_kcol;
                            calc_sum = calc_sum
                                     + ($signed({1'b0, img_mem[calc_img_idx]})
                                     * $signed(l0_weight_mem[calc_w_idx]));
                        end
                    end

                    exp_conv_map[(calc_lane * SRC_LEN) + (calc_row * SRC_W) + calc_col] = calc_sum;
                end
            end
        end

        for(calc_lane = 0; calc_lane < LANE_NUM; calc_lane = calc_lane + 1)
        begin
            for(pool_row = 0; pool_row < DST_H; pool_row = pool_row + 1)
            begin
                for(pool_col = 0; pool_col < DST_W; pool_col = pool_col + 1)
                begin
                    max_val = relu_quant_func(exp_conv_map[(calc_lane * SRC_LEN) + ((pool_row * 2) * SRC_W) + (pool_col * 2)]);

                    for(calc_krow = 0; calc_krow < POOL_K; calc_krow = calc_krow + 1)
                    begin
                        for(calc_kcol = 0; calc_kcol < POOL_K; calc_kcol = calc_kcol + 1)
                        begin
                            pool_idx = (calc_lane * SRC_LEN)
                                     + (((pool_row * 2) + calc_krow) * SRC_W)
                                     + ((pool_col * 2) + calc_kcol);
                            if(relu_quant_func(exp_conv_map[pool_idx]) > max_val)
                            begin
                                max_val = relu_quant_func(exp_conv_map[pool_idx]);
                            end
                        end
                    end

                    exp_pool_map[(calc_lane * DST_LEN) + (pool_row * DST_W) + pool_col] = max_val[POOL_OUT_WIDTH-1:0];
                end
            end
        end

        #60;
        rstn = 1'b1;

        send_one_frame;
        load_full_global_weight_stream;
        start_l1_scan_and_wait;
        start_pool_and_wait;
        check_all_pool_feature_maps;
        release_input_frame_and_check;

        if(cfg_last_err)
        begin
            $display("ERROR: cfg_last_err should stay low in good flow");
            err_cnt = err_cnt + 1;
        end

        if(!cfg_weight_done_seen)
        begin
            $display("ERROR: cfg_weight_done pulse was not observed");
            err_cnt = err_cnt + 1;
        end

        if(!pool_done_seen)
        begin
            $display("ERROR: pool_done pulse was not observed");
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d", err_cnt);
        #80;
        $finish;
    end

    task send_one_frame;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(negedge clk);
            frame_start = 1'b0;

            image_tvalid = 1'b1;
            image_tdata = img_mem[0];
            idx = 0;
            wait_cycle = 0;

            while(idx < IMAGE_LEN)
            begin
                @(posedge clk);
                #1;

                if(image_tvalid && image_tready)
                begin
                    idx = idx + 1;
                    wait_cycle = 0;
                end
                else
                begin
                    wait_cycle = wait_cycle + 1;
                    if(wait_cycle > 2000)
                    begin
                        $display("ERROR: image load timeout idx=%0d", idx);
                        err_cnt = err_cnt + 1;
                        disable send_one_frame;
                    end
                end

                @(negedge clk);
                if(idx < IMAGE_LEN)
                begin
                    image_tdata = img_mem[idx];
                end
            end

            @(negedge clk);
            image_tvalid = 1'b0;
            image_tdata = 8'd0;

            repeat(2) @(posedge clk);
            #1;
            if(!img_frame_valid)
            begin
                $display("ERROR: img_frame_valid should go high after write done");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task load_full_global_weight_stream;
        begin
            for(global_idx = 0; global_idx < TOTAL_GLOBAL_WEIGHT; global_idx = global_idx + 1)
            begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_last = (global_idx == TOTAL_GLOBAL_WEIGHT - 1);
                cfg_weight_data = global_weight_mem[global_idx];

                while(!cfg_weight_ready)
                begin
                    @(negedge clk);
                end
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 'd0;
            cfg_weight_last = 1'b0;
        end
    endtask

    task start_l1_scan_and_wait;
        begin
            wait(scan_ready == 1'b1);

            @(negedge clk);
            scan_start = 1'b1;
            @(negedge clk);
            scan_start = 1'b0;

            wait_cycle = 0;
            while(!scan_done)
            begin
                @(posedge clk);
                #1;
                wait_cycle = wait_cycle + 1;

                if(wait_cycle > 800000)
                begin
                    $display("ERROR: scan timeout");
                    err_cnt = err_cnt + 1;
                    disable start_l1_scan_and_wait;
                end
            end

            repeat(2) @(posedge clk);
            #1;
            if(&l1_ofmap_frame_valid !== 1'b1)
            begin
                $display("ERROR: l1 ofmap frame valid should all be high after scan");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task start_pool_and_wait;
        begin
            wait(pool_ready == 1'b1);

            @(negedge clk);
            pool_start = 1'b1;
            @(negedge clk);
            pool_start = 1'b0;

            wait_cycle = 0;
            while(!pool_done)
            begin
                @(posedge clk);
                #1;
                wait_cycle = wait_cycle + 1;

                if(wait_cycle > 800000)
                begin
                    $display("ERROR: pool timeout");
                    err_cnt = err_cnt + 1;
                    disable start_pool_and_wait;
                end
            end

            repeat(2) @(posedge clk);
            #1;
            if(&pool_dst_frame_valid !== 1'b1)
            begin
                $display("ERROR: pool dst frame valid should all be high after done");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task check_all_pool_feature_maps;
        begin
            for(lane = 0; lane < LANE_NUM; lane = lane + 1)
            begin
                read_back_one_pool_lane(lane);
            end
        end
    endtask

    task read_back_one_pool_lane;
        input integer lane_id;
        begin
            for(idx = 0; idx < DST_LEN; idx = idx + 1)
            begin
                drive_pool_read_addr(lane_id, idx / DST_W, idx % DST_W);

                @(posedge clk);
                #1;

                if(!pool_dst_rd_valid[lane_id])
                begin
                    $display("ERROR: pool lane=%0d rd_valid low at idx=%0d", lane_id, idx);
                    err_cnt = err_cnt + 1;
                    disable read_back_one_pool_lane;
                end

                rd_value = pick_pool_lane_rd_data(lane_id);
                if(lane_id == CHECK_LANE)
                begin
                    $display("L1L2_SIM lane=%0d idx=%0d row=%0d col=%0d data=%0d",
                             lane_id,
                             idx,
                             idx / DST_W,
                             idx % DST_W,
                             rd_value);
                end

                if(rd_value !== pick_exp_pool_map(lane_id, idx))
                begin
                    $display("ERROR: pool lane=%0d idx=%0d data=%0d expect=%0d",
                             lane_id,
                             idx,
                             rd_value,
                             pick_exp_pool_map(lane_id, idx));
                    err_cnt = err_cnt + 1;
                    disable read_back_one_pool_lane;
                end
            end

            @(negedge clk);
            pool_dst_rd_en[lane_id] = 1'b0;
            pool_dst_rd_addr2d[((lane_id + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = {ADDR2D_WIDTH{1'b0}};
            pool_dst_rd_done[lane_id] = 1'b1;

            @(negedge clk);
            pool_dst_rd_done[lane_id] = 1'b0;

            repeat(2) @(posedge clk);
            #1;
            if(pool_dst_frame_valid[lane_id])
            begin
                $display("ERROR: pool dst_frame_valid[%0d] should clear after rd_done", lane_id);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task release_input_frame_and_check;
        begin
            @(negedge clk);
            frame_release = 1'b1;
            @(negedge clk);
            frame_release = 1'b0;

            repeat(3) @(posedge clk);
            #1;
            if(img_frame_valid)
            begin
                $display("ERROR: img_frame_valid should clear after frame_release");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task drive_pool_read_addr;
        input integer lane_id;
        input integer row_id;
        input integer col_id;
        reg [ADDR2D_WIDTH-1:0] pack_addr;
        begin
            pack_addr = {row_id[ROW_ADDR_WIDTH-1:0], col_id[COL_ADDR_WIDTH-1:0]};

            @(negedge clk);
            pool_dst_rd_en[lane_id] = 1'b1;
            pool_dst_rd_addr2d[((lane_id + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
        end
    endtask

    function signed [POOL_OUT_WIDTH-1:0] relu_quant_func;
        input signed [CONV_OUT_WIDTH-1:0] conv_val;
        reg signed [CONV_OUT_WIDTH-1:0] clip_val;
        reg signed [CONV_OUT_WIDTH-1:0] shift_val;
        begin
            if(conv_val[CONV_OUT_WIDTH-1])
            begin
                clip_val = {CONV_OUT_WIDTH{1'b0}};
            end
            else
            begin
                clip_val = conv_val;
            end

            shift_val = clip_val >>> SHIFT_BITS;
            relu_quant_func = shift_val[POOL_OUT_WIDTH-1:0];
        end
    endfunction

    function signed [POOL_OUT_WIDTH-1:0] pick_pool_lane_rd_data;
        input integer lane_id;
        begin
            case(lane_id)
                0: pick_pool_lane_rd_data = pool_dst_rd_data[(1 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
                1: pick_pool_lane_rd_data = pool_dst_rd_data[(2 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
                2: pick_pool_lane_rd_data = pool_dst_rd_data[(3 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
                3: pick_pool_lane_rd_data = pool_dst_rd_data[(4 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
                4: pick_pool_lane_rd_data = pool_dst_rd_data[(5 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
                default: pick_pool_lane_rd_data = pool_dst_rd_data[(6 * POOL_OUT_WIDTH) - 1 -: POOL_OUT_WIDTH];
            endcase
        end
    endfunction

    function signed [POOL_OUT_WIDTH-1:0] pick_exp_pool_map;
        input integer lane_id;
        input integer point_idx;
        integer flat_idx;
        begin
            flat_idx = (lane_id * DST_LEN) + point_idx;
            pick_exp_pool_map = exp_pool_map[flat_idx];
        end
    endfunction

endmodule


