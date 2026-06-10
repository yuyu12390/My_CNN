# FC INT4 DSP Packing 与现有 CNN 结构兼容说明

> 目标：说明 `my_cnnV5` 是如何把第五层 FC 的乘加路径改成 `INT4 DSP packing`，同时尽量不破坏你已经验证通过的 `V4/V5` 整体结构、地址流、权重流和握手接口。

---

## 1. 先说结论

这次改造的核心思路不是“把第五层整层推翻重写”，而是：

1. **保留第五层外部结构不变**
2. **只替换第五层内部单神经元的算术实现**
3. **用一层层 wrapper 把新算术核心塞回你原来的接口框架里**

所以你看到的结果是：

- 上一级 `L4` 到 `L5` 的数据读取方式没变
- `fc_addr_mgr` 还是原来的地址管理方式
- `fc_wgt_dist_raw` 还是原来的串行权重分发方式
- `10` 个输出神经元并行这个结构没变
- 每个神经元还是“每拍吃 6 路输入，共吃 32 拍”的节奏
- 最终输出还是 `10` 个 `32bit score`

真正变化的地方只有一块：

- 原来 `fc_neuron.v` 里面的 `8bit x 8bit` 乘法路径
- 改成了 `fc_neuron_int4_core.v` 里面的：
  - `8bit -> INT4` 量化
  - `2 路 INT4 packing 到 1 个 DSP48E1`
  - `6 路输入 = 3 个 packed DSP`

也就是说，这次不是“改结构”，而是“**保持结构，替换内核**”。

---

## 2. 原始第五层结构是什么

你原来的第五层主链路可以概括成下面这样：

```text
L4 12 路 4x4 特征图
    ↓
fc_addr_mgr
    ↓
每拍取 6 路数据，共 32 拍
    ↓
10 个 fc_neuron 并行
    ↓
输出 10 个分类分数
```

更具体一点：

- 输入来自 `L4`
  - 尺寸是 `12 x 4 x 4`
  - 总共有 `192` 个特征值
- 由于一个 `fc_neuron` 每拍只处理 `6` 路
  - 所以 `12` 路输入被分成 `2` 个 group
  - 每个 group 有 `6 x 4 x 4 = 96` 个值
  - 也就是每个 group 需要 `16` 拍
- 两个 group 加起来一共 `32` 拍

所以第五层的结构性节拍是固定的：

- `LANE_NUM = 6`
- `IN_CH_NUM = 12`
- `GROUP_NUM = 2`
- `BEATS_PER_GROUP = 16`
- `TOTAL_BEATS = 32`

这几个量是你原结构的骨架，**我没有动它们**。

---

## 3. 为什么选第五层先做 INT4 packing

先做第五层，而不是先动卷积层，有几个现实原因：

1. 第五层本来就已经是非常规则的乘加结构
2. 它的数据访问已经被 `fc_addr_mgr` 整理成“每拍 6 路并行”
3. 权重分发已经被 `fc_wgt_dist_raw` 整理成稳定的串行装载流
4. 它比卷积层更容易做“只改算术、不改系统结构”的替换

换句话说，第五层是最适合做这件事的地方：

- 系统边界清楚
- 时序清楚
- 验证也清楚

因此这次 `DSP packing` 不是全网乱改，而是先从 **结构最规整的 FC 层** 下手。

---

## 4. 这次改造坚持的第一原则：外部接口不变

这是最重要的一条。

为了保证能“吻合你的结构”，我没有去改这些外部接口协议：

### 4.1 单神经元接口保持同类风格

原版 `fc_neuron.v` 的核心接口是：

- 权重装载：
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
  - `cfg_weight_ready`
  - `cfg_weight_done`
- 输入计算：
  - `in_valid`
  - `in_data`
  - `in_last`
  - `in_ready`
- 输出结果：
  - `out_valid`
  - `out_data`
  - `out_ready`

新的 `fc_neuron_int4_core.v` 继续保持这个边界。

所以从上层看：

- 它仍然像一个“可预装权重、可流式吃输入、最后吐出结果”的神经元
- 上层并不需要知道它内部已经变成了 `INT4 packing`

### 4.2 第五层顶层接口保持同类风格

