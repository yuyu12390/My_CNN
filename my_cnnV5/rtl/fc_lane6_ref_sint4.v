`timescale 1ns / 1ns

// FC 6 路单拍基线数据通路
// 1. 模拟 FC 神经元单拍 6 路有符号 INT4 乘法
// 2. 内部使用 3 个 ref_mul2_sint4, 总计 6 个 DSP
// 3. 输出 6 路乘积求和结果, 用来和打包版对照
(* keep_hierarchy = "yes" *)
module fc_lane6_ref_sint4
(
    input  signed [23:0] in_data,      // 6 路输入数据, 每路 4bit
    input  signed [23:0] weight_data,  // 6 路权重数据, 每路 4bit

    output signed [11:0] out_sum       // 6 路乘积求和
);

    wire signed [7:0] prod0;
    wire signed [7:0] prod1;
    wire signed [7:0] prod2;
    wire signed [7:0] prod3;
    wire signed [7:0] prod4;
    wire signed [7:0] prod5;

    ref_mul2_sint4 u_ref_mul01 (
        .a0(in_data[3:0]),
        .b0(weight_data[3:0]),
        .a1(in_data[7:4]),
        .b1(weight_data[7:4]),
        .p0(prod0),
        .p1(prod1)
    );

    ref_mul2_sint4 u_ref_mul23 (
        .a0(in_data[11:8]),
        .b0(weight_data[11:8]),
        .a1(in_data[15:12]),
        .b1(weight_data[15:12]),
        .p0(prod2),
        .p1(prod3)
    );

    ref_mul2_sint4 u_ref_mul45 (
        .a0(in_data[19:16]),
        .b0(weight_data[19:16]),
        .a1(in_data[23:20]),
        .b1(weight_data[23:20]),
        .p0(prod4),
        .p1(prod5)
    );

    assign out_sum = $signed({{4{prod0[7]}}, prod0})
                   + $signed({{4{prod1[7]}}, prod1})
                   + $signed({{4{prod2[7]}}, prod2})
                   + $signed({{4{prod3[7]}}, prod3})
                   + $signed({{4{prod4[7]}}, prod4})
                   + $signed({{4{prod5[7]}}, prod5});

endmodule
