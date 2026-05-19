`timescale 1ns / 1ns

// 第五层对外顶层仿真
// 1. 用 12 个输入乒乓缓存模拟第四层 4x4 输出特征图
// 2. 先送完整全局权重流, 其中前两层权重为占位, 第三段为 FC 真实权重
// 3. 启动一次完整第五层计算
// 4. 检查 10 个分类分数与 TB 软件结果是否一致
module l5_top_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IN_CH_NUM = 12;
    localparam integer LANE_NUM = 6;
    localparam integer OUT_NUM = 10;
    localparam integer GROUP_NUM = IN_CH_NUM / LANE_NUM;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer IMG_W = 4;
    localparam integer IMG_H = 4;
    localparam integer OUT_WIDTH = 32;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer SRC_DEPTH = IMG_W * IMG_H;
    localparam integer SRC_ADDR_WIDTH = 6;
    localparam integer LAYER_ID_WIDTH = 2;
    localparam integer KERNEL_ID_WIDTH = 4;
    localparam integer WEIGHT_IDX_WIDTH = 8;
    localparam integer L0_KERNEL_NUM = 6;
    localparam integer L0_WEIGHT_NUM = 25;
    localparam integer L1_KERNEL_NUM = 12;
    localparam integer L1_WEIGHT_NUM = 150;
    localparam integer L2_KERNEL_NUM = 10;
    localparam integer L2_WEIGHT_NUM = 192;
    localparam integer TOTAL_GLOBAL_WEIGHT = (L0_KERNEL_NUM * L0_WEIGHT_NUM)
                                           + (L1_KERNEL_NUM * L1_WEIGHT_NUM)
                                           + (L2_KERNEL_NUM * L2_WEIGHT_NUM);
    localparam integer DST2D_WIDTH = LAYER_ID_WIDTH + KERNEL_ID_WIDTH;

    reg clk;
    reg rstn;
    reg start;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg score_ready;

    reg [IN_CH_NUM-1:0] src_wr_valid;
    reg signed [IN_CH_NUM*DATA_WIDTH-1:0] src_wr_data;
    reg [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_wr_addr2d;
    reg [IN_CH_NUM-1:0] src_wr_last;
    reg [IN_CH_NUM-1:0] src_buf_rd_done_tb;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire cfg_last_err;
    wire ready;
    wire busy;
    wire done;
    wire weight_loaded;
    wire [IN_CH_NUM-1:0] src_rd_en;
    wire [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d;
    wire [IN_CH_NUM-1:0] src_rd_done;
    wire score_valid;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] score_data;

    wire [IN_CH_NUM-1:0] src_wr_ready;
    wire [IN_CH_NUM-1:0] src_wr_done;
    wire signed [IN_CH_NUM*DATA_WIDTH-1:0] src_rd_data;
    wire [IN_CH_NUM-1:0] src_rd_valid;
    wire [IN_CH_NUM-1:0] src_frame_valid;

    reg signed [DATA_WIDTH-1:0] src_map [0:IN_CH_NUM-1][0:IMG_H-1][0:IMG_W-1];
    reg signed [WEIGHT_WIDTH-1:0] fc_weight_map [0:OUT_NUM-1][0:IN_CH_NUM-1][0:(IMG_W*IMG_H)-1];
    reg signed [WEIGHT_WIDTH-1:0] global_weight_mem [0:TOTAL_GLOBAL_WEIGHT-1];
    reg signed [OUT_WIDTH-1:0] exp_score [0:OUT_NUM-1];
    reg signed [OUT_WIDTH-1:0] rtl_score [0:OUT_NUM-1];

    integer src_idx;
    integer out_idx;
    integer row_idx;
    integer col_idx;
    integer pos_idx;
    integer lane_idx;
    integer group_idx;
    integer global_idx;
    integer err_cnt;
    integer exp_val;
    reg done_seen;
    reg cfg_weight_done_seen;
    reg cfg_last_err_seen;

    l5_top #(
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .OUT_NUM(OUT_NUM),
        .GROUP_NUM(GROUP_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .OUT_WIDTH(OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .LAYER_ID_WIDTH(LAYER_ID_WIDTH),
        .KERNEL_ID_WIDTH(KERNEL_ID_WIDTH),
        .WEIGHT_IDX_WIDTH(WEIGHT_IDX_WIDTH),
        .L0_KERNEL_NUM(L0_KERNEL_NUM),
        .L0_WEIGHT_NUM(L0_WEIGHT_NUM),
        .L1_KERNEL_NUM(L1_KERNEL_NUM),
        .L1_WEIGHT_NUM(L1_WEIGHT_NUM),
        .L2_KERNEL_NUM(L2_KERNEL_NUM),
        .L2_WEIGHT_NUM(L2_WEIGHT_NUM),
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
        .score_ready(score_ready),
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
        .score_valid(score_valid),
        .score_data(score_data)
    );

    genvar gi;
    generate
        for(gi = 0; gi < IN_CH_NUM; gi = gi + 1)
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
                .ADDR_WIDTH(SRC_ADDR_WIDTH)
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
        for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
        begin
            for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
                begin
                    src_map[src_idx][row_idx][col_idx] = (src_idx * 7) + (row_idx * IMG_W) + col_idx + 1;
                end
            end
        end

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
            begin
                for(pos_idx = 0; pos_idx < (IMG_W * IMG_H); pos_idx = pos_idx + 1)
                begin
                    fc_weight_map[out_idx][src_idx][pos_idx] = $signed(((out_idx * 3) + src_idx + pos_idx) % 7) - 3;
                end
            end
        end
    end
    endtask

    task build_global_weight_stream;
    begin
        global_idx = 0;

        for(pos_idx = 0; pos_idx < (L0_KERNEL_NUM * L0_WEIGHT_NUM); pos_idx = pos_idx + 1)
        begin
            global_weight_mem[global_idx] = $signed((pos_idx % 5) - 2);
            global_idx = global_idx + 1;
        end

        for(pos_idx = 0; pos_idx < (L1_KERNEL_NUM * L1_WEIGHT_NUM); pos_idx = pos_idx + 1)
        begin
            global_weight_mem[global_idx] = $signed((pos_idx % 7) - 3);
            global_idx = global_idx + 1;
        end

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(group_idx = 0; group_idx < GROUP_NUM; group_idx = group_idx + 1)
            begin
                for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
                begin
                    src_idx = (group_idx * LANE_NUM) + lane_idx;
                    for(pos_idx = 0; pos_idx < (IMG_W * IMG_H); pos_idx = pos_idx + 1)
                    begin
                        global_weight_mem[global_idx] = fc_weight_map[out_idx][src_idx][pos_idx];
                        global_idx = global_idx + 1;
                    end
                end
            end
        end
    end
    endtask

    task calc_expected_scores;
        integer acc_int;
    begin
        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            acc_int = 0;
            for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
            begin
                for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
                begin
                    for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
                    begin
                        pos_idx = (row_idx * IMG_W) + col_idx;
                        acc_int = acc_int
                                + (src_map[src_idx][row_idx][col_idx] * fc_weight_map[out_idx][src_idx][pos_idx]);
                    end
                end
            end
            exp_score[out_idx] = acc_int;
        end
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
                for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
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
        src_wr_valid <= {IN_CH_NUM{1'b0}};
        src_wr_data <= {IN_CH_NUM*DATA_WIDTH{1'b0}};
        src_wr_addr2d <= {IN_CH_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last <= {IN_CH_NUM{1'b0}};
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
            cfg_weight_last <= (global_idx == TOTAL_GLOBAL_WEIGHT - 1);
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= 0;
        cfg_weight_last <= 1'b0;
    end
    endtask

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 0;
        cfg_weight_last = 1'b0;
        score_ready = 1'b0;
        src_wr_valid = {IN_CH_NUM{1'b0}};
        src_wr_data = {IN_CH_NUM*DATA_WIDTH{1'b0}};
        src_wr_addr2d = {IN_CH_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last = {IN_CH_NUM{1'b0}};
        src_buf_rd_done_tb = {IN_CH_NUM{1'b0}};
        err_cnt = 0;
        done_seen = 1'b0;
        cfg_weight_done_seen = 1'b0;
        cfg_last_err_seen = 1'b0;

        init_case_data;
        build_global_weight_stream;
        calc_expected_scores;

        repeat(10) @(posedge clk);
        rstn = 1'b1;

        write_src_frames;
        wait(&src_wr_done);

        send_global_weights;
        wait(cfg_weight_done_seen == 1'b1);
        wait(weight_loaded == 1'b1);
        wait(ready == 1'b1);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(score_valid == 1'b1);

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            rtl_score[out_idx] = score_data[((out_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
            $display("L5_SCORE out=%0d rtl=%0d exp=%0d", out_idx, rtl_score[out_idx], exp_score[out_idx]);
            if(rtl_score[out_idx] !== exp_score[out_idx])
            begin
                err_cnt = err_cnt + 1;
                $display("ERROR: score mismatch out=%0d rtl=%0d exp=%0d",
                         out_idx, rtl_score[out_idx], exp_score[out_idx]);
            end
        end

        repeat(3) @(posedge clk);
        score_ready <= 1'b1;
        @(posedge clk);
        score_ready <= 1'b0;

        repeat(10) @(posedge clk);

        $display("SUMMARY: err_cnt=%0d weight_loaded=%0d done_seen=%0d cfg_last_err_seen=%0d",
                 err_cnt, weight_loaded, done_seen, cfg_last_err_seen);

        if((err_cnt == 0) && (cfg_last_err_seen == 1'b0))
        begin
            $display("TB_PASS");
        end
        else
        begin
            $display("TB_FAIL");
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