原版 `l5_top_raw.v` 的结构性接口有：

- 来自上一级缓存：
  - `src_frame_valid`
  - `src_rd_data`
  - `src_rd_valid`
- 发往上一级缓存：
  - `src_rd_en`
  - `src_rd_addr2d`
  - `src_rd_done`
- 来自权重流：
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
- 对外状态：
  - `ready`
  - `busy`
  - `done`
  - `score_valid`
  - `score_data`

新的 `l5_top_raw_int4_core.v` 与 `l5_top_raw_int4_pack.v` 也继续保持这套边界。

所以从 `CNN.v` 往下接的时候，不需要重做第五层前后级接口。

---

## 5. 改造路径总览：我替换了哪些模块

### 5.1 原始路径

```text
l5_top_raw
    └── 10 x fc_neuron
            └── 6 x 8bit*8bit 乘法
```

### 5.2 新路径

```text
l5_top_raw_int4_pack
    └── l5_top_raw_int4_core
            └── 10 x fc_neuron_int4_core(USE_PACKED=1)
                    └── fc_lane6_pack_sint4
                            └── 3 x pack_mul2_sint4
                                    └── 1 x DSP48E1 / 每个 pack_mul2
```

### 5.3 为了保持结构兼容，我用了三层替换

#### 第一层：单神经元替换

- 原版：`fc_neuron.v`
- 新版：
  - `fc_neuron_int4_core.v`
  - `fc_neuron_int4_pack.v`
  - `fc_neuron_int4_ref.v`

#### 第二层：第五层顶层替换

- 原版：`l5_top_raw.v`
- 新版：
  - `l5_top_raw_int4_core.v`
  - `l5_top_raw_int4_pack.v`
  - `l5_top_raw_int4_ref.v`

#### 第三层：整网选择开关

- 在 `CNN.v` 里加入参数：
  - `USE_L5_INT4_PACK`
- 再额外给一个 wrapper：
  - `CNN_l5_int4_pack.v`

这样做的意义是：

- 原网络入口还在
- 新网络入口也有
- 你可以按 top 来切换
- 不会把整网原始版本直接破坏掉

---

## 6. 真正改掉的是什么：8bit 乘加改成 INT4 量化后再打包

### 6.1 原版单神经元是怎么做的

原版 `fc_neuron.v` 的本质是：

1. 先把 `192` 个权重按原始 `8bit` 串行装进 `weight_mem`
2. 每拍输入 `6` 路 `8bit` 数据
3. 每一路做 `8bit x 8bit`
4. 6 路乘积求和
5. 连续累计 `32` 拍
6. 输出一个神经元结果

这个结构是对的，但对 DSP packing 不友好，因为：

- 它保留的是原始 `8bit` 精度
- 每个乘法天然倾向于“1 路乘法对应 1 个独立算术单元”

### 6.2 新版单神经元怎么改

新的 `fc_neuron_int4_core.v` 改成了两步：

1. **先量化**
2. **再乘法打包**

也就是：

```text
8bit 输入 / 8bit 权重
    ↓
右移 + 饱和裁剪
    ↓
signed INT4
    ↓
2 路打包到 1 个 DSP48E1
    ↓
恢复 2 路 signed 乘积
    ↓
6 路求和
    ↓
32 拍累计
```

---

## 7. INT4 量化到底怎么做

### 7.1 为什么不用改你的外部权重文件和输入格式

这里我特意保留了你原来的输入形式：

- 上一级 `L4` 仍然输出 `8bit`
- `fcw.txt` 仍然按原始 `8bit` 权重流送进来

原因很简单：

- 这样不会破坏你前四层已经验证过的链路
- 也不会要求你重做一套新的 `fcw.txt`
- 你的权重分发模块 `fc_wgt_dist_raw` 可以原样复用

所以量化不是在系统外部做，而是在 **第五层内部** 做。

### 7.2 量化函数逻辑

`fc_neuron_int4_core.v` 里有一个关键函数：

```verilog
function signed [QUANT_WIDTH-1:0] quant_s8_to_s4;
```

它做的事情是：

1. 对输入做算术右移
2. 再做饱和裁剪到 `[-8, 7]`
3. 最终保留为 `signed 4bit`

