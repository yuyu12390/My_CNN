`timescale 1ns / 1ns

module fc_neuron_tb;

    localparam integer LANE_NUM         = 6;
    localparam integer DATA_WIDTH       = 8;
    localparam integer WEIGHT_WIDTH     = 8;
    localparam integer GROUP_NUM        = 2;
    localparam integer BEATS_PER_GROUP  = 16;
    localparam integer TOTAL_WEIGHT_NUM = LANE_NUM * GROUP_NUM * BEATS_PER_GROUP;
    localparam integer OUT_WIDTH        = 32;

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [WEIGHT_WIDTH-1:0] cfg_weight_data;
    reg cfg_weight_last;
    reg in_valid;
    reg signed [LANE_NUM*DATA_WIDTH-1:0] in_data;
    reg in_last;
    reg out_ready;

    wire cfg_weight_ready;
    wire cfg_weight_done;
    wire in_ready;
    wire out_valid;
    wire signed [OUT_WIDTH-1:0] out_data;
    wire busy;
    wire weight_loaded;

    reg signed [7:0] weight_mem [0:TOTAL_WEIGHT_NUM-1];
    reg signed [7:0] input_mem [0:(GROUP_NUM * BEATS_PER_GROUP * LANE_NUM)-1];
    reg signed [31:0] golden_sum;
    reg [31:0] err_cnt;
    reg out_seen;

    integer idx;
    integer beat_idx;
    integer lane_idx;
    integer group_idx;
    integer beat_pos;
    integer weight_sel_idx;
    integer fp_weight;
    integer fp_input;

    fc_neuron #(
        .LANE_NUM(LANE_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .GROUP_NUM(GROUP_NUM),
        .BEATS_PER_GROUP(BEATS_PER_GROUP),
        .TOTAL_WEIGHT_NUM(TOTAL_WEIGHT_NUM),
        .OUT_WIDTH(OUT_WIDTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
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

    initial
    begin
        clk = 1'b0;
        rstn = 1'b0;
        cfg_weight_valid = 1'b0;
        cfg_weight_data = 0;
        cfg_weight_last = 1'b0;
        in_valid = 1'b0;
        in_data = 0;
        in_last = 1'b0;
        out_ready = 1'b0;
        err_cnt = 32'd0;
        out_seen = 1'b0;

        for(idx = 0; idx < TOTAL_WEIGHT_NUM; idx = idx + 1)
        begin
            weight_mem[idx] = 8'sd0;
        end

        for(idx = 0; idx < (GROUP_NUM * BEATS_PER_GROUP * LANE_NUM); idx = idx + 1)
        begin
            input_mem[idx] = 8'sd0;
        end

        // 默认先构造一组确定性数据
        for(idx = 0; idx < TOTAL_WEIGHT_NUM; idx = idx + 1)
        begin
            weight_mem[idx] = $signed((idx % 17) - 8);
        end

        for(idx = 0; idx < (GROUP_NUM * BEATS_PER_GROUP * LANE_NUM); idx = idx + 1)
        begin
            input_mem[idx] = $signed((idx % 11) + 1);
        end

        // 如果存在外部文件, 优先使用外部文件
        fp_weight = $fopen("fc_weight_input.txt", "r");
        if(fp_weight != 0)
        begin
            idx = 0;
            while((idx < TOTAL_WEIGHT_NUM) && ($fscanf(fp_weight, "%d", weight_mem[idx]) == 1))
            begin
                idx = idx + 1;
            end
            $fclose(fp_weight);
        end

        fp_input = $fopen("fc_input_data.txt", "r");
        if(fp_input != 0)
        begin
            idx = 0;
            while((idx < (GROUP_NUM * BEATS_PER_GROUP * LANE_NUM)) && ($fscanf(fp_input, "%d", input_mem[idx]) == 1))
            begin
                idx = idx + 1;
            end
            $fclose(fp_input);
        end

        golden_sum = 32'sd0;
        for(beat_idx = 0; beat_idx < (GROUP_NUM * BEATS_PER_GROUP); beat_idx = beat_idx + 1)
        begin
            group_idx = beat_idx / BEATS_PER_GROUP;
            beat_pos = beat_idx - (group_idx * BEATS_PER_GROUP);

            for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
            begin
                weight_sel_idx = (group_idx * LANE_NUM * BEATS_PER_GROUP)
                               + (lane_idx * BEATS_PER_GROUP)
                               + beat_pos;
                golden_sum = golden_sum
                           + (input_mem[beat_idx * LANE_NUM + lane_idx] * weight_mem[weight_sel_idx]);
            end
        end

        repeat(10) @(posedge clk);
        rstn = 1'b1;

        // 串行装载 192 个权重
        for(idx = 0; idx < TOTAL_WEIGHT_NUM; idx = idx + 1)
        begin
            @(posedge clk);
            while(!cfg_weight_ready)
            begin
                @(posedge clk);
            end
            cfg_weight_valid <= 1'b1;
            cfg_weight_data <= weight_mem[idx];
            cfg_weight_last <= (idx == TOTAL_WEIGHT_NUM - 1);
        end

        @(posedge clk);
        cfg_weight_valid <= 1'b0;
        cfg_weight_data <= 0;
        cfg_weight_last <= 1'b0;

        wait(weight_loaded == 1'b1);
        wait(cfg_weight_done == 1'b1);

        // 32 拍并行送 6 路输入
        for(beat_idx = 0; beat_idx < (GROUP_NUM * BEATS_PER_GROUP); beat_idx = beat_idx + 1)
        begin
            @(posedge clk);
            while(!in_ready)
            begin
                @(posedge clk);
            end

            for(lane_idx = 0; lane_idx < LANE_NUM; lane_idx = lane_idx + 1)
            begin
                in_data[((lane_idx + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] <= input_mem[beat_idx * LANE_NUM + lane_idx];
            end

            in_valid <= 1'b1;
            in_last <= (beat_idx == (GROUP_NUM * BEATS_PER_GROUP - 1));
        end

        @(posedge clk);
        in_valid <= 1'b0;
        in_last <= 1'b0;
        in_data <= 0;

        wait(out_valid == 1'b1);
        out_ready <= 1'b1;
        @(posedge clk);
        out_ready <= 1'b0;

        repeat(10) @(posedge clk);

        $display("FC_EXPECT=%0d", golden_sum);
        $display("FC_GOT=%0d", out_data);
        $display("SUMMARY: err_cnt=%0d weight_loaded=%0d out_seen=%0d", err_cnt, weight_loaded, out_seen);

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
        if(out_valid)
        begin
            out_seen <= 1'b1;
            if(out_data !== golden_sum)
            begin
                err_cnt <= err_cnt + 1'b1;
                $display("ERROR: fc out mismatch exp=%0d got=%0d time=%0t", golden_sum, out_data, $time);
            end
            else
            begin
                $display("FC_OUT_OK value=%0d time=%0t", out_data, $time);
            end
        end
    end

endmodule
