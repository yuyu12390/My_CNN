`timescale 1ns / 1ns

module l1_addr_mgr_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IMG_W = 28;
    localparam integer IMG_H = 28;
    localparam integer K = 5;
    localparam integer STRIDE = 1;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer OUT_W = ((IMG_W - K) / STRIDE) + 1;
    localparam integer OUT_H = ((IMG_H - K) / STRIDE) + 1;
    localparam integer WIN_SIZE = K * K;
    localparam integer TOTAL_WIN = OUT_W * OUT_H;

    reg clk;
    reg rstn;
    reg start;
    reg rd_addr_ready;
    reg out_fire;

    wire rd_addr_valid;
    wire [ADDR2D_WIDTH-1:0] rd_addr2d;
    wire rd_addr_last;
    wire wr_addr_valid;
    wire [ADDR2D_WIDTH-1:0] wr_addr2d;
    wire wr_last;
    wire busy;
    wire win_done;
    wire map_done;
    wire [ROW_ADDR_WIDTH-1:0] cur_base_row;
    wire [COL_ADDR_WIDTH-1:0] cur_base_col;
    wire [ROW_ADDR_WIDTH-1:0] cur_krow;
    wire [COL_ADDR_WIDTH-1:0] cur_kcol;

    integer err_cnt;
    integer win_idx;
    integer pix_idx;
    integer exp_base_row;
    integer exp_base_col;
    integer exp_krow;
    integer exp_kcol;
    integer exp_row;
    integer exp_col;

    l1_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .K(K),
        .STRIDE(STRIDE),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .rd_addr_ready(rd_addr_ready),
        .out_fire(out_fire),
        .rd_addr_valid(rd_addr_valid),
        .rd_addr2d(rd_addr2d),
        .rd_addr_last(rd_addr_last),
        .wr_addr_valid(wr_addr_valid),
        .wr_addr2d(wr_addr2d),
        .wr_last(wr_last),
        .busy(busy),
        .win_done(win_done),
        .map_done(map_done),
        .cur_base_row(cur_base_row),
        .cur_base_col(cur_base_col),
        .cur_krow(cur_krow),
        .cur_kcol(cur_kcol)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        rd_addr_ready = 1'b0;
        out_fire = 1'b0;
        err_cnt = 0;

        #40;
        rstn = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for(win_idx = 0; win_idx < TOTAL_WIN; win_idx = win_idx + 1)
        begin
            for(pix_idx = 0; pix_idx < WIN_SIZE; pix_idx = pix_idx + 1)
            begin
                check_read_addr;
                @(negedge clk);
                rd_addr_ready = 1'b1;
                @(posedge clk);
                #1;
                rd_addr_ready = 1'b0;
            end

            @(posedge clk);
            #1;
            if(!wr_addr_valid)
            begin
                $display("ERROR: win=%0d write address should hold after 25 reads", win_idx);
                err_cnt = err_cnt + 1;
            end

            if(wr_addr2d !== {exp_base_row[ROW_ADDR_WIDTH-1:0], exp_base_col[COL_ADDR_WIDTH-1:0]})
            begin
                $display("ERROR: win=%0d wr_addr2d mismatch got_row=%0d got_col=%0d expect_row=%0d expect_col=%0d",
                         win_idx,
                         wr_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH],
                         wr_addr2d[COL_ADDR_WIDTH-1:0],
                         exp_base_row,
                         exp_base_col);
                err_cnt = err_cnt + 1;
            end

            if(wr_last !== (win_idx == TOTAL_WIN - 1))
            begin
                $display("ERROR: win=%0d wr_last=%b expect=%b",
                         win_idx, wr_last, (win_idx == TOTAL_WIN - 1));
                err_cnt = err_cnt + 1;
            end

            @(negedge clk);
            out_fire = 1'b1;
            @(posedge clk);
            #1;
            out_fire = 1'b0;

            if(win_idx == TOTAL_WIN - 1)
            begin
                if(!map_done)
                begin
                    $display("ERROR: map_done should pulse on final out_fire");
                    err_cnt = err_cnt + 1;
                end
            end
        end

        @(posedge clk);
        #1;
        if(busy)
        begin
            $display("ERROR: busy should clear after final map_done");
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d total_win=%0d", err_cnt, TOTAL_WIN);
        #40;
        $finish;
    end

    task check_read_addr;
        begin
            exp_base_row = (win_idx / OUT_W) * STRIDE;
            exp_base_col = (win_idx % OUT_W) * STRIDE;
            exp_krow = pix_idx / K;
            exp_kcol = pix_idx % K;
            exp_row = exp_base_row + exp_krow;
            exp_col = exp_base_col + exp_kcol;

            @(posedge clk);
            #1;

            if(!rd_addr_valid)
            begin
                $display("ERROR: win=%0d pix=%0d rd_addr_valid low", win_idx, pix_idx);
                err_cnt = err_cnt + 1;
            end

            if(cur_base_row !== exp_base_row[ROW_ADDR_WIDTH-1:0] ||
               cur_base_col !== exp_base_col[COL_ADDR_WIDTH-1:0] ||
               cur_krow !== exp_krow[ROW_ADDR_WIDTH-1:0] ||
               cur_kcol !== exp_kcol[COL_ADDR_WIDTH-1:0])
            begin
                $display("ERROR: win=%0d pix=%0d base/k mismatch", win_idx, pix_idx);
                err_cnt = err_cnt + 1;
            end

            if(rd_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH] !== exp_row[ROW_ADDR_WIDTH-1:0] ||
               rd_addr2d[COL_ADDR_WIDTH-1:0] !== exp_col[COL_ADDR_WIDTH-1:0])
            begin
                $display("ERROR: win=%0d pix=%0d rd_addr mismatch got_row=%0d got_col=%0d expect_row=%0d expect_col=%0d",
                         win_idx,
                         pix_idx,
                         rd_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH],
                         rd_addr2d[COL_ADDR_WIDTH-1:0],
                         exp_row,
                         exp_col);
                err_cnt = err_cnt + 1;
            end

            if(rd_addr_last !== (pix_idx == WIN_SIZE - 1))
            begin
                $display("ERROR: win=%0d pix=%0d rd_addr_last=%b expect=%b",
                         win_idx, pix_idx, rd_addr_last, (pix_idx == WIN_SIZE - 1));
                err_cnt = err_cnt + 1;
            end
        end
    endtask

endmodule
