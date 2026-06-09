`timescale 1ns / 1ns

// FC neuron INT4 packed experiment testbench
// 1. Load identical weights into reference and packed neurons
// 2. Feed identical 32-beat input vectors
// 3. Compare final neuron score exactly
module fc_neuron_pack_sint4_tb;

    reg clk;
    reg rstn;
    reg cfg_weight_valid;
    reg signed [3:0] cfg_weight_data;
    reg cfg_weight_last;
    reg in_valid;
    reg signed [23:0] in_data;
    reg in_last;
    reg out_ready;

    wire ref_cfg_weight_ready;
    wire ref_cfg_weight_done;
    wire ref_in_ready;
    wire ref_out_valid;
    wire signed [19:0] ref_out_data;
    wire ref_busy;
    wire ref_weight_loaded;

    wire pack_cfg_weight_ready;
    wire pack_cfg_weight_done;
    wire pack_in_ready;
    wire pack_out_valid;
    wire signed [19:0] pack_out_data;
    wire pack_busy;
    wire pack_weight_loaded;

    integer case_idx;
    integer err_cnt;
    integer stall_cnt;

    fc_neuron_ref_sint4 u_ref (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(ref_cfg_weight_ready),
        .cfg_weight_done(ref_cfg_weight_done),
        .in_ready(ref_in_ready),
        .out_valid(ref_out_valid),
        .out_data(ref_out_data),
        .busy(ref_busy),
        .weight_loaded(ref_weight_loaded)
    );

    fc_neuron_pack_sint4 u_pack (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(pack_cfg_weight_ready),
        .cfg_weight_done(pack_cfg_weight_done),
        .in_ready(pack_in_ready),
        .out_valid(pack_out_valid),
        .out_data(pack_out_data),
        .busy(pack_busy),
        .weight_loaded(pack_weight_loaded)
    );

    always #5 clk = ~clk;

    function [3:0] to_sint4;
        input integer val;
        begin
            to_sint4 = val[3:0];
        end
    endfunction

    task apply_reset;
        begin
            rstn = 1'b0;
            cfg_weight_valid = 1'b0;
            cfg_weight_data  = 4'sd0;
            cfg_weight_last  = 1'b0;
            in_valid         = 1'b0;
            in_data          = 24'sd0;
            in_last          = 1'b0;
            out_ready        = 1'b1;
            repeat(3) @(posedge clk);
            rstn = 1'b1;
            @(negedge clk);
            repeat(2) @(posedge clk);
        end
    endtask

    task load_weights;
        input integer seed;
        integer i;
        integer wv;
        begin
            for(i = 0; i < 192; i = i + 1)
            begin
                stall_cnt = 0;
                while(!(ref_cfg_weight_ready && pack_cfg_weight_ready))
                begin
                    stall_cnt = stall_cnt + 1;
                    if(stall_cnt > 200)
                    begin
                        $display("TIMEOUT weight_ready case=%0d i=%0d ref_ready=%b pack_ready=%b ref_loaded=%b pack_loaded=%b ref_busy=%b pack_busy=%b",
                                 case_idx, i, ref_cfg_weight_ready, pack_cfg_weight_ready,
                                 ref_weight_loaded, pack_weight_loaded, ref_busy, pack_busy);
                        $finish;
                    end
                    @(posedge clk);
                end

                wv = ((seed + (i * 3)) % 16) - 8;
                @(negedge clk);
                cfg_weight_valid = 1'b1;
                cfg_weight_data  = to_sint4(wv);
                cfg_weight_last  = (i == 191);
                @(posedge clk);
            end

            @(negedge clk);
            cfg_weight_valid = 1'b0;
            cfg_weight_data  = 4'sd0;
            cfg_weight_last  = 1'b0;

            stall_cnt = 0;
            while(!(ref_weight_loaded && pack_weight_loaded))
            begin
                stall_cnt = stall_cnt + 1;
                if(stall_cnt > 50)
                begin
                    $display("TIMEOUT weight_loaded case=%0d ref_loaded=%b pack_loaded=%b ref_done=%b pack_done=%b",
                             case_idx, ref_weight_loaded, pack_weight_loaded,
                             ref_cfg_weight_done, pack_cfg_weight_done);
                    $finish;
                end
                @(posedge clk);
            end
        end
    endtask

    task send_vector;
        input integer seed;
        integer beat_idx;
        integer v0;
        integer v1;
        integer v2;
        integer v3;
        integer v4;
        integer v5;
        begin
            for(beat_idx = 0; beat_idx < 32; beat_idx = beat_idx + 1)
            begin
                stall_cnt = 0;
                while(!(ref_in_ready && pack_in_ready))
                begin
                    stall_cnt = stall_cnt + 1;
                    if(stall_cnt > 200)
                    begin
                        $display("TIMEOUT in_ready case=%0d beat=%0d ref_in_ready=%b pack_in_ready=%b ref_out_valid=%b pack_out_valid=%b",
                                 case_idx, beat_idx, ref_in_ready, pack_in_ready,
                                 ref_out_valid, pack_out_valid);
                        $finish;
                    end
                    @(posedge clk);
                end

                v0 = ((seed + beat_idx + 0) % 16) - 8;
                v1 = ((seed + beat_idx + 2) % 16) - 8;
                v2 = ((seed + beat_idx + 4) % 16) - 8;
                v3 = ((seed + beat_idx + 6) % 16) - 8;
                v4 = ((seed + beat_idx + 8) % 16) - 8;
                v5 = ((seed + beat_idx + 10) % 16) - 8;

                @(negedge clk);
                in_valid = 1'b1;
                in_last  = (beat_idx == 31);
                in_data  = {to_sint4(v5), to_sint4(v4), to_sint4(v3),
                            to_sint4(v2), to_sint4(v1), to_sint4(v0)};
                @(posedge clk);
            end

            @(negedge clk);
            in_valid = 1'b0;
            in_last  = 1'b0;
            in_data  = 24'sd0;
        end
    endtask

    task check_result;
        input integer cid;
        begin
            stall_cnt = 0;
            while(!(ref_out_valid && pack_out_valid))
            begin
                stall_cnt = stall_cnt + 1;
                if(stall_cnt > 200)
                begin
                    $display("TIMEOUT out_valid case=%0d ref_out_valid=%b pack_out_valid=%b ref_busy=%b pack_busy=%b ref_in_ready=%b pack_in_ready=%b",
                             cid, ref_out_valid, pack_out_valid, ref_busy, pack_busy,
                             ref_in_ready, pack_in_ready);
                    $finish;
                end
                @(posedge clk);
            end

            #1;
            if(ref_out_data !== pack_out_data)
            begin
                err_cnt = err_cnt + 1;
                $display("MISMATCH case=%0d ref=%0d pack=%0d", cid, ref_out_data, pack_out_data);
            end
            else
            begin
                $display("CASE_PASS case=%0d score=%0d", cid, ref_out_data);
            end

            @(negedge clk);
            @(posedge clk);
        end
    endtask

    initial
    begin
        clk = 1'b0;
        err_cnt = 0;

        for(case_idx = 0; case_idx < 12; case_idx = case_idx + 1)
        begin
            $display("CASE_START case=%0d", case_idx);
            apply_reset;
            load_weights(case_idx + 1);
            send_vector(case_idx + 3);
            check_result(case_idx);
        end

        if(err_cnt == 0)
        begin
            $display("FC_NEURON_PACK_SINT4_PASS all sampled cases matched.");
        end
        else
        begin
            $display("FC_NEURON_PACK_SINT4_FAIL err_cnt=%0d", err_cnt);
        end

        $finish;
    end

endmodule