当前默认参数是：

- `INPUT_SHIFT = 4`
- `WEIGHT_SHIFT = 4`
- `QUANT_WIDTH = 4`

所以量化规则可以理解成：

```text
INT4值 = sat(原始8bit值 >>> 4, -8, 7)
```

### 7.3 为什么要做饱和裁剪

如果只右移、不裁剪，会有两个问题：

1. 超出 `INT4` 范围的数据会溢出
2. 溢出后符号会乱，结果不可控

所以必须做：

- 大于 `7` 的钳到 `7`
- 小于 `-8` 的钳到 `-8`

这样你后面的打包乘法才能有确定行为。

---

## 8. 权重为什么还能和你的原结构吻合

这是你结构兼容的关键之一。

### 8.1 我没有改权重装载顺序

原来 `fc_neuron.v` 的权重顺序约定是：

- `group0`
  - `cin0 ~ cin5`
  - 每个通道 `16` 个空间点
- `group1`
  - `cin6 ~ cin11`
  - 每个通道 `16` 个空间点

新的 `fc_neuron_int4_core.v` 继续使用同样的索引公式：

```text
weight_idx =
    group_idx * (LANE_NUM * BEATS_PER_GROUP)
  + lane_idx  * BEATS_PER_GROUP
  + beat_pos
```

这意味着：

- 权重的排列方式没变
- `fc_wgt_dist_raw` 的输出顺序没变
- `fc_addr_mgr` 发地址的节奏也不用重做

### 8.2 我改的是“存进去的精度”，不是“存放顺序”

也就是说：

- 原版：`weight_mem` 里存 `8bit`
- 新版：`weight_mem` 里存量化后的 `signed 4bit`

但是：

- 第 `0` 个权重还是写到原来第 `0` 个位置
- 第 `191` 个权重还是写到原来第 `191` 个位置

因此你整个第五层的权重调度关系仍然成立。

---

## 9. 输入为什么还能和你的原结构吻合

这也是结构兼容的第二个关键。

### 9.1 输入地址管理器没有换

第五层还是继续用：

- `fc_addr_mgr.v`

它仍然负责：

1. 启动后按 `12 x 4 x 4` 顺序给出二维地址
2. 每拍按 group 取 `6` 路
3. 一共发 `32` 拍
4. 最后一拍打 `last`

### 9.2 我没有改输入读回组织方式

`l5_top_raw_int4_core.v` 仍然保持：

- `src_rd_en`
- `src_rd_addr2d`
- `src_rd_done`

这套控制逻辑不变。

同时，读回后还是先组成：

- `rsp_data_reg`
- `rsp_last_reg`

再统一送给 `10` 个神经元。

这意味着：

- 对上一级缓存来说，它根本不知道你内部是不是 INT4
- 它只知道“第五层还是按原来的方式来读 12 路 4x4 数据”

### 9.3 输入量化是在神经元内部做的

跟权重量化一样，输入量化也不是在外面做的，而是在 `fc_neuron_int4_core.v` 里逐拍完成：

- 每拍拿到 `6` 路 `8bit`
- 每一路执行 `quant_s8_to_s4`
- 再组成 `6` 路 `signed INT4`

所以：

- 上一级 `L4` 的输出格式不需要改
- `L5` 的地址管理不需要改
- 只是进入算术核的那一刻被量化成了 `INT4`

---

## 10. DSP packing 是怎么嵌进 6 路结构里的

这部分是算术核心。

### 10.1 你的第五层天然是 6 路并行

因为单神经元每拍吃：

- `6` 路输入
- 对应 `6` 个权重

所以一拍里本来就有 `6` 个乘法。

这正好适合拆成：

```text
6 路 = 2 路 + 2 路 + 2 路
```

于是我就把它变成：

- `3` 个 `pack_mul2_sint4`
- 每个 `pack_mul2_sint4` 负责 `2` 路 `INT4 x INT4`

### 10.2 6 路 packing 核怎么组织

`fc_lane6_pack_sint4.v` 做的事情很直接：

1. 第 `0/1` 路交给 `u_pack_mul01`
2. 第 `2/3` 路交给 `u_pack_mul23`
3. 第 `4/5` 路交给 `u_pack_mul45`
4. 把 `6` 路结果加起来，得到本拍的 `beat_sum`

