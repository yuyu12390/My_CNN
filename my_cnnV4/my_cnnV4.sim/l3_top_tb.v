`timescale 1ns / 1ns

// 第三层对外顶层仿真
// 1. 用 6 个输入乒乓缓存模拟上一级 12x12 输出特征图
// 2. 先送完整全局权重流, 其中前 150 个为第一层占位权重
// 3. 启动一次完整第三层 8x8 扫描
// 4. 读回 12 路输出并与 TB 软件结果逐点比较
module l3_top_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer SRC_NUM = 6;
    localparam integer OUT_NUM = 12;
    localparam integer SRC_SEL_WIDTH = 3;
    localparam integer OUT_SEL_WIDTH = 4;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer IMG_W = 12;
    localparam integer IMG_H = 12;
    localparam integer K = 5;
    localparam integer STRIDE = 1;
    localparam integer OUT_WIDTH = 32;
    localparam integer OFMAP_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer OFMAP_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer SRC_DEPTH = IMG_W * IMG_H;
    localparam integer DST_DEPTH = OFMAP_W * OFMAP_H;
    localparam integer ADDR1D_WIDTH = 8;
    localparam integer LAYER_ID_WIDTH = 1;
    localparam integer KERNEL_ID_WIDTH = 4;
    localparam integer WEIGHT_IDX_WIDTH = 8;
    localparam integer L0_KERNEL_NUM = 6;
    localparam integer L0_WEIGHT_NUM = 25;
    localparam integer L1_KERNEL_NUM = 12;
    localparam integer L1_WEIGHT_NUM = 150;
    localparam integer TOTAL_GLOBAL_WEIGHT = (L0_KERNEL_NUM * L0_WEIGHT_NUM)
                                           + (L1_KERNEL_NUM * L1_WEIGHT_NUM);
    localparam integer DST2D_WIDTH = LAYER_ID_WIDTH + KERNEL_ID_WIDTH;
    localparam GOLDEN_WEIGHT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/l3_top12_global_weights.txt";
    localparam GOLDEN_RESULT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/l3_top12_feature_map_all.txt";

    reg clk;
    reg rstn;
    reg start;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg [OUT_NUM-1:0] dst_rd_en;
    reg [OUT_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d;
    reg [OUT_NUM-1:0] dst_rd_done;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire cfg_last_err;
    wire ready;
    wire busy;
    wire done;
    wire weight_loaded;
    wire [SRC_NUM-1:0] src_rd_en;
    wire [SRC_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d;
    wire [SRC_NUM-1:0] src_rd_done;
    wire [OUT_NUM-1:0] dst_frame_valid;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] dst_rd_data;
    wire [OUT_NUM-1:0] dst_rd_valid;

    reg [SRC_NUM-1:0] src_wr_valid;
    reg signed [SRC_NUM*DATA_WIDTH-1:0] src_wr_data;
    reg [SRC_NUM*ADDR2D_WIDTH-1:0] src_wr_addr2d;
    reg [SRC_NUM-1:0] src_wr_last;
    reg [SRC_NUM-1:0] src_buf_rd_done_tb;

    wire [SRC_NUM-1:0] src_wr_ready;
    wire [SRC_NUM-1:0] src_wr_done;
    wire signed [SRC_NUM*DATA_WIDTH-1:0] src_rd_data;
    wire [SRC_NUM-1:0] src_rd_valid;
    wire [SRC_NUM-1:0] src_frame_valid;

    reg [DATA_WIDTH-1:0] src_map [0:SRC_NUM-1][0:IMG_H-1][0:IMG_W-1];
    reg signed [WEIGHT_WIDTH-1:0] weight_map [0:OUT_NUM-1][0:SRC_NUM-1][0:(K*K)-1];
    reg signed [WEIGHT_WIDTH-1:0] global_weight_mem [0:TOTAL_GLOBAL_WEIGHT-1];
    reg signed [OUT_WIDTH-1:0] exp_map [0:OUT_NUM-1][0:OFMAP_H-1][0:OFMAP_W-1];

    integer fp_weight;
    integer fp_result;
    integer rc;
    integer src_idx;
    integer out_idx;
    integer row_idx;
    integer col_idx;
    integer krow_idx;
    integer kcol_idx;
    integer tap_idx;
    integer global_idx;
    integer err_cnt;
    integer rd_cnt;
    integer prev_row_idx;
    integer prev_col_idx;
    integer exp_val;
    reg [255:0] header_str;
    reg signed [OUT_WIDTH-1:0] rtl_console_val [0:OUT_NUM-1];

    reg done_seen;
    reg cfg_weight_done_seen;
    reg cfg_last_err_seen;

    l3_top #(
        .SRC_NUM(SRC_NUM),
        .OUT_NUM(OUT_NUM),
        .SRC_SEL_WIDTH(SRC_SEL_WIDTH),
        .OUT_SEL_WIDTH(OUT_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .OUT_WIDTH(OUT_WIDTH),
        .OFMAP_W(OFMAP_W),
        .OFMAP_H(OFMAP_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .ADDR1D_WIDTH(ADDR1D_WIDTH),
        .LAYER_ID_WIDTH(LAYER_ID_WIDTH),
        .KERNEL_ID_WIDTH(KERNEL_ID_WIDTH),
        .WEIGHT_IDX_WIDTH(WEIGHT_IDX_WIDTH),
        .L0_KERNEL_NUM(L0_KERNEL_NUM),
        .L0_WEIGHT_NUM(L0_WEIGHT_NUM),
        .L1_KERNEL_NUM(L1_KERNEL_NUM),
        .L1_WEIGHT_NUM(L1_WEIGHT_NUM),
        .DST2D_WIDTH(DST2D_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_frame_valid),
        .src_rd_data(src_rd_data),
        .src_rd_valid(src_rd_valid),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .dst_rd_en(dst_rd_en),
        .dst_rd_addr2d(dst_rd_addr2d),
        .dst_rd_done(dst_rd_done),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .cfg_last_err(cfg_last_err),
        .ready(ready),
        .busy(busy),
        .done(done),
        .weight_loaded(weight_loaded),
        .src_rd_en(src_rd_en),
        .src_rd_addr2d(src_rd_addr2d),
        .src_rd_done(src_rd_done),
        .dst_frame_valid(dst_frame_valid),
        .dst_rd_data(dst_rd_data),
        .dst_rd_valid(dst_rd_valid)
    );

    genvar gi;
    generate
        for(gi = 0; gi < SRC_NUM; gi = gi + 1)
        begin: g_src_buf
            wire [ADDR2D_WIDTH-1:0] src_wr_addr2d_i;
            wire [ADDR2D_WIDTH-1:0] src_rd_addr2d_i;
            wire signed [DATA_WIDTH-1:0] src_rd_data_i;

            assign src_wr_addr2d_i = src_wr_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_addr2d_i = src_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_data[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = src_rd_data_i;

            pingpong_img_buf #(
                .DATA_WIDTH(DATA_WIDTH),
                .IMG_W(IMG_W),
                .IMG_H(IMG_H),
                .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
                .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
                .ADDR2D_WIDTH(ADDR2D_WIDTH),
                .DEPTH(SRC_DEPTH),
                .ADDR_WIDTH(ADDR1D_WIDTH)
            ) u_src_buf (
                .clk(clk),
                .rstn(rstn),
                .wr_valid(src_wr_valid[gi]),
                .wr_data(src_wr_data[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]),
                .wr_addr2d(src_wr_addr2d_i),
                .wr_last(src_wr_last[gi]),
                .rd_en(src_rd_en[gi]),
                .rd_addr2d(src_rd_addr2d_i),
                .rd_done(src_rd_done[gi] || src_buf_rd_done_tb[gi]),
                .wr_ready(src_wr_ready[gi]),
                .wr_done(src_wr_done[gi]),
                .rd_data(src_rd_data_i),
                .rd_valid(src_rd_valid[gi]),
                .rd_frame_valid(src_frame_valid[gi])
            );
        end
    endgenerate

    always #(CLK_PERIOD / 2) clk = ~clk;

    task init_case_data;
    begin
        for(src_idx = 0; src_idx < SRC_NUM; src_idx = src_idx + 1)
        begin
            for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
                begin
                    src_map[src_idx][row_idx][col_idx] = (src_idx * 20) + (row_idx * IMG_W) + col_idx + 1;
                end
            end
        end

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(src_idx = 0; src_idx < SRC_NUM; src_idx = src_idx + 1)
            begin
                for(tap_idx = 0; tap_idx < (K * K); tap_idx = tap_idx + 1)
                begin
                    weight_map[out_idx][src_idx][tap_idx] = $signed(out_idx + src_idx + tap_idx + 1);
                end
            end
        end
    end
    endtask

    task load_golden_files;
    begin
        fp_weight = $fopen(GOLDEN_WEIGHT_FILE, "r");
        if(fp_weight == 0)
        begin
            $display("ERROR: failed to open %s", GOLDEN_WEIGHT_FILE);
            $finish;
        end

        for(global_idx = 0; global_idx < TOTAL_GLOBAL_WEIGHT; global_idx = global_idx + 1)
        begin
            rc = $fscanf(fp_weight, "%d", global_weight_mem[global_idx]);
            if(rc != 1)
            begin
                $display("ERROR: weight preload failed at line %0d", global_idx);
                $finish;
            end
        end
        $fclose(fp_weight);

        fp_result = $fopen(GOLDEN_RESULT_FILE, "r");
        if(fp_result == 0)
        begin
            $display("ERROR: failed to open %s", GOLDEN_RESULT_FILE);
            $finish;
        end

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            rc = $fscanf(fp_result, "%s", header_str);
            if(rc != 1)
            begin
                $display("ERROR: result header token missing at out=%0d", out_idx);
                $finish;
            end

            rc = $fscanf(fp_result, "%d", exp_val);
            if(rc != 1)
            begin
                $display("ERROR: result header index missing at out=%0d", out_idx);
                $finish;
            end

            if(exp_val != out_idx)
            begin
                $display("ERROR: result header mismatch got=%0d exp=%0d", exp_val, out_idx);
                $finish;
            end

            for(row_idx = 0; row_idx < OFMAP_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < OFMAP_W; col_idx = col_idx + 1)
                begin
                    rc = $fscanf(fp_result, "%d", exp_val);
                    if(rc != 1)
                    begin
                        $display("ERROR: result data missing out=%0d row=%0d col=%0d",
                                 out_idx, row_idx, col_idx);
                        $finish;
                    end
                    exp_map[out_idx][row_idx][col_idx] = exp_val;
                end
            end
        end

        $fclose(fp_result);
    end
    endtask

    task write_src_frames;
        reg [ADDR2D_WIDTH-1:0] addr2d_pack;
    begin
        for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
        begin
            for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
            begin
                @(posedge clk);
                for(src_idx = 0; src_idx < SRC_NUM; src_idx = src_idx + 1)
                begin
                    src_wr_valid[src_idx] <= 1'b1;
                    src_wr_data[((src_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] <= src_map[src_idx][row_idx][col_idx];
                    addr2d_pack = {row_idx[ROW_ADDR_WIDTH-1:0], col_idx[COL_ADDR_WIDTH-1:0]};
                    src_wr_addr2d[((src_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    src_wr_last[src_idx] <= (row_idx == (IMG_H - 1)) && (col_idx == (IMG_W - 1));
                end
            end
        end

        @(posedge clk);
        src_wr_valid <= {SRC_NUM{1'b0}};
        src_wr_data <= {SRC_NUM*DATA_WIDTH{1'b0}};
        src_wr_addr2d <= {SRC_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last <= {SRC_NUM{1'b0}};
    end
    endtask

    task send_global_weights;
    begin
        for(global_idx = 0; global_idx < TOTAL_GLOBAL_WEIGHT; global_idx = global_idx + 1)
        begin
            @(posedge clk);
            while(!cfg_weight_ready)
            begin
                @(posedge clk);
            end

            cfg_weight_valid <= 1'b1;
            cfg_weight_data <= global_weight_mem[global_idx];
            cfg_weight_last <= (global_idx == (TOTAL_GLOBAL_WEIGHT - 1));
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= 'd0;
        cfg_weight_last <= 1'b0;
    end
    endtask

    task read_dst_frames_and_check;
        reg [ADDR2D_WIDTH-1:0] addr2d_pack;
        reg signed [OUT_WIDTH-1:0] rtl_val;
    begin
        for(row_idx = 0; row_idx < OFMAP_H; row_idx = row_idx + 1)
        begin
            for(col_idx = 0; col_idx < OFMAP_W; col_idx = col_idx + 1)
            begin
                @(posedge clk);
                for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
                begin
                    dst_rd_en[out_idx] <= 1'b1;
                    addr2d_pack = {row_idx[ROW_ADDR_WIDTH-1:0], col_idx[COL_ADDR_WIDTH-1:0]};
                    dst_rd_addr2d[((out_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    dst_rd_done[out_idx] <= 1'b0;
                end

                @(posedge clk);
                if(!((row_idx == 0) && (col_idx == 0)))
                begin
                    for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
                    begin
                        rtl_val = dst_rd_data[((out_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
                        rtl_console_val[out_idx] = rtl_val;
                        if(dst_rd_valid[out_idx] !== 1'b1)
                        begin
                            err_cnt = err_cnt + 1;
                            $display("ERR_RDVALID out=%0d row=%0d col=%0d", out_idx, prev_row_idx, prev_col_idx);
                        end
                        else if(rtl_val !== exp_map[out_idx][prev_row_idx][prev_col_idx])
                        begin
                            err_cnt = err_cnt + 1;
                            $display("ERR_DATA out=%0d row=%0d col=%0d rtl=%0d exp=%0d",
                                     out_idx,
                                     prev_row_idx,
                                     prev_col_idx,
                                     rtl_val,
                                     exp_map[out_idx][prev_row_idx][prev_col_idx]);
                        end
                    end
                    $display("RTL_L3 idx=%0d row=%0d col=%0d out0=%0d out1=%0d out2=%0d out3=%0d out4=%0d out5=%0d out6=%0d out7=%0d out8=%0d out9=%0d out10=%0d out11=%0d",
                             rd_cnt,
                             prev_row_idx,
                             prev_col_idx,
                             rtl_console_val[0],
                             rtl_console_val[1],
                             rtl_console_val[2],
                             rtl_console_val[3],
                             rtl_console_val[4],
                             rtl_console_val[5],
                             rtl_console_val[6],
                             rtl_console_val[7],
                             rtl_console_val[8],
                             rtl_console_val[9],
                             rtl_console_val[10],
                             rtl_console_val[11]);
                    rd_cnt = rd_cnt + 1;
                end

                prev_row_idx = row_idx;
                prev_col_idx = col_idx;
            end
        end

        @(posedge clk);
        dst_rd_en <= {OUT_NUM{1'b0}};
        dst_rd_addr2d <= {OUT_NUM*ADDR2D_WIDTH{1'b0}};
        dst_rd_done <= {OUT_NUM{1'b1}};

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            rtl_val = dst_rd_data[((out_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
            rtl_console_val[out_idx] = rtl_val;
            if(dst_rd_valid[out_idx] !== 1'b1)
            begin
                err_cnt = err_cnt + 1;
                $display("ERR_RDVALID out=%0d row=%0d col=%0d", out_idx, prev_row_idx, prev_col_idx);
            end
            else if(rtl_val !== exp_map[out_idx][prev_row_idx][prev_col_idx])
            begin
                err_cnt = err_cnt + 1;
                $display("ERR_DATA out=%0d row=%0d col=%0d rtl=%0d exp=%0d",
                         out_idx,
                         prev_row_idx,
                         prev_col_idx,
                         rtl_val,
                         exp_map[out_idx][prev_row_idx][prev_col_idx]);
            end
        end
        $display("RTL_L3 idx=%0d row=%0d col=%0d out0=%0d out1=%0d out2=%0d out3=%0d out4=%0d out5=%0d out6=%0d out7=%0d out8=%0d out9=%0d out10=%0d out11=%0d",
                 rd_cnt,
                 prev_row_idx,
                 prev_col_idx,
                 rtl_console_val[0],
                 rtl_console_val[1],
                 rtl_console_val[2],
                 rtl_console_val[3],
                 rtl_console_val[4],
                 rtl_console_val[5],
                 rtl_console_val[6],
                 rtl_console_val[7],
                 rtl_console_val[8],
                 rtl_console_val[9],
                 rtl_console_val[10],
                 rtl_console_val[11]);
        rd_cnt = rd_cnt + 1;

        @(posedge clk);
        dst_rd_done <= {OUT_NUM{1'b0}};
    end
    endtask

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 'd0;
        cfg_weight_last = 1'b0;
        dst_rd_en = {OUT_NUM{1'b0}};
        dst_rd_addr2d = {OUT_NUM*ADDR2D_WIDTH{1'b0}};
        dst_rd_done = {OUT_NUM{1'b0}};
        src_wr_valid = {SRC_NUM{1'b0}};
        src_wr_data = {SRC_NUM*DATA_WIDTH{1'b0}};
        src_wr_addr2d = {SRC_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last = {SRC_NUM{1'b0}};
        src_buf_rd_done_tb = {SRC_NUM{1'b0}};
        err_cnt = 0;
        rd_cnt = 0;
        prev_row_idx = 0;
        prev_col_idx = 0;
        done_seen = 1'b0;
        cfg_weight_done_seen = 1'b0;
        cfg_last_err_seen = 1'b0;

        init_case_data();
        load_golden_files();

        repeat(8) @(posedge clk);
        rstn = 1'b1;
        repeat(2) @(posedge clk);

        write_src_frames();
        wait(&src_frame_valid);
        repeat(2) @(posedge clk);

        send_global_weights();
        wait(cfg_weight_done_seen == 1'b1);
        wait(weight_loaded == 1'b1);
        repeat(2) @(posedge clk);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done == 1'b1);
        repeat(2) @(posedge clk);

        read_dst_frames_and_check();

        repeat(4) @(posedge clk);
        $display("SUMMARY: err_cnt=%0d rd_cnt=%0d weight_loaded=%0d done_seen=%0d cfg_last_err_seen=%0d",
                 err_cnt, rd_cnt, weight_loaded, done_seen, cfg_last_err_seen);
        if((err_cnt == 0) && (cfg_last_err_seen == 1'b0))
        begin
            $display("TB PASS");
        end
        else
        begin
            $display("TB FAIL");
        end
        $finish;
    end

    always @(posedge clk)
    begin
        if(done)
        begin
            done_seen <= 1'b1;
        end

        if(cfg_weight_done)
        begin
            cfg_weight_done_seen <= 1'b1;
        end

        if(cfg_last_err)
        begin
            cfg_last_err_seen <= 1'b1;
        end
    end

endmodule
