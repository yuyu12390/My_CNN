`timescale 1ns / 1ns

// FC 单路有符号 8x8 DSP 乘法模块
// 1. 直接例化 1 个 DSP48E1, 强制乘法进入 DSP
// 2. 当前只做纯乘法, 不把加法树并进 DSP
// 3. 输出保持 16bit 有符号结果, 供 FC 神经元后级累加
(* keep_hierarchy = "yes" *)
module fc_mul_dsp_s8
(
    input  signed [7:0] a,      // 输入特征图数据
    input  signed [7:0] b,      // 输入权重数据

    output signed [15:0] p      // 16bit 有符号乘法结果
);

    wire [29:0] a_dsp;
    wire [17:0] b_dsp;
    wire [47:0] p_full;

    assign a_dsp = {{22{a[7]}}, a};
    assign b_dsp = {{10{b[7]}}, b};

    // 纯乘法模式: P = A * B
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
    ) u_dsp48e1_mul (
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
        .P(p_full),
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

    assign p = p_full[15:0];

endmodule