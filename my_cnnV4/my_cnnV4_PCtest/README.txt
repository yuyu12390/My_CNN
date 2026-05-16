conv_l1_case0 说明

1. 本目录用于在 PC 上计算 conv_l1 的黄金卷积结果
2. 当前样例与 conv_l1_tb.v 和 l1_top_tb.v 使用同一组输入图像与同一组权重
3. 运行 conv_l1_case0.py 后会生成:
   - conv_l1_case0_pixels.txt
   - conv_l1_case0_weights.txt
   - conv_l1_case0_result.txt
   - conv_l1_case0_feature_map.txt
4. conv_l1_case0_result.txt 是指定窗口的单个卷积和
5. conv_l1_case0_feature_map.txt 是完整的 24x24 卷积结果矩阵
6. l1_top_tb.v 会按顺序读取 feature_map 文件中的 576 个数做逐点比对
7. RTL 仿真结果应当与上述黄金文件完全一致
