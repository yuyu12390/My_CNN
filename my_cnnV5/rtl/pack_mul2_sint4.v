`timescale 1ns / 1ns

// 2 路有符号 INT4 打包乘法
// 1. 先把每一路有符号 INT4 转成幅值与符号
// 2. 幅值乘法仍按 2 路 unsigned INT4 打包到 1 个 DSP
// 3. 最后按每一路符号单独恢复有符号乘积
(* keep_hierarchy = "yes" *)
module pack_mul2_sint4
(
    input  signed [3:0] a0,  // 第 0 路被乘数
    input  signed [3:0] b0,  // 第 0 路乘数
    input  signed [3:0] a1,  // 第 1 路被乘数
    input  signed [3:0] b1,  // 第 1 路乘数

    output signed [7:0] p0,  // 第 0 路乘积
    output signed [7:0] p1   // 第 1 路乘积
);

    wire [3:0] a0_mag;
    wire [3:0] b0_mag;
    wire [3:0] a1_mag;
    wire [3:0] b1_mag;

    wire p0_neg;
    wire p1_neg;

    wire [12:0] pack_a;
    wire [12:0] pack_b;
    wire [29:0] a_dsp;
    wire [17:0] b_dsp;
    wire [47:0] prod_full;

    wire [7:0] p0_mag;
    wire [7:0] p1_mag;
    wire signed [8:0] p0_signed_ext;
    wire signed [8:0] p1_signed_ext;

    assign a0_mag = a0[3] ? (~a0 + 1'b1) : a0;
    assign b0_mag = b0[3] ? (~b0 + 1'b1) : b0;
    assign a1_mag = a1[3] ? (~a1 + 1'b1) : a1;
    assign b1_mag = b1[3] ? (~b1 + 1'b1) : b1;

    assign p0_neg = a0[3] ^ b0[3];
    assign p1_neg = a1[3] ^ b1[3];

    assign pack_a = {a1_mag, 5'b0, a0_mag};
    assign pack_b = {b1_mag, 5'b0, b0_mag};
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

    assign p0_mag = prod_full[7:0];
    assign p1_mag = prod_full[25:18];

    assign p0_signed_ext = p0_neg ? -$signed({1'b0, p0_mag}) : $signed({1'b0, p0_mag});
    assign p1_signed_ext = p1_neg ? -$signed({1'b0, p1_mag}) : $signed({1'b0, p1_mag});

    assign p0 = p0_signed_ext[7:0];
    assign p1 = p1_signed_ext[7:0];

endmodule
