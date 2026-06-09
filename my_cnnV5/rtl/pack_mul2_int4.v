`timescale 1ns / 1ns

// 2路INT4打包乘法
// 1. 把两路4bit无符号数打包成一次大乘法
// 2. 直接例化1个DSP48E1
// 3. 用来和基线版本做DSP占用对照
(* keep_hierarchy = "yes" *)
module pack_mul2_int4
(
    input  [3:0] a0,  // 第0路被乘数
    input  [3:0] b0,  // 第0路乘数
    input  [3:0] a1,  // 第1路被乘数
    input  [3:0] b1,  // 第1路乘数

    output [7:0] p0,  // 第0路乘积
    output [7:0] p1   // 第1路乘积
);

    wire [12:0] pack_a;
    wire [12:0] pack_b;
    wire [29:0] a_dsp;
    wire [17:0] b_dsp;
    wire [47:0] prod_full;

    assign pack_a = {a1, 5'b0, a0};
    assign pack_b = {b1, 5'b0, b0};
    assign a_dsp  = {17'd0, pack_a};
    assign b_dsp  = {5'd0, pack_b};

    (* dont_touch = "true" *)
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .USE_SIMD("ONE48"),
        .ACASCREG(0),
        .ADREG(0),
        .ALUMODEREG(0),
        .AREG(0),
        .BCASCREG(0),
        .BREG(0),
        .CARRYINREG(0),
        .CARRYINSELREG(0),
        .CREG(0),
        .DREG(0),
        .INMODEREG(0),
        .MREG(0),
        .OPMODEREG(0),
        .PREG(0)
    ) u_pack_mul (
        .A(a_dsp),
        .ACIN(30'd0),
        .ALUMODE(4'b0000),
        .B(b_dsp),
        .BCIN(18'd0),
        .C(48'd0),
        .CARRYCASCIN(1'b0),
        .CARRYIN(1'b0),
        .CARRYINSEL(3'b000),
        .CEA1(1'b0),
        .CEA2(1'b0),
        .CEAD(1'b0),
        .CEALUMODE(1'b0),
        .CEB1(1'b0),
        .CEB2(1'b0),
        .CEC(1'b0),
        .CECARRYIN(1'b0),
        .CECTRL(1'b0),
        .CED(1'b0),
        .CEINMODE(1'b0),
        .CEM(1'b0),
        .CEP(1'b0),
        .CLK(1'b0),
        .D(25'd0),
        .INMODE(5'b00000),
        .MULTSIGNIN(1'b0),
        .OPMODE(7'b0000101),
        .PCIN(48'd0),
        .RSTA(1'b0),
        .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0),
        .RSTB(1'b0),
        .RSTC(1'b0),
        .RSTCTRL(1'b0),
        .RSTD(1'b0),
        .RSTINMODE(1'b0),
        .RSTM(1'b0),
        .RSTP(1'b0),
        .P(prod_full),
        .ACOUT(),
        .BCOUT(),
        .CARRYCASCOUT(),
        .CARRYOUT(),
        .MULTSIGNOUT(),
        .OVERFLOW(),
        .PATTERNBDETECT(),
        .PATTERNDETECT(),
        .PCOUT(),
        .UNDERFLOW()
    );

    assign p0 = prod_full[7:0];
    assign p1 = prod_full[25:18];

endmodule
