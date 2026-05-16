`timescale 1ns / 1ns

module l1_wgt_dist_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer LANE_NUM = 6;
    localparam integer LANE_SEL_WIDTH = 3;
    localparam integer K = 5;
    localparam integer WIN_SIZE = K * K;
    localparam integer TOTAL_WEIGHT = LANE_NUM * WIN_SIZE;

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [7:0] cfg_weight_data;
    reg cfg_weight_last;
    reg lane_cfg_weight_ready;

    wire cfg_weight_ready;
    wire lane_cfg_weight_valid;
    wire signed [7:0] lane_cfg_weight_data;
    wire lane_cfg_weight_last;
    wire [LANE_SEL_WIDTH-1:0] lane_cfg_weight_lane;
    wire load_busy;
    wire load_done;
    wire cfg_last_err;
    wire [LANE_SEL_WIDTH-1:0] dbg_lane_idx;
    wire [7:0] dbg_weight_idx;

    integer idx;
    integer err_cnt;
    integer fire_cnt;
    integer exp_lane;
    integer exp_widx;
    integer good_done_seen;
    integer bad_last_seen;

    l1_wgt_dist #(
        .LANE_NUM(LANE_NUM),
        .LANE_SEL_WIDTH(LANE_SEL_WIDTH),
        .WEIGHT_WIDTH(8),
        .K(K)
    ) u_l1_wgt_dist (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .lane_cfg_weight_ready(lane_cfg_weight_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .lane_cfg_weight_valid(lane_cfg_weight_valid),
        .lane_cfg_weight_data(lane_cfg_weight_data),
        .lane_cfg_weight_last(lane_cfg_weight_last),
        .lane_cfg_weight_lane(lane_cfg_weight_lane),
        .load_busy(load_busy),
        .load_done(load_done),
        .cfg_last_err(cfg_last_err),
        .dbg_lane_idx(dbg_lane_idx),
        .dbg_weight_idx(dbg_weight_idx)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
    begin
        #1;

        if(load_done)
        begin
            good_done_seen = good_done_seen + 1;
        end

        if(cfg_last_err)
        begin
            bad_last_seen = bad_last_seen + 1;
        end
    end

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 8'sd0;
        cfg_weight_last = 1'b0;
        lane_cfg_weight_ready = 1'b0;
        err_cnt = 0;
        fire_cnt = 0;
        exp_lane = 0;
        exp_widx = 0;
        good_done_seen = 0;
        bad_last_seen = 0;

        #60;
        rstn = 1'b1;

        run_good_case;
        run_bad_last_case;

        if(good_done_seen != 2)
        begin
            $display("ERROR: good_done_seen=%0d expect=2", good_done_seen);
            err_cnt = err_cnt + 1;
        end

        if(bad_last_seen != 1)
        begin
            $display("ERROR: bad_last_seen=%0d expect=1", bad_last_seen);
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d good_done_seen=%0d bad_last_seen=%0d",
                 err_cnt, good_done_seen, bad_last_seen);
        #80;
        $finish;
    end

    task run_good_case;
        begin
            $display("CASE1: good full weight stream with handshake stall");
            fire_cnt = 0;

            for(idx = 0; idx < TOTAL_WEIGHT; idx = idx + 1)
            begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data = idx - 60;
                cfg_weight_last = (idx == TOTAL_WEIGHT - 1);
                lane_cfg_weight_ready = ((idx % 11) == 5) ? 1'b0 : 1'b1;
                #1;

                while(!cfg_weight_ready)
                begin
                    @(negedge clk);
                    lane_cfg_weight_ready = 1'b1;
                    #1;
                end
                check_one_fire(idx);
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 8'sd0;
            cfg_weight_last = 1'b0;
            lane_cfg_weight_ready = 1'b1;

            repeat(2) @(posedge clk);

            if(load_busy)
            begin
                $display("ERROR: load_busy should clear after good full stream");
                err_cnt = err_cnt + 1;
            end

            if(dbg_lane_idx != 0 || dbg_weight_idx != 0)
            begin
                $display("ERROR: counters should return to zero after good full stream");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task run_bad_last_case;
        begin
            $display("CASE2: early external last should only raise cfg_last_err");
            fire_cnt = 0;

            for(idx = 0; idx < TOTAL_WEIGHT; idx = idx + 1)
            begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data = idx + 7;
                cfg_weight_last = (idx == 10) || (idx == TOTAL_WEIGHT - 1);
                lane_cfg_weight_ready = 1'b1;
                #1;
                check_one_fire(idx);
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 8'sd0;
            cfg_weight_last = 1'b0;

            repeat(2) @(posedge clk);

            if(load_busy)
            begin
                $display("ERROR: load_busy should clear after bad-last stream still completes");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task check_one_fire;
        input integer fire_id;
        begin
            exp_lane = fire_id / WIN_SIZE;
            exp_widx = fire_id % WIN_SIZE;

            if(!lane_cfg_weight_valid)
            begin
                $display("ERROR: fire=%0d lane_cfg_weight_valid should be high", fire_id);
                err_cnt = err_cnt + 1;
            end

            if(lane_cfg_weight_lane != exp_lane[LANE_SEL_WIDTH-1:0])
            begin
                $display("ERROR: fire=%0d lane=%0d expect=%0d",
                         fire_id, lane_cfg_weight_lane, exp_lane);
                err_cnt = err_cnt + 1;
            end

            if(lane_cfg_weight_last != (exp_widx == WIN_SIZE - 1))
            begin
                $display("ERROR: fire=%0d lane_last=%b expect=%b",
                         fire_id, lane_cfg_weight_last, (exp_widx == WIN_SIZE - 1));
                err_cnt = err_cnt + 1;
            end

            fire_cnt = fire_cnt + 1;
        end
    endtask

endmodule
