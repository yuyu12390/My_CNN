`timescale 1ns / 1ns

module img_in_path_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer DATA_WIDTH = 8;
    localparam integer IMG_W = 28;
    localparam integer IMG_H = 28;
    localparam integer IMAGE_LEN = IMG_W * IMG_H;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer ADDR1D_WIDTH = 10;
    localparam IMAGE_FILE = "C:/Users/28010/Desktop/my_cnn/test/0.txt";

    reg clk;
    reg rstn;
    reg frame_start;
    reg [DATA_WIDTH-1:0] image_tdata;
    reg image_tvalid;
    wire image_tready;
    wire addr_valid;
    wire addr_ready;
    wire [ADDR2D_WIDTH-1:0] addr2d;
    wire addr_last;
    wire frame_busy;
    wire frame_done;
    wire [ROW_ADDR_WIDTH-1:0] cur_row;
    wire [COL_ADDR_WIDTH-1:0] cur_col;
    wire wr_done;
    wire frame_valid;
    reg rd_en;
    reg [ADDR2D_WIDTH-1:0] rd_addr2d;
    reg rd_done;
    wire [DATA_WIDTH-1:0] rd_data;
    wire rd_valid;
    wire [ADDR1D_WIDTH-1:0] dbg_wr_addr1d;
    wire [ADDR1D_WIDTH-1:0] dbg_rd_addr1d;

    reg [7:0] frame0 [0:IMAGE_LEN-1];

    integer fp_img;
    integer rc;
    integer i;
    integer idx;
    integer err_cnt;
    integer wait_cycle;
    reg frame_done_seen;
    reg [ROW_ADDR_WIDTH-1:0] exp_row;
    reg [COL_ADDR_WIDTH-1:0] exp_col;
    reg [ADDR2D_WIDTH-1:0] exp_addr2d;

    img_in_addr_mgr #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH)
    ) u_addr_mgr (
        .clk(clk),
        .rstn(rstn),
        .frame_start(frame_start),
        .addr_valid(addr_valid),
        .addr_ready(addr_ready),
        .addr2d(addr2d),
        .addr_last(addr_last),
        .frame_busy(frame_busy),
        .frame_done(frame_done),
        .cur_row(cur_row),
        .cur_col(cur_col)
    );

    img_in_buf #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),
        .COL_ADDR_WIDTH(COL_ADDR_WIDTH),
        .ADDR2D_WIDTH(ADDR2D_WIDTH),
        .DEPTH(IMAGE_LEN),
        .ADDR1D_WIDTH(ADDR1D_WIDTH)
    ) u_img_buf (
        .clk(clk),
        .rstn(rstn),
        .image_tdata(image_tdata),
        .image_tvalid(image_tvalid),
        .image_tready(image_tready),
        .addr_valid(addr_valid),
        .addr_ready(addr_ready),
        .addr2d(addr2d),
        .addr_last(addr_last),
        .wr_done(wr_done),
        .frame_valid(frame_valid),
        .rd_en(rd_en),
        .rd_addr2d(rd_addr2d),
        .rd_done(rd_done),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .dbg_wr_addr1d(dbg_wr_addr1d),
        .dbg_rd_addr1d(dbg_rd_addr1d)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk) begin
        #1;
        if(frame_done) begin
            frame_done_seen = 1'b1;
        end
    end

    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        frame_start = 1'b0;
        image_tdata = 8'd0;
        image_tvalid = 1'b0;
        rd_en = 1'b0;
        rd_addr2d = {ADDR2D_WIDTH{1'b0}};
        rd_done = 1'b0;
        err_cnt = 0;
        frame_done_seen = 1'b0;

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
        end
        $fclose(fp_img);

        #40;
        rstn = 1'b1;

        start_and_send_frame;
        readback_frame;
        check_final_status;

        $display("SUMMARY: err_cnt=%0d", err_cnt);
        #100;
        $finish;
    end

    task start_and_send_frame;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(negedge clk);
            frame_start = 1'b0;

            image_tvalid = 1'b1;
            image_tdata = frame0[0];
            idx = 0;
            wait_cycle = 0;

            while(idx < IMAGE_LEN) begin
                @(posedge clk);

                if(image_tvalid && addr_valid && addr_ready) begin
                    exp_row = idx / IMG_W;
                    exp_col = idx % IMG_W;

                    if(addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH] !== exp_row) begin
                        $display("ERROR: idx=%0d row=%0d expect=%0d",
                                 idx,
                                 addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH],
                                 exp_row);
                        err_cnt = err_cnt + 1;
                    end

                    if(addr2d[COL_ADDR_WIDTH-1:0] !== exp_col) begin
                        $display("ERROR: idx=%0d col=%0d expect=%0d",
                                 idx,
                                 addr2d[COL_ADDR_WIDTH-1:0],
                                 exp_col);
                        err_cnt = err_cnt + 1;
                    end

                    if(dbg_wr_addr1d !== idx[ADDR1D_WIDTH-1:0]) begin
                        $display("ERROR: idx=%0d addr1d=%0d expect=%0d",
                                 idx, dbg_wr_addr1d, idx);
                        err_cnt = err_cnt + 1;
                    end

                    if(idx < 8) begin
                        $display("WRITE idx=%0d row=%0d col=%0d addr1d=%0d data=%0d last=%b",
                                 idx,
                                 addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH],
                                 addr2d[COL_ADDR_WIDTH-1:0],
                                 dbg_wr_addr1d,
                                 image_tdata,
                                 addr_last);
                    end

                    idx = idx + 1;
                    wait_cycle = 0;
                end
                else begin
                    wait_cycle = wait_cycle + 1;
                    if(wait_cycle > 2000) begin
                        $display("ERROR: input path timeout idx=%0d frame_busy=%b image_tready=%b addr_valid=%b",
                                 idx, frame_busy, image_tready, addr_valid);
                        err_cnt = err_cnt + 1;
                        disable start_and_send_frame;
                    end
                end

                @(negedge clk);
                if(idx < IMAGE_LEN) begin
                    image_tdata = frame0[idx];
                end
            end

            @(negedge clk);
            image_tvalid = 1'b0;
            image_tdata = 8'd0;
        end
    endtask

    task readback_frame;
        begin
            if(!frame_valid) begin
                repeat(3) @(posedge clk);
            end

            for(idx = 0; idx < IMAGE_LEN; idx = idx + 1) begin
                exp_row = idx / IMG_W;
                exp_col = idx % IMG_W;
                exp_addr2d = {exp_row, exp_col};

                @(negedge clk);
                rd_en = 1'b1;
                rd_addr2d = exp_addr2d;

                @(posedge clk);
                #1;

                if(!rd_valid) begin
                    $display("ERROR: read idx=%0d rd_valid low", idx);
                    err_cnt = err_cnt + 1;
                end
                else if(rd_data !== frame0[idx]) begin
                    $display("ERROR: read idx=%0d data=%0d expect=%0d",
                             idx, rd_data, frame0[idx]);
                    err_cnt = err_cnt + 1;
                end
                else if(idx < 8) begin
                    $display("READ idx=%0d row=%0d col=%0d addr1d=%0d data=%0d",
                             idx, exp_row, exp_col, dbg_rd_addr1d, rd_data);
                end
            end

            @(negedge clk);
            rd_en = 1'b0;
            rd_addr2d = {ADDR2D_WIDTH{1'b0}};
            rd_done = 1'b1;
            @(negedge clk);
            rd_done = 1'b0;
        end
    endtask

    task check_final_status;
        begin
            repeat(3) @(posedge clk);

            if(!frame_done_seen) begin
                $display("ERROR: frame_done pulse not observed");
                err_cnt = err_cnt + 1;
            end

            if(frame_busy) begin
                $display("ERROR: frame_busy still high after frame end");
                err_cnt = err_cnt + 1;
            end

            if(addr_valid) begin
                $display("ERROR: addr_valid still high after frame end");
                err_cnt = err_cnt + 1;
            end

            if(frame_valid) begin
                $display("ERROR: frame_valid still high after rd_done");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

endmodule