`timescale 1ns / 1ns

// 有符号 INT4 打包乘法穷举测试
// 1. 穷举 4 路输入全部 65536 组组合
// 2. 比较打包版与基线版输出是否完全一致
// 3. 通过后再进入更大一级的 FC packing 设计
module pack_mul2_sint4_tb;

    reg signed [3:0] a0;
    reg signed [3:0] b0;
    reg signed [3:0] a1;
    reg signed [3:0] b1;

    wire signed [7:0] ref_p0;
    wire signed [7:0] ref_p1;
    wire signed [7:0] pack_p0;
    wire signed [7:0] pack_p1;

    integer ia0;
    integer ib0;
    integer ia1;
    integer ib1;
    integer err_cnt;

    ref_mul2_sint4 u_ref (
        .a0(a0),
        .b0(b0),
        .a1(a1),
        .b1(b1),
        .p0(ref_p0),
        .p1(ref_p1)
    );

    pack_mul2_sint4 u_pack (
        .a0(a0),
        .b0(b0),
        .a1(a1),
        .b1(b1),
        .p0(pack_p0),
        .p1(pack_p1)
    );

    initial
    begin
        err_cnt = 0;

        for(ia0 = -8; ia0 <= 7; ia0 = ia0 + 1)
        begin
            for(ib0 = -8; ib0 <= 7; ib0 = ib0 + 1)
            begin
                for(ia1 = -8; ia1 <= 7; ia1 = ia1 + 1)
                begin
                    for(ib1 = -8; ib1 <= 7; ib1 = ib1 + 1)
                    begin
                        a0 = ia0[3:0];
                        b0 = ib0[3:0];
                        a1 = ia1[3:0];
                        b1 = ib1[3:0];
                        #1;

                        if((ref_p0 !== pack_p0) || (ref_p1 !== pack_p1))
                        begin
                            err_cnt = err_cnt + 1;
                            $display("MISMATCH a0=%0d b0=%0d a1=%0d b1=%0d | ref=(%0d,%0d) pack=(%0d,%0d)",
                                     ia0, ib0, ia1, ib1, ref_p0, ref_p1, pack_p0, pack_p1);
                        end
                    end
                end
            end
        end

        if(err_cnt == 0)
        begin
            $display("PACK_MUL2_SINT4_PASS all 65536 cases matched.");
        end
        else
        begin
            $display("PACK_MUL2_SINT4_FAIL err_cnt=%0d", err_cnt);
        end

        $finish;
    end

endmodule
