`timescale 1ns / 1ns

// 第三层局部集成核心仿真
// 1. 用 6 个输入乒乓缓存模拟上一级 12x12 输出特征图
// 2. 给 12 个输出核顺序装载 12 x 6 x 25 个权重
// 3. 启动一次完整 8x8 扫描
// 4. 读回 12 路输出并与 TB 软件结果逐点比较
module l3_core_tb;

    localparam SRC_NUM = 6;
    localparam OUT_NUM = 12;
    localparam SRC_SEL_WIDTH = 3;
    localparam OUT_SEL_WIDTH = 4;
    localparam DATA_WIDTH = 8;
    localparam WEIGHT_WIDTH = 8;
    localparam IMG_W = 12;
    localparam IMG_H = 12;
    localparam K = 5;
    localparam STRIDE = 1;
    localparam OUT_WIDTH = 32;
    localparam OFMAP_W = ((IMG_W - K) / STRIDE) + 1;
    localparam OFMAP_H = ((IMG_H - K) / STRIDE) + 1;
    localparam ROW_ADDR_WIDTH = 5;
    localparam COL_ADDR_WIDTH = 5;
    localparam ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam SRC_DEPTH = IMG_W * IMG_H;
    localparam DST_DEPTH = OFMAP_W * OFMAP_H;
    localparam ADDR1D_WIDTH = 8;

    reg clk;
    reg rstn;
    reg start;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg [OUT_SEL_WIDTH-1:0] cfg_weight_out;
    reg [SRC_SEL_WIDTH-1:0] cfg_weight_cin;
    reg [OUT_NUM-1:0] dst_rd_en;
    reg [OUT_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d;
    reg [OUT_NUM-1:0] dst_rd_done;

    wire ready;
    wire busy;
    wire done;
    wire cfg_weight_ready;
    wire cfg_weight_done;
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
    reg signed [OUT_WIDTH-1:0] exp_map [0:OUT_NUM-1][0:OFMAP_H-1][0:OFMAP_W-1];

    integer src_idx;
    integer out_idx;
    integer row_idx;
    integer col_idx;
    integer krow_idx;
    integer kcol_idx;
    integer tap_idx;
    integer err_cnt;
    integer rd_cnt;
    integer acc_sum;
    integer prev_row_idx;
    integer prev_col_idx;

    reg done_seen;

    l3_core #(
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
        .ADDR1D_WIDTH(ADDR1D_WIDTH)
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
        .cfg_weight_out(cfg_weight_out),
        .cfg_weight_cin(cfg_weight_cin),
        .dst_rd_en(dst_rd_en),
        .dst_rd_addr2d(dst_rd_addr2d),
        .dst_rd_done(dst_rd_done),
        .ready(ready),
        .busy(busy),
        .done(done),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
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

    always #5 clk = ~clk;

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

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(row_idx = 0; row_idx < OFMAP_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < OFMAP_W; col_idx = col_idx + 1)
                begin
                    acc_sum = 0;
                    for(src_idx = 0; src_idx < SRC_NUM; src_idx = src_idx + 1)
                    begin
                        for(krow_idx = 0; krow_idx < K; krow_idx = krow_idx + 1)
                        begin
                            for(kcol_idx = 0; kcol_idx < K; kcol_idx = kcol_idx + 1)
                            begin
                                tap_idx = (krow_idx * K) + kcol_idx;
                                acc_sum = acc_sum
                                        + ($signed({1'b0, src_map[src_idx][row_idx + krow_idx][col_idx + kcol_idx]})
                                        * weight_map[out_idx][src_idx][tap_idx]);
                            end
                        end
                    end
                    exp_map[out_idx][row_idx][col_idx] = acc_sum;
                end
            end
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

    task send_weight_all;
    begin
        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(src_idx = 0; src_idx < SRC_NUM; src_idx = src_idx + 1)
            begin
                for(tap_idx = 0; tap_idx < (K * K); tap_idx = tap_idx + 1)
                begin
                    @(posedge clk);
                    while(!cfg_weight_ready)
                    begin
                        @(posedge clk);
                    end

                    cfg_weight_valid <= 1'b1;
                    cfg_weight_data <= weight_map[out_idx][src_idx][tap_idx];
                    cfg_weight_last <= (tap_idx == ((K * K) - 1));
                    cfg_weight_out <= out_idx[OUT_SEL_WIDTH-1:0];
                    cfg_weight_cin <= src_idx[SRC_SEL_WIDTH-1:0];
                end
            end
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= 'd0;
        cfg_weight_last <= 1'b0;
        cfg_weight_out <= {OUT_SEL_WIDTH{1'b0}};
        cfg_weight_cin <= {SRC_SEL_WIDTH{1'b0}};
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
        cfg_weight_out = {OUT_SEL_WIDTH{1'b0}};
        cfg_weight_cin = {SRC_SEL_WIDTH{1'b0}};
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

        init_case_data();

        repeat(8) @(posedge clk);
        rstn = 1'b1;
        repeat(2) @(posedge clk);

        write_src_frames();
        wait(&src_frame_valid);
        repeat(2) @(posedge clk);

        send_weight_all();
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
        $display("SUMMARY: err_cnt=%0d rd_cnt=%0d weight_loaded=%0d done_seen=%0d",
                 err_cnt, rd_cnt, weight_loaded, done_seen);
        if(err_cnt == 0)
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
    end

endmodule
