conv_l1_case0 说明

1. 本目录用于在 PC 上计算 conv_l1 的黄金卷积结果
2. 当前样例与 conv_l1_tb.v 使用同一组输入窗口和同一组权重
3. 运行 conv_l1_case0.py 后会生成:
   - conv_l1_case0_pixels.txt
   - conv_l1_case0_weights.txt
   - conv_l1_case0_result.txt
4. RTL 仿真应当与 conv_l1_case0_result.txt 完全一致
