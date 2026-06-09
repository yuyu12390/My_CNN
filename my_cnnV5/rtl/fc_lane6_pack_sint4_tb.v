`timescale 1ns / 1ns

// FC 6 路单拍打包数据通路测试
// 1. 用随机与边界样例比较基线版和打包版
// 2. 重点确认 6 路求和后结果完全一致
// 3. 该实验用于评估 FC 神经元单拍从 6 DSP 降到 3 DSP 的可行性
module fc_lane6_pack_sint4_tb;

    reg signed [23:0] in_data;
    reg signed [23:0] weight_data;

    wire signed [11:0] ref_sum;
    wire signed [11:0] pack_sum;

    integer idx;
    integer err_cnt;

    reg signed [3:0] in_lane [0:5];
    reg signed [3:0] wt_lane [0:5];

    fc_lane6_ref_sint4 u_ref (
        .in_data(in_data),
        .weight_data(weight_data),
        .out_sum(ref_sum)
    );

    fc_lane6_pack_sint4 u_pack (
        .in_data(in_data),
        .weight_data(weight_data),
        .out_sum(pack_sum)
    );

    task load_case;
        input integer base;
        begin
            in_lane[0] = ((base + 0) % 16) - 8;
            in_lane[1] = ((base + 3) % 16) - 8;
            in_lane[2] = ((base + 5) % 16) - 8;
            in_lane[3] = ((base + 7) % 16) - 8;
            in_lane[4] = ((base + 9) % 16) - 8;
            in_lane[5] = ((base + 11) % 16) - 8;

            wt_lane[0] = ((base + 2) % 16) - 8;
            wt_lane[1] = ((base + 4) % 16) - 8;
            wt_lane[2] = ((base + 6) % 16) - 8;
            wt_lane[3] = ((base + 8) % 16) - 8;
            wt_lane[4] = ((base + 10) % 16) - 8;
            wt_lane[5] = ((base + 12) % 16) - 8;

            in_data     = {in_lane[5], in_lane[4], in_lane[3], in_lane[2], in_lane[1], in_lane[0]};
            weight_data = {wt_lane[5], wt_lane[4], wt_lane[3], wt_lane[2], wt_lane[1], wt_lane[0]};
        end
    endtask

    task check_now;
        begin
            #1;
            if(ref_sum !== pack_sum)
            begin
                err_cnt = err_cnt + 1;
                $display("MISMATCH in=%h weight=%h ref_sum=%0d pack_sum=%0d",
                         in_data, weight_data, ref_sum, pack_sum);
            end
        end
    endtask

    initial
    begin
        err_cnt = 0;

        in_data     = 24'sh0;
        weight_data = 24'sh0;
        check_now;

        in_data     = {6{4'sd7}};
        weight_data = {6{4'sd7}};
        check_now;

        in_data     = {6{-4'sd8}};
        weight_data = {6{4'sd7}};
        check_now;

        in_data     = {6{-4'sd8}};
        weight_data = {6{-4'sd8}};
        check_now;

        for(idx = 0; idx < 5000; idx = idx + 1)
        begin
            load_case(idx);
            check_now;
        end

        if(err_cnt == 0)
        begin
            $display("FC_LANE6_PACK_SINT4_PASS all sampled cases matched.");
        end
        else
        begin
            $display("FC_LANE6_PACK_SINT4_FAIL err_cnt=%0d", err_cnt);
        end

        $finish;
    end

endmodule