也就是说：

- 原来 6 路需要 6 个单路乘法
- 现在 6 路只需要 3 个打包乘法

从结构上看，你的“每拍 6 路并行”没有变；
变的只是“这 6 路并行在 DSP 内部怎么落地”。

---

## 11. `pack_mul2_sint4` 的核心原理

### 11.1 为什么要先拆符号和幅值

`DSP48E1` 最适合做的是一个大的乘法。

但我们这里是：

- 两路 `signed INT4`

为了让两路可以安全打包到一个大乘法里，我采用的做法是：

1. 每一路先拆成：
   - 符号
   - 幅值
2. 先对幅值做“unsigned packing”
3. 最后再把符号恢复回来

也就是：

```text
signed INT4 × signed INT4
    ↓
sign + magnitude
    ↓
magnitude packing multiply
    ↓
recover sign
```

这样做的好处是：

- packing 部分更稳定
- 中间位段更容易分析
- 不容易因为直接 signed 打包而把位解释搞乱

### 11.2 两路是怎么打包的

`pack_mul2_sint4.v` 里，每一路幅值都是 `4bit`。

打包方式是：

```text
pack_a = {a1_mag, 5'b0, a0_mag}
pack_b = {b1_mag, 5'b0, b0_mag}
```

中间留了 `5bit` 空隙。

这个空隙的目的就是：

- 让交叉项落在中间带
- 不污染低路结果
- 也不污染高路结果提取位段

### 11.3 结果怎么拆出来

乘法结果出来后：

- 低路乘积取 `prod_full[7:0]`
- 高路乘积取 `prod_full[25:18]`

然后根据 `p0_neg`、`p1_neg` 再恢复正负号。

所以一个 `pack_mul2_sint4` 最终能给出：

- `p0`
- `p1`

也就是两路原始 signed 乘法的结果。

### 11.4 为什么能对应到 1 个 DSP48E1

在 `pack_mul2_sint4.v` 里，我没有依赖推断，而是直接例化了：

- `DSP48E1`

这样做的目的不是为了“写起来酷”，而是为了两件事：

1. **强制这条 packing 乘法真的落到 DSP 上**
2. **避免 Vivado 自己乱推断成 LUT 或其它结构**

这对做 DSP packing 验证很关键。

---

## 12. 为什么这套 packing 还能吻合你的整网结构

这部分是最关键的回答。

### 12.1 没动层间接口

我没有改：

- `L4 -> L5` 的数据接口
- `L5 -> CNN` 的结果接口

所以整网层级结构还是原来的层级结构。

### 12.2 没动地址流

我没有改：

- `fc_addr_mgr`
- `src_rd_en`
- `src_rd_addr2d`
- `src_rd_done`

所以你的地址分发和上一级缓存交互完全延续原来模式。

### 12.3 没动权重流

我没有改：

- `fc_wgt_dist_raw`
- `cfg_weight_valid/data/last`
- 每个神经元收 `192` 个权重的事实

所以你的权重文件、权重装载顺序、神经元编号逻辑都还能用。

### 12.4 没动输出组织

我没有改：

- `10` 个神经元并行
- `score_valid`
- `score_data[10*32bit]`

所以 `CNN.v` 最后串行吐 `10` 个 score 的逻辑仍然可以复用。

### 12.5 只在“神经元内部算术”这一层换核

真正变化只发生在：

- `fc_neuron` 的内部计算单元

而这恰好是结构最局部、最安全的改造点。

因此你可以把这次改造理解成：

> 第五层的“壳子”没变，变的是壳子里面的乘法发动机。

---

## 13. 我是怎么一步步保证“能替换但不炸结构”的

### 13.1 第一步：先做最底层 packing 原子模块

先做：

- `pack_mul2_sint4.v`
- `ref_mul2_sint4.v`

目的：

- 证明“2 路 signed INT4 -> 1 个 DSP”可行
- 同时保留一个 `ref` 版本做对照

### 13.2 第二步：扩展成 6 路单拍核

再做：

- `fc_lane6_pack_sint4.v`
- `fc_lane6_ref_sint4.v`

