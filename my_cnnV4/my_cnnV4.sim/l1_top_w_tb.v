`timescale 1ns / 1ns

module l1_top_w_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer LANE_NUM = 6;
    localparam integer LANE_SEL_WIDTH = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer IMG_W = 28;
    localparam integer IMG_H = 28;
    localparam integer K = 5;
    localparam integer STRIDE = 1;
    localparam integer OUT_WIDTH = 32;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer OUT_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer OUT_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer TOTAL_WIN = OUT_W * OUT_H;
    localparam integer IMAGE_LEN = IMG_W * IMG_H;
    localparam integer WIN_SIZE = K * K;
    localparam integer TARGET_BASE_ROW = 4;
    localparam integer TARGET_BASE_COL = 12;
    localparam integer TARGET_WIN_IDX = (TARGET_BASE_ROW * OUT_W) + TARGET_BASE_COL;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";
    localparam WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/conv_l1_case0_weights.txt";
    localparam RESULT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/conv_l1_case0_result.txt";
    localparam FEATURE_MAP_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/conv_l1_case0_feature_map.txt";

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
    reg out_ready;
    reg [LANE_NUM-1:0] ofmap_rd_en;
    reg [LANE_NUM*ADDR2D_WIDTH-1:0] ofmap_rd_addr2d;
    reg [LANE_NUM-1:0] ofmap_rd_done;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire cfg_last_err;
    wire image_tready;
    wire scan_ready;
    wire img_wr_done;
    wire img_frame_valid;
    wire scan_busy;
    wire scan_done;
    wire out_valid;
    wire signed [OUT_WIDTH-1:0] out_data;
    wire weight_loaded;
    wire conv_busy;
    wire [LANE_NUM-1:0] lane_cfg_weight_ready;
    wire [LANE_NUM-1:0] lane_cfg_weight_done;
    wire [LANE_NUM-1:0] lane_weight_loaded;
    wire [LANE_NUM-1:0] lane_conv_busy;
    wire [LANE_NUM-1:0] lane_out_valid;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] lane_out_data;
    wire [ADDR2D_WIDTH-1:0] dbg_img_wr_addr2d;
    wire [ADDR2D_WIDTH-1:0] dbg_win_addr2d;
    wire dbg_win_addr_last;
    wire [ADDR2D_WIDTH-1:0] dbg_out_wr_addr2d;
    wire dbg_out_wr_last;
    wire [ROW_ADDR_WIDTH-1:0] dbg_win_base_row;
    wire [COL_ADDR_WIDTH-1:0] dbg_win_base_col;
    wire [ROW_ADDR_WIDTH-1:0] dbg_win_krow;
    wire [COL_ADDR_WIDTH-1:0] dbg_win_kcol;
    wire dbg_rd_pending;
    wire dbg_pix_valid;
    wire dbg_conv_in_last;
    wire ofmap_wr_ready;
    wire ofmap_wr_done;
    wire ofmap_frame_valid;
    wire [LANE_NUM-1:0] lane_ofmap_wr_ready;
    wire [LANE_NUM-1:0] lane_ofmap_wr_done;
    wire [LANE_NUM-1:0] lane_ofmap_frame_valid;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] ofmap_rd_data;
    wire [LANE_NUM-1:0] ofmap_rd_valid;
    wire [LANE_SEL_WIDTH-1:0] dbg_cfg_lane_idx;
    wire [7:0] dbg_cfg_weight_idx;
    wire dbg_cfg_load_busy;

    reg [7:0] img_mem [0:IMAGE_LEN-1];
    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:WIN_SIZE-1];
    reg signed [OUT_WIDTH-1:0] exp_feature_map [0:TOTAL_WIN-1];

    integer fp_img;
    integer fp_weight;
    integer fp_result;
    integer fp_feature_map;
    integer rc;
    integer i;
    integer idx;
    integer lane;
    integer err_cnt;
    integer exp_sum;
    integer out_cnt;
    integer wait_cycle;
    reg target_seen;
    reg ofmap_wr_done_seen;
    reg cfg_weight_done_seen;
    reg cfg_last_err_seen;

    l1_top_w #(
        .LANE_NUM(LANE_NUM),
        .LANE_SEL_WIDTH(LANE_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .OUT_WIDTH(OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .ADDR1D_WIDTH(10)
    ) u_l1_top_w (
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
        .out_ready(out_ready),
        .ofmap_rd_en(ofmap_rd_en),
        .ofmap_rd_addr2d(ofmap_rd_addr2d),
        .ofmap_rd_done(ofmap_rd_done),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .cfg_last_err(cfg_last_err),
        .image_tready(image_tready),
        .scan_ready(scan_ready),
        .img_wr_done(img_wr_done),
        .img_frame_valid(img_frame_valid),
        .scan_busy(scan_busy),
        .scan_done(scan_done),
        .out_valid(out_valid),
        .out_data(out_data),
        .weight_loaded(weight_loaded),
        .conv_busy(conv_busy),
        .lane_cfg_weight_ready(lane_cfg_weight_ready),
        .lane_cfg_weight_done(lane_cfg_weight_done),
        .lane_weight_loaded(lane_weight_loaded),
        .lane_conv_busy(lane_conv_busy),
        .lane_out_valid(lane_out_valid),
        .lane_out_data(lane_out_data),
        .dbg_img_wr_addr2d(dbg_img_wr_addr2d),
        .dbg_win_addr2d(dbg_win_addr2d),
        .dbg_win_addr_last(dbg_win_addr_last),
        .dbg_out_wr_addr2d(dbg_out_wr_addr2d),
        .dbg_out_wr_last(dbg_out_wr_last),
        .dbg_win_base_row(dbg_win_base_row),
        .dbg_win_base_col(dbg_win_base_col),
        .dbg_win_krow(dbg_win_krow),
        .dbg_win_kcol(dbg_win_kcol),
        .dbg_rd_pending(dbg_rd_pending),
        .dbg_pix_valid(dbg_pix_valid),
        .dbg_conv_in_last(dbg_conv_in_last),
        .ofmap_wr_ready(ofmap_wr_ready),
        .ofmap_wr_done(ofmap_wr_done),
        .ofmap_frame_valid(ofmap_frame_valid),
        .lane_ofmap_wr_ready(lane_ofmap_wr_ready),
        .lane_ofmap_wr_done(lane_ofmap_wr_done),
        .lane_ofmap_frame_valid(lane_ofmap_frame_valid),
        .ofmap_rd_data(ofmap_rd_data),
        .ofmap_rd_valid(ofmap_rd_valid),
        .dbg_cfg_lane_idx(dbg_cfg_lane_idx),
        .dbg_cfg_weight_idx(dbg_cfg_weight_idx),
        .dbg_cfg_load_busy(dbg_cfg_load_busy)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
    begin
        #1;

        if(ofmap_wr_done)
        begin
            ofmap_wr_done_seen = 1'b1;
        end

        if(cfg_weight_done)
        begin
            cfg_weight_done_seen = 1'b1;
        end

        if(cfg_last_err)
        begin
            cfg_last_err_seen = 1'b1;
        end

        if(out_valid)
        begin
            if(out_data !== exp_feature_map[out_cnt])
            begin
                $display("ERROR: lane0 out idx=%0d data=%0d expect=%0d",
                         out_cnt, out_data, exp_feature_map[out_cnt]);
                err_cnt = err_cnt + 1;
            end

            if(out_cnt == TARGET_WIN_IDX)
            begin
                target_seen = 1'b1;
                if(out_data == exp_sum)
                begin
                    $display("TARGET_OK win=%0d row=%0d col=%0d data=%0d",
                             out_cnt, TARGET_BASE_ROW, TARGET_BASE_COL, out_data);
                end
            end

            out_cnt = out_cnt + 1;
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
        out_ready = 1'b1;
        ofmap_rd_en = {LANE_NUM{1'b0}};
        ofmap_rd_addr2d = {(LANE_NUM * ADDR2D_WIDTH){1'b0}};
        ofmap_rd_done = {LANE_NUM{1'b0}};
        err_cnt = 0;
        exp_sum = 0;
        out_cnt = 0;
        target_seen = 1'b0;
        ofmap_wr_done_seen = 1'b0;
        cfg_weight_done_seen = 1'b0;
        cfg_last_err_seen = 1'b0;

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

        fp_result = $fopen(RESULT_FILE, "r");
        if(fp_result == 0)
        begin
            $display("ERROR: failed to open %s", RESULT_FILE);
            $finish;
        end

        fp_feature_map = $fopen(FEATURE_MAP_FILE, "r");
        if(fp_feature_map == 0)
        begin
            $display("ERROR: failed to open %s", FEATURE_MAP_FILE);
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

        for(i = 0; i < WIN_SIZE; i = i + 1)
        begin
            rc = $fscanf(fp_weight, "%d", weight_mem[i]);
            if(rc != 1)
            begin
                $display("ERROR: weight preload failed at line %0d", i);
                $finish;
            end
        end
        $fclose(fp_weight);

        rc = $fscanf(fp_result, "%d", exp_sum);
        if(rc != 1)
        begin
            $display("ERROR: result preload failed");
            $finish;
        end
        $fclose(fp_result);

        for(i = 0; i < TOTAL_WIN; i = i + 1)
        begin
            rc = $fscanf(fp_feature_map, "%d", exp_feature_map[i]);
            if(rc != 1)
            begin
                $display("ERROR: feature_map preload failed at idx=%0d", i);
                $finish;
            end
        end
        $fclose(fp_feature_map);

        #60;
        rstn = 1'b1;

        send_one_frame;
        load_six_kernels_by_stream;
        start_scan_and_wait;
        check_all_lane_feature_maps;
        release_input_frame_and_check;

        if(cfg_last_err_seen)
        begin
            $display("ERROR: cfg_last_err should stay low in good wrapper flow");
            err_cnt = err_cnt + 1;
        end

        if(!cfg_weight_done_seen)
        begin
            $display("ERROR: cfg_weight_done pulse was not observed");
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d out_cnt=%0d target_seen=%b",
                 err_cnt, out_cnt, target_seen);
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

    task load_six_kernels_by_stream;
        begin
            for(lane = 0; lane < LANE_NUM; lane = lane + 1)
            begin
                for(idx = 0; idx < WIN_SIZE; idx = idx + 1)
                begin
                    @(negedge clk);
                    cfg_weight_valid = 1'b1;
                    cfg_weight_data = weight_mem[idx];
                    cfg_weight_last = (lane == LANE_NUM - 1) && (idx == WIN_SIZE - 1);

                    while(!cfg_weight_ready)
                    begin
                        @(negedge clk);
                    end
                end
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 'd0;
            cfg_weight_last = 1'b0;

            repeat(2) @(posedge clk);
            #1;

            if(!weight_loaded)
            begin
                $display("ERROR: all weight_loaded should go high after stream load");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task start_scan_and_wait;
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
                    $display("ERROR: scan timeout out_cnt=%0d", out_cnt);
                    err_cnt = err_cnt + 1;
                    disable start_scan_and_wait;
                end
            end

            @(posedge clk);
            #1;

            if(out_cnt != TOTAL_WIN)
            begin
                $display("ERROR: out_cnt=%0d expect=%0d", out_cnt, TOTAL_WIN);
                err_cnt = err_cnt + 1;
            end

            if(!target_seen)
            begin
                $display("ERROR: target window result not observed");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task check_all_lane_feature_maps;
        begin
            repeat(2) @(posedge clk);
            #1;

            if(!ofmap_wr_done_seen)
            begin
                $display("ERROR: ofmap_wr_done pulse was not observed");
                err_cnt = err_cnt + 1;
            end

            for(lane = 0; lane < LANE_NUM; lane = lane + 1)
            begin
                if(!lane_ofmap_frame_valid[lane])
                begin
                    $display("ERROR: lane_ofmap_frame_valid[%0d] should be high", lane);
                    err_cnt = err_cnt + 1;
                end

                read_back_one_lane(lane);
            end
        end
    endtask

    task read_back_one_lane;
        input integer lane_id;
        reg signed [OUT_WIDTH-1:0] rd_value;
        begin
            for(idx = 0; idx < TOTAL_WIN; idx = idx + 1)
            begin
                drive_lane_read_addr(lane_id, idx / OUT_W, idx % OUT_W);

                @(posedge clk);
                #1;

                if(!ofmap_rd_valid[lane_id])
                begin
                    $display("ERROR: lane=%0d rd_valid low at idx=%0d", lane_id, idx);
                    err_cnt = err_cnt + 1;
                    disable read_back_one_lane;
                end

                rd_value = pick_lane_rd_data(lane_id);
                if(rd_value !== exp_feature_map[idx])
                begin
                    $display("ERROR: lane=%0d ofmap idx=%0d data=%0d expect=%0d",
                             lane_id, idx, rd_value, exp_feature_map[idx]);
                    err_cnt = err_cnt + 1;
                    disable read_back_one_lane;
                end
            end

            @(negedge clk);
            ofmap_rd_en[lane_id] = 1'b0;
            ofmap_rd_done[lane_id] = 1'b1;
            drive_lane_read_addr(lane_id, 0, 0);

            @(negedge clk);
            ofmap_rd_done[lane_id] = 1'b0;

            repeat(2) @(posedge clk);
            #1;
            if(lane_ofmap_frame_valid[lane_id])
            begin
                $display("ERROR: lane_ofmap_frame_valid[%0d] should clear after rd_done", lane_id);
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

    task drive_lane_read_addr;
        input integer lane_id;
        input integer row_id;
        input integer col_id;
        reg [ADDR2D_WIDTH-1:0] pack_addr;
        begin
            pack_addr = {row_id[ROW_ADDR_WIDTH-1:0], col_id[COL_ADDR_WIDTH-1:0]};

            @(negedge clk);
            case(lane_id)
                0:
                begin
                    ofmap_rd_en[0] = 1'b1;
                    ofmap_rd_addr2d[(1 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
                1:
                begin
                    ofmap_rd_en[1] = 1'b1;
                    ofmap_rd_addr2d[(2 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
                2:
                begin
                    ofmap_rd_en[2] = 1'b1;
                    ofmap_rd_addr2d[(3 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
                3:
                begin
                    ofmap_rd_en[3] = 1'b1;
                    ofmap_rd_addr2d[(4 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
                4:
                begin
                    ofmap_rd_en[4] = 1'b1;
                    ofmap_rd_addr2d[(5 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
                5:
                begin
                    ofmap_rd_en[5] = 1'b1;
                    ofmap_rd_addr2d[(6 * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] = pack_addr;
                end
            endcase
        end
    endtask

    function signed [OUT_WIDTH-1:0] pick_lane_rd_data;
        input integer lane_id;
        begin
            case(lane_id)
                0: pick_lane_rd_data = ofmap_rd_data[(1 * OUT_WIDTH) - 1 -: OUT_WIDTH];
                1: pick_lane_rd_data = ofmap_rd_data[(2 * OUT_WIDTH) - 1 -: OUT_WIDTH];
                2: pick_lane_rd_data = ofmap_rd_data[(3 * OUT_WIDTH) - 1 -: OUT_WIDTH];
                3: pick_lane_rd_data = ofmap_rd_data[(4 * OUT_WIDTH) - 1 -: OUT_WIDTH];
                4: pick_lane_rd_data = ofmap_rd_data[(5 * OUT_WIDTH) - 1 -: OUT_WIDTH];
                default: pick_lane_rd_data = ofmap_rd_data[(6 * OUT_WIDTH) - 1 -: OUT_WIDTH];
            endcase
        end
    endfunction

endmodule
