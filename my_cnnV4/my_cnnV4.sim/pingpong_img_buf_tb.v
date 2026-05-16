`timescale 1ns / 1ns

module pingpong_img_buf_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer IMAGE_W = 28;
    localparam integer IMAGE_H = 28;
    localparam integer IMAGE_LEN = IMAGE_W * IMAGE_H;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";

    reg clk;
    reg rstn;
    reg wr_valid;
    reg [7:0] wr_data;
    reg [ADDR2D_WIDTH-1:0] wr_addr2d;
    reg wr_last;
    wire wr_ready;
    wire wr_done;
    reg rd_en;
    reg [ADDR2D_WIDTH-1:0] rd_addr2d;
    wire [7:0] rd_data;
    wire rd_valid;
    reg rd_done;
    wire rd_frame_valid;
    wire wr_bank_sel;
    wire rd_bank_sel;
    wire bank0_valid;
    wire bank1_valid;

    reg [7:0] frame0 [0:IMAGE_LEN-1];
    reg [7:0] frame1 [0:IMAGE_LEN-1];

    integer fp_img;
    integer rc;
    integer i;
    integer err_cnt;

    pingpong_img_buf dut(
        .clk(clk),
        .rstn(rstn),
        .wr_valid(wr_valid),
        .wr_data(wr_data),
        .wr_addr2d(wr_addr2d),
        .wr_last(wr_last),
        .wr_ready(wr_ready),
        .wr_done(wr_done),
        .rd_en(rd_en),
        .rd_addr2d(rd_addr2d),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .rd_done(rd_done),
        .rd_frame_valid(rd_frame_valid),
        .wr_bank_sel(wr_bank_sel),
        .rd_bank_sel(rd_bank_sel),
        .bank0_valid(bank0_valid),
        .bank1_valid(bank1_valid)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        wr_valid = 1'b0;
        wr_data = 8'd0;
        wr_addr2d = {ADDR2D_WIDTH{1'b0}};
        wr_last = 1'b0;
        rd_en = 1'b0;
        rd_addr2d = {ADDR2D_WIDTH{1'b0}};
        rd_done = 1'b0;
        err_cnt = 0;

        fp_img = $fopen(IMAGE_FILE, "r");
        if(fp_img == 0) begin
            $display("ERROR: failed to open %s", IMAGE_FILE);
            $finish;
        end

        for(i = 0; i < IMAGE_LEN; i = i + 1) begin
            rc = $fscanf(fp_img, "%b", frame0[i]);
            if(rc != 1) begin
                $display("ERROR: image preload failed at line %0d", i);
                $finish;
            end
            frame1[i] = (frame0[i] == 8'd127) ? 8'd0 : (frame0[i] + 1'b1);
        end

        $fclose(fp_img);

        #40;
        rstn = 1'b1;

        $display("STEP1: write frame0 into bank0 with forward addr2d");
        write_frame_forward(0);

        if(!rd_frame_valid || !bank0_valid) begin
            $display("ERROR: frame0 write did not make bank0 readable");
            $finish;
        end

        $display("STEP2: read frame0 while writing frame1 with reverse addr2d");
        fork
            read_frame_scan(0, 1'b1);
            write_frame_reverse(1);
        join

        if(!rd_frame_valid || !bank1_valid || (rd_bank_sel != 1'b1)) begin
            $display("ERROR: frame1 did not become active read bank");
            $finish;
        end

        $display("STEP3: read frame1");
        read_frame_scan(1, 1'b1);

        if(rd_frame_valid || bank0_valid || bank1_valid) begin
            $display("ERROR: both banks should be empty after final release");
            $finish;
        end

        $display("SUMMARY: err_cnt=%0d", err_cnt);
        #100;
        $finish;
    end

    task write_frame_forward;
        input integer frame_sel;
        integer row;
        integer col;
        integer idx;
        begin
            @(negedge clk);
            wr_valid = 1'b1;
            for(row = 0; row < IMAGE_H; row = row + 1) begin
                for(col = 0; col < IMAGE_W; col = col + 1) begin
                    idx = row * IMAGE_W + col;
                    if(frame_sel == 0) begin
                        wr_data = frame0[idx];
                    end
                    else begin
                        wr_data = frame1[idx];
                    end
                    wr_addr2d = {row[ROW_ADDR_WIDTH-1:0], col[COL_ADDR_WIDTH-1:0]};
                    wr_last = (idx == IMAGE_LEN - 1);
                    while(!wr_ready) begin
                        @(negedge clk);
                    end
                    @(negedge clk);
                end
            end
            wr_valid = 1'b0;
            wr_data = 8'd0;
            wr_addr2d = {ADDR2D_WIDTH{1'b0}};
            wr_last = 1'b0;
            wait(wr_done == 1'b1);
            @(negedge clk);
        end
    endtask

    task write_frame_reverse;
        input integer frame_sel;
        integer row;
        integer col;
        integer idx;
        integer rev_row;
        integer rev_col;
        begin
            @(negedge clk);
            wr_valid = 1'b1;
            for(idx = 0; idx < IMAGE_LEN; idx = idx + 1) begin
                rev_row = (IMAGE_H - 1) - (idx / IMAGE_W);
                rev_col = (IMAGE_W - 1) - (idx % IMAGE_W);
                row = rev_row;
                col = rev_col;
                if(frame_sel == 0) begin
                    wr_data = frame0[row * IMAGE_W + col];
                end
                else begin
                    wr_data = frame1[row * IMAGE_W + col];
                end
                wr_addr2d = {row[ROW_ADDR_WIDTH-1:0], col[COL_ADDR_WIDTH-1:0]};
                wr_last = (idx == IMAGE_LEN - 1);
                while(!wr_ready) begin
                    @(negedge clk);
                end
                @(negedge clk);
            end
            wr_valid = 1'b0;
            wr_data = 8'd0;
            wr_addr2d = {ADDR2D_WIDTH{1'b0}};
            wr_last = 1'b0;
            wait(wr_done == 1'b1);
            @(negedge clk);
        end
    endtask

    task read_frame_scan;
        input integer frame_sel;
        input release_after_read;
        integer row;
        integer col;
        integer idx;
        reg [7:0] expect_data;
        begin
            wait(rd_frame_valid == 1'b1);
            for(row = 0; row < IMAGE_H; row = row + 1) begin
                for(col = 0; col < IMAGE_W; col = col + 1) begin
                    idx = row * IMAGE_W + col;
                    @(negedge clk);
                    rd_en = 1'b1;
                    rd_addr2d = {row[ROW_ADDR_WIDTH-1:0], col[COL_ADDR_WIDTH-1:0]};
                    @(posedge clk);
                    #1;
                    if(frame_sel == 0) begin
                        expect_data = frame0[idx];
                    end
                    else begin
                        expect_data = frame1[idx];
                    end
                    if(!rd_valid || (rd_data !== expect_data)) begin
                        err_cnt = err_cnt + 1;
                        $display("MISMATCH frame=%0d row=%0d col=%0d got=%0d expect=%0d",
                                 frame_sel, row, col, rd_data, expect_data);
                    end
                    else if(idx < 8) begin
                        $display("MATCH frame=%0d row=%0d col=%0d data=%0d bank=%0d",
                                 frame_sel, row, col, rd_data, rd_bank_sel);
                    end
                end
            end

            @(negedge clk);
            rd_en = 1'b0;
            rd_addr2d = {ADDR2D_WIDTH{1'b0}};

            if(release_after_read) begin
                rd_done = 1'b1;
                @(negedge clk);
                rd_done = 1'b0;
            end
        end
    endtask

endmodule