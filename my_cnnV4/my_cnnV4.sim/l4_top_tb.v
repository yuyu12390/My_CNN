`timescale 1ns / 1ns

// 第四层 relu+pool 12 路顶层仿真
// 1. 用 12 个输入乒乓缓存模拟第三层 8x8 输出特征图
// 2. 启动一次完整第四层 4x4 relu+pool
// 3. 读回 12 路输出, 与 PC 生成黄金结果逐点比较
module l4_top_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer LANE_NUM = 12;
    localparam integer IN_WIDTH = 32;
    localparam integer OUT_WIDTH = 8;
    localparam integer IMG_W = 8;
    localparam integer IMG_H = 8;
    localparam integer K = 2;
    localparam integer STRIDE = 2;
    localparam integer SHIFT_BITS = 10;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer OUT_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer OUT_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer SRC_DEPTH = IMG_W * IMG_H;
    localparam integer DST_DEPTH = OUT_W * OUT_H;
    localparam integer SRC_ADDR_WIDTH = 8;
    localparam integer DST_ADDR_WIDTH = 6;
    localparam GOLDEN_RESULT_FILE = "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_PCtest/l4_top12_feature_map_all.txt";

    reg clk;
    reg rstn;
    reg start;
    reg [LANE_NUM-1:0] dst_rd_en;
    reg [LANE_NUM*ADDR2D_WIDTH-1:0] dst_rd_addr2d;
    reg [LANE_NUM-1:0] dst_rd_done;

    reg [LANE_NUM-1:0] src_wr_valid;
    reg signed [LANE_NUM*IN_WIDTH-1:0] src_wr_data;
    reg [LANE_NUM*ADDR2D_WIDTH-1:0] src_wr_addr2d;
    reg [LANE_NUM-1:0] src_wr_last;
    reg [LANE_NUM-1:0] src_buf_rd_done_tb;

    wire ready;
    wire busy;
    wire done;
    wire [LANE_NUM-1:0] src_rd_en;
    wire [LANE_NUM*ADDR2D_WIDTH-1:0] src_rd_addr2d;
    wire [LANE_NUM-1:0] src_rd_done;
    wire [LANE_NUM-1:0] dst_frame_valid;
    wire signed [LANE_NUM*OUT_WIDTH-1:0] dst_rd_data;
    wire [LANE_NUM-1:0] dst_rd_valid;

    wire [LANE_NUM-1:0] src_wr_ready;
    wire [LANE_NUM-1:0] src_wr_done;
    wire signed [LANE_NUM*IN_WIDTH-1:0] src_rd_data;
    wire [LANE_NUM-1:0] src_rd_valid;
    wire [LANE_NUM-1:0] src_frame_valid;

    reg signed [IN_WIDTH-1:0] src_map [0:LANE_NUM-1][0:IMG_H-1][0:IMG_W-1];
    reg signed [OUT_WIDTH-1:0] exp_pool_map [0:LANE_NUM-1][0:OUT_H-1][0:OUT_W-1];

    integer fp_result;
    integer rc;
    integer lane_idx;
    integer row_idx;
    integer col_idx;
    integer prow_idx;
    integer pcol_idx;
    integer err_cnt;
    integer rd_cnt;
    integer prev_row_idx;
    integer prev_col_idx;
    integer exp_val;

    reg done_seen;
    reg [IN_WIDTH-1:0] tmp_src_val;
    reg signed [OUT_WIDTH-1:0] rtl_val;
    reg [255:0] header_str;
    reg signed [OUT_WIDTH-1:0] rtl_console_val [0:LANE_NUM-1];

    l4_top #(
        .LANE_NUM(LANE_NUM),
        .IN_WIDTH(IN_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .SHIFT_BITS(SHIFT_BITS),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .OUT_W(OUT_W),
        .OUT_H(OUT_H),
        .OUT_ADDR_WIDTH(DST_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_frame_valid),
        .src_rd_data(src_rd_data),
        .src_rd_valid(src_rd_valid),
        .dst_rd_en(dst_rd_en),
        .dst_rd_addr2d(dst_rd_addr2d),
        .dst_rd_done(dst_rd_done),
        .ready(ready),
        .busy(busy),
        .done(done),
        .src_rd_en(src_rd_en),
        .src_rd_addr2d(src_rd_addr2d),
        .src_rd_done(src_rd_done),
        .dst_frame_valid(dst_frame_valid),
        .dst_rd_data(dst_rd_data),
        .dst_rd_valid(dst_rd_valid)
    );

    genvar gi;
    generate
        for(gi = 0; gi < LANE_NUM; gi = gi + 1)
        begin: g_src_buf
            wire [ADDR2D_WIDTH-1:0] src_wr_addr2d_i;
            wire [ADDR2D_WIDTH-1:0] src_rd_addr2d_i;
            wire signed [IN_WIDTH-1:0] src_rd_data_i;

            assign src_wr_addr2d_i = src_wr_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_addr2d_i = src_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_data[((gi + 1) * IN_WIDTH) - 1 -: IN_WIDTH] = src_rd_data_i;

            pingpong_img_buf #(
                .DATA_WIDTH(IN_WIDTH),
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
                .wr_data(src_wr_data[((gi + 1) * IN_WIDTH) - 1 -: IN_WIDTH]),
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
        for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
        begin
            for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
                begin
                    tmp_src_val = (lane_idx * 300) + (row_idx * IMG_W * 12) + (col_idx * 17) - 400;
                    src_map[lane_idx][row_idx][col_idx] = $signed(tmp_src_val);
                end
            end
        end
    end
    endtask

    task load_golden_file;
    begin
        fp_result = $fopen(GOLDEN_RESULT_FILE, "r");
        if(fp_result == 0)
        begin
            $display("ERROR: failed to open %s", GOLDEN_RESULT_FILE);
            $finish;
        end

        for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
        begin
            rc = $fscanf(fp_result, "%s", header_str);
            if(rc != 1)
            begin
                $display("ERROR: result header token missing at out=%0d", lane_idx);
                $finish;
            end

            rc = $fscanf(fp_result, "%d", exp_val);
            if(rc != 1)
            begin
                $display("ERROR: result header index missing at out=%0d", lane_idx);
                $finish;
            end

            if(exp_val != lane_idx)
            begin
                $display("ERROR: result header mismatch got=%0d exp=%0d", exp_val, lane_idx);
                $finish;
            end

            for(prow_idx = 0; prow_idx < OUT_H; prow_idx = prow_idx + 1)
            begin
                for(pcol_idx = 0; pcol_idx < OUT_W; pcol_idx = pcol_idx + 1)
                begin
                    rc = $fscanf(fp_result, "%d", exp_val);
                    if(rc != 1)
                    begin
                        $display("ERROR: result data missing out=%0d row=%0d col=%0d",
                                 lane_idx, prow_idx, pcol_idx);
                        $finish;
                    end
                    exp_pool_map[lane_idx][prow_idx][pcol_idx] = exp_val;
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
                for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
                begin
                    src_wr_valid[lane_idx] <= 1'b1;
                    src_wr_data[((lane_idx + 1) * IN_WIDTH) - 1 -: IN_WIDTH] <= src_map[lane_idx][row_idx][col_idx];
                    addr2d_pack = {row_idx[ROW_ADDR_WIDTH-1:0], col_idx[COL_ADDR_WIDTH-1:0]};
                    src_wr_addr2d[((lane_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    src_wr_last[lane_idx] <= (row_idx == (IMG_H - 1)) && (col_idx == (IMG_W - 1));
                end
            end
        end

        @(posedge clk);
        src_wr_valid <= {LANE_NUM{1'b0}};
        src_wr_data <= {LANE_NUM*IN_WIDTH{1'b0}};
        src_wr_addr2d <= {LANE_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last <= {LANE_NUM{1'b0}};
    end
    endtask

    task read_dst_frames_and_check;
        reg [ADDR2D_WIDTH-1:0] addr2d_pack;
    begin
        for(row_idx = 0; row_idx < OUT_H; row_idx = row_idx + 1)
        begin
            for(col_idx = 0; col_idx < OUT_W; col_idx = col_idx + 1)
            begin
                @(posedge clk);
                for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
                begin
                    dst_rd_en[lane_idx] <= 1'b1;
                    addr2d_pack = {row_idx[ROW_ADDR_WIDTH-1:0], col_idx[COL_ADDR_WIDTH-1:0]};
                    dst_rd_addr2d[((lane_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    dst_rd_done[lane_idx] <= 1'b0;
                end

                @(posedge clk);
                if(!((row_idx == 0) && (col_idx == 0)))
                begin
                    for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
                    begin
                        rtl_val = dst_rd_data[((lane_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
                        rtl_console_val[lane_idx] = rtl_val;
                        if(dst_rd_valid[lane_idx] !== 1'b1)
                        begin
                            err_cnt = err_cnt + 1;
                            $display("ERR_RDVALID lane=%0d row=%0d col=%0d", lane_idx, prev_row_idx, prev_col_idx);
                        end
                        else if(rtl_val !== exp_pool_map[lane_idx][prev_row_idx][prev_col_idx])
                        begin
                            err_cnt = err_cnt + 1;
                            $display("ERR_DATA lane=%0d row=%0d col=%0d rtl=%0d exp=%0d",
                                     lane_idx,
                                     prev_row_idx,
                                     prev_col_idx,
                                     rtl_val,
                                     exp_pool_map[lane_idx][prev_row_idx][prev_col_idx]);
                        end
                    end
                    $display("RTL_L4 idx=%0d row=%0d col=%0d out0=%0d out1=%0d out2=%0d out3=%0d out4=%0d out5=%0d out6=%0d out7=%0d out8=%0d out9=%0d out10=%0d out11=%0d",
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
        dst_rd_en <= {LANE_NUM{1'b0}};
        dst_rd_addr2d <= {LANE_NUM*ADDR2D_WIDTH{1'b0}};
        dst_rd_done <= {LANE_NUM{1'b1}};

        for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
        begin
            rtl_val = dst_rd_data[((lane_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
            rtl_console_val[lane_idx] = rtl_val;
            if(dst_rd_valid[lane_idx] !== 1'b1)
            begin
                err_cnt = err_cnt + 1;
                $display("ERR_RDVALID lane=%0d row=%0d col=%0d", lane_idx, prev_row_idx, prev_col_idx);
            end
            else if(rtl_val !== exp_pool_map[lane_idx][prev_row_idx][prev_col_idx])
            begin
                err_cnt = err_cnt + 1;
                $display("ERR_DATA lane=%0d row=%0d col=%0d rtl=%0d exp=%0d",
                         lane_idx,
                         prev_row_idx,
                         prev_col_idx,
                         rtl_val,
                         exp_pool_map[lane_idx][prev_row_idx][prev_col_idx]);
            end
        end
        $display("RTL_L4 idx=%0d row=%0d col=%0d out0=%0d out1=%0d out2=%0d out3=%0d out4=%0d out5=%0d out6=%0d out7=%0d out8=%0d out9=%0d out10=%0d out11=%0d",
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
        dst_rd_done <= {LANE_NUM{1'b0}};
    end
    endtask

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        dst_rd_en = {LANE_NUM{1'b0}};
        dst_rd_addr2d = {LANE_NUM*ADDR2D_WIDTH{1'b0}};
        dst_rd_done = {LANE_NUM{1'b0}};
        src_wr_valid = {LANE_NUM{1'b0}};
        src_wr_data = {LANE_NUM*IN_WIDTH{1'b0}};
        src_wr_addr2d = {LANE_NUM*ADDR2D_WIDTH{1'b0}};
        src_wr_last = {LANE_NUM{1'b0}};
        src_buf_rd_done_tb = {LANE_NUM{1'b0}};
        err_cnt = 0;
        rd_cnt = 0;
        prev_row_idx = 0;
        prev_col_idx = 0;
        done_seen = 1'b0;
        tmp_src_val = {IN_WIDTH{1'b0}};
        rtl_val = {OUT_WIDTH{1'b0}};

        init_case_data();
        load_golden_file();

        repeat(8) @(posedge clk);
        rstn = 1'b1;
        repeat(2) @(posedge clk);

        write_src_frames();
        wait(&src_frame_valid);
        repeat(2) @(posedge clk);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done == 1'b1);
        repeat(2) @(posedge clk);

        read_dst_frames_and_check();

        repeat(4) @(posedge clk);
        $display("SUMMARY: err_cnt=%0d rd_cnt=%0d done_seen=%0d",
                 err_cnt, rd_cnt, done_seen);
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
