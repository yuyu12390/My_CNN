`timescale 1ns / 1ns

module fc_addr_mgr_tb;

    localparam integer IN_CH_NUM      = 12;
    localparam integer LANE_NUM       = 6;
    localparam integer IMG_W          = 4;
    localparam integer IMG_H          = 4;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH   = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;

    reg clk;
    reg rstn;
    reg start;
    reg rd_addr_ready;

    wire rd_addr_valid;
    wire [IN_CH_NUM-1:0] rd_en;
    wire [IN_CH_NUM*ADDR2D_WIDTH-1:0] rd_addr2d;
    wire rd_addr_last;
    wire busy;
    wire done;
    wire cur_group;
    wire [ROW_ADDR_WIDTH-1:0] cur_row;
    wire [COL_ADDR_WIDTH-1:0] cur_col;

    reg [31:0] beat_cnt;
    reg [31:0] err_cnt;

    integer ch_idx;
    integer exp_group;
    integer exp_row;
    integer exp_col;
    reg [ADDR2D_WIDTH-1:0] addr_i;

    fc_addr_mgr #(
        .IN_CH_NUM(IN_CH_NUM),
        .LANE_NUM(LANE_NUM),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .rd_addr_ready(rd_addr_ready),
        .rd_addr_valid(rd_addr_valid),
        .rd_en(rd_en),
        .rd_addr2d(rd_addr2d),
        .rd_addr_last(rd_addr_last),
        .busy(busy),
        .done(done),
        .cur_group(cur_group),
        .cur_row(cur_row),
        .cur_col(cur_col)
    );

    always #5 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        rd_addr_ready = 1'b0;
        beat_cnt = 32'd0;
        err_cnt = 32'd0;

        repeat(10) @(posedge clk);
        rstn = 1'b1;

        @(posedge clk);
        start <= 1'b1;
        rd_addr_ready <= 1'b1;

        @(posedge clk);
        start <= 1'b0;

        // 中途拉低一拍, 验证 ready 控制住地址推进
        repeat(8) @(posedge clk);
        rd_addr_ready <= 1'b0;
        @(posedge clk);
        rd_addr_ready <= 1'b1;

        wait(done == 1'b1);
        @(posedge clk);

        $display("SUMMARY: err_cnt=%0d beat_cnt=%0d", err_cnt, beat_cnt);
        if(err_cnt == 0)
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
        if(rd_addr_valid && rd_addr_ready)
        begin
            exp_group = beat_cnt / 16;
            exp_row = (beat_cnt % 16) / 4;
            exp_col = beat_cnt % 4;

            if(cur_group !== exp_group)
            begin
                err_cnt <= err_cnt + 1'b1;
                $display("ERROR: group mismatch exp=%0d got=%0d time=%0t", exp_group, cur_group, $time);
            end

            if(cur_row !== exp_row)
            begin
                err_cnt <= err_cnt + 1'b1;
                $display("ERROR: row mismatch exp=%0d got=%0d time=%0t", exp_row, cur_row, $time);
            end

            if(cur_col !== exp_col)
            begin
                err_cnt <= err_cnt + 1'b1;
                $display("ERROR: col mismatch exp=%0d got=%0d time=%0t", exp_col, cur_col, $time);
            end

            for(ch_idx = 0; ch_idx < IN_CH_NUM; ch_idx = ch_idx + 1)
            begin
                addr_i = rd_addr2d[((ch_idx + 1) * ADDR2D_WIDTH) - 1 -: ADDR2D_WIDTH];

                if(addr_i !== {cur_row, cur_col})
                begin
                    err_cnt <= err_cnt + 1'b1;
                    $display("ERROR: addr2d mismatch ch=%0d exp=%0h got=%0h time=%0t",
                             ch_idx, {cur_row, cur_col}, addr_i, $time);
                end

                if(exp_group == 0)
                begin
                    if((ch_idx < 6) && (rd_en[ch_idx] !== 1'b1))
                    begin
                        err_cnt <= err_cnt + 1'b1;
                        $display("ERROR: rd_en low on group0 active lane=%0d time=%0t", ch_idx, $time);
                    end
                    if((ch_idx >= 6) && (rd_en[ch_idx] !== 1'b0))
                    begin
                        err_cnt <= err_cnt + 1'b1;
                        $display("ERROR: rd_en high on group0 inactive lane=%0d time=%0t", ch_idx, $time);
                    end
                end
                else
                begin
                    if((ch_idx < 6) && (rd_en[ch_idx] !== 1'b0))
                    begin
                        err_cnt <= err_cnt + 1'b1;
                        $display("ERROR: rd_en high on group1 inactive lane=%0d time=%0t", ch_idx, $time);
                    end
                    if((ch_idx >= 6) && (rd_en[ch_idx] !== 1'b1))
                    begin
                        err_cnt <= err_cnt + 1'b1;
                        $display("ERROR: rd_en low on group1 active lane=%0d time=%0t", ch_idx, $time);
                    end
                end
            end

            if((beat_cnt == 31) && (rd_addr_last !== 1'b1))
            begin
                err_cnt <= err_cnt + 1'b1;
                $display("ERROR: rd_addr_last should be high on final beat time=%0t", $time);
            end

            beat_cnt <= beat_cnt + 1'b1;
            $display("FC_ADDR beat=%0d group=%0d row=%0d col=%0d rd_en=%b last=%0d",
                     beat_cnt, cur_group, cur_row, cur_col, rd_en, rd_addr_last);
        end
    end

endmodule
