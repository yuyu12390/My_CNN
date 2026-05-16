`timescale 1ns / 1ns

// 全局权重分发模块仿真
// 1. 正常路径: 检查顺序、分组、回压保持
// 2. 异常路径: 检查外部 last 提前时只报码不乱序
module wgt_dist_global_tb;

    localparam integer CLK_PERIOD = 20;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer LAYER_ID_WIDTH = 1;
    localparam integer KERNEL_ID_WIDTH = 4;
    localparam integer WEIGHT_IDX_WIDTH = 8;
    localparam integer L0_KERNEL_NUM = 6;
    localparam integer L0_WEIGHT_NUM = 25;
    localparam integer L1_KERNEL_NUM = 12;
    localparam integer L1_WEIGHT_NUM = 150;
    localparam integer DST2D_WIDTH = LAYER_ID_WIDTH + KERNEL_ID_WIDTH;
    localparam integer TOTAL_WEIGHT = (L0_KERNEL_NUM * L0_WEIGHT_NUM) + (L1_KERNEL_NUM * L1_WEIGHT_NUM);

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg weight_ready;

    wire cfg_weight_ready;
    wire weight_valid;
    wire signed [WEIGHT_WIDTH-1:0] weight_data;
    wire [DST2D_WIDTH-1:0] weight_dst2d;
    wire [WEIGHT_IDX_WIDTH-1:0] weight_idx;
    wire dst_last;
    wire load_busy;
    wire load_done;
    wire cfg_last_err;

    integer idx;
    integer err_cnt;
    integer done_seen;
    integer err_pulse_seen;
    integer hold_active;
    integer hold_layer;
    integer hold_kernel;
    integer hold_idx;
    reg [DST2D_WIDTH-1:0] last_dst_seen;
    reg [WEIGHT_IDX_WIDTH-1:0] last_idx_seen;
    reg last_dst_last_seen;

    wgt_dist_global #(
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .LAYER_ID_WIDTH(LAYER_ID_WIDTH),
        .KERNEL_ID_WIDTH(KERNEL_ID_WIDTH),
        .WEIGHT_IDX_WIDTH(WEIGHT_IDX_WIDTH),
        .L0_KERNEL_NUM(L0_KERNEL_NUM),
        .L0_WEIGHT_NUM(L0_WEIGHT_NUM),
        .L1_KERNEL_NUM(L1_KERNEL_NUM),
        .L1_WEIGHT_NUM(L1_WEIGHT_NUM),
        .DST2D_WIDTH(DST2D_WIDTH)
    ) u_wgt_dist_global (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .weight_ready(weight_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .weight_valid(weight_valid),
        .weight_data(weight_data),
        .weight_dst2d(weight_dst2d),
        .weight_idx(weight_idx),
        .dst_last(dst_last),
        .load_busy(load_busy),
        .load_done(load_done),
        .cfg_last_err(cfg_last_err)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
    begin
        #1;

        if(load_done)
        begin
            done_seen = done_seen + 1;
        end

        if(cfg_last_err)
        begin
            err_pulse_seen = err_pulse_seen + 1;
        end

        if(weight_valid && !weight_ready)
        begin
            if(!hold_active)
            begin
                hold_active = 1;
                hold_layer = pick_layer(weight_dst2d);
                hold_kernel = pick_kernel(weight_dst2d);
                hold_idx = weight_idx;
            end
            else
            begin
                if(pick_layer(weight_dst2d) != hold_layer)
                begin
                    $display("ERROR: hold layer changed from %0d to %0d",
                             hold_layer, pick_layer(weight_dst2d));
                    err_cnt = err_cnt + 1;
                end

                if(pick_kernel(weight_dst2d) != hold_kernel)
                begin
                    $display("ERROR: hold kernel changed from %0d to %0d",
                             hold_kernel, pick_kernel(weight_dst2d));
                    err_cnt = err_cnt + 1;
                end

                if(weight_idx != hold_idx[WEIGHT_IDX_WIDTH-1:0])
                begin
                    $display("ERROR: hold idx changed from %0d to %0d",
                             hold_idx, weight_idx);
                    err_cnt = err_cnt + 1;
                end
            end
        end
        else
        begin
            hold_active = 0;
        end

    end

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 8'sd0;
        cfg_weight_last = 1'b0;
        weight_ready = 1'b0;
        err_cnt = 0;
        done_seen = 0;
        err_pulse_seen = 0;
        hold_active = 0;
        hold_layer = 0;
        hold_kernel = 0;
        hold_idx = 0;
        last_dst_seen = {DST2D_WIDTH{1'b0}};
        last_idx_seen = {WEIGHT_IDX_WIDTH{1'b0}};
        last_dst_last_seen = 1'b0;

        #60;
        rstn = 1'b1;

        run_good_case;
        run_bad_last_case;

        if(done_seen != 2)
        begin
            $display("ERROR: done_seen=%0d expect=2", done_seen);
            err_cnt = err_cnt + 1;
        end

        if(err_pulse_seen != 1)
        begin
            $display("ERROR: err_pulse_seen=%0d expect=1", err_pulse_seen);
            err_cnt = err_cnt + 1;
        end

        $display("SUMMARY: err_cnt=%0d done_seen=%0d err_pulse_seen=%0d",
                 err_cnt, done_seen, err_pulse_seen);
        #80;

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

    task run_good_case;
        begin
            $display("CASE1: good full global stream with backpressure");

            for(idx = 0; idx < TOTAL_WEIGHT; idx = idx + 1)
            begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data = idx - 100;
                cfg_weight_last = (idx == TOTAL_WEIGHT - 1);
                weight_ready = ((idx % 17) == 8) ? 1'b0 : 1'b1;
                #1;
                check_one_offer(idx);

                // 回压期间, 目标号和组内编号必须保持不变
                while(!cfg_weight_ready)
                begin
                    @(posedge clk);
                    #1;
                    check_hold_one_offer(idx);

                    @(negedge clk);
                    weight_ready = 1'b1;
                    #1;
                    check_one_offer(idx);
                end

                last_dst_seen = weight_dst2d;
                last_idx_seen = weight_idx;
                last_dst_last_seen = dst_last;
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 8'sd0;
            cfg_weight_last = 1'b0;
            weight_ready = 1'b1;

            repeat(2) @(posedge clk);
            #1;

            if(load_busy)
            begin
                $display("ERROR: load_busy should clear after good full stream");
                err_cnt = err_cnt + 1;
            end

            if(last_dst_seen != pack_dst(1, 11))
            begin
                $display("ERROR: final dst=%0d expect=%0d", last_dst_seen, pack_dst(1, 11));
                err_cnt = err_cnt + 1;
            end

            if(last_idx_seen != (L1_WEIGHT_NUM - 1))
            begin
                $display("ERROR: final idx=%0d expect=%0d", last_idx_seen, L1_WEIGHT_NUM - 1);
                err_cnt = err_cnt + 1;
            end

            if(!last_dst_last_seen)
            begin
                $display("ERROR: final dst_last should be high");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task run_bad_last_case;
        begin
            $display("CASE2: wrong external last should only pulse cfg_last_err");

            for(idx = 0; idx < TOTAL_WEIGHT; idx = idx + 1)
            begin
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data = idx + 23;
                cfg_weight_last = (idx == 10) || (idx == TOTAL_WEIGHT - 1);
                weight_ready = 1'b1;
                #1;
                check_one_offer(idx);
                last_dst_seen = weight_dst2d;
                last_idx_seen = weight_idx;
                last_dst_last_seen = dst_last;
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data = 8'sd0;
            cfg_weight_last = 1'b0;

            repeat(2) @(posedge clk);
            #1;

            if(load_busy)
            begin
                $display("ERROR: load_busy should clear after bad-last stream");
                err_cnt = err_cnt + 1;
            end

            if(last_dst_seen != pack_dst(1, 11))
            begin
                $display("ERROR: bad-last final dst=%0d expect=%0d",
                         last_dst_seen, pack_dst(1, 11));
                err_cnt = err_cnt + 1;
            end

            if(last_idx_seen != (L1_WEIGHT_NUM - 1))
            begin
                $display("ERROR: bad-last final idx=%0d expect=%0d",
                         last_idx_seen, L1_WEIGHT_NUM - 1);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task check_one_offer;
        input integer fire_id;
        integer exp_layer;
        integer exp_kernel;
        integer exp_idx;
        integer exp_len;
        begin
            calc_expect(fire_id, exp_layer, exp_kernel, exp_idx, exp_len);

            if(!weight_valid)
            begin
                $display("ERROR: fire=%0d weight_valid should be high", fire_id);
                err_cnt = err_cnt + 1;
            end

            if(weight_data != cfg_weight_data)
            begin
                $display("ERROR: fire=%0d weight_data=%0d expect=%0d",
                         fire_id, weight_data, cfg_weight_data);
                err_cnt = err_cnt + 1;
            end

            if(pick_layer(weight_dst2d) != exp_layer)
            begin
                $display("ERROR: fire=%0d layer=%0d expect=%0d",
                         fire_id, pick_layer(weight_dst2d), exp_layer);
                err_cnt = err_cnt + 1;
            end

            if(pick_kernel(weight_dst2d) != exp_kernel)
            begin
                $display("ERROR: fire=%0d kernel=%0d expect=%0d",
                         fire_id, pick_kernel(weight_dst2d), exp_kernel);
                err_cnt = err_cnt + 1;
            end

            if(weight_idx != exp_idx[WEIGHT_IDX_WIDTH-1:0])
            begin
                $display("ERROR: fire=%0d weight_idx=%0d expect=%0d",
                         fire_id, weight_idx, exp_idx);
                err_cnt = err_cnt + 1;
            end

            if(dst_last != (exp_idx == (exp_len - 1)))
            begin
                $display("ERROR: fire=%0d dst_last=%b expect=%b",
                         fire_id, dst_last, (exp_idx == (exp_len - 1)));
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task check_hold_one_offer;
        input integer fire_id;
        integer exp_layer;
        integer exp_kernel;
        integer exp_idx;
        integer exp_len;
        begin
            calc_expect(fire_id, exp_layer, exp_kernel, exp_idx, exp_len);

            if(!weight_valid)
            begin
                $display("ERROR: hold fire=%0d weight_valid should stay high", fire_id);
                err_cnt = err_cnt + 1;
            end

            if(pick_layer(weight_dst2d) != exp_layer)
            begin
                $display("ERROR: hold fire=%0d layer=%0d expect=%0d",
                         fire_id, pick_layer(weight_dst2d), exp_layer);
                err_cnt = err_cnt + 1;
            end

            if(pick_kernel(weight_dst2d) != exp_kernel)
            begin
                $display("ERROR: hold fire=%0d kernel=%0d expect=%0d",
                         fire_id, pick_kernel(weight_dst2d), exp_kernel);
                err_cnt = err_cnt + 1;
            end

            if(weight_idx != exp_idx[WEIGHT_IDX_WIDTH-1:0])
            begin
                $display("ERROR: hold fire=%0d weight_idx=%0d expect=%0d",
                         fire_id, weight_idx, exp_idx);
                err_cnt = err_cnt + 1;
            end

            if(dst_last != (exp_idx == (exp_len - 1)))
            begin
                $display("ERROR: hold fire=%0d dst_last=%b expect=%b",
                         fire_id, dst_last, (exp_idx == (exp_len - 1)));
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task calc_expect;
        input integer fire_id;
        output integer exp_layer;
        output integer exp_kernel;
        output integer exp_idx;
        output integer exp_len;
        integer l0_total;
        integer rem;
        begin
            l0_total = L0_KERNEL_NUM * L0_WEIGHT_NUM;
            if(fire_id < l0_total)
            begin
                exp_layer = 0;
                exp_kernel = fire_id / L0_WEIGHT_NUM;
                exp_idx = fire_id % L0_WEIGHT_NUM;
                exp_len = L0_WEIGHT_NUM;
            end
            else
            begin
                rem = fire_id - l0_total;
                exp_layer = 1;
                exp_kernel = rem / L1_WEIGHT_NUM;
                exp_idx = rem % L1_WEIGHT_NUM;
                exp_len = L1_WEIGHT_NUM;
            end
        end
    endtask

    function integer pick_layer;
        input [DST2D_WIDTH-1:0] dst;
        begin
            pick_layer = dst[DST2D_WIDTH-1:KERNEL_ID_WIDTH];
        end
    endfunction

    function integer pick_kernel;
        input [DST2D_WIDTH-1:0] dst;
        begin
            pick_kernel = dst[KERNEL_ID_WIDTH-1:0];
        end
    endfunction

    function [DST2D_WIDTH-1:0] pack_dst;
        input integer layer_id;
        input integer kernel_id;
        begin
            pack_dst = {layer_id[LAYER_ID_WIDTH-1:0], kernel_id[KERNEL_ID_WIDTH-1:0]};
        end
    endfunction

endmodule