目的：

- 对齐你单神经元每拍 `6` 路输入的天然结构
- 证明“6 路 = 3 个 packed DSP”成立

### 13.3 第三步：把 6 路单拍核塞进神经元

再做：

- `fc_neuron_int4_core.v`

目的：

- 保留原来神经元的权重装载、拍计数、累计、输出时序
- 只换中间的“每拍 6 路乘加”实现

### 13.4 第四步：把神经元塞回第五层顶层

再做：

- `l5_top_raw_int4_core.v`

目的：

- 保留 `l5_top_raw.v` 的外层控制壳
- 用 `10` 个新神经元替换 `10` 个老神经元

### 13.5 第五步：把第五层挂回整网

最后做：

- `CNN.v` 增加 `USE_L5_INT4_PACK`
- `CNN_l5_int4_pack.v`

目的：

- 整网可以选择是否使用新第五层
- 原整网链路不被强制破坏

这个分层替换过程，就是“能吻合你结构”的根本原因。

---

## 14. 这次改造保留了哪些你原来的设计思想

虽然第五层算术改了，但下面这些“你的设计思想”我是刻意保留下来的：

### 14.1 先统一装权重，再启动计算

这和你之前一直强调的流程一致：

- 先装权重
- 权重装好后再开始正式计算

新的 INT4 版本没有绕开这一点。

### 14.2 地址管理单独模块化

你不希望计算模块自己乱管地址。

所以现在仍然是：

- `fc_addr_mgr` 管地址
- 神经元只负责“吃数据、做运算”

这和你前面一路开发形成的模块边界保持一致。

### 14.3 计算核尽量只负责吃数据

你之前就强调过：

> 卷积最好只负责吃数据

这次第五层也是同样思路：

- 地址管理不塞进神经元
- 权重分发不塞进神经元
- 神经元只负责：
  - 权重本地存储
  - 输入量化
  - 乘加
  - 输出结果

### 14.4 顶层用 wrapper 做平滑替换

你一直不喜欢因为做实验把整网主干直接搅乱。

所以这次我没有把原 `CNN` 一把改死，而是：

- 参数切换
- wrapper 切换

这样你随时可以：

- 跑原版
- 跑 INT4 ref
- 跑 INT4 pack

---

## 15. 为什么需要 `ref` 版本

这也是结构改造里非常关键的一步。

我不是直接从原版 `8bit FC` 跳到 `pack` 版本，而是中间插了一层：

- `INT4 ref`

目的有两个：

1. 把“数值量化误差”与“packing 实现错误”分开
2. 让你验证时知道问题到底出在哪一层

所以验证关系变成：

```text
原8bit FC
    ↓
INT4 ref
    ↓
INT4 pack
```

这样如果：

- `INT4 ref == INT4 pack`

就说明：

- packing 没有破坏 INT4 算术正确性

如果最终和原 `8bit FC` 有差异，那是量化带来的，不是 packing 本身算错。

这个分层验证方式，能最大限度保护你原来的系统结构和调试节奏。

---

## 16. 模块对应关系总表

| 原结构模块 | 新结构模块 | 变化性质 |
|---|---|---|
| `fc_neuron.v` | `fc_neuron_int4_core.v` | 内部算术改造 |
| 无 | `fc_neuron_int4_pack.v` | wrapper，固定 `USE_PACKED=1` |
| 无 | `fc_neuron_int4_ref.v` | wrapper，固定 `USE_PACKED=0` |
| `l5_top_raw.v` | `l5_top_raw_int4_core.v` | 第五层外壳平移 + 内部实例替换 |
| 无 | `l5_top_raw_int4_pack.v` | wrapper，固定 `USE_PACKED=1` |
| 无 | `l5_top_raw_int4_ref.v` | wrapper，固定 `USE_PACKED=0` |
| `CNN.v` | `CNN.v + USE_L5_INT4_PACK` | 整网增加切换能力 |
| 无 | `CNN_l5_int4_pack.v` | 整网 pack 版本 wrapper |

---

## 17. 这次改造最重要的“兼容性约束”

后面如果你继续扩展或者重构，这几条最好保持：

