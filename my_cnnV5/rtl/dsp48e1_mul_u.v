`timescale 1ns / 1ns

// DSP48E1 无符号乘法封装
// 1. 直接例化 DSP48E1，避免让 Vivado 自由推断
// 2. 当前只做纯乘法对照实验，不接加法器和级联
// 3. A 侧有效乘法位宽最大 25bit，B 侧最大 18bit
(* keep_hierarchy = "yes" *)
module dsp48e1_mul_u
#(
    parameter A_WIDTH = 13,
    parameter B_WIDTH = 13
)
(
    input  [A_WIDTH-1:0] a,   // A 侧输入
    input  [B_WIDTH-1:0] b,   // B 侧输入

    output [47:0] p           // DSP 原始乘法结果
);

    wire [29:0] a_dsp;
    wire [17:0] b_dsp;

    assign a_dsp = {{(30-A_WIDTH){1'b0}}, a};
    assign b_dsp = {{(18-B_WIDTH){1'b0}}, b};

    // 纯乘法模式: X=0, Y=M, Z=0，最终 P=M
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
        .P(p),
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

endmodule
