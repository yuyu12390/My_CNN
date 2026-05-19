conv_core_case0 说明

1. 本目录用于在 PC 上生成第一层和前两层联调的黄金结果
2. `l1_top6_pc_check.py` 使用真实 `0.txt` 与 `cw.txt` 计算第一层 6 路卷积输出
3. `l1l2_lane0_pc_check.py` 使用真实 `0.txt` 与 `cw.txt` 计算 `l1+l2` 联调中的 lane0 池化输出
4. 这些脚本运行后会重新生成对应的文本结果, 用来和 RTL 仿真控制台输出逐项对比
