`timescale 1ns / 1ns

// 第五层INT4参考版与打包版对拍TB
// 1. 两边喂同一份8bit特征图和8bit FC权重
// 2. TB内部按同一量化规则算一份期望结果
// 3. 检查ref / pack / exp三者逐路一致
module l5_top_raw_int4_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IN_CH_NUM = 12;
    localparam integer LANE_NUM = 6;
    localparam integer OUT_NUM = 10;
    localparam integer GROUP_NUM = IN_CH_NUM / LANE_NUM;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer QUANT_WIDTH = 4;
    localparam integer INPUT_SHIFT = 4;
    localparam integer WEIGHT_SHIFT = 4;
    localparam integer IMG_W = 4;
    localparam integer IMG_H = 4;
    localparam integer OUT_WIDTH = 32;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer SRC_DEPTH = IMG_W * IMG_H;
    localparam integer SRC_ADDR_WIDTH = 6;
    localparam integer FC_WEIGHT_NUM = 192;
    localparam integer FC_WEIGHT_TOTAL = OUT_NUM * FC_WEIGHT_NUM;
    localparam signed [DATA_WIDTH-1:0] QUANT_MAX_VAL = (1 <<< (QUANT_WIDTH - 1)) - 1;
    localparam signed [DATA_WIDTH-1:0] QUANT_MIN_VAL = -(1 <<< (QUANT_WIDTH - 1));

    reg clk;
    reg rstn;
    reg start;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg score_ready;

    reg [IN_CH_NUM-1:0] src_wr_valid;
    reg signed [IN_CH_NUM*DATA_WIDTH-1:0] src_wr_data_ref;
    reg signed [IN_CH_NUM*DATA_WIDTH-1:0] src_wr_data_pack;
    reg [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_wr_addr2d_ref;
    reg [IN_CH_NUM*ADDR2D_WIDTH-1:0] src_wr_addr2d_pack;
    reg [IN_CH_NUM-1:0] src_wr_last;
    reg [IN_CH_NUM-1:0] src_buf_rd_done_tb_ref;
    reg [IN_CH_NUM-1:0] src_buf_rd_done_tb_pack;

    wire ref_cfg_weight_ready;
    wire ref_cfg_weight_done;
    wire ref_cfg_last_err;
    wire ref_ready;
    wire ref_busy;
    wire ref_done;
    wire ref_weight_loaded;
    wire [IN_CH_NUM-1:0] ref_src_rd_en;
    wire [IN_CH_NUM*ADDR2D_WIDTH-1:0] ref_src_rd_addr2d;
    wire [IN_CH_NUM-1:0] ref_src_rd_done;
    wire ref_score_valid;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] ref_score_data;

    wire pack_cfg_weight_ready;
    wire pack_cfg_weight_done;
    wire pack_cfg_last_err;
    wire pack_ready;
    wire pack_busy;
    wire pack_done;
    wire pack_weight_loaded;
    wire [IN_CH_NUM-1:0] pack_src_rd_en;
    wire [IN_CH_NUM*ADDR2D_WIDTH-1:0] pack_src_rd_addr2d;
    wire [IN_CH_NUM-1:0] pack_src_rd_done;
    wire pack_score_valid;
    wire signed [OUT_NUM*OUT_WIDTH-1:0] pack_score_data;

    wire [IN_CH_NUM-1:0] src_wr_ready_ref;
    wire [IN_CH_NUM-1:0] src_wr_done_ref;
    wire signed [IN_CH_NUM*DATA_WIDTH-1:0] src_rd_data_ref;
    wire [IN_CH_NUM-1:0] src_rd_valid_ref;
    wire [IN_CH_NUM-1:0] src_frame_valid_ref;

    wire [IN_CH_NUM-1:0] src_wr_ready_pack;
    wire [IN_CH_NUM-1:0] src_wr_done_pack;
    wire signed [IN_CH_NUM*DATA_WIDTH-1:0] src_rd_data_pack;
    wire [IN_CH_NUM-1:0] src_rd_valid_pack;
    wire [IN_CH_NUM-1:0] src_frame_valid_pack;

    reg signed [DATA_WIDTH-1:0] src_map [0:IN_CH_NUM-1][0:IMG_H-1][0:IMG_W-1];
    reg signed [WEIGHT_WIDTH-1:0] fc_weight_map [0:OUT_NUM-1][0:IN_CH_NUM-1][0:(IMG_W*IMG_H)-1];
    reg signed [WEIGHT_WIDTH-1:0] fc_weight_stream [0:FC_WEIGHT_TOTAL-1];
    reg signed [OUT_WIDTH-1:0] exp_score [0:OUT_NUM-1];
    reg signed [OUT_WIDTH-1:0] ref_score [0:OUT_NUM-1];
    reg signed [OUT_WIDTH-1:0] pack_score [0:OUT_NUM-1];

    integer out_idx;
    integer src_idx;
    integer row_idx;
    integer col_idx;
    integer pos_idx;
    integer group_idx;
    integer lane_idx;
    integer flat_idx;
    integer err_cnt;

    reg ref_cfg_weight_done_seen;
    reg pack_cfg_weight_done_seen;
    reg ref_done_seen;
    reg pack_done_seen;

    function signed [QUANT_WIDTH-1:0] quant_s8_to_s4;
        input signed [DATA_WIDTH-1:0] din;
        input integer shift_val;
        reg signed [DATA_WIDTH-1:0] shift_res;
        begin
            shift_res = din >>> shift_val;

            if(shift_res > QUANT_MAX_VAL)
            begin
                quant_s8_to_s4 = QUANT_MAX_VAL[QUANT_WIDTH-1:0];
            end
            else if(shift_res < QUANT_MIN_VAL)
            begin
                quant_s8_to_s4 = QUANT_MIN_VAL[QUANT_WIDTH-1:0];
            end
            else
            begin
                quant_s8_to_s4 = shift_res[QUANT_WIDTH-1:0];
            end
        end
    endfunction

    l5_top_raw_int4_ref #(
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .OUT_NUM(OUT_NUM),
        .GROUP_NUM(GROUP_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .QUANT_WIDTH(QUANT_WIDTH),
        .INPUT_SHIFT(INPUT_SHIFT),
        .WEIGHT_SHIFT(WEIGHT_SHIFT),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .OUT_WIDTH(OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .FC_WEIGHT_NUM(FC_WEIGHT_NUM)
    ) u_l5_top_raw_int4_ref (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_frame_valid_ref),
        .src_rd_data(src_rd_data_ref),
        .src_rd_valid(src_rd_valid_ref),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .score_ready(score_ready),
        .cfg_weight_ready(ref_cfg_weight_ready),
        .cfg_weight_done(ref_cfg_weight_done),
        .cfg_last_err(ref_cfg_last_err),
        .ready(ref_ready),
        .busy(ref_busy),
        .done(ref_done),
        .weight_loaded(ref_weight_loaded),
        .src_rd_en(ref_src_rd_en),
        .src_rd_addr2d(ref_src_rd_addr2d),
        .src_rd_done(ref_src_rd_done),
        .score_valid(ref_score_valid),
        .score_data(ref_score_data)
    );

    l5_top_raw_int4_pack #(
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .OUT_NUM(OUT_NUM),
        .GROUP_NUM(GROUP_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .QUANT_WIDTH(QUANT_WIDTH),
        .INPUT_SHIFT(INPUT_SHIFT),
        .WEIGHT_SHIFT(WEIGHT_SHIFT),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .OUT_WIDTH(OUT_WIDTH),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .FC_WEIGHT_NUM(FC_WEIGHT_NUM)
    ) u_l5_top_raw_int4_pack (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .src_frame_valid(src_frame_valid_pack),
        .src_rd_data(src_rd_data_pack),
        .src_rd_valid(src_rd_valid_pack),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .score_ready(score_ready),
        .cfg_weight_ready(pack_cfg_weight_ready),
        .cfg_weight_done(pack_cfg_weight_done),
        .cfg_last_err(pack_cfg_last_err),
        .ready(pack_ready),
        .busy(pack_busy),
        .done(pack_done),
        .weight_loaded(pack_weight_loaded),
        .src_rd_en(pack_src_rd_en),
        .src_rd_addr2d(pack_src_rd_addr2d),
        .src_rd_done(pack_src_rd_done),
        .score_valid(pack_score_valid),
        .score_data(pack_score_data)
    );

    genvar gi;
    generate
        for(gi = 0; gi < IN_CH_NUM; gi = gi + 1)
        begin: g_src_buf_ref
            wire [ADDR2D_WIDTH-1:0] wr_addr2d_i;
            wire [ADDR2D_WIDTH-1:0] rd_addr2d_i;
            wire signed [DATA_WIDTH-1:0] rd_data_i;

            assign wr_addr2d_i = src_wr_addr2d_ref[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign rd_addr2d_i = ref_src_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_data_ref[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = rd_data_i;

            pingpong_img_buf #(
                .DATA_WIDTH(DATA_WIDTH),
                .IMG_W(IMG_W),
                .IMG_H(IMG_H),
                .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
                .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
                .ADDR2D_WIDTH(ADDR2D_WIDTH),
                .DEPTH(SRC_DEPTH),
                .ADDR_WIDTH(SRC_ADDR_WIDTH)
            ) u_src_buf_ref (
                .clk(clk),
                .rstn(rstn),
                .wr_valid(src_wr_valid[gi]),
                .wr_data(src_wr_data_ref[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]),
                .wr_addr2d(wr_addr2d_i),
                .wr_last(src_wr_last[gi]),
                .rd_en(ref_src_rd_en[gi]),
                .rd_addr2d(rd_addr2d_i),
                .rd_done(ref_src_rd_done[gi] || src_buf_rd_done_tb_ref[gi]),
                .wr_ready(src_wr_ready_ref[gi]),
                .wr_done(src_wr_done_ref[gi]),
                .rd_data(rd_data_i),
                .rd_valid(src_rd_valid_ref[gi]),
                .rd_frame_valid(src_frame_valid_ref[gi])
            );
        end
    endgenerate

    generate
        for(gi = 0; gi < IN_CH_NUM; gi = gi + 1)
        begin: g_src_buf_pack
            wire [ADDR2D_WIDTH-1:0] wr_addr2d_i;
            wire [ADDR2D_WIDTH-1:0] rd_addr2d_i;
            wire signed [DATA_WIDTH-1:0] rd_data_i;

            assign wr_addr2d_i = src_wr_addr2d_pack[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign rd_addr2d_i = pack_src_rd_addr2d[((gi + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];
            assign src_rd_data_pack[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = rd_data_i;

            pingpong_img_buf #(
                .DATA_WIDTH(DATA_WIDTH),
                .IMG_W(IMG_W),
                .IMG_H(IMG_H),
                .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
                .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
                .ADDR2D_WIDTH(ADDR2D_WIDTH),
                .DEPTH(SRC_DEPTH),
                .ADDR_WIDTH(SRC_ADDR_WIDTH)
            ) u_src_buf_pack (
                .clk(clk),
                .rstn(rstn),
                .wr_valid(src_wr_valid[gi]),
                .wr_data(src_wr_data_pack[((gi + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]),
                .wr_addr2d(wr_addr2d_i),
                .wr_last(src_wr_last[gi]),
                .rd_en(pack_src_rd_en[gi]),
                .rd_addr2d(rd_addr2d_i),
                .rd_done(pack_src_rd_done[gi] || src_buf_rd_done_tb_pack[gi]),
                .wr_ready(src_wr_ready_pack[gi]),
                .wr_done(src_wr_done_pack[gi]),
                .rd_data(rd_data_i),
                .rd_valid(src_rd_valid_pack[gi]),
                .rd_frame_valid(src_frame_valid_pack[gi])
            );
        end
    endgenerate

    always #(CLK_PERIOD / 2) clk = ~clk;

    task init_case_data;
        integer src_val;
        integer weight_val;
    begin
        for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
        begin
            for(row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1)
            begin
                for(col_idx = 0; col_idx < IMG_W; col_idx = col_idx + 1)
                begin
                    src_val = 12 + (src_idx * 6) + (row_idx * 11) + (col_idx * 4);
                    src_map[src_idx][row_idx][col_idx] = src_val[DATA_WIDTH-1:0];
                end
            end
        end

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(src_idx = 0; src_idx < IN_CH_NUM; src_idx = src_idx + 1)
            begin
                for(pos_idx = 0; pos_idx < (IMG_W * IMG_H); pos_idx = pos_idx + 1)
                begin
                    weight_val = (((out_idx * 17) + (src_idx * 11) + (pos_idx * 9)) % 223) - 111;
                    fc_weight_map[out_idx][src_idx][pos_idx] = weight_val[WEIGHT_WIDTH-1:0];
                end
            end
        end
    end
    endtask

    task build_fc_weight_stream;
    begin
        flat_idx = 0;
        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            for(group_idx = 0; group_idx < GROUP_NUM; group_idx = group_idx + 1)
            begin
                for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
                begin
                    src_idx = (group_idx * LANE_NUM) + lane_idx;
                    for(pos_idx = 0; pos_idx < (IMG_W * IMG_H); pos_idx = pos_idx + 1)
                    begin
                        fc_weight_stream[flat_idx] = fc_weight_map[out_idx][src_idx][pos_idx];
                        flat_idx = flat_idx + 1;
                    end
                end
            end
        end
    end
    endtask

    task calc_expected_scores;
        integer acc_int;
        integer qin_int;
        integer qw_int;
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
                        qin_int = quant_s8_to_s4(src_map[src_idx][row_idx][col_idx], INPUT_SHIFT);
                        qw_int = quant_s8_to_s4(fc_weight_map[out_idx][src_idx][pos_idx], WEIGHT_SHIFT);
                        acc_int = acc_int + (qin_int * qw_int);
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
                    src_wr_data_ref[((src_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]
                        <= src_map[src_idx][row_idx][col_idx];
                    src_wr_data_pack[((src_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH]
                        <= src_map[src_idx][row_idx][col_idx];
                    addr2d_pack = {row_idx[ROW_ADDR_WIDTH-1:0], col_idx[COL_ADDR_WIDTH-1:0]};
                    src_wr_addr2d_ref[((src_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    src_wr_addr2d_pack[((src_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH] <= addr2d_pack;
                    src_wr_last[src_idx] <= (row_idx == (IMG_H - 1)) && (col_idx == (IMG_W - 1));
                end
            end
        end

        @(posedge clk);
        src_wr_valid <= {IN_CH_NUM{1'b0}};
        src_wr_data_ref <= {(IN_CH_NUM * DATA_WIDTH){1'b0}};
        src_wr_data_pack <= {(IN_CH_NUM * DATA_WIDTH){1'b0}};
        src_wr_addr2d_ref <= {(IN_CH_NUM * ADDR2D_WIDTH){1'b0}};
        src_wr_addr2d_pack <= {(IN_CH_NUM * ADDR2D_WIDTH){1'b0}};
        src_wr_last <= {IN_CH_NUM{1'b0}};
    end
    endtask

    task send_fc_weights;
    begin
        for(flat_idx = 0; flat_idx < FC_WEIGHT_TOTAL; flat_idx = flat_idx + 1)
        begin
            @(posedge clk);
            while(!(ref_cfg_weight_ready && pack_cfg_weight_ready))
            begin
                @(posedge clk);
            end

            cfg_weight_valid <= 1'b1;
            cfg_weight_data <= fc_weight_stream[flat_idx];
            cfg_weight_last <= (flat_idx == (FC_WEIGHT_TOTAL - 1));
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= {WEIGHT_WIDTH{1'b0}};
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
        score_ready = 1'b1;
        src_wr_valid = {IN_CH_NUM{1'b0}};
        src_wr_data_ref = {(IN_CH_NUM * DATA_WIDTH){1'b0}};
        src_wr_data_pack = {(IN_CH_NUM * DATA_WIDTH){1'b0}};
        src_wr_addr2d_ref = {(IN_CH_NUM * ADDR2D_WIDTH){1'b0}};
        src_wr_addr2d_pack = {(IN_CH_NUM * ADDR2D_WIDTH){1'b0}};
        src_wr_last = {IN_CH_NUM{1'b0}};
        src_buf_rd_done_tb_ref = {IN_CH_NUM{1'b0}};
        src_buf_rd_done_tb_pack = {IN_CH_NUM{1'b0}};
        err_cnt = 0;
        ref_cfg_weight_done_seen = 1'b0;
        pack_cfg_weight_done_seen = 1'b0;
        ref_done_seen = 1'b0;
        pack_done_seen = 1'b0;

        init_case_data;
        build_fc_weight_stream;
        calc_expected_scores;

        repeat(8) @(posedge clk);
        rstn = 1'b1;

        write_src_frames;
        wait((&src_wr_done_ref) && (&src_wr_done_pack));

        send_fc_weights;
        wait(ref_cfg_weight_done_seen && pack_cfg_weight_done_seen);
        wait(ref_weight_loaded && pack_weight_loaded);
        wait(ref_ready && pack_ready);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(ref_score_valid && pack_score_valid);
        @(posedge clk);

        for(out_idx = 0; out_idx < OUT_NUM; out_idx = out_idx + 1)
        begin
            ref_score[out_idx] = ref_score_data[((out_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
            pack_score[out_idx] = pack_score_data[((out_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];

            $display("REF_SCORE idx=%0d score=%0d", out_idx, ref_score[out_idx]);
            $display("PACK_SCORE idx=%0d score=%0d", out_idx, pack_score[out_idx]);
            $display("EXP_SCORE idx=%0d score=%0d", out_idx, exp_score[out_idx]);

            if(ref_score[out_idx] !== exp_score[out_idx])
            begin
                err_cnt = err_cnt + 1;
                $display("REF_MISMATCH idx=%0d ref=%0d exp=%0d", out_idx, ref_score[out_idx], exp_score[out_idx]);
            end

            if(pack_score[out_idx] !== exp_score[out_idx])
            begin
                err_cnt = err_cnt + 1;
                $display("PACK_MISMATCH idx=%0d pack=%0d exp=%0d", out_idx, pack_score[out_idx], exp_score[out_idx]);
            end
        end

        if(ref_cfg_last_err || pack_cfg_last_err)
        begin
            err_cnt = err_cnt + 1;
            $display("CFG_LAST_ERR ref=%b pack=%b", ref_cfg_last_err, pack_cfg_last_err);
        end

        if(!ref_done_seen || !pack_done_seen)
        begin
            $display("DONE_NOTE ref_done_seen=%b pack_done_seen=%b", ref_done_seen, pack_done_seen);
        end


        if(err_cnt == 0)
        begin
            $display("L5_TOP_RAW_INT4_PASS ref/pack/exp all matched.");
        end
        else
        begin
            $display("L5_TOP_RAW_INT4_FAIL err_cnt=%0d", err_cnt);
        end

        $finish;
    end

    always @(posedge clk)
    begin
        if(ref_cfg_weight_done)
        begin
            ref_cfg_weight_done_seen <= 1'b1;
        end

        if(pack_cfg_weight_done)
        begin
            pack_cfg_weight_done_seen <= 1'b1;
        end
    end

    always @(posedge ref_done)
    begin
        ref_done_seen = 1'b1;
    end

    always @(posedge pack_done)
    begin
        pack_done_seen = 1'b1;
    end

endmodule
