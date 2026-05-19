`timescale 1ns / 1ns

// 第三层单输出核心仿真
// 1. 顺序给 6 个输入通道切片分别装载 25 个权重
// 2. 连续送入 2 个 5x5 窗口
// 3. 控制台打印每个窗口 6 路部分和求和后的结果
// 4. 自检 RTL 结果是否等于 TB 侧软件求和结果
module l3_out_core_tb;

    localparam CIN_NUM = 6;
    localparam CIN_SEL_WIDTH = 3;
    localparam DATA_WIDTH = 8;
    localparam WEIGHT_WIDTH = 8;
    localparam K = 5;
    localparam OUT_WIDTH = 32;
    localparam WIN_SIZE = K * K;
    localparam WIN_NUM = 2;

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg [CIN_SEL_WIDTH-1:0] cfg_weight_cin;
    reg in_valid;
    reg [CIN_NUM*DATA_WIDTH-1:0] in_data;
    reg in_last;
    reg out_ready;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire in_ready;
    wire out_valid;
    wire signed [OUT_WIDTH-1:0] out_data;
    wire busy;
    wire weight_loaded;

    reg signed [WEIGHT_WIDTH-1:0] weight_mem [0:CIN_NUM-1][0:WIN_SIZE-1];
    reg [DATA_WIDTH-1:0] pixel_mem [0:WIN_NUM-1][0:CIN_NUM-1][0:WIN_SIZE-1];
    reg signed [OUT_WIDTH-1:0] exp_lane_sum [0:WIN_NUM-1][0:CIN_NUM-1];
    reg signed [OUT_WIDTH-1:0] exp_total_sum [0:WIN_NUM-1];

    integer cin_idx;
    integer tap_idx;
    integer win_idx;
    integer err_cnt;
    integer out_cnt;
    integer acc_lane;
    integer acc_total;

    l3_out_core #(
        .CIN_NUM(CIN_NUM),
        .CIN_SEL_WIDTH(CIN_SEL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .K(K),
        .OUT_WIDTH(OUT_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .cfg_weight_cin(cfg_weight_cin),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .busy(busy),
        .weight_loaded(weight_loaded)
    );

    always #5 clk = ~clk;

    task init_case_data;
    begin
        for(cin_idx = 0; cin_idx < CIN_NUM; cin_idx = cin_idx + 1)
        begin
            for(tap_idx = 0; tap_idx < WIN_SIZE; tap_idx = tap_idx + 1)
            begin
                weight_mem[cin_idx][tap_idx] = $signed((cin_idx + 1) + tap_idx);
                pixel_mem[0][cin_idx][tap_idx] = ((cin_idx + 2) * 3 + tap_idx);
                pixel_mem[1][cin_idx][tap_idx] = ((cin_idx + 1) * 5 + (tap_idx * 2));
            end
        end

        for(win_idx = 0; win_idx < WIN_NUM; win_idx = win_idx + 1)
        begin
            exp_total_sum[win_idx] = 0;
            for(cin_idx = 0; cin_idx < CIN_NUM; cin_idx = cin_idx + 1)
            begin
                acc_lane = 0;
                for(tap_idx = 0; tap_idx < WIN_SIZE; tap_idx = tap_idx + 1)
                begin
                    acc_lane = acc_lane
                             + ($signed({1'b0, pixel_mem[win_idx][cin_idx][tap_idx]})
                             * weight_mem[cin_idx][tap_idx]);
                end
                exp_lane_sum[win_idx][cin_idx] = acc_lane;
                exp_total_sum[win_idx] = exp_total_sum[win_idx] + acc_lane;
            end
        end
    end
    endtask

    task send_weight_group;
        input integer target_cin;
    begin
        for(tap_idx = 0; tap_idx < WIN_SIZE; tap_idx = tap_idx + 1)
        begin
            @(posedge clk);
            while(!cfg_weight_ready)
            begin
                @(posedge clk);
            end

            cfg_weight_valid <= 1'b1;
            cfg_weight_data <= weight_mem[target_cin][tap_idx];
            cfg_weight_last <= (tap_idx == (WIN_SIZE - 1));
            cfg_weight_cin <= target_cin[CIN_SEL_WIDTH-1:0];
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= 'd0;
        cfg_weight_last <= 1'b0;
        cfg_weight_cin <= {CIN_SEL_WIDTH{1'b0}};
    end
    endtask

    task send_window;
        input integer target_win;
        reg [CIN_NUM*DATA_WIDTH-1:0] pack_data;
    begin
        for(tap_idx = 0; tap_idx < WIN_SIZE; tap_idx = tap_idx + 1)
        begin
            pack_data = {CIN_NUM*DATA_WIDTH{1'b0}};
            for(cin_idx = 0; cin_idx < CIN_NUM; cin_idx = cin_idx + 1)
            begin
                pack_data[((cin_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = pixel_mem[target_win][cin_idx][tap_idx];
            end

            @(posedge clk);
            while(!in_ready)
            begin
                @(posedge clk);
            end

            in_valid <= 1'b1;
            in_data <= pack_data;
            in_last <= (tap_idx == (WIN_SIZE - 1));
        end

        @(posedge clk);
        in_valid <= 1'b0;
        in_data <= {CIN_NUM*DATA_WIDTH{1'b0}};
        in_last <= 1'b0;
    end
    endtask

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 'd0;
        cfg_weight_last = 1'b0;
        cfg_weight_cin = {CIN_SEL_WIDTH{1'b0}};
        in_valid = 1'b0;
        in_data = {CIN_NUM*DATA_WIDTH{1'b0}};
        in_last = 1'b0;
        out_ready = 1'b1;
        err_cnt = 0;
        out_cnt = 0;

        init_case_data();

        repeat(8) @(posedge clk);
        rstn = 1'b1;
        repeat(2) @(posedge clk);

        for(cin_idx = 0; cin_idx < CIN_NUM; cin_idx = cin_idx + 1)
        begin
            send_weight_group(cin_idx);
        end

        wait(weight_loaded == 1'b1);
        repeat(2) @(posedge clk);

        send_window(0);
        send_window(1);

        wait(out_cnt == WIN_NUM);
        repeat(6) @(posedge clk);

        $display("SUMMARY: err_cnt=%0d out_cnt=%0d weight_loaded=%0d", err_cnt, out_cnt, weight_loaded);
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
        if(cfg_weight_done)
        begin
            $display("CFG_DONE cin=%0d time=%0t", cfg_weight_cin, $time);
        end

        if(out_valid && out_ready)
        begin
            acc_total = exp_total_sum[out_cnt];
            $display("L3_OUT idx=%0d sum=%0d exp=%0d lane0=%0d lane1=%0d lane2=%0d lane3=%0d lane4=%0d lane5=%0d",
                     out_cnt,
                     out_data,
                     acc_total,
                     exp_lane_sum[out_cnt][0],
                     exp_lane_sum[out_cnt][1],
                     exp_lane_sum[out_cnt][2],
                     exp_lane_sum[out_cnt][3],
                     exp_lane_sum[out_cnt][4],
                     exp_lane_sum[out_cnt][5]);

            if(out_data !== exp_total_sum[out_cnt])
            begin
                err_cnt = err_cnt + 1;
                $display("ERR: idx=%0d rtl=%0d exp=%0d", out_cnt, out_data, exp_total_sum[out_cnt]);
            end

            out_cnt = out_cnt + 1;
        end
    end

endmodule