1. **不要改第五层对上一级缓存的地址接口**
2. **不要改第五层串行权重装载协议**
3. **不要改每个神经元 192 权重、32 拍完成的事实**
4. **不要把地址管理重新塞回神经元**
5. **不要让整网 top 直接强绑某一个实验版本**

只要这几条不破，后面你再做：

- 更 aggressive 的 packing
- 更低 bit 宽
- 卷积层 packing

都还能沿着这条结构继续推进。

---

## 18. Scenario: FC INT4 DSP Packing Must Preserve The Validated L5 Structural Contract

### 1. Scope / Trigger

- Trigger: `my_cnnV5` needed a DSP-packing version of the FC layer, but the user had already validated the full `L1~L5` structural flow and did not want the address path, weight path, or top-level handshake to be rewritten from scratch.

### 2. Signatures

- Original neuron:
  - `fc_neuron.v`
- New neuron core:
  - `fc_neuron_int4_core.v`
- New neuron wrappers:
  - `fc_neuron_int4_pack.v`
  - `fc_neuron_int4_ref.v`
- Original L5 top:
  - `l5_top_raw.v`
- New L5 top:
  - `l5_top_raw_int4_core.v`
  - `l5_top_raw_int4_pack.v`
  - `l5_top_raw_int4_ref.v`
- Whole-network selection:
  - `CNN.v` with `USE_L5_INT4_PACK`
  - `CNN_l5_int4_pack.v`

### 3. Contracts

- Upstream feature-map contract must remain:
  - `src_rd_en`
  - `src_rd_addr2d`
  - `src_rd_done`
  - `src_rd_data`
  - `src_rd_valid`
- Weight-load contract must remain:
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
  - `cfg_weight_ready`
  - `cfg_weight_done`
- Neuron run-time contract must remain:
  - each beat consumes `6` lanes
  - total `32` beats per output neuron
  - total `192` weights per output neuron
- Internal arithmetic may change from `8bit` to `INT4`, but only behind the same external handshake boundary.

### 4. Validation & Error Matrix

- change weight ordering while introducing INT4 -> packed core may be numerically correct locally, but full L5 result will mismatch due to structural misalignment
- change `fc_addr_mgr` traversal together with packing -> hard to distinguish arithmetic bugs from address bugs
- quantize outside the neuron boundary -> forces upstream data-format changes and breaks validated `L4 -> L5` contract
- keep address flow and weight flow unchanged, change only neuron arithmetic -> structural compatibility is preserved and debug scope stays local

### 5. Good/Base/Bad Cases

- Good: `l5_top_raw_int4_pack` keeps the original `L5` control shell and replaces only the neuron arithmetic path.
- Base: `fc_wgt_dist_raw` and `fc_addr_mgr` are reused without protocol changes.
- Bad: rewrite the full `L5` top and upstream interface together with packing, making it impossible to tell whether failures come from packing or structural drift.

### 6. Tests Required

- Run local `INT4 ref` vs `INT4 pack` simulation and assert packed output matches reference output.
- Run `l5_top_raw_int4_tb.v` and compare:
  - `REF_SCORE`
  - `PACK_SCORE`
  - `EXP_SCORE`
- Run whole-network simulation with the `V5` FC path selected and confirm:
  - `10` output scores are produced
  - final predicted class still completes through the original top-level score path

### 7. Wrong vs Correct

#### Wrong

```text
为了做 DSP packing, 直接把第五层地址管理、权重分发、神经元调度一起改掉
```

#### Correct

```text
保留第五层外壳、地址流、权重流、结果流
只把单神经元内部的乘加算术替换成 INT4 + DSP packing
再用 wrapper 一层层挂回原结构
```

---

## 19. 给后续开发的直接建议

如果你后面要继续推进 `V5`，最稳的路线是：

1. 先把当前 `L5 INT4 pack` 整网入口固定好
2. 再考虑是否把 `ref` 链从工程默认源里摘出去
3. 如果要继续研究 packing，优先复用现在这套方法：
   - 先做 `ref`
   - 再做 `pack`
   - 最后再挂回系统

这条路线的优点是：

- 结构不会乱
- 每一层都能单测
- 出问题时容易定位是：
  - 量化问题
  - packing 问题
  - 还是系统接口问题

