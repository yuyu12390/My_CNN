# FPGA RTL Guidelines

> Project-level RTL conventions captured from `my_cnnV4` architecture work.

---

## Convention: Channel-Local Ping-Pong Input Buffer

**What**: When a convolution kernel cannot consume a new sliding-window result every cycle, buffer the full feature map first, then let the compute core read pixels back by address. For the current `my_cnnV4` first-layer direction, each convolution lane may own its own input ping-pong buffer instance.

**Why**:
- It decouples input loading from convolution compute latency.
- It avoids the timing contract imposed by a continuously shifting window register chain.
- It makes later address-generation modules explicit instead of hiding scheduling inside the buffer.

### Required Interface Contract

For image-input ping-pong buffers, keep these boundaries explicit:

- `wr_valid` + `wr_data`: write payload for one pixel
- `wr_addr2d`: external write address in packed 2D form `{row, col}`
- `wr_last`: one-cycle pulse marking the final pixel of the current frame/block
- `wr_ready`: backpressure when the selected write bank is unavailable
- `wr_done`: one-cycle pulse when one full bank has been filled
- `rd_en`: read request for one pixel
- `rd_addr2d`: external read address in packed 2D form `{row, col}`
- `rd_valid` + `rd_data`: synchronous read response
- `rd_done`: explicit release of the current read bank after the consumer finishes the frame/block

### Required Behavior

- A single module contains two banks of identical depth.
- One bank is writable while the other bank is readable.
- The module must unpack the incoming 2D address bus and translate it to linear BRAM address internally.
- The module must not generate convolution traversal addresses internally.
- The module must not generate write traversal addresses internally.
- Read-side code must never assume the writable bank is stable.
- Write-side code must never assume the next address is implicit.
- Frame completion for the write side is declared by external control with `wr_last`.

### Good Pattern

```verilog
pingpong_img_buf u_buf(
    .clk(clk),
    .rstn(rstn),
    .wr_valid(img_wr_valid),
    .wr_data(img_wr_data),
    .wr_addr2d(img_wr_addr2d),
    .wr_last(img_wr_last),
    .wr_ready(img_wr_ready),
    .wr_done(img_wr_done),
    .rd_en(conv_rd_en),
    .rd_addr2d(conv_rd_addr2d),
    .rd_data(conv_rd_data),
    .rd_valid(conv_rd_valid),
    .rd_done(conv_frame_done)
);
```

### Wrong Pattern

- Do not hide convolution traversal state inside the ping-pong buffer.
- Do not couple the buffer to one specific kernel implementation.
- Do not require a sliding-window register chain to remain stable for multiple cycles.
- Do not let the buffer own an internal auto-increment write address for feature-map storage in V4.

### Tests Required

- Write one full `28x28` frame with explicit `wr_addr2d` and verify it becomes readable.
- Read one bank while writing the other bank.
- Write at least one frame with a non-trivial external address order and verify readback still matches the expected `(row, col)` image.
- Release the current read bank with `rd_done` and verify bank hand-off.
- Verify both banks return to empty after the final frame is released.

---

## Scenario: Ping-Pong Buffer Address Ownership

### 1. Scope / Trigger
- Trigger: `my_cnnV4` first-layer buffer contract changed from implicit sequential write addressing to explicit packed-2D external address ownership.

### 2. Signatures
- RTL signature:
  - write side: `wr_valid`, `wr_data`, `wr_addr2d`, `wr_last`, `wr_ready`, `wr_done`
  - read side: `rd_en`, `rd_addr2d`, `rd_data`, `rd_valid`, `rd_done`

### 3. Contracts
- Request fields:
  - `wr_addr2d`: packed address `{row, col}`, where upper bits are row and lower bits are col
  - `wr_last`: asserted only on the final pixel of the current frame/block
  - `rd_addr2d`: packed address `{row, col}` for the pixel to read
- Response fields:
  - `wr_ready`: high only when the selected write bank can accept the incoming pixel
  - `wr_done`: one-cycle pulse after the final pixel has been committed
  - `rd_valid`: high on cycles where `rd_data` corresponds to the requested pixel

### 4. Validation & Error Matrix
- `wr_valid=1` while `wr_ready=0` -> producer must hold address/data until accepted
- `wr_last=1` on a non-final pixel -> bank marked complete too early, considered controller bug
- missing `wr_last` on final pixel -> bank never becomes readable
- malformed `wr_addr2d` or `rd_addr2d` outside legal row/col range -> considered controller bug
- `rd_en=1` while `rd_frame_valid=0` -> no valid frame to serve, `rd_valid` remains low

### 5. Good/Base/Bad Cases
- Good: controller writes the full `28x28` frame with explicit packed row/col addresses and asserts `wr_last` only on the final pixel.
- Base: controller writes in standard raster order and reads back in standard raster order.
- Bad: controller relies on the buffer to infer the next write address.

### 6. Tests Required
- Behavioral simulation covering forward write order, reverse write order, concurrent read/write, and bank hand-off.
- Assertions/checks must confirm `err_cnt=0`, correct `rd_bank_sel` switching, and final empty-bank state.

### 7. Wrong vs Correct
#### Wrong
```verilog
// V4 缓冲模块内部自己推下一个写地址
reg [9:0] wr_addr;
always @(posedge clk) begin
    if(wr_fire) begin
        bank0[wr_addr] <= wr_data;
        wr_addr <= wr_addr + 1'b1;
    end
end
```

#### Correct
```verilog
// V4 由外部地址管理器显式给拼接二维地址
wire [4:0] wr_row;
wire [4:0] wr_col;
wire [9:0] wr_addr_1d;

assign wr_row = wr_addr2d[9:5];
assign wr_col = wr_addr2d[4:0];
assign wr_addr_1d = (wr_row * IMG_W) + wr_col;

always @(posedge clk) begin
    if(wr_fire) begin
        bank0[wr_addr_1d] <= wr_data;
    end
end
```

---

## Design Decision: First V4 Version Prioritizes Structural Decoupling

**Context**: The user wants `my_cnnV4` to avoid the tight coupling seen in earlier versions, even if that costs extra memory in the first implementation.

**Decision**: The first version is allowed to duplicate input image storage per convolution lane if it simplifies control and makes each lane more independent.

**Consequence**:
- Higher RAM cost is acceptable in the first version.
- Shared-input optimization can be introduced later as a separate step.

---

## Convention: RTL Port Ordering And Port Comments

**What**: For handwritten RTL modules in `my_cnnV4`, declare module ports in one input block and one output block. Do not interleave `input` and `output` declarations arbitrarily.

**Why**:
- It makes module boundaries easier to scan during review.
- It reduces wiring mistakes when the design grows.
- It keeps the interface style consistent across address, buffer, and compute modules.

### Required Style

- Put all `input` ports together.
- Put all `output` ports together.
- Keep `clk` and `rstn` at the top of the input block when they exist.
- Add a short port comment for each interface signal or each small signal group.
- Port comments must stay `GB2312` compatible.

### Good Pattern

```verilog
module example_mod
(
    input  clk,          // 时钟
    input  rstn,         // 低有效复位
    input  in_valid,     // 输入有效
    input  [7:0] in_data,// 输入数据

    output in_ready,     // 输入准备好
    output out_valid,    // 输出有效
    output [7:0] out_data// 输出数据
);
```

### Wrong Pattern

```verilog
module example_mod
(
    input  clk,
    output out_valid,
    input  rstn,
    output [7:0] out_data,
    input  [7:0] in_data,
    output in_ready,
    input  in_valid
);
```

### Tests Required

- Review each new RTL module port list and confirm inputs/outputs are grouped.
- Review each new RTL module port list and confirm short interface comments are present.

---

## Convention: Reusable RTL Modules Must Use Functional Names, Not Layer-Tied Names

**What**: If one RTL module is intentionally reused across multiple CNN stages, its public file name and module name must describe the function it performs, not the layer where it was first introduced.

**Why**:
- Layer-tied names such as `conv_l1` or `l1_addr_mgr` become misleading once the same module is reused in later stages.
- Misleading names make top-level integration and review harder, because the reader cannot tell whether a module is truly layer-local or a reusable core.
- The current V4 architecture already reuses the same serial convolution slice and the same window address manager beyond the first layer.

### Required Naming Rule

- Reusable arithmetic kernels use functional names:
  - `conv_core` instead of `conv_l1`
  - keep layer-local wrappers in layer scope, for example `l1_core`, `l3_out_core`
- Reusable traversal / scheduling helpers use functional names:
  - `win_addr_mgr` instead of `l1_addr_mgr`
- Layer-specific tops may still use layer names:
  - `l1_top`
  - `l2_top`
  - `l3_top`
  - `l4_top`
  - `l5_top`

### Good Pattern

```verilog
win_addr_mgr u_win_addr_mgr (...);
conv_core    u_conv_core    (...);
```

### Wrong Pattern

```verilog
// 这个模块已经被第三层复用, 但名字还绑在第一层
l1_addr_mgr u_l3_addr_mgr (...);
conv_l1     u_conv_l3_slice (...);
```

### Tests Required

- Search the codebase after a reusable-module rename and confirm:
  - no old module symbol remains in RTL
  - no old file path remains in project files
  - no old name remains in the active TB / PC check flow
- Re-run at least one regression on every stage that reuses the renamed module.

---

## Scenario: FC Layer DSP Baseline And Packing Entry Point

### 1. Scope / Trigger
- Trigger: `my_cnnV5` will start DSP-packing work from the FC stage first, because the current synthesized network already concentrates its DSP usage in `fc_neuron`.

### 2. Signatures
- Current FC top: `l5_top_raw`
- Current neuron core: `fc_neuron`
- Structural fact from RTL:
  - `l5_top_raw` instantiates `OUT_NUM = 10` neurons
  - each `fc_neuron` consumes `LANE_NUM = 6` signed `8bit` inputs per beat
  - each neuron processes `192` weights in total

### 3. Contracts
- When investigating DSP packing in FC, keep the public ports and timing contract of `l5_top_raw` unchanged first.
- The first optimization target is `fc_neuron` internal multiply path only.
- Weight order, beat order, `in_last`, and final score behavior must remain bit-consistent with the baseline unless an explicit quantization change is being evaluated.

### 4. Validation & Error Matrix
- Packed / refactored `fc_neuron` changes any of the 10 final FC scores -> functional failure
- Packed / refactored `fc_neuron` changes weight loading order -> integration failure
- DSP count changes but FC scores mismatch -> reject optimization result
- FC score matches baseline but DSP count does not move in the expected direction -> inspect synthesis DSP report before changing higher-level modules

### 5. Good / Base / Bad Cases
- Good: optimize only `fc_neuron`, preserve `l5_top_raw` behavior, and verify RTL score output equals the PC baseline.
- Base: the current synthesized CNN uses `50` DSP48E1 in total, and these DSPs are concentrated in the FC stage.
- Bad: start by modifying `conv_core` or changing top-level FC scheduling before the FC neuron DSP baseline is understood.

### 6. Tests Required
- Re-run the FC-related RTL / PC score comparison after every `fc_neuron` arithmetic change.
- Re-run synthesis and record:
  - total `DSP48E1`
  - FC-stage DSP delta
  - LUT / FF delta
  - timing delta
- Keep one baseline report and one post-change report for side-by-side comparison.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 一边研究 DSP packing, 一边改 FC 顶层调度和权重顺序
// 这样一旦结果错了, 很难判断问题来自算术路径还是系统集成
```

#### Correct
```verilog
// 先锁死 l5_top_raw 对外接口和调度
// 只替换 fc_neuron 内部乘法实现
// 然后用 PC / RTL 分数对比验证
```

### Current Project Facts

- `CNN_utilization_synth.rpt` currently reports `50` DSP48E1 in the synthesized network.
- `CNN.vds` final DSP report lists `50` `fc_neuron | A*B` DSP entries.
- Because `l5_top_raw` instantiates `10` identical `fc_neuron` blocks, the current FC baseline is treated as:
  - `5 DSP` per `fc_neuron`
  - `50 DSP` for the full FC stage

---

## Scenario: V5 FC Packing Formal Integration Uses A Parallel INT4 Branch

### 1. Scope / Trigger
- Trigger: after the isolated `pack_mul2_sint4`, `fc_lane6_pack_sint4`, and `fc_neuron_pack_sint4` experiments passed, `my_cnnV5` needs a formal FC-layer integration path that preserves the existing 8bit CNN branch.

### 2. Signatures
- New formal neuron branch:
  - `fc_neuron_int4_core`
  - `fc_neuron_int4_ref`
  - `fc_neuron_int4_pack`
- New formal L5 branch:
  - `l5_top_raw_int4_core`
  - `l5_top_raw_int4_ref`
  - `l5_top_raw_int4_pack`

### 3. Contracts
- The new INT4 branch must keep the same public handshake as `l5_top_raw`:
  - `cfg_weight_valid/cfg_weight_ready/cfg_weight_last`
  - `start/ready/busy/done`
  - `src_rd_en/src_rd_addr2d/src_rd_done`
  - `score_valid/score_data`
- The 8bit source feature map stream and 8bit FC weight stream are quantized only inside the new INT4 branch.
- Default quantization for the first formal branch is:
  - feature input: arithmetic right shift by `INPUT_SHIFT=4`, then saturate to signed INT4
  - FC weight: arithmetic right shift by `WEIGHT_SHIFT=4`, then saturate to signed INT4
- The old `l5_top_raw` and old `fc_neuron` remain untouched as the 8bit baseline.

### 4. Validation & Error Matrix
- `l5_top_raw_int4_ref` and `l5_top_raw_int4_pack` produce different scores under the same stimulus -> packing integration failure
- `l5_top_raw_int4_ref` matches `pack` but both differ from TB expected INT4 result -> quantization or scheduling bug
- INT4 branch changes any 8bit baseline module behavior -> layering violation
- Reusing the experiment modules directly inside `CNN.v` before the formal L5 branch is verified -> forbidden integration order

### 5. Good / Base / Bad Cases
- Good: keep the 8bit network branch intact, add an INT4 FC branch in parallel, and verify `ref = pack = expected`.
- Base: `fc_neuron_int4_core` reuses the proven lane-level packed datapath and only adds explicit 8bit-to-INT4 quantization plus the existing FC scheduling.
- Bad: replace `l5_top_raw` in the main CNN before the INT4 branch has a standalone L5-level regression.

### 6. Tests Required
- Behavioral TB at L5 level that:
  - instantiates both `l5_top_raw_int4_ref` and `l5_top_raw_int4_pack`
  - feeds the same 12-channel `4x4` source maps and the same FC weight stream
  - computes one expected INT4 score set inside the TB
  - checks `ref`, `pack`, and `expected` all match for all 10 outputs
- OOC synthesis comparison that records:
  - `fc_neuron_int4_ref` DSP count
  - `fc_neuron_int4_pack` DSP count
  - `l5_top_raw_int4_ref` DSP count
  - `l5_top_raw_int4_pack` DSP count

### 7. Wrong vs Correct
#### Wrong
```verilog
// 还没做层级联调, 就直接把 CNN.v 里的 l5_top_raw 换掉
// 这样一旦结果错了, 无法分辨是量化问题, 还是打包实现问题, 还是整网集成问题
```

#### Correct
```verilog
// 先保留旧的 8bit l5_top_raw
// 新增 l5_top_raw_int4_ref / l5_top_raw_int4_pack
// 先在 L5 级别做 ref / pack / expected 三方一致性回归
```
- This also means the current `6-lane` FC neuron is **not** mapping to `6 DSP` per neuron. One lane-equivalent multiply is currently being absorbed or reimplemented outside the obvious one-multiply-per-DSP expectation, so baseline auditing must happen before packing claims are made.

### Recommended Optimization Order

1. Keep `l5_top_raw` unchanged.
2. Audit `fc_neuron` first and treat `5 DSP / neuron` as the baseline.
3. Build a small packed-multiply experiment in the V5 sandbox before touching the full FC neuron.
4. Only after the packed arithmetic matches baseline scores should it be integrated back into `fc_neuron`.

---

## Design Decision: FC DSP Packing Must Be Split Into Baseline-Forcing And Packing Experiment

**Context**: The current V4/V5 CNN already classifies correctly, and the user wants to start DSP-packing work from the FC layer because FC is the only stage that already consumes a visible number of DSPs in synthesis.

**Problem**:
- `fc_neuron` code structure is `6` signed `8x8` multiplies per beat.
- Current synthesis result is only `5 DSP / neuron`, not the naive `6 DSP / neuron`.
- This means Vivado is restructuring the arithmetic internally, so if we jump directly into packing we lose the ability to tell whether score mismatches come from packing math or from the original DSP mapping changing under us.

**Decision**: FC optimization work must happen in two stages.

### Stage A: Baseline-Forcing Stage

**Goal**: Make the FC neuron DSP usage deterministic first.

**Required edits**:
- Keep `l5_top_raw` public interface unchanged.
- Keep FC weight load order unchanged.
- Keep FC input beat order unchanged.
- Replace the inferred multiply expressions inside `fc_neuron` with explicit DSP48E1-backed signed multiply wrappers.
- Leave the 6-lane adder tree in logic first.

**Expected result**:
- Functional score output must stay bit-identical to the current FC baseline.
- DSP usage should move from the current `5 DSP / neuron` toward the structural `6 DSP / neuron`.
- For `10` neurons, the FC-stage expectation becomes approximately `60 DSP`.

### Stage B: Packing Experiment Stage

**Goal**: Explore whether multiple low-bit multiplies can be packed into fewer DSPs.

**Required boundary**:
- This stage starts in the V5 sandbox experiment area first, not directly in the CNN mainline.
- Do not replace the production `fc_neuron` with a packed arithmetic core until score agreement and synthesis behavior are both understood.

**Why**:
- Exact signed `INT8` multi-multiply packing into one `DSP48E1` is not a trivial drop-in replacement.
- The current `pack_mul2_int4` experiment proves the resource idea, but it does not yet prove a drop-in path for the production FC neuron.
- The production CNN and the packing experiment must stay separable until arithmetic equivalence or acceptable quantization loss is explicitly verified.

### First Signed Experiment Rule

- The first FC-oriented packing experiment should not start from full signed `INT8`.
- Start with a signed `INT4` experiment that mirrors FC arithmetic structure more closely:
  - baseline: `2` signed `INT4` multiplies -> `2 DSP`
  - packed: convert each operand to `sign + magnitude`, pack the `2` magnitude multiplies into `1 DSP`, then restore each product sign separately in logic
- This keeps the experiment exact, small, and easy to exhaustively verify before moving toward neuron-level packing.

### Second FC-Oriented Experiment Rule

- After the `2-lane` signed `INT4` experiment is proven, the next step is not full-network integration.
- Build a `6-lane` single-beat FC datapath experiment that matches one FC neuron beat structurally:
  - reference path: `3 x ref_mul2_sint4` -> `6 DSP`
  - packed path: `3 x pack_mul2_sint4` -> `3 DSP`
  - both paths must produce the same signed sum of 6 products
- This isolates the exact FC packing leverage before any weight quantization or control-path integration work starts.

### Good Pattern

```verilog
// Stage A: 先强制单路乘法进 DSP
// 6 路乘法仍然是 6 路, 只是把乘法映射方式固定住
// 顶层时序、权重顺序、输入顺序全部不动
```

### Wrong Pattern

```verilog
// 还没固定 baseline, 就直接把 fc_neuron 改成 packed 版本
// 一旦结果错了, 无法判断是 packing 公式错还是原始 DSP 映射变了
```

### Tests Required

- Stage A:
  - Re-run FC RTL / PC score comparison and require all 10 scores bit-match baseline.
  - Re-run synthesis and record DSP delta from `50` to the new FC-stage count.
- Stage B:
  - Keep the small packed multiplier as an isolated synthesis target first.
  - For the first signed experiment, run exhaustive simulation across all signed `INT4` input combinations and require zero mismatches.
  - For the second FC-oriented experiment, compare the `6-lane` packed datapath against the `6-lane` reference datapath and require zero mismatches on the sampled integration set.
  - Only after arithmetic verification passes may it be integrated into a neuron-level experiment.

---

## Scenario: Layer-Boundary Ping-Pong Ownership

### 1. Scope / Trigger
- Trigger: the `my_cnnV4` ping-pong mechanism is defined as a boundary resource between two layers, not as a window-holding helper inside one compute kernel.

### 2. Signatures
- Upstream write-side contract:
  - `wr_valid`, `wr_data`, `wr_addr2d`, `wr_last`, `wr_ready`, `wr_done`
- Downstream read-side contract:
  - `rd_en`, `rd_addr2d`, `rd_valid`, `rd_data`, `rd_done`

### 3. Contracts
- Ownership:
  - the upstream layer owns writes into the current write bank
  - the downstream layer owns reads from the current read bank
- Granularity:
  - one bank stores one complete feature map or one complete image frame for that layer boundary
  - `wr_last` marks that the upstream layer has finished producing the current bank payload
  - `rd_done` marks that the downstream layer has finished consuming the current bank payload
- Role switching:
  - bank read/write roles are switched only at feature-map granularity, never at window granularity
  - for the current serial-MAC first version, one output feature-map compute period is modeled as `Cin * K * K * Wout * Hout`

### 4. Validation & Error Matrix
- switch banks before `wr_last` -> downstream may read an incomplete feature map
- release read bank before downstream asserts `rd_done` -> current feature map may be truncated
- reuse a bank while it is still the active read bank -> layer-boundary data hazard
- treat one window result as one ping-pong cycle -> wrong buffering granularity

### 5. Good/Base/Bad Cases
- Good: previous layer writes a full feature map, next layer reads that full feature map, then bank roles switch.
- Base: one layer writes bank A while the next layer reads bank B, then the roles swap after both sides complete their current feature-map transaction.
- Bad: bank roles toggle every pixel or every window shift.

### 6. Tests Required
- Simulate one full-bank write followed by one full-bank read and explicit `rd_done`.
- Simulate overlapping write/read on opposite banks.
- Check that a bank never becomes writable again until the consumer has released it.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 每来一个窗口就切换一次bank
always @(posedge clk) begin
    if(window_done) begin
        bank_sel <= ~bank_sel;
    end
end
```

#### Correct
```verilog
// 只有完整特征图事务结束后，bank角色才允许切换
assign wr_frame_done = wr_fire && wr_last;
// rd_done 由下一级在读完整帧/完整特征图后显式给出
```

---

## Scenario: Stream-Fed Serial Convolution Kernel

### 1. Scope / Trigger
- Trigger: `my_cnnV4` first-layer convolution is refactored so `conv_core` only consumes a pixel stream during run phase and no longer owns image-cache addressing.

### 2. Signatures
- Weight-load side:
  - `cfg_weight_valid`, `cfg_weight_ready`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_done`
- Pixel-stream side:
  - `in_valid`, `in_ready`, `in_data`, `in_last`
- Result side:
  - `out_valid`, `out_ready`, `out_data`

### 3. Contracts
- The convolution kernel must not generate read addresses for `img_in_buf`.
- The convolution kernel must not generate write addresses for downstream feature-map buffers.
- The first-layer kernel may still have a weight-load phase, but that phase is a unified pre-run stage before window streaming starts.
- One `5x5` window is delivered as `25` serial pixel beats.
- `in_last` marks the last pixel beat of the current window.
- `cfg_weight_last` marks the last weight beat of the current kernel.
- First-layer input pixels are treated as unsigned `8bit`.
- First-layer weights are treated as signed `8bit`.
- The accumulated convolution result is exported as signed `32bit`.
- The kernel may stall the next window when `out_valid=1` and `out_ready=0`.

### 4. Validation & Error Matrix
- `in_valid=1` before weights are fully loaded -> `in_ready` must stay low
- `cfg_weight_valid=1` while a window is being consumed -> weight side must wait
- `out_valid=1` and `out_ready=0` -> result must be held stable, next input window must be stalled
- fewer than `25` weights with `cfg_weight_last=1` -> considered controller bug, kernel still treats this as end of load transaction
- fewer than `25` pixels with `in_last=1` -> considered controller bug, kernel still treats this as end of the current window

### 5. Good/Base/Bad Cases
- Good: in unified startup stage load `25` weights first, then enter run stage and stream `25` pixels for one window, then consume exactly one result.
- Base: downstream accepts the result immediately, so windows are processed back-to-back with one result per `25` input beats.
- Bad: tie the kernel directly to BRAM addresses and make it fetch pixels by itself.

### 6. Tests Required
- Load one full `5x5` weight set and check `cfg_weight_done=1`.
- Stream one `25`-pixel window and verify exactly one `out_valid` pulse and the expected signed result.

---

## Scenario: Third-Layer Raw Weight Order Must Match V1 Baseline

### 1. Scope / Trigger
- Trigger: whole-network `CNN_tb` and PC script matched each other but disagreed with the original `my_cnnV1` prediction on the same `28x28` image and `cw.txt/fcw.txt`.

### 2. Signatures
- Global convolution weight stream:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
- Third-layer local translation fields:
  - `cfg_weight_out`
  - `cfg_weight_cin`
  - `cfg_weight_last`

### 3. Contracts
- The third-layer (`6in12out`) logical kernel weights must follow the original raw `cw.txt` stream order from `my_cnnV1`.
- This order is not `out-major 150 weights per output`.
- Correct order is:
  - `cin0`: `out0~out5`, then `out6~out11`
  - `cin1`: `out0~out5`, then `out6~out11`
  - ...
  - `cin5`: `out0~out5`, then `out6~out11`
- Each `(cin, out)` slice still contains one contiguous `5x5 = 25` tap group.

### 4. Validation & Error Matrix
- Use `150 + out*150 + cin*25` for L3 interpretation -> RTL/PC may stay mutually consistent but whole-network prediction can differ from `V1`
- Align PC script but not RTL -> PC/RTL mismatch
- Align RTL but not PC script -> golden score file mismatch in `CNN_tb`

### 5. Good/Base/Bad Cases
- Good: `test/0.txt + cw.txt + fcw.txt` yields the same final predicted digit as the original `V1` baseline.
- Base: third-layer local translator reconstructs `cfg_weight_cin` and `cfg_weight_out` from the raw stream index before feeding `l3_core`.
- Bad: assume the second convolution layer uses the same weight-major layout as the first layer.

### 6. Tests Required
- Recompute the whole network in PC with the corrected L3 raw-stream order and compare against original `V1` logs.
- Re-run `CNN_tb` and confirm RTL scores match the PC score file.
- Check at least one known sample where filename expectation is known, such as the corrected digit-`0` case.

### 7. Wrong vs Correct
#### Wrong
```python
# 把第三层当成每个输出核连续150个权重
oc_base = 150 + oc * 150
ic_base = oc_base + ic * 25
```

#### Correct
```python
# 第三层沿用V1原始权重流: cin-major -> out-group -> lane -> 25 taps
kbase = 150 + (ic * 300) + (group * 150) + (lane * 25)
```
- Hold `out_ready=0` for at least one cycle after the result appears and verify `out_data` stays stable and `in_ready` stays low.
- Verify `in_ready=0` before weights are loaded.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 卷积核内部自己去遍历图像缓存地址
always @(posedge clk) begin
    if(start_conv) begin
        rd_addr2d <= rd_addr2d + 1'b1;
    end
end
```

#### Correct
```verilog
// 卷积核只吃上游整理好的像素流
assign in_fire = in_valid && in_ready;

always @(posedge clk) begin
    if(in_fire) begin
        acc_reg <= acc_next;
    end
end
```

---

## Scenario: External Image Input Address Ownership

### 1. Scope / Trigger
- Trigger: the first-layer external image input path is split into a dedicated image-input module and a dedicated address manager.

### 2. Signatures
- Address-manager output:
  - packed 2D address `{row, col}`
- Image-buffer module input:
  - `wr_addr2d`
- RAM-side internal signal:
  - linear address `wr_addr_1d`

### 3. Contracts
- The address manager owns 2D traversal order.
- The image-input buffer module must only translate `{row, col}` into `row * IMG_W + col`.
- The image-input buffer module must not internally create raster-order addresses once the external address manager exists.
- For an `IMG_W = 8` example:
  - input 2D sequence `(0,0) (0,1) (0,2) (1,0) (1,1) (1,2) (2,0) (2,1) (2,2)`
  - translated 1D sequence `0 1 2 8 9 10 16 17 18`

### 4. Validation & Error Matrix
- writer module generates addresses internally after the contract is externalized -> ownership violation
- 2D packing order does not match `{row, col}` -> wrong RAM index
- translation uses the wrong image width constant -> all row strides after row 0 are wrong

### 5. Good/Base/Bad Cases
- Good: external control sends packed `{row,col}` and the buffer converts it with `row * IMG_W + col`.
- Base: standard raster-order image loading from `(0,0)` to `(H-1,W-1)`.
- Bad: the buffer auto-increments a hidden linear address counter.

### 6. Tests Required
- Write a known 2D address pattern and confirm the RAM-side 1D addresses are correct.
- Include a non-zero-row case such as `(2,2)` to verify row-stride multiplication.
- Verify the write path still works when addresses are not generated internally.

### 7. Wrong vs Correct
#### Wrong
```verilog
always @(posedge clk) begin
    if(wr_fire) begin
        wr_addr_1d <= wr_addr_1d + 1'b1;
    end
end
```

#### Correct
```verilog
assign wr_row = wr_addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
assign wr_col = wr_addr2d[COL_ADDR_WIDTH-1:0];
assign wr_addr_1d = (wr_row * IMG_W) + wr_col;
```

---

## Scenario: First-Layer Image Input Front-End Split

### 1. Scope / Trigger
- Trigger: the V4 first-layer input path is split into an address manager and an image-input buffer module with internal RAM.

### 2. Signatures
- Address manager:
  - input: `frame_start`
  - handshake: `addr_valid`, `addr_ready`
  - payload: `addr2d`, `addr_last`
  - status: `frame_busy`, `frame_done`, `cur_row`, `cur_col`
- Image-input buffer:
  - input stream: `image_tvalid`, `image_tready`, `image_tdata`
  - address side: `addr_valid`, `addr_ready`, `addr2d`, `addr_last`
  - internal storage: RAM / inferred memory
  - read side: `rd_en`, `rd_addr2d`, `rd_data`, `rd_valid`, `rd_done`

### 3. Contracts
- `img_in_addr_mgr` owns only 2D address traversal.
- `img_in_buf` owns 2D-to-1D translation and owns the image RAM.
- `img_in_buf` must convert `{row,col}` into `row * IMG_W + col` internally before indexing memory.
- The first accepted address must be `(0,0)`.
- The final accepted address must be `(IMG_H-1, IMG_W-1)`.
- The write path marks one full image as valid only after the final accepted write beat.

---

## Scenario: FC Single-Neuron Stream Contract

### 1. Scope / Trigger
- Trigger: `my_cnnV4` fifth layer reuses the V4 stream/handshake style instead of directly copying the original monolithic FC scheduling.

### 2. Signatures
- Weight-load side:
  - `cfg_weight_valid`, `cfg_weight_ready`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_done`
- Input-vector side:
  - `in_valid`, `in_ready`, `in_data[LANE_NUM*DATA_WIDTH-1:0]`, `in_last`
- Result side:
  - `out_valid`, `out_ready`, `out_data`

### 3. Contracts
- One `fc_neuron` instance owns exactly one output neuron.
- The neuron must preload its full weight set before accepting runtime input data.
- Current V4 FC base contract uses:
  - `LANE_NUM = 6`
  - `GROUP_NUM = 2`
  - `BEATS_PER_GROUP = 16`
  - total beats per inference = `32`
  - total weights per neuron = `192`
- Runtime input format:
  - each beat carries `6` signed `8bit` values in parallel
  - first 16 beats correspond to input channels `0~5`
  - next 16 beats correspond to input channels `6~11`
- Weight layout inside one neuron:
  - first `96` weights map to group0 (`6 x 16`)
  - next `96` weights map to group1 (`6 x 16`)
  - within each group, weights are stored channel-major then spatial-minor
- `in_last` marks the final beat of the current neuron input vector.
- `out_valid` must hold until `out_ready`.

### 4. Validation & Error Matrix
- `in_valid=1` before `weight_loaded=1` -> `in_ready` must stay low
- `cfg_weight_valid=1` while runtime input is active -> weight side must wait for `cfg_weight_ready`
- fewer than `192` weights with `cfg_weight_last=1` -> controller bug, module still closes the preload transaction
- fewer than `32` runtime beats with `in_last=1` -> controller bug, module still closes the current inference transaction
- `out_valid=1` and `out_ready=0` -> result must be held stable

### 5. Good/Base/Bad Cases
- Good: preload 192 weights, then send 32 beats of 6-lane input, then consume exactly one 32bit score.
- Base: downstream accepts the score immediately and the neuron returns to idle.
- Bad: make the neuron generate upper-layer read addresses by itself.

### 6. Tests Required
- Load one full 192-weight set and check `cfg_weight_done=1`.
- Send one complete 32-beat input vector and verify one `out_valid` pulse with the expected signed sum.
- Hold `out_ready=0` for at least one cycle after `out_valid=1` and verify result stability.

### 7. Wrong vs Correct
#### Wrong
```verilog
// FC 绁炵粡鍏冨唴閮ㄧ洿鎺ヨ嚜宸卞幓绠′笂涓€绾х紦瀛樺湴鍧€
always @(posedge clk) begin
    if(start_fc) begin
        rd_addr2d <= rd_addr2d + 1'b1;
    end
end
```

#### Correct
```verilog
// FC 绁炵粡鍏冨彧鍚?6 璺苟琛岃緭鍏ユ祦, 涓嶆嫢鏈夊湴鍧€閬嶅巻
assign in_fire = in_valid && in_ready;

always @(posedge clk) begin
    if(in_fire) begin
        acc_reg <= acc_next_comb;
    end
end
```

---

## Scenario: FC Address Manager Contract

### 1. Scope / Trigger
- Trigger: the fifth-layer FC input is read from the fourth-layer `12 x 4 x 4` feature-map boundary using an explicit address manager.

### 2. Signatures
- Start/handshake:
  - `start`, `rd_addr_valid`, `rd_addr_ready`, `done`, `busy`
- Read-side payload:
  - `rd_en[11:0]`
  - `rd_addr2d[12*ADDR2D_WIDTH-1:0]`
  - `rd_addr_last`
- Debug/status:
  - `cur_group`, `cur_row`, `cur_col`

### 3. Contracts
- `fc_addr_mgr` owns only traversal order, not data storage and not MAC computation.
- One full FC read transaction is exactly `32` accepted beats:
  - beats `0~15`: enable channels `0~5`
  - beats `16~31`: enable channels `6~11`
- On each beat, the active 6 lanes share the same packed 2D address `{row,col}`.
- Spatial order is raster order on `4x4`:
  - `(0,0)` to `(0,3)`
  - `(1,0)` to `(1,3)`
  - `(2,0)` to `(2,3)`
  - `(3,0)` to `(3,3)`
- The manager may advance only on `rd_addr_valid && rd_addr_ready`.
- `rd_addr_last` is asserted only on the final accepted beat of the full 32-beat transaction.

### 4. Validation & Error Matrix
- `rd_addr_ready=0` -> group/row/col must hold
- inactive channel lane has `rd_en=1` -> address fanout bug
- active channel lane has `rd_en=0` -> data starvation bug
- `rd_addr_last=1` before beat 31 -> premature end bug

### 5. Good/Base/Bad Cases
- Good: address manager outputs 32 accepted beats and switches from group0 to group1 exactly after the first 16 beats.
- Base: a single downstream FC neuron consumes all 32 beats.
- Bad: make the FC compute module infer channel grouping by itself.

### 6. Tests Required
- Simulate one full 32-beat run and verify:
  - group0 active mask `000000111111`
  - group1 active mask `111111000000`
  - raster-order `{row,col}`
  - `rd_addr_last=1` only on beat 31
- Insert at least one `rd_addr_ready=0` stall and verify counters hold.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 鏈?FC 妯″潡閲岄殣寮忔帹鏂璇诲摢 6 璺?
assign lane_sel = beat_cnt[4];
```

#### Correct
```verilog
// 鐢盳c_addr_mgr 鏄惧紡缁欏嚭鍝簺閫氶亾鍦ㄥ綋鍓嶆媿鏈夋晥
assign rd_fire = rd_addr_valid && rd_addr_ready;
assign rd_en[5:0] = (cur_group == 0);
assign rd_en[11:6] = (cur_group == 1);
```

---

## Scenario: Global Weight Stream Extended To FC Layer

### 1. Scope / Trigger
- Trigger: `wgt_dist_global` is extended so the same global preload flow can also feed the FC layer.

### 2. Signatures
- Existing interface remains unchanged:
  - input: `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`, `weight_ready`
  - output: `cfg_weight_ready`, `weight_valid`, `weight_data`, `weight_dst2d`, `weight_idx`, `dst_last`, `load_busy`, `load_done`, `cfg_last_err`
- New parameters:
  - `ENABLE_L2`
  - `L2_KERNEL_NUM`
  - `L2_WEIGHT_NUM`

### 3. Contracts
- Default compatibility mode:
  - `ENABLE_L2 = 0`
  - behavior must remain exactly the old two-stage stream:
    - `(0,0)~(0,5)` with 25 weights each
    - `(1,0)~(1,11)` with 150 weights each
- FC-extended mode:
  - requires `LAYER_ID_WIDTH >= 2`
  - `ENABLE_L2 = 1`
  - append the FC segment after layer1:
    - `(2,0)~(2,9)` with 192 weights each
- Internal target progression is driven only by successful handshake and internal counters, not by external `cfg_weight_last`.
- `cfg_weight_last` is validation-only and must match the actual final configured destination.

### 4. Validation & Error Matrix
- `ENABLE_L2=1` with `LAYER_ID_WIDTH=1` -> FC segment is disabled by contract
- external `cfg_weight_last` mismatches the internally expected final beat -> pulse `cfg_last_err`
- downstream backpressure -> target id and `weight_idx` must hold

### 5. Good/Base/Bad Cases
- Good: old first-layer and third-layer tops continue to work unchanged with default parameters.
- Base: FC top widens `LAYER_ID_WIDTH` to `2` and enables the third segment.
- Bad: change the meaning of the existing first two stream segments while extending FC support.

### 6. Tests Required
- Re-run existing L1/L3 global-weight simulations with default parameters and verify no behavior change.
- In FC-enabled mode, verify the global target sequence reaches `(2, last_kernel)` only after layer1 completes.
- Verify `load_done=1` only on the truly final enabled segment.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 鎵╁睍 FC 鏃剁洿鎺ユ敼鎺夊師鏈夊眰鍙风紪鐮?
assign LAYER1_ID = 2;
```

#### Correct
```verilog
// 淇濇寔鏃ф祦姘村叏鍏煎, FC 鍙湪鍙傛暟寮€鍚椂杩藉姞绗笁娈?
parameter ENABLE_L2 = 0;
parameter L2_KERNEL_NUM = 10;
parameter L2_WEIGHT_NUM = 192;
```

---

## Scenario: FC Top-Level Boundary Contract

### 1. Scope / Trigger
- Trigger: the fifth layer is promoted from standalone `fc_neuron` / `fc_addr_mgr` blocks to a complete `l5_top` that consumes fourth-layer feature-map buffers and produces 10 class scores.

### 2. Signatures
- Upstream feature-map side:
  - input: `src_frame_valid[11:0]`, `src_rd_data[12*8-1:0]`, `src_rd_valid[11:0]`
  - output: `src_rd_en[11:0]`, `src_rd_addr2d[12*ADDR2D_WIDTH-1:0]`, `src_rd_done[11:0]`
- Global weight side:
  - input: `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
  - output: `cfg_weight_ready`, `cfg_weight_done`, `cfg_last_err`
- Score side:
  - input: `score_ready`
  - output: `score_valid`, `score_data[10*32-1:0]`
- Control/status:
  - input: `start`
  - output: `ready`, `busy`, `done`, `weight_loaded`

### 3. Contracts
- `l5_top` owns only:
  - FC-target weight routing from `wgt_dist_global`
  - FC read-address launch through `fc_addr_mgr`
  - packing 12 single-lane buffer returns into one 6-lane input beat for all FC neurons
- `l5_top` must not own upstream BRAM address translation or storage internals.
- Current baseline topology is:
  - 12 single-channel upstream feature-map buffers
  - 1 shared `fc_addr_mgr`
  - 10 parallel `fc_neuron`
- One FC runtime transaction is:
  - `32` accepted beats total
  - beats `0~15` consume channels `0~5`
  - beats `16~31` consume channels `6~11`
- The top may assert `ready=1` only after:
  - FC global preload finished
  - all 10 neurons report `weight_loaded=1`
  - all 12 input feature-map buffers report `src_frame_valid=1`
  - no pending read response or held score is active
- `done` is a one-cycle pulse when the 10-score vector first becomes valid.
- `score_valid` is the vector-level result-valid flag and is true only when all 10 neuron outputs are valid together.
- When the final FC input beat is consumed, `l5_top` must release the 12 upstream buffers with `src_rd_done`.

### 4. Validation & Error Matrix
- `start=1` before preload or input frames are ready -> `l5_top` must block launch through `ready=0`
- any of the 12 lanes missing `src_rd_valid` for the active 6-lane group -> top must hold the packed response and not advance
- `src_rd_done` asserted before final beat consumption -> upstream frame may be truncated
- `score_valid=1` while any neuron output is not valid -> vector assembly bug

### 5. Good/Base/Bad Cases
- Good: preload full global stream, wait for `ready=1`, launch once, then observe one 10-score output vector.
- Base: the fifth-layer TB uses 12 ping-pong source buffers, generated FC weights, and software-computed 10-way scores.
- Bad: connect one single upstream buffer directly to one `fc_neuron` and assume it can provide 6 values per beat.

### 6. Tests Required
- Compile and run `l5_top_tb`.
- Check `cfg_last_err_seen=0`.
- Check `weight_loaded=1` before launch.
- Check all 10 printed `L5_SCORE` lines match the TB software results.
- Final summary must report `err_cnt=0` and `TB_PASS`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 鎶?12 璺?buffer 褰撴垚 1 涓彲浠ヤ竴鎷嶅悙鍑?6 涓暟鐨勫崟鍙?
assign neuron_in_data = src_rd_data[47:0];
```

#### Correct
```verilog
// 鍙褰撳墠 active 6 璺? 鎶婂畠浠墦鍖呮垚涓€涓?6-lane beat
assign addr_rd_fire = addr_rd_valid && addr_rd_ready;
assign rsp_capture_fire = rd_pending && rsp_all_valid_comb;
assign neuron_in_valid = rsp_valid_reg && all_neuron_in_ready;
```

---

## Scenario: FC Multiply Width Must Be Explicitly Extended

### 1. Scope / Trigger
- Trigger: fifth-layer top-level integration exposed a hidden arithmetic truncation bug that did not show up in the earlier small-value standalone neuron TB.

### 2. Signatures
- Affected logic:
  - `fc_neuron` combinational MAC block
  - per-lane multiply term inside `beat_sum_comb`

### 3. Contracts
- The 8bit input lane and 8bit signed weight must be sign-extended explicitly before multiplication when building the per-beat MAC term.
- Do not rely on simulator or synthesis implicit width inference for the `8 x 8` multiply feeding a 32bit accumulator.
- The FC neuron accumulation path must preserve the full signed multiply result before adding into `beat_sum_comb` / `acc_reg`.

### 4. Validation & Error Matrix
- omit explicit extension -> some directed low-range tests may pass, but larger real layer data will silently accumulate wrong scores
- unsigned/signed interpretation mismatch -> class scores diverge only for a subset of neurons or channels

### 5. Good/Base/Bad Cases
- Good: explicit sign-extension is present on both multiplicand and multiplier before the multiply.
- Base: standalone `fc_neuron_tb` plus integrated `l5_top_tb` both pass.
- Bad: cast the multiply result only after the multiply has already been width-truncated.

### 6. Tests Required
- Re-run standalone `fc_neuron_tb`.
- Re-run integrated `l5_top_tb`.
- Ensure a case with larger source activations and negative weights still produces `err_cnt=0`.

### 7. Wrong vs Correct
#### Wrong
```verilog
beat_sum_comb = beat_sum_comb
              + $signed(in_lane * weight_lane);
```

#### Correct
```verilog
beat_sum_comb = beat_sum_comb
              + $signed(
                    $signed({{WEIGHT_WIDTH{in_lane[DATA_WIDTH-1]}}, in_lane})
                  * $signed({{DATA_WIDTH{weight_lane[WEIGHT_WIDTH-1]}}, weight_lane})
                );
```

### 4. Validation & Error Matrix
- image data arrives while no address is valid -> buffer must wait for a valid address
- address advances without a matching image beat -> address/data alignment bug
- RAM is placed outside the image-input buffer after this contract is established -> ownership violation
- 2D address is not converted to 1D inside the image-input buffer -> wrong boundary split

### 5. Good/Base/Bad Cases
- Good: one input pixel handshakes with one packed 2D address and writes one RAM location inside `img_in_buf`.
- Base: raster-order `(0,0)` to `(27,27)` followed by full-frame readback.
- Bad: a writer-only module forwards 2D addresses outward and leaves RAM ownership to another unnamed stage.

### 6. Tests Required
- Behavioral simulation with the real image file `test/0.txt`.
- Check the first several write beats show:
  - `(0,0) -> addr1d 0`
  - `(0,1) -> addr1d 1`
  - `(0,2) -> addr1d 2`
- Read back the full image through the module read port and confirm `err_cnt=0`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 只做数据对齐, 不带RAM
assign wr_addr2d = addr2d;
```

#### Correct
```verilog
assign wr_row = addr2d[ADDR2D_WIDTH-1:COL_ADDR_WIDTH];
assign wr_col = addr2d[COL_ADDR_WIDTH-1:0];
assign wr_addr1d = (wr_row * IMG_W) + wr_col;
always @(posedge clk) begin
    if(wr_fire) begin
        mem[wr_addr1d] <= image_tdata;
    end
end
```

---

## Scenario: First-Layer Serial Convolution Kernel Handshake

### 1. Scope / Trigger
- Trigger: `my_cnnV4` first-layer arithmetic core is split from BRAM addressing and implemented as `conv_core`, a stream-fed serial convolution kernel.

### 2. Signatures
- Weight side:
  - `cfg_weight_valid`, `cfg_weight_ready`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_done`
- Pixel side:
  - `in_valid`, `in_ready`, `in_data`, `in_last`
- Result side:
  - `out_valid`, `out_ready`, `out_data`
- Status:
  - `busy`, `weight_loaded`

### 3. Contracts
- The kernel must not own image read address generation.
- The kernel must not own downstream write address generation.
- One full kernel weight group is `25` signed `8bit` weights for `5x5`.
- One full input window is `25` unsigned `8bit` pixels for `5x5`.
- Weight loading and pixel consumption do not overlap in the first baseline.
- Weight loading happens in one unified pre-run phase, not interleaved with normal window computation.
- `cfg_weight_done` is a one-cycle pulse on the final accepted weight beat.
- `out_valid` must hold the final result stable until `out_ready=1`.
- While `out_valid=1`, `in_ready` must stay low.

### 4. Validation & Error Matrix
- `in_valid=1` before `weight_loaded=1` -> `in_ready` must stay low
- `cfg_weight_valid=1` while a window is being consumed -> controller bug, weight side must wait
- `out_valid=1` and `out_ready=0` -> result must hold stable, next window must be blocked
- fewer than `25` weight beats but `cfg_weight_last=1` -> controller bug
- fewer than `25` pixel beats but `in_last=1` -> controller bug

### 5. Good/Base/Bad Cases
- Good: load `25` weights, then send `25` pixels, then receive one held result.
- Base: use a real non-zero `5x5` image window from `test/0.txt` for behavioral simulation.
- Bad: the kernel directly walks RAM addresses or starts consuming pixels before weights are ready.

### 6. Tests Required
- Verify `in_ready=0` before the weight group is fully loaded.
- Verify `cfg_weight_done=1` on the last accepted weight beat.
- Verify one `25`-pixel window produces exactly one result.
- Verify `out_ready=0` holds `out_valid` and `out_data` stable.
- A passing TB should finish with `err_cnt=0`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 卷积核内部自己控制 BRAM 地址
always @(posedge clk) begin
    if(start_conv) begin
        rd_addr <= rd_addr + 1'b1;
    end
end
```

#### Correct
```verilog
// 外部模块送入像素流, 卷积核只做乘加和握手
assign in_fire = in_valid && in_ready;
assign acc_next = (sample_cnt == 0) ? mult_term_ext : (acc_reg + mult_term_ext);
```

---

## Scenario: PC Golden Convolution Cross-Check

### 1. Scope / Trigger
- Trigger: `my_cnnV4` first-layer convolution needs a PC-side golden result so RTL simulation is checked against the same input window and the same weight set.

### 2. Signatures
- PC test directory:
  - `my_cnnV4/my_cnnV4_PCtest/`
- Current first sample files:
  - `conv_core_case0.py`
  - `conv_core_case0_pixels.txt`
  - `conv_core_case0_weights.txt`
  - `conv_core_case0_result.txt`
- RTL TB inputs:
  - `WEIGHT_FILE`
  - `RESULT_FILE`

### 3. Contracts
- The PC script and RTL TB must use the same image file, the same window coordinates, and the same weight sequence.
- The PC script owns the golden result generation.
- The RTL TB must read the golden weight file and golden result file instead of re-deriving the expected value independently.
- The PC-side result is the reference truth for the current directed case.
- When a full-layer top-level TB exists, the PC script must also generate the complete output feature map for the current kernel and input image.
- The feature-map golden file may be stored as a human-readable matrix, but the numeric traversal order must still match RTL output order.

### 4. Validation & Error Matrix
- PC script and TB use different window coordinates -> false mismatch
- PC script and TB use different weight order -> false mismatch
- TB recomputes the expected result locally after this contract is introduced -> duplicated truth source
- stale result file after weights changed -> controller/test flow bug

### 5. Good/Base/Bad Cases
- Good: run the PC script first, generate weight/result files, then run RTL TB to compare with those files.
- Base: current directed case uses one non-zero `5x5` window from `test/0.txt` and one signed `25`-weight set.
- Bad: hand-edit the TB expected result and leave the PC script disconnected from verification.

### 6. Tests Required
- Run the PC script and check the generated result file value.
- Run RTL simulation and confirm `out_data == exp_sum`.
- A passing directed case must end with `err_cnt=0`.
- For full-chain first-layer simulation, generate `24 x 24 = 576` golden outputs and verify the TB finishes with `out_cnt=576` and `err_cnt=0`.

### Convention: Full Feature Map Golden File For L1 Top

**What**: `l1_top_tb` must compare every first-layer convolution output against one PC-generated full feature-map golden file, not only one directed window result.

**Why**:
- A single directed window only proves one `5x5` MAC instance.
- The full `24x24` map also checks window traversal order, pixel-feed order, and end-of-scan behavior.
- Keeping the feature-map file human-readable makes manual inspection easier during bring-up.

### Required File Contract

- PC script output:
  - `conv_core_case0_feature_map.txt`
- File content:
  - `24` rows
  - each row contains `24` signed decimal convolution results
  - whitespace-separated formatting is allowed so `$fscanf("%d", ...)` can read all `576` values in sequence
- RTL TB behavior:
  - preload all `576` expected results
  - compare every `out_valid` beat against the corresponding golden value
  - keep one visible directed checkpoint such as `(4,12) -> 1158`

### Tests Required

- Run the PC script and confirm the feature-map file is emitted in `24x24` matrix form.
- Run `l1_top_tb` and confirm:
  - `SUMMARY: err_cnt=0 out_cnt=576`
  - the directed checkpoint window still matches the PC golden value

### 7. Wrong vs Correct
#### Wrong
```verilog
// TB 内部自己再算一遍黄金值
for(i = 0; i < WIN_SIZE; i = i + 1) begin
    exp_sum = exp_sum + ($signed({1'b0, window_pix[i]}) * weight_mem[i]);
end
```

#### Correct
```verilog
// TB 直接读取 PC 侧生成的黄金结果
fp_result = $fopen(RESULT_FILE, "r");
rc = $fscanf(fp_result, "%d", exp_sum);
```

---

## Convention: Window Address Manager Owns Only Spatial Scan

**What**: The reusable window address manager for `my_cnnV4` owns only spatial window traversal over one feature map. It does not know output-channel count, ping-pong bank roles, or BRAM linear address math.

**Why**:
- First-layer `out=6` and later-layer `out=12` still reuse the same spatial window sequence.
- Channel scheduling and bank ownership change between layers, but `(row, col)` window scan rules do not.
- Keeping the module spatial-only prevents the address generator from becoming another tightly coupled control block.

### Required Interface Contract

- Control input:
  - `start`
  - `addr_ready`
- Address output:
  - `addr_valid`
  - packed `addr2d = {row, col}`
  - `addr_last` for the last pixel of the current window
- Status output:
  - `busy`
  - `win_done`
  - `all_done`
  - current debug-visible window base and kernel offsets

### Required Behavior

- The module must scan one `K x K` window in row-major order.
- After one window completes, the base column moves by `STRIDE`.
- After the rightmost legal window completes, the base column resets and the base row moves by `STRIDE`.
- After the final legal window completes, the module pulses `all_done` and returns idle.
- The module must hold the current address stable while `addr_valid=1` and `addr_ready=0`.
- The module must not include any `Cout` or channel index logic.
- The module must not translate `{row, col}` into BRAM linear address.

### Good Pattern

```verilog
win_addr_mgr #(
    .FMAP_W(28),
    .FMAP_H(28),
    .K(5),
    .STRIDE(1)
) u_win_addr_mgr (
    .clk(clk),
    .rstn(rstn),
    .start(win_scan_start),
    .addr_ready(img_rd_addr_ready),
    .addr_valid(img_rd_addr_valid),
    .addr2d(img_rd_addr2d),
    .addr_last(win_pix_last),
    .win_done(one_window_done),
    .all_done(all_window_done)
);
```

### Wrong Pattern

- Do not hard-code `6` or `12` output channels into the spatial address module.
- Do not make the window address manager own ping-pong read-bank selection.
- Do not make the window address manager own `row * width + col` conversion.

### Tests Required

- Verify the first window of `28x28`, `K=5`, `stride=1` scans from `(0,0)` to `(4,4)`.
- Verify the second window starts at base `(0,1)`.
- Verify the first beat of the next output row starts at base `(1,0)` after the `(0,23)` window completes.
- Verify `addr_valid` and `addr2d` hold stable while `addr_ready=0`.
- Verify the final beat of the full scan pulses both `win_done` and `all_done`.

---

## Scenario: Generic Spatial Window Address Generation

### 1. Scope / Trigger
- Trigger: `my_cnnV4` now needs a reusable convolution-read address manager that works for first-layer image RAM and later-layer ping-pong feature-map buffers.

### 2. Signatures
- RTL signature:
  - inputs: `clk`, `rstn`, `start`, `addr_ready`
  - outputs: `addr_valid`, `addr2d`, `addr_last`, `busy`, `win_done`, `all_done`
  - debug/status outputs: `cur_base_row`, `cur_base_col`, `cur_krow`, `cur_kcol`

### 3. Contracts
- `FMAP_W`, `FMAP_H`, `K`, and `STRIDE` define the legal scan region.
- `addr2d` is packed as `{row, col}`, with row in the upper bits and col in the lower bits.
- One handshake corresponds to one pixel address inside the current convolution window.
- `addr_last` is asserted on the last accepted address of the current window.
- `win_done` is a one-cycle pulse after the final address of one window is accepted.
- `all_done` is a one-cycle pulse after the final address of the final legal window is accepted.
- The module is channel-count agnostic and must be broadcast-capable to multiple kernels or multiple source buffers.

### 4. Validation & Error Matrix
- `start=1` while `busy=1` -> new request ignored until current scan finishes
- `addr_ready=0` while `addr_valid=1` -> current address and window state must hold
- illegal design that mixes channel count into this module -> architectural coupling bug
- illegal design that converts to linear BRAM address here -> ownership violation

### 5. Good/Base/Bad Cases
- Good: one spatial scan module broadcasts the same packed `{row,col}` sequence to six first-layer kernels.
- Base: one module scans `28x28`, `K=5`, `stride=1` and produces `24 x 24 x 25` address beats.
- Bad: duplicate six separate address counters only because there are six output channels.

### 6. Tests Required
- Standalone TB with `28x28`, `K=5`, `stride=1` and handshake stalls.
- Assertions/checks for first window, second window, row-wrap window, and final `all_done`.
- A passing TB should finish with `err_cnt=0`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 把输出通道数也耦合进窗口地址模块
for(i = 0; i < 6; i = i + 1) begin
    addr2d_ch[i] <= addr2d_ch[i] + 1'b1;
end
```

#### Correct
```verilog
// 只生成一套空间地址, 由上层广播到多个卷积核或多个缓存
assign img_rd_addr2d = win_addr2d;
assign lane0_addr2d = win_addr2d;
assign lane1_addr2d = win_addr2d;
```

---

## Convention: First-Layer Integration Top Uses Single Outstanding Read

**What**: The first bring-up top for `my_cnnV4` may keep the data path simple by allowing only one outstanding read from `img_in_buf` at a time before feeding `conv_core`.

**Why**:
- `img_in_buf` returns one pixel per accepted read address.
- `conv_core` consumes one pixel stream beat at a time and may stall on output hold.
- A single-outstanding-read bridge is the lowest-risk way to verify the full layer boundary before introducing a richer reader or pipelined prefetch.

### Required Behavior

- The top may issue a new window address only when:
  - scan is active
  - source frame is valid
  - no prior read response is pending
  - no buffered pixel is waiting for `conv_core`
  - `conv_core.in_ready=1`
- After one read request is accepted, the top must remember whether that request was the window-last beat.
- When `img_in_buf.rd_valid=1`, the returned pixel is buffered into one local register stage and then forwarded to `conv_core`.
- The top must not start the next read request until the buffered pixel has been consumed by `conv_core`.

### Good Pattern

```verilog
assign win_addr_ready = scan_running
                     && buf_frame_valid
                     && !rd_pending
                     && !pix_valid_reg
                     && conv_in_ready;

if(rd_issue_fire) begin
    rd_pending <= 1'b1;
    rd_last_pending <= win_addr_last;
end

if(buf_rd_valid) begin
    rd_pending <= 1'b0;
    pix_valid_reg <= 1'b1;
    pix_data_reg <= buf_rd_data;
    pix_last_reg <= rd_last_pending;
end
```

### Wrong Pattern

- Do not let `win_addr_mgr` free-run while `img_in_buf` responses are still pending.
- Do not feed `conv_core` directly from `img_in_buf.rd_data` without a valid-holding stage.
- Do not use `image_tready=1` at the top boundary unless the write-side address is also valid for the same beat.

### Tests Required

- Full-chain TB must load one `28x28` image, load one `5x5` weight group, run all `576` windows, and observe `out_cnt=576`.
- The directed window at `(4,12)` must still produce the PC golden result `1158`.
- A passing TB should finish with `err_cnt=0`.

---

## Convention: First-Layer Unified Read-Write Address Manager

**What**: The current first-layer baseline may use one dedicated controller to manage both the `25` window-read addresses and the single output-write address for each window result.

**Why**:
- For `5x5 stride=1` first-layer convolution, one input window maps directly to one output point.
- The write address is exactly the current window base coordinate `{base_row, base_col}`.
- Keeping this relation in one first-layer controller reduces top-level glue without pushing address ownership back into `conv_core`.

### Required Interface Contract

- Control input:
  - `start`
  - `rd_addr_ready`
  - `out_fire`
- Read-side output:
  - `rd_addr_valid`
  - `rd_addr2d`
  - `rd_addr_last`
- Write-side output:
  - `wr_addr_valid`
  - `wr_addr2d`
  - `wr_last`
- Status output:
  - `busy`
  - `win_done`
  - `map_done`

### Required Behavior

- The controller must emit exactly `K*K` read addresses for one window before exposing the corresponding write address.
- The controller must hold the current write address stable until `out_fire=1`.
- `out_fire` means the convolution result was both valid and successfully accepted by the downstream feature-map buffer.
- The controller must not advance to the next output point merely because the `25` read addresses were issued.
- `wr_addr2d` must equal the current window base coordinate.
- `wr_last` must assert only on the final output point of the full output map.

### Good Pattern

```verilog
assign conv_out_ready_int = ext_out_ready
                         && ofmap_wr_ready
                         && l1_wr_addr_valid;

assign ofmap_out_fire = conv_out_valid && conv_out_ready_int;

win_addr_mgr u_win_addr_mgr(
    .rd_addr_ready(l1_rd_addr_ready),
    .out_fire(ofmap_out_fire),
    .wr_addr2d(l1_wr_addr2d),
    .wr_last(l1_wr_last)
);
```

### Wrong Pattern

- Do not increment the output write address immediately after the `25th` read beat if the convolution result has not been written yet.
- Do not make `conv_core` count full-map output coordinates by itself.
- Do not reuse the generic `win_addr_mgr` unchanged when the design also needs output-write hold behavior.

### Tests Required

- Standalone `win_addr_mgr_tb` must verify `25` reads followed by one held write address for each output point.
- Full-chain `l1_top_tb` must verify output write coordinates match the expected output-map traversal.
- Final write must assert `wr_last` on output point `(23,23)` for the `28x28`, `K=5`, `stride=1` first-layer case.

---

## Convention: First-Layer Output Ping-Pong Buffer Stores 32bit Convolution Sums

**What**: Before ReLU / quantization / pooling are inserted, the first-layer output ping-pong buffer stores raw `32bit signed` convolution sums.

**Why**:
- `conv_core` currently exports signed `32bit` accumulation results.
- The first baseline should preserve numerical truth across RTL / PC-golden comparison.
- Early truncation would make bring-up harder and hide arithmetic mismatches.

### Required Interface Contract

- `pingpong_img_buf.DATA_WIDTH = OUT_WIDTH`
- First-layer output buffer geometry:
  - `IMG_W = 24`
  - `IMG_H = 24`
- Write payload:
  - signed `32bit` convolution result

### Required Behavior

- The output feature-map ping-pong buffer must accept signed `32bit` write data without truncation.
- The buffer may still use the same packed `{row, col}` write/read address convention as the image buffer.
- Width reduction, activation, or pooling must happen in later dedicated stages, not implicitly inside the buffer.

### Tests Required

- Standalone `pingpong_img_buf_tb` must pass with signed `32bit` data values, including negative numbers.
- `l1_top_tb` must confirm the stored output feature map matches the PC-generated `24x24` golden matrix exactly.

---

## Convention: First-Layer 1x6 Broadcast Top

**What**: The current first-layer top may use one shared image-read path and one shared spatial address manager, then broadcast the same `5x5` pixel stream to `6` parallel `conv_core` lanes.

**Why**:
- First-layer `Cin=1`, so every output channel reads the same input window coordinates.
- Broadcasting one spatial stream removes duplicated read-control logic.
- The top still keeps output-channel parallelism explicit by giving each lane its own weight state and its own output ping-pong buffer.

### Required Interface Contract

- Shared image side:
  - one `img_in_buf`
  - one `win_addr_mgr`
- Weight side:
  - one serialized weight input stream
  - one lane-select input `cfg_weight_lane`
- Compute side:
  - `6` instances of `conv_core`
- Output side:
  - `6` instances of `pingpong_img_buf`

### Required Behavior

- The top must issue only one spatial read-address stream for one window.
- The returned pixel beats must be broadcast to all `6` convolution lanes on the same accepted cycles.
- Each lane owns its own preloaded `5x5` weight set.
- Each lane writes its own output feature map into its own ping-pong buffer.
- The shared address manager must advance to the next output point only when all `6` lanes have:
  - `out_valid=1`
  - downstream `wr_ready=1`
  - committed the current output point on the same cycle
- The top-level aggregate `weight_loaded` is high only when all `6` lanes have completed weight load.
- The top-level aggregate `out_valid` represents a synchronized `6`-lane result point, not a single-lane early result.

### Good Pattern

```verilog
assign all_conv_in_ready = &lane_in_ready_vec;
assign all_lane_out_valid = &lane_out_valid_vec;
assign all_lane_ofmap_wr_ready = &lane_ofmap_wr_ready_vec;

assign all_lane_commit_fire = out_ready
                           && l1_wr_addr_valid
                           && all_lane_out_valid
                           && all_lane_ofmap_wr_ready;

win_addr_mgr u_win_addr_mgr(
    .out_fire(all_lane_commit_fire)
);
```

### Wrong Pattern

- Do not instantiate `6` separate spatial window address managers for first-layer `Cin=1`.
- Do not allow lane 0 to advance the output write address before the other `5` lanes commit the same output point.
- Do not couple output-channel counting into `conv_core`.
- Do not let each lane fetch its own image window independently in this first baseline.

### Tests Required

- Load all `6` lanes with valid weight groups, then confirm aggregate `weight_loaded=1`.
- Run one full `24x24` scan and confirm aggregate `out_cnt=576`.
- Confirm lane 0 still matches the PC golden feature-map file exactly.
- Confirm every lane output buffer becomes frame-valid after the full scan.
- Confirm each lane buffer can be read back independently and released with its own `rd_done`.

---

## Scenario: First-Layer 6-Lane Shared-Read / Per-Lane-Write Top

### 1. Scope / Trigger
- Trigger: the first-layer baseline is upgraded from one convolution lane to `1 -> 6` output-channel parallelism.

### 2. Signatures
- Weight side:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_lane`
- Shared result-commit side:
  - aggregate `out_valid`, aggregate `out_ready`
  - `lane_out_valid[5:0]`
  - `lane_ofmap_wr_ready[5:0]`
- Output-buffer side:
  - `lane_ofmap_frame_valid[5:0]`
  - per-lane `rd_en`, `rd_addr2d`, `rd_valid`, `rd_data`, `rd_done`

### 3. Contracts
- The top broadcasts one window pixel stream to all `6` lanes.
- `cfg_weight_lane` selects which lane accepts the current serialized weight beat.
- A lane not selected by `cfg_weight_lane` must ignore that beat.
- The aggregate output-point commit occurs only when all `6` lanes and all `6` downstream output buffers are ready on the same cycle.
- `win_addr_mgr.out_fire` is driven by this aggregate commit, not by any single lane.
- Each lane output buffer stores one full `24x24` feature map for that lane.

### 4. Validation & Error Matrix
- advance address manager after only one lane commits -> lane-to-lane output coordinate skew
- duplicate `win_addr_mgr` per lane -> architectural duplication and control drift
- lane accepts weights while not selected by `cfg_weight_lane` -> wrong kernel image
- expose aggregate `weight_loaded=1` before all `6` lanes are loaded -> scan may start too early
- write all lane outputs into one shared output buffer -> output-channel ownership violation

### 5. Good/Base/Bad Cases
- Good: one shared input frame is scanned once, and all `6` lanes consume the exact same pixel order while keeping separate weights and separate output buffers.
- Base: TB may load the same `25` weights into all `6` lanes first, then verify all `6` output maps are identical.
- Bad: lane 0 computes and writes immediately while the other lanes trail behind by one or more output points.

### 6. Tests Required
- Behavioral full-chain TB covering frame load, `6`-lane weight load, full scan, and per-lane readback.
- Assertion/check points:
  - aggregate `weight_loaded=1`
  - aggregate `out_cnt=576`
  - directed checkpoint `(4,12) -> 1158` on lane 0
  - every lane readback equals the expected `24x24` golden matrix when all `6` lanes use the same weights
  - each lane `rd_done` clears only its own `lane_ofmap_frame_valid`

### 7. Wrong vs Correct
#### Wrong
```verilog
// 某一路先写成功就推进下一输出点
assign l1_out_fire = lane_out_valid[0] && lane_ofmap_wr_ready[0];
```

#### Correct
```verilog
// 6 路结果必须同拍提交后, 地址管理器才推进
assign all_lane_commit_fire = out_ready
                           && l1_wr_addr_valid
                           && (&lane_out_valid)
                           && (&lane_ofmap_wr_ready);
```

---

## Convention: First-Layer Sequential Weight Stream Distributor

**What**: For first-layer `1 -> 6` bring-up, the external controller may send one continuous serialized weight stream, and a dedicated distributor module splits it into `lane + last` control for the existing `l1_core`.

**Why**:
- It removes manual per-lane drive logic from the top-level TB and future control path.
- It keeps `conv_core` unchanged and preserves the existing lane-local weight ownership.
- It provides one clear boundary where stream-level validation such as final `last` timing can be checked.

### Required Interface Contract

- Upstream stream side:
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
  - `cfg_weight_ready`
- Downstream lane-select side:
  - `lane_cfg_weight_valid`
  - `lane_cfg_weight_data`
  - `lane_cfg_weight_last`
  - `lane_cfg_weight_lane`
  - `lane_cfg_weight_ready`

### Required Behavior

- One complete first-layer load transaction contains `LANE_NUM * K * K` weight beats.
- The distributor must emit lane `0` first, then lane `1`, up to lane `LANE_NUM-1`.
- Every `K*K` accepted beats, the distributor must assert `lane_cfg_weight_last` for exactly one accepted beat.
- The external `cfg_weight_last` must only assert on the final accepted beat of the full stream.
- If external `cfg_weight_last` timing is wrong, the module may raise an error flag such as `cfg_last_err`, but it must still preserve internal lane grouping based on its own counters.
- The distributor must fully respect downstream backpressure through `lane_cfg_weight_ready`.

### Good Pattern

```verilog
assign cfg_weight_ready = lane_cfg_weight_ready;
assign lane_cfg_weight_valid = cfg_weight_valid;
assign lane_cfg_weight_lane = cur_lane_idx;
assign lane_cfg_weight_last = lane_cfg_weight_valid && (cur_weight_idx == WIN_SIZE - 1);
```

### Wrong Pattern

- Do not require the upstream to manually drive both `cfg_weight_lane` and `cfg_weight_last` for every lane-group beat.
- Do not let an early external `cfg_weight_last` reset the internal lane counters immediately.
- Do not merge weight-stream distribution into `conv_core`.

### Tests Required

- Standalone `l1_wgt_dist_tb` must verify:
  - correct lane order `0 -> 5`
  - correct per-lane `25`-beat grouping
  - backpressure stall behavior
  - one error pulse on deliberate wrong external `cfg_weight_last`
- Wrapper `l1_top_w_tb` must verify the full `24x24` feature-map result still matches the PC golden file.

---

## Scenario: First-Layer Wrapper Top With Weight Distributor

### 1. Scope / Trigger
- Trigger: the first-layer `6`-lane top now needs a cleaner external control entry that accepts one continuous weight stream without explicit external lane numbering.

### 2. Signatures
- Wrapper top input:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
- Wrapper top status:
  - `cfg_weight_ready`, `cfg_weight_done`, `cfg_last_err`
- Internal bridge:
  - distributor output `lane_cfg_weight_*`
  - existing `l1_core` input `cfg_weight_* + cfg_weight_lane`

### 3. Contracts
- `l1_top_w` owns the adaptation from continuous stream weights to the existing `l1_core` per-lane weight-load contract.
- `l1_top` remains the compute/integration core and should not absorb the stream-distribution logic.
- `cfg_weight_done` at wrapper level means the full `6 * 25` weight stream has been accepted.
- `weight_loaded` at wrapper level still means all six `conv_core` lanes report loaded.

### 4. Validation & Error Matrix
- wrapper bypasses distributor and still requires manual `cfg_weight_lane` externally -> wrong integration boundary
- `cfg_weight_done` pulses after only one lane group -> premature start hazard
- wrong external `cfg_weight_last` is silently ignored with no visibility -> debug blind spot

### 5. Good/Base/Bad Cases
- Good: upstream sends the same `25`-weight file six times in sequence and wrapper produces the same six feature maps.
- Base: current TB reuses `conv_core_case0_weights.txt` for all six lanes and verifies lane 0 against the PC golden map.
- Bad: wrapper mutates the accepted weight order relative to the input stream.

### 6. Tests Required
- `l1_top_w_tb` must cover:
  - real image load
  - one continuous `150`-beat weight stream
  - full `576` output-point scan
  - output readback from all six lane buffers
  - `cfg_last_err=0` for the good path

### 7. Wrong vs Correct
#### Wrong
```verilog
// 外部还要手写 lane 编号, 包装层形同虚设
assign top_cfg_weight_lane = ext_cfg_weight_lane;
```

#### Correct
```verilog
// 包装层内部自动把串行权重流拆给 6 路卷积核
l1_wgt_dist u_l1_wgt_dist (
    .cfg_weight_valid(cfg_weight_valid),
    .lane_cfg_weight_lane(dist_cfg_weight_lane)
);
```

---

## Design Decision: Use One Global Weight Distributor Across Layers

**Context**: The first-layer weight distributor is already split out, and later layers will also need ordered power-on weight preload. The user wants one unified numbering rule instead of different ad-hoc lane selectors per layer.

**Decision**: Future weight preload should be described as one global weight-distribution problem, not only as a first-layer helper. The global target identifier is a packed 2D logical address:
- `weight_dst2d = {layer_id, kernel_id}`
- first layer example: `(0,0)` to `(0,5)`
- second layer example: `(1,0)` to `(1,11)`

**Why**:
- It gives one stable addressing rule across first layer and later layers.
- It keeps layer index and output-kernel index explicit at the control boundary.
- It avoids redesigning the preload protocol again when moving from `6` output channels to `12` output channels.

**Extensibility**:
- Later, the same global distributor can drive first-layer `6` kernels, second-layer `12` kernels, and any later fully connected or convolution stage that still uses startup preload.
- The packed 2D destination ID is a logical destination only; local modules may still translate it into their own lane-select or bank-select format internally.

---

## Convention: Global Weight Destination Uses Packed 2D Logical Address

**What**: Weight preload control should use a packed 2D logical destination ID instead of a layer-local single-lane selector.

**Why**:
- The design already uses packed 2D addressing heavily for image and feature-map ownership.
- Reusing the same idea for weight routing keeps the control style consistent.
- It makes later multi-layer weight preload easier to reason about.

### Required Interface Contract

- Upstream weight stream:
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
- Global logical destination:
  - `weight_dst2d = {layer_id, kernel_id}`
- Recommended field meaning:
  - `layer_id`: identifies which CNN layer owns the weight
  - `kernel_id`: identifies which output kernel inside that layer owns the weight

### Required Behavior

- The first-layer logical kernel IDs are:
  - `(0,0)` `(0,1)` `(0,2)` `(0,3)` `(0,4)` `(0,5)`
- The second-layer logical kernel IDs are:
  - `(1,0)` through `(1,11)`
- The global distributor must preserve this logical ID order when performing startup preload.
- Local layer wrappers may internally convert:
  - `(0, kernel_id)` -> first-layer lane select
  - `(1, kernel_id)` -> second-layer lane select
- The logical 2D destination does not replace per-layer weight-group sizing. Each layer still owns its own `Cin * K * K` or other local weight-count rule.

### Good Pattern

```verilog
// 全局权重目标采用逻辑二维编号
// 第一层: (0,0) ~ (0,5)
// 第二层: (1,0) ~ (1,11)
assign weight_dst2d = {layer_id, kernel_id};
```

### Wrong Pattern

- Do not define one unrelated lane-numbering scheme for each layer without a shared top-level meaning.
- Do not overload first-layer-only `cfg_weight_lane` as the permanent project-wide weight-routing contract.
- Do not make compute kernels infer their own global layer identity during preload.

### Tests Required

- When a global distributor RTL is implemented, TB must verify:
  - first-layer IDs are emitted in `(0,0)` to `(0,5)` order
  - second-layer IDs are emitted in `(1,0)` to `(1,11)` order
  - the destination ID remains stable while downstream `ready=0`

---

## Convention: Power-On Weight Preload Completes Before Compute Starts

**What**: At current V4 architecture stage, weight distribution is a startup transaction. All required layer weights for the current run are loaded first, then normal image / feature-map compute is allowed to start.

**Why**:
- This matches the current `conv_core` contract: compute waits for weight-ready state.
- It reduces overlap complexity during bring-up.
- It keeps the first full system easier to debug before introducing runtime weight switching.

### Required Behavior

- On power-up or reset release, the system may enter a dedicated preload phase.
- During preload phase:
  - global weight stream is routed to the target layer/kernel destinations
  - normal convolution scan must not start
  - later layer address/compute flow may remain idle
- After all required destinations report loaded, the system may enter normal compute phase.
- For the current first-layer wrapper:
  - `cfg_weight_done` means the external preload stream finished
  - `weight_loaded` means all local first-layer convolution lanes report loaded

### Good Pattern

```verilog
assign scan_ready = img_frame_valid
                 && weight_loaded
                 && !scan_busy;
```

### Wrong Pattern

- Do not start image-window scan before the target layer weights are fully loaded.
- Do not interleave normal window compute with unfinished startup preload in the first bring-up baseline.
- Do not treat `cfg_weight_done` alone as global compute-enable unless the corresponding per-layer loaded flags are also complete.

### Tests Required

- Current layer-level TBs must continue to verify compute cannot start before `weight_loaded=1`.
- When global preload control is implemented, integration TB must verify:
  - preload completes first
  - then scan/compute starts
  - no output feature-map write occurs before preload completion

---

## Scenario: Future Global Multi-Layer Weight Preload

### 1. Scope / Trigger
- Trigger: the architecture is expanding from a first-layer-only distributor to a project-wide startup weight preload path that must cover multiple CNN layers.

### 2. Signatures
- Global stream side:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_ready`
- Global destination side:
  - `weight_dst2d = {layer_id, kernel_id}`
- Layer-local loaded status:
  - per-layer `weight_loaded`
  - optional per-layer `cfg_weight_done`

### 3. Contracts
- The global distributor owns the logical routing order across layers.
- Each layer wrapper owns translation from `weight_dst2d` to local lane/kernel select.
- Startup compute enable must be gated by the completion of the preload phase.
- First layer and second layer must share the same destination-ID meaning, even if their local kernel counts differ.

### 4. Validation & Error Matrix
- first layer uses one numbering convention and second layer uses another unrelated convention -> cross-layer routing ambiguity
- preload stream ends before all required `(layer_id, kernel_id)` targets are loaded -> incomplete startup state
- compute starts before corresponding layer `weight_loaded=1` -> undefined convolution result
- a local wrapper ignores `layer_id` and accepts weights for the wrong layer -> layer ownership violation

### 5. Good/Base/Bad Cases
- Good: startup first routes `(0,0)~(0,5)`, then `(1,0)~(1,11)`, and only after all targets are loaded does the system start feature-map compute.
- Base: first implementation may still instantiate a first-layer-only wrapper, but its interface and spec should already align with future global `weight_dst2d` meaning.
- Bad: later add second-layer preload by inventing a separate incompatible control bus unrelated to first-layer numbering.

### 6. Tests Required
- Future global distributor TB must check destination traversal across multiple layers.
- Future system TB must check that no layer begins normal compute before preload completion.
- At minimum one integration assertion point must confirm:
  - `compute_start` implies all required layer-loaded flags are high

### 7. Wrong vs Correct
#### Wrong
```verilog
// 第一层和第二层各自定义无关编号, 顶层无法统一调度
assign l1_lane_id = ext_lane_id;
assign l2_kernel_id = ext_kernel_id_other_rule;
```

#### Correct
```verilog
// 顶层统一使用逻辑二维目标编号
assign weight_dst2d = {layer_id, kernel_id};
// 各层包装模块再把它翻译成各自本地选择
```

---

## Scenario: First-Layer Wrapper Top With Global Weight Distributor

### 1. Scope / Trigger
- Trigger: the project now has a global logical weight distributor, but only the first convolution layer is integrated into the runnable compute chain.

### 2. Signatures
- Wrapper top input:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
- Global distributor bridge:
  - `weight_valid`, `weight_data`, `weight_dst2d`, `weight_idx`, `dst_last`, `weight_ready`
- First-layer local bridge:
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`, `cfg_weight_lane`
- Compute/start gating:
  - wrapper `scan_ready`
  - wrapper `cfg_weight_done`
  - local first-layer `weight_loaded`

### 3. Contracts
- `l1_top` owns the translation from global logical weight target `{layer_id, kernel_id}` into the existing local first-layer `cfg_weight_lane` contract.
- Only global targets `(0,0)` through `(0,5)` may be forwarded into `l1_top`.
- The wrapper must preserve the existing `l1_core` ownership split:
  - image load and image buffer stay inside `l1_core`
  - address management stays inside `l1_top`
  - `6`-lane convolution and `6` output ping-pong buffers stay inside `l1_core`
- During the current first-layer-only bring-up:
  - non-first-layer targets are accepted by the wrapper so the global preload stream can complete
  - those non-first-layer weights must not be forwarded into `l1_top`
- `scan_ready` at wrapper level must stay low until the global preload transaction has completed.
- `weight_loaded` at wrapper level still means all six first-layer convolution lanes have loaded their own weights.
- `cfg_weight_done` at wrapper level means the full global preload stream has finished.

### 4. Validation & Error Matrix
- forward `(layer_id != 0)` weights into `l1_top` -> first-layer kernels receive wrong weights
- block global preload on an unimplemented later-layer target -> startup deadlock
- allow `scan_ready=1` before global preload completes -> compute may start before the intended startup preload phase ends
- rewrite image/cache/address logic into the wrapper -> layer-boundary ownership drift and tighter coupling

### 5. Good/Base/Bad Cases
- Good: wrapper accepts the full global preload stream, routes only `(0,0)~(0,5)` into `l1_top`, then starts first-layer compute after preload completion.
- Base: first-layer TB uses real `6 * 25` weights for layer 0 and placeholder zero weights for layer 1 so the global preload transaction can still end normally.
- Bad: bypass the translation layer and directly connect global `weight_valid` to local `cfg_weight_valid` without checking `layer_id`.

### 6. Tests Required
- Behavioral integration TB for `l1_top` must cover:
  - real image load from `test/0.txt`
  - full global preload stream:
    - layer 0: `6 * 25` real weights
    - layer 1: `12 * 150` placeholder weights
  - assertion points:
    - `cfg_weight_done` pulses once after the full global stream
    - `cfg_last_err=0` for the good path
    - wrapper `scan_ready` only becomes high after preload completion
    - first-layer `24x24` output map still matches the PC golden file
    - all six output ping-pong buffers can be read back and released independently

### 7. Wrong vs Correct
#### Wrong
```verilog
// 不区分层号, 直接把全局权重流送进第一层
assign l1_cfg_weight_valid = gw_weight_valid;
assign l1_cfg_weight_last  = gw_dst_last;
assign l1_cfg_weight_lane  = gw_weight_dst2d[KERNEL_ID_WIDTH-1:0];
```

#### Correct
```verilog
// 只有第一层逻辑目标才允许进入 l1_top
assign gw_is_l1_target = (gw_layer_id == LAYER0_ID) && (gw_kernel_id < L0_KERNEL_NUM);
assign l1_cfg_weight_valid = gw_weight_valid && gw_is_l1_target;
assign l1_cfg_weight_last  = gw_dst_last && gw_is_l1_target;
assign l1_cfg_weight_lane  = gw_kernel_id[LANE_SEL_WIDTH-1:0];
assign gw_weight_ready     = gw_is_l1_target ? l1_cfg_weight_ready : 1'b1;
```

---

## Scenario: First-Layer Production Top Uses Minimal Integration Interface

### 1. Scope / Trigger
- Trigger: the first-layer full chain is already verified, so `l1_top` must now serve as the formal integration boundary for later layers instead of continuing to expose bring-up-only debug signals.

### 2. Signatures
- Top control inputs:
  - `frame_start`, `scan_start`, `frame_release`
- Top data inputs:
  - `image_tdata`, `image_tvalid`
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
- Downstream feature-map read inputs:
  - `ofmap_rd_en`, `ofmap_rd_addr2d`, `ofmap_rd_done`
- Top status outputs:
  - `cfg_weight_ready`, `cfg_weight_done`, `cfg_last_err`
  - `image_tready`, `scan_ready`, `img_frame_valid`, `weight_loaded`, `scan_busy`, `scan_done`
- Top output-feature-map outputs:
  - `ofmap_frame_valid`, `ofmap_rd_data`, `ofmap_rd_valid`

### 3. Contracts
- `img_in_addr_mgr` owns only external image write traversal.
- `img_in_buf` owns image storage and 2D-to-1D RAM translation.
- `win_addr_mgr` owns convolution spatial read traversal and output-point write traversal.
- `l1_core` owns the internal glue among image-buffer reads, six serial convolution lanes, and six output ping-pong buffers.
- Production-facing `l1_top` must not export verification-only ports such as:
  - `dbg_*`
  - `lane_cfg_weight_*`
  - `lane_conv_busy`
  - `lane_out_*`
  - direct internal compute stream ports like `out_valid` and `out_data`
- The current formal first-layer boundary is buffer-based:
  - later stages read results only through `ofmap_rd_*`
  - `l1_top` ties internal `l1_core.out_ready` high and does not re-export the internal result stream
- Testbenches may still observe hierarchical internal nodes for verification convenience, but those hierarchical names are not part of the production top contract.
- `scan_ready` must stay low until:
  - one full input frame is valid
  - all six first-layer kernels report `weight_loaded`
  - global preload has completed

### 4. Validation & Error Matrix
- re-expose `dbg_*` or lane-local internal status on `l1_top` -> top-level coupling regression
- downstream logic depends on internal conv result pulses instead of `ofmap_rd_*` -> layer-boundary contract violation
- `scan_ready=1` before global preload completion -> compute may start before startup preload finishes
- duplicate address generation inside `l1_top` instead of using `img_in_addr_mgr` or `win_addr_mgr` -> ownership drift

### 5. Good/Base/Bad Cases
- Good: later modules treat `l1_top` as a six-lane feature-map producer with readable output buffers and do not depend on internal debug behavior.
- Base: `l1_top_tb` uses hierarchical references only for console trace and comparison, while the formal `l1_top` interface remains minimal.
- Bad: keep bring-up-only ports on `l1_top` forever and let later layers wire against internal debug or internal conv result pulses.

### 6. Tests Required
- Full-chain `l1_top_tb` behavioral simulation must still end with:
  - `SUMMARY: err_cnt=0 out_cnt=576 target_seen=1`
- TB must still confirm:
  - `cfg_last_err=0`
  - `cfg_weight_done` pulse observed
  - all six `ofmap_frame_valid` bits assert after one full scan
  - each lane clears its own `ofmap_frame_valid` after corresponding `ofmap_rd_done`
  - directed window `idx=108 row=4 col=12` still matches lane0 result `59976`

### 7. Wrong vs Correct
#### Wrong
```verilog
module l1_top(
    output out_valid,
    output signed [31:0] out_data,
    output [9:0] dbg_win_addr2d,
    output [191:0] lane_out_data
);
```

#### Correct
```verilog
module l1_top(
    input  frame_start,
    input  scan_start,
    input  frame_release,
    input  [5:0] ofmap_rd_en,
    input  [59:0] ofmap_rd_addr2d,
    input  [5:0] ofmap_rd_done,
    output scan_ready,
    output img_frame_valid,
    output weight_loaded,
    output [5:0] ofmap_frame_valid,
    output signed [191:0] ofmap_rd_data,
    output [5:0] ofmap_rd_valid
);
```




---

## Scenario: Compute Kernels Must Not Re-Own Address Generation

### 1. Scope / Trigger
- Trigger: later CNN stages such as `relu_pool` may be tempting to expose upstream read-address ports directly from the compute module, even though the project already established separate address-manager ownership for `conv_core` and layer wrappers.

### 2. Signatures
- Compute-kernel style interface:
  - data side only: `in_valid`, `in_data`, `in_last`, `out_valid`, `out_data`, `out_ready`
- Address-manager / wrapper side:
  - read address generation: `rd_en`, `rd_addr2d`, `rd_done`
  - write address generation: `wr_addr2d`, `wr_last`
- Buffer side:
  - storage and 2D-to-1D translation only

### 3. Contracts
- In this project, address generation belongs to dedicated address-manager modules or to a thin layer wrapper that instantiates those address managers.
- Compute kernels such as `conv_core` and future `relu_pool`-style arithmetic cores must not become the formal owner of upstream read addresses or downstream write addresses.
- If one integrated bring-up module temporarily bundles address generation with compute for faster verification, that module is a transitional wrapper, not the final compute-kernel boundary.
- The stable architectural split is:
  - address manager decides which spatial coordinates are needed
  - buffer converts packed 2D addresses to linear RAM indices and stores data
  - compute kernel only consumes data stream beats and produces result stream beats
- Later-stage wrappers may still expose address signals outward when they are acting as the orchestrating layer boundary, but the inner arithmetic kernel should remain address-agnostic.

### 4. Validation & Error Matrix
- arithmetic core exports `rd_addr2d` / `wr_addr2d` as part of its long-term public contract -> coupling regression against `conv_core` style
- both wrapper and compute kernel try to own spatial progression -> duplicated counters and state drift
- buffer stops being a passive storage element and starts inferring traversal order -> ownership violation
- later layer cannot reuse the same compute kernel under a different address schedule -> extensibility loss

### 5. Good/Base/Bad Cases
- Good: one wrapper instantiates `win_addr_mgr`, drives buffer read addresses, streams returned pixels into a compute-only `relu_pool` kernel, and separately writes the pooled outputs to the next buffer.
- Base: `relu_pool_l1` is allowed to exist as a wrapper-level integration block that instantiates `win_addr_mgr`, a compute-only `relu_pool_core`, and the destination ping-pong buffer. The inner arithmetic kernel still remains address-agnostic.
- Bad: copy the current interim interface into every future pool kernel and let each compute block directly own upstream read addresses.

### 6. Tests Required
- Architecture review must confirm compute-only kernels do not own BRAM traversal state.
- When refactoring `relu_pool` into wrapper + kernel split, TB must still verify:
  - same `12x12` pooled result map
  - address traversal remains owned by the wrapper/address-manager path
  - compute kernel can be reused under the same stream contract without buffer-specific ports

### 7. Wrong vs Correct
#### Wrong
```verilog
module relu_pool_core(
    output rd_en,
    output [9:0] rd_addr2d,
    output rd_done,
    output [9:0] wr_addr2d
);
```

#### Correct
```verilog
module relu_pool_core(
    input  in_valid,
    input  signed [31:0] in_data,
    input  in_last,
    input  out_ready,
    output in_ready,
    output out_valid,
    output signed [7:0] out_data
);
```

---

## Scenario: Pooling Reuses Generic Window Address Manager

### 1. Scope / Trigger
- Trigger: the single-channel `relu_pool_l1` stage needs `2x2 stride=2` window traversal, but the project already has a reusable `win_addr_mgr` for generic window scanning.

### 2. Signatures
- Reused manager:
  - `win_addr_mgr`
- Pool stage interface:
  - source side: `src_rd_en`, `src_rd_addr2d`, `src_rd_valid`, `src_rd_data`
  - output-buffer write side: `wr_valid`, `wr_addr2d`, `wr_last`, `wr_ready`
- Reused manager outputs consumed by pool stage:
  - `rd_addr_valid`, `rd_addr2d`, `rd_addr_last`
  - `wr_addr_valid`, `wr_last`
  - `cur_base_row`, `cur_base_col`

### 3. Contracts
- Pooling must reuse `win_addr_mgr` for window read traversal when the behavior is still generic sliding-window traversal.
- Do not create a second dedicated pool-only address manager when `IMG_W`, `IMG_H`, `K`, and `STRIDE` parameterization is sufficient.
- For `2x2 stride=2` pooling over a `24x24` source map:
  - read window bases are `0, 2, 4, ... , 22`
  - output write coordinates are `0..11`
- Therefore, the pool stage must not forward `win_addr_mgr.wr_addr2d` directly into the output ping-pong buffer.
- The pool stage must derive pooled output coordinates from the current base coordinate:
  - `pool_wr_row = cur_base_row / STRIDE`
  - `pool_wr_col = cur_base_col / STRIDE`
  - `pool_wr_addr2d = {pool_wr_row, pool_wr_col}`
- `wr_last` may still be reused directly from `win_addr_mgr`, because frame completion order is unchanged.

### 4. Validation & Error Matrix
- instantiate a dedicated `pool_addr_mgr` that duplicates `win_addr_mgr` traversal logic -> code reuse regression
- connect `win_addr_mgr.wr_addr2d` directly to the pool output buffer for `stride=2` pooling -> output addresses become `0,2,4...` and overflow the `12x12` map contract
- derive pooled write coordinates from `rd_addr2d` instead of base coordinates -> write address may wobble inside one `2x2` window
- reuse `wr_last` but change traversal order -> completion pulse may no longer align with final pooled output point

### 5. Good/Base/Bad Cases
- Good: `relu_pool_l1` reuses `win_addr_mgr`, reads source windows at `(0,0)~(1,1)`, `(0,2)~(1,3)`, and writes pooled outputs to `(0,0)`, `(0,1)`, ... `(11,11)`.
- Base: one generic address manager services both first-layer convolution and single-channel pooling with different parameter sets.
- Bad: maintain one traversal module for convolution and another nearly identical traversal module for pooling.

### 6. Tests Required
- Behavioral TB must compile with `win_addr_mgr.v` and without any `pool_addr_mgr.v` dependency.
- `relu_pool_l1_tb` must still end with:
  - `SUMMARY: err_cnt=0 done_seen=1 src_done_seen=1`
- Console traces should show pooled write addresses covering the `12x12` output map in raster order.

### 7. Wrong vs Correct
#### Wrong
```verilog
assign pool_wr_addr2d = pool_mgr_wr_addr2d;
```

#### Correct
```verilog
assign pool_wr_row = pool_base_row / STRIDE;
assign pool_wr_col = pool_base_col / STRIDE;
assign pool_wr_addr2d = {pool_wr_row, pool_wr_col};
```

---

## Scenario: Layer Name Must Match Architectural Boundary

### 1. Scope / Trigger
- Trigger: the project started first-layer bring-up with names such as `relu_pool_l1` and `pool_l1_top`, but the user clarified that ReLU+pool belongs to the next layer boundary, not to `l1`.

### 2. Signatures
- Naming contract:
  - first convolution layer only -> `l1_*`
  - next ReLU+pool stage -> `l2_*`
  - first-layer plus next-stage joint bring-up / integration -> `*_l1l2` or `l1l2_*`
- Typical examples:
  - single-stage compute / wrapper: `conv_core`, `relu_pool_l2`
  - same-stage top: `l1_top`, `l2_top`
  - cross-stage integration TB/top: `l1l2_top`, `l1l2_top_tb`

### 3. Contracts
- In `my_cnnV4`, layer names must follow architectural ownership, not temporary bring-up order.
- `l1` means the first convolution stage only.
- ReLU+pool that consumes first-layer output and prepares the next stage input must be treated as `l2` naming space.
- When one module or TB verifies the boundary from first convolution into ReLU+pool together, it must use `l1l2` naming rather than forcing everything under `l1`.
- Transitional files that were already verified under older names may remain temporarily, but all future modules, TBs, and top-level wrappers must follow the corrected naming rule.

### 4. Validation & Error Matrix
- name a ReLU+pool wrapper as `*_l1` after this decision -> layer-boundary naming drift
- use `l2_*` for a pure first-layer convolution-only block -> stage ownership confusion
- use one stage-local name for a cross-stage integration TB -> hard to tell whether the TB is unit-level or boundary-level
- rename old files immediately without need while active verification depends on them -> unnecessary churn risk

### 5. Good/Base/Bad Cases
- Good: future single-channel ReLU+pool wrapper is named `relu_pool_l2`, and a 6-lane first-conv plus pool integration TB is named `l1l2_top_tb`.
- Base: already verified older file names may stay in place until the next intentional rename/refactor step, but new work must stop extending the old `relu_pool_l1` naming.
- Bad: continue adding more `*_l1` pool modules and TBs after the architectural boundary was clarified.

### 6. Tests Required
- Review every new RTL/TB filename and module name added after this decision:
  - first-conv-only stage must use `l1`
  - relu+pool stage must use `l2`
  - cross-stage integration must use `l1l2`
- When old files are later renamed, the associated Vivado project entries and TB top-module settings must be updated together.

### 7. Wrong vs Correct
#### Wrong
```verilog
module relu_pool_l1;
module pool_l1_top_tb;
```

#### Correct
```verilog
module relu_pool_l2;
module l1l2_top_tb;
```

---

## Scenario: First-Layer Output Ping-Pong Buffer Must Infer BRAM

### 1. Scope / Trigger
- Trigger: first-layer `6` 路输出特征图缓存从寄存器阵列实现切换到 BRAM 推断友好实现, 避免 `24x24x32x2x6` 规模被综合成大量 LUT/FF.

### 2. Signatures
- Module:
  - `pingpong_img_buf`
- Storage side:
  - `bank0 [0:DEPTH-1]`
  - `bank1 [0:DEPTH-1]`
- Interface:
  - `wr_valid`, `wr_data`, `wr_addr2d`, `wr_last`, `wr_ready`, `wr_done`
  - `rd_en`, `rd_addr2d`, `rd_data`, `rd_valid`, `rd_done`

### 3. Contracts
- Output特征图乒乓缓存必须优先实现为块RAM, 不能默认依赖综合器把普通寄存器数组自动优化成可接受的存储资源.
- 两个bank都必须使用 BRAM 推断友好写法:
  - `(* ram_style = "block" *) reg ... bank0 [...]`
  - `(* ram_style = "block" *) reg ... bank1 [...]`
- 读口必须保持当前系统已经使用的单拍同步读接口:
  - 外部在第 `N` 拍给出 `rd_en + rd_addr2d`
  - 模块在第 `N+1` 拍给出对应 `rd_data + rd_valid`
- 写口仍由外部二维地址显式驱动, 模块内部只做 `row * IMG_W + col` 转换.
- 不能为了省事把完整 `24x24x32` 特征图bank综合成触发器阵列.

### 4. Validation & Error Matrix
- `pingpong_img_buf` 综合后 `RAMB18/RAMB36 = 0` 且 `FF/LUT` 异常膨胀 -> 视为实现错误
- 修改为BRAM版后, `rd_valid` 相对旧接口多拖一拍 -> 视为接口回归
- 为了推断BRAM把读口改成异步读组合逻辑 -> 视为错误写法
- 顶层资源暴涨且主要来源为 `FDRE` / `LUT6` 而非 `RAMB18` -> 优先检查 `pingpong_img_buf` 是否仍在寄存器化

### 5. Good/Base/Bad Cases
- Good: `pingpong_img_buf` 的两个bank都以 block RAM 推断, 顶层 6 路输出缓存主要消耗 BRAM.
- Base: 维持现有外部接口和 TB 时序, 只替换内部存储实现.
- Bad: 继续使用普通 `reg [31:0] bank0 [0:575]` / `bank1 [0:575]` 并让 Vivado 把整块数据摊成寄存器.

### 6. Tests Required
- 行为仿真:
  - 现有 `l1_top_tb` 必须继续通过
  - 断言点: `SUMMARY: err_cnt=0`
- 综合检查:
  - 单独综合 `pingpong_img_buf` 或完整综合 `l1_top`
  - 断言点: 输出缓存相关资源开始进入 `RAMB18/RAMB36`
  - 断言点: 不再出现此前那种 `FDRE` 二十多万级的异常膨胀

### 7. Wrong vs Correct
#### Wrong
```verilog
reg signed [31:0] bank0 [0:575];
reg signed [31:0] bank1 [0:575];

always @(posedge clk) begin
    if(wr_fire) bank0[wr_addr_1d] <= wr_data;
    if(rd_en)   rd_data <= bank0[rd_addr_1d];
end
```

#### Correct
```verilog
(* ram_style = "block" *) reg signed [31:0] bank0 [0:575];
(* ram_style = "block" *) reg signed [31:0] bank1 [0:575];

always @(posedge clk) begin
    if(bank0_wr_fire) bank0[wr_addr_1d] <= wr_data;
    if(bank0_rd_fire) bank0_rd_data <= bank0[rd_addr_1d];
end
```

---

## Scenario: First-Layer Six-Lane Console Trace Must Match PC Golden Format

### 1. Scope / Trigger
- Trigger: first-layer bring-up now needs direct human-readable comparison between RTL simulation console output and PC-side six-lane convolution golden output.

### 2. Signatures
- RTL console trace:
  - `SIM_WIN idx=<idx> row=<row> col=<col> lane0=<v0> ... lane5=<v5>`
- PC golden trace:
  - `PC_WIN idx=<idx> row=<row> col=<col> lane0=<v0> ... lane5=<v5>`

### 3. Contracts
- `l1_top_tb` must print one line per output window when `out_valid=1`.
- Each printed line must contain:
  - flattened output index `idx`
  - output coordinates `row`, `col`
  - all six first-layer lane results in fixed `lane0` to `lane5` order
- The PC-side golden script must emit the same traversal order:
  - raster order over the `24x24` output map
  - same lane ordering `0..5`
- The purpose of the prefix difference `SIM_WIN` vs `PC_WIN` is only source tagging; field order after that must remain aligned.

### 4. Validation & Error Matrix
- RTL prints only lane0 while PC generates six-lane output -> manual comparison becomes incomplete
- RTL and PC use different window traversal order -> line-by-line comparison becomes misleading
- RTL and PC use different lane ordering -> false mismatch during review

### 5. Good/Base/Bad Cases
- Good: `SIM_WIN idx=108 row=4 col=12 ...` and `PC_WIN idx=108 row=4 col=12 ...` differ only by prefix and match lane values.
- Base: console traces are compared by eye or with a simple diff after prefix normalization.
- Bad: one side prints matrix blocks while the other side prints flattened stream order with no shared indexing.

### 6. Tests Required
- `l1_top_tb` behavioral simulation must still end with `SUMMARY: err_cnt=0`.
- PC golden script must generate:
  - one six-lane full-map text file
  - one line-by-line console-style text file

---

## Scenario: L1-L2 Joint Bring-Up Must Use PC + RTL Cross-Check On One Lane

### 1. Scope / Trigger
- Trigger: after `l1l2_top_tb` is behaviorally stable, the user wants one more verification layer: use the joint TB dataflow, then cross-check one selected lane against a PC-computed relu+pool result to confirm the upstream modules are numerically correct through the first two stages.

### 2. Signatures
- Joint simulation TB:
  - `l1l2_top_tb`
- Joint RTL path:
  - `l1_top` -> `l2_top`
- Compared result scope:
  - one selected lane `lane_id`
  - one full `12x12` pooled output map for that lane
- Pass summary:
  - `SUMMARY: err_cnt=0`

### 3. Contracts
- The verification source remains the joint integration TB, not a detached single-module TB.
- The PC side must use:
  - the same input image file as `l1l2_top_tb`
  - the same first-layer weight file as `l1l2_top_tb`
  - the same relu rule and right-shift quantization rule
  - the same `2x2 stride=2` pooling traversal rule
- The PC side must select one concrete lane and compute that lane's full `12x12` pooled map.
- `l1l2_top_tb` must read back the same lane's pooled output map from RTL and compare point-by-point.
- This check is not optional after joint bring-up is declared stable; it is the numerical truth check for the whole `l1 -> l2` path.

### 4. Validation & Error Matrix
- PC computes first-layer conv only while TB checks pooled output -> verification scope mismatch
- PC and TB choose different lane indices -> false mismatch
- PC uses different quantization or pooling order -> false mismatch
- TB only checks `pool_done` / `frame_valid` and skips numerical comparison -> integration correctness remains unproven

### 5. Good/Base/Bad Cases
- Good: choose `lane0` (or any explicitly named lane), run PC to generate one `12x12` pooled golden map, then let `l1l2_top_tb` read back the same lane from RTL and confirm every point matches.
- Base: one-lane numerical cross-check is sufficient for bring-up, while the other lanes are still covered by existing RTL internal checks and shared-path logic.
- Bad: visually inspect waveforms only and conclude the whole two-stage path is correct without a PC numerical golden comparison.

### 6. Tests Required
- `l1l2_top_tb` must still end with:
  - `SUMMARY: err_cnt=0`
- One PC script or one PC calculation step must generate:
  - one selected lane's `12x12` pooled golden result
- The joint TB must compare:
  - same lane index
  - same raster-order `12x12` coordinates
  - same pooled output values
- Review record must state clearly:
  - which lane was selected
  - which input image file was used
  - which weight file was used

### 7. Wrong vs Correct
#### Wrong
```text
Run l1l2_top_tb, see pool_done=1, then assume l1+l2 is correct.
```

#### Correct
```text
Run l1l2_top_tb, choose one lane, compute the same lane's 12x12 relu+pool map on PC,
then compare every output point and require SUMMARY: err_cnt=0.
```
- At least one directed window such as `idx=108 row=4 col=12` must be visually checkable across both outputs.

### 7. Wrong vs Correct
#### Wrong
```verilog
$display("lane0=%0d", out_data);
```

#### Correct
```verilog
$display("SIM_WIN idx=%0d row=%0d col=%0d lane0=%0d lane1=%0d lane2=%0d lane3=%0d lane4=%0d lane5=%0d",
         out_cnt,
         out_cnt / OUT_W,
         out_cnt % OUT_W,
         pick_lane_out_data(0),
         pick_lane_out_data(1),
         pick_lane_out_data(2),
         pick_lane_out_data(3),
         pick_lane_out_data(4),
         pick_lane_out_data(5));
```

---

## Scenario: Third-Layer `6in12out` Reuses `72` First-Layer Conv Slices

### 1. Scope / Trigger
- Trigger: the project is moving from verified `l1 + l2` into the third convolution stage, and the chosen first implementation route is to reuse the existing `conv_core` arithmetic slice directly instead of redesigning a new `6in1out` kernel first.

### 2. Signatures
- Reused arithmetic slice:
  - `conv_core`
- Third-layer logical output grouping:
  - `12` logical output kernels
  - each logical output kernel consumes `6` input channels
- Third-layer physical compute grouping:
  - `12` groups
  - each group contains `6` instances of `conv_core`
  - total physical slice count = `72`
- Weight preload meaning:
  - one logical third-layer output kernel owns `6 * 25 = 150` weights
  - one physical `conv_core` slice still owns only `25` weights

### 3. Contracts
- In current architecture, `conv_core` is a `1in1out` serial `5x5` convolution slice, not a full `Cin x Cout` kernel.
- Therefore, true third-layer `6in12out` must not be modeled as only `12` unchanged `conv_core` instances.
- The accepted first implementation is:
  - one shared window-address traversal for the current spatial output point
  - `6` parallel source feature-map reads for the `6` input channels
  - `12` logical output groups in parallel
  - inside each logical output group, `6` `conv_core` slices consume the `6` channel streams
  - one local adder combines the `6` partial sums into one final `32bit` output result for that output channel
- Interface hierarchy must stay two-level:
  - external / layer-facing view stays at `12` logical output kernels
  - internal implementation may expand each logical output kernel into `6` physical `conv_core` slices
- Global weight preload should still keep the logical destination meaning:
  - layer-local destination remains `12` output-kernel IDs
  - local third-layer wrapper is responsible for splitting one logical `150`-weight block into `6` physical `25`-weight slice loads
- Address-generation ownership must remain outside `conv_core`.
- The third-layer output buffer ownership should stay one buffer per logical output channel, not one buffer per physical slice.

### 4. Validation & Error Matrix
- instantiate only `12` unchanged `conv_core` blocks and call that `6in12out` -> functionally incomplete, because each output channel misses `5` input-channel partial sums
- expose `72` physical slice IDs directly as the long-term layer-facing top contract -> cross-layer weight and buffer ownership become harder to manage
- give each physical slice its own spatial address manager -> duplicated control and channel-skew risk
- store one physical slice result per buffer instead of summing `6` slices into one logical output -> wrong output feature-map meaning
- push `6`-channel accumulation responsibility back into `conv_core` without redesigning the module contract -> violates the chosen reuse-first route

### 5. Good/Base/Bad Cases
- Good: build one `l3_out_core` style wrapper that owns one logical output channel, instantiates `6` `conv_core` slices, sums their results, and later replicate that wrapper `12` times.
- Base: even before the full `12`-output top exists, verification may begin from one logical `6in1out` output core that proves the reuse route is numerically correct.
- Bad: flatten the whole third layer directly into one `72`-instance unstructured top with no logical-output grouping.

### 6. Tests Required
- First verification step must target one logical output group:
  - `6` source channels
  - `6` physical `conv_core` slices
  - `1` summed output
- Assertions/check points for that step:
  - all `6` slices consume aligned window progress
  - all `6` slice weight groups are independently loaded
  - one logical output result equals the PC golden `6`-channel convolution sum
- Full third-layer verification later must cover:
  - `12` logical outputs
  - total preload matching `12 * 6 * 25 = 1800` weights
  - one output buffer per logical output channel
  - no spatial skew among the `12` output channels

### 7. Wrong vs Correct
#### Wrong
```text
6in12out = instantiate 12 unchanged conv_core blocks
```

#### Correct
```text
6in12out = 12 logical output groups
each logical output group = 6 unchanged conv_core slices + 1 local partial-sum combiner
total physical conv_core count = 72
```

---

## Scenario: Third-Layer `l3_core` Uses Shared Window Addressing With `12` Parallel Output Groups

### 1. Scope / Trigger
- Trigger: after `l3_out_core` is verified, the next bring-up stage is not the full system top yet, but a third-layer local integration block that connects `6` input feature-map buffers, one shared address manager, `12` parallel output groups, and `12` output ping-pong buffers.

### 2. Signatures
- Local integration block:
  - `l3_core`
- Upstream source side:
  - `src_frame_valid[5:0]`
  - `src_rd_en[5:0]`
  - `src_rd_addr2d[5:0]`
  - `src_rd_data[5:0]`
  - `src_rd_valid[5:0]`
  - `src_rd_done[5:0]`
- Weight side:
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
  - `cfg_weight_out`
  - `cfg_weight_cin`
- Output side:
  - `dst_frame_valid[11:0]`
  - `dst_rd_en[11:0]`
  - `dst_rd_addr2d[11:0]`
  - `dst_rd_data[11:0]`
  - `dst_rd_valid[11:0]`
  - `dst_rd_done[11:0]`

### 3. Contracts
- `l3_core` is a layer-local integration core, not the final global wrapper for third-layer preload and cross-layer orchestration.
- `l3_core` must reuse:
  - one `win_addr_mgr` parameterized for `12x12`, `K=5`, `stride=1`
  - `12` instances of `l3_out_core`
  - `12` instances of `pingpong_img_buf` for `8x8` signed `32bit` outputs
- The shared address manager owns only one spatial traversal stream for the current window.
- That one spatial address must be broadcast to all `6` upstream input feature-map buffers.
- `l3_core` must wait until all `6` source buffers return valid data for the same requested address before broadcasting one `6`-lane pixel beat into the `12` output groups.
- `l3_core` must wait until all `12` `l3_out_core` instances produce valid results and all `12` destination output buffers are writable before asserting one aggregate commit and advancing the shared address manager.
- `src_rd_done` is a frame-level release signal for the `6` upstream source buffers and must assert only after the full `8x8` third-layer output map has completed for the current source-frame transaction.
- `cfg_weight_out` selects which of the `12` logical output groups currently accepts weight beats.
- `cfg_weight_cin` is forwarded into the selected `l3_out_core` and selects which of that output group's `6` internal conv slices currently accepts the beat.
- `weight_loaded` at `l3_core` level means all `12` logical output groups report loaded, not just one output group.

### 4. Validation & Error Matrix
- let each source buffer receive a different traversal address in the same cycle -> input-channel spatial misalignment
- broadcast source pixels into `12` output groups before all `6` source buffers return valid -> mixed-window data hazard
- advance the shared address manager when only some output groups finished -> output-channel coordinate skew
- pulse `src_rd_done` every window or every row instead of after the full map -> upstream frame released too early
- treat `l3_core` as the final weight-routing owner and fold in unrelated global preload policy -> boundary coupling regression

### 5. Good/Base/Bad Cases
- Good: `l3_core` reads one `5x5` window position across all `6` input channels, feeds all `12` output groups in parallel, then writes one `8x8` output point into each of `12` output buffers.
- Base: `l3_core_tb` may instantiate `6` local source ping-pong buffers, preload them with synthetic `12x12` maps, then verify all `12` `8x8` outputs against TB-side software convolution.
- Bad: duplicate `win_addr_mgr` twelve times and let each output group walk the source feature maps independently.

### 6. Tests Required
- `l3_core_tb` must verify:
  - source side: all `6` source buffers become frame-valid before start
  - preload side: `12 * 6 * 25` weights are accepted and `weight_loaded=1`
  - run side: one full `8x8` scan completes and `done` pulses
  - readback side: all `12 * 8 * 8` output points match TB-side expected results
- Assertion points:
  - `SUMMARY: err_cnt=0`
  - `rd_cnt=64`
  - `weight_loaded=1`
  - completion pulse observed once for the run

### 7. Wrong vs Correct
#### Wrong
```text
Third layer output group 0 and output group 1 may advance their write coordinates independently.
```

#### Correct
```text
All 12 third-layer output groups share one window traversal and commit one output coordinate together.
```

---

## Scenario: Third-Layer `l3_top` Bridges Global Weight Stream Into Local `6x25` Slice Loads

### 1. Scope / Trigger
- Trigger: after `l3_core` is verified, the next bring-up stage adds a third-layer outer wrapper that accepts the existing global serialized weight stream and translates third-layer logical kernel weights into the local `cfg_weight_out + cfg_weight_cin + cfg_weight_last` contract required by `l3_core`.

### 2. Signatures
- Outer wrapper:
  - `l3_top`
- Global preload side:
  - `cfg_weight_valid`
  - `cfg_weight_data`
  - `cfg_weight_last`
  - `cfg_weight_ready`
  - `cfg_weight_done`
  - `cfg_last_err`
- Local third-layer weight side:
  - `cfg_weight_out`
  - `cfg_weight_cin`
  - `cfg_weight_last`
- Run side:
  - `start`
  - `ready`
  - `busy`
  - `done`

### 3. Contracts
- `l3_top` is the layer-facing third-layer wrapper; `l3_core` remains the local compute-and-buffer integration core.
- The current global weight stream still uses logical destination `{layer_id, kernel_id}` from `wgt_dist_global`.
- At this stage:
  - `layer_id=0` still represents first-layer `6 x 25` preload blocks
  - `layer_id=1` represents third-layer logical output kernels, each with `150` weights
- `l3_top` must accept only third-layer targets `(1,0) ~ (1,11)` and forward those beats into `l3_core`.
- For one accepted third-layer logical kernel:
  - weight index `0..24` -> `cfg_weight_cin=0`
  - weight index `25..49` -> `cfg_weight_cin=1`
  - weight index `50..74` -> `cfg_weight_cin=2`
  - weight index `75..99` -> `cfg_weight_cin=3`
  - weight index `100..124` -> `cfg_weight_cin=4`
  - weight index `125..149` -> `cfg_weight_cin=5`
- `l3_top` must generate local `cfg_weight_last` only on the final beat of each `25`-weight slice, not only on the final beat of the full `150`-weight logical kernel.
- Non-third-layer targets on the global stream must not block progress in this wrapper stage; they are acknowledged and skipped locally.
- `start` must be gated so third-layer run phase begins only after the full global preload transaction has completed.
- `weight_loaded` at `l3_top` level means `l3_core` reports all `12` third-layer logical output groups loaded.

### 4. Validation & Error Matrix
- forward one `150`-weight logical kernel into `l3_core` without splitting into `6 x 25` slices -> internal `conv_core` slices receive wrong load boundaries
- generate local `cfg_weight_last` only on weight index `149` -> only one internal slice sees end-of-load, other slices never report loaded
- let non-third-layer global targets wait on third-layer local readiness -> unnecessary cross-layer preload coupling
- allow `start` before global preload completion -> third-layer compute may begin before all logical kernels are loaded

### 5. Good/Base/Bad Cases
- Good: one third-layer logical output kernel consumes `150` serialized global weights, and the wrapper translates them into `6` independent `25`-beat local slice loads.
- Base: `l3_top_tb` may prepend first-layer placeholder weights, then send the third-layer logical blocks and still observe correct third-layer output maps.
- Bad: expose raw global `weight_idx[0:149]` directly to `l3_core` and expect it to infer slice boundaries by itself.

### 6. Tests Required
- `l3_top_tb` must verify:
  - one full global preload stream of `6 * 25 + 12 * 150 = 1950` beats is accepted
  - `cfg_last_err=0`
  - `cfg_weight_done` pulses once at end of the full global preload
  - `weight_loaded=1` before run starts
  - one full `8x8` scan completes and `done` pulses
  - all `12 * 8 * 8` readback points match TB-side software convolution
- Assertion points:
  - `SUMMARY: err_cnt=0`
  - `rd_cnt=64`
  - `weight_loaded=1`
  - `cfg_last_err_seen=0`

### 7. Wrong vs Correct
#### Wrong
```text
Third-layer top receives one 150-weight logical kernel and forwards only cfg_weight_out, leaving l3_core to guess which internal slice the current beat belongs to.
```

#### Correct
```text
Third-layer top receives one 150-weight logical kernel, maps weight_idx into cfg_weight_cin=0..5, and asserts local cfg_weight_last on every 25th beat.
```

---

## Scenario: Fourth-Layer `relu+pool` Reuses The Existing Single-Channel Wrapper Across `12` Lanes

### 1. Scope / Trigger
- Trigger: after third-layer `12 x 8x8` output maps are verified, the next bring-up step is the following relu+pool stage, and the chosen route is to reuse the already verified single-channel relu+pool wrapper instead of redesigning a new fourth-layer-specialized datapath.

### 2. Signatures
- Reused single-channel wrapper:
  - `relu_pool_l2`
- Reused pure compute core:
  - `relu_pool_core`
- New fourth-layer top:
  - `l4_top`
- Upstream source side:
  - `src_frame_valid[11:0]`
  - `src_rd_en[11:0]`
  - `src_rd_addr2d[11:0]`
  - `src_rd_data[11:0]`
  - `src_rd_valid[11:0]`
  - `src_rd_done[11:0]`
- Output side:
  - `dst_frame_valid[11:0]`
  - `dst_rd_en[11:0]`
  - `dst_rd_addr2d[11:0]`
  - `dst_rd_data[11:0]`
  - `dst_rd_valid[11:0]`
  - `dst_rd_done[11:0]`

### 3. Contracts
- Fourth-layer stage is still `relu` first, then `2x2 stride=2` max-pooling.
- Quantization rule remains the same as the original design and current second-stage implementation:
  - negative `32bit` input -> clamp to `0`
  - non-negative value -> arithmetic right shift by `10`
  - quantized output width -> signed `8bit`
- The current reuse rule is:
  - one `relu_pool_l2` instance still owns one single-channel map traversal
  - `l4_top` replicates that wrapper `12` times in parallel
- For fourth-layer use, the parameter set becomes:
  - input map `8x8`
  - output map `4x4`
  - input width `32bit`
  - output width `8bit`
- `l4_top` must not introduce a new address-generation rule; it reuses the same wrapper-owned pooled-window traversal used by `relu_pool_l2`.
- `l4_top` aggregate `done` means all `12` lanes finished one full `4x4` map.
- Upstream read-bank release remains lane-local; each lane asserts its own `src_rd_done` only after its full `4x4` pooled map is complete.

### 4. Validation & Error Matrix
- skip ReLU and pool raw signed conv outputs directly -> function mismatch with baseline
- change shift amount for fourth layer only -> cross-stage quantization mismatch
- redesign a new pool traversal path even though the single-channel wrapper already matches `8x8 -> 4x4` -> unnecessary divergence and new bug surface
- collapse `12` lanes into one serialized wrapper without updating top contract -> throughput and interface regression

### 5. Good/Base/Bad Cases
- Good: `l4_top` is structurally the same pattern as `l2_top`, but scaled from `6` lanes to `12` lanes and parameterized from `24x24 -> 12x12` to `8x8 -> 4x4`.
- Base: `l4_top_tb` may preload synthetic `12 x 8x8` feature maps, run one full pass, and compare all `12 x 4 x 4` pooled results against TB-side software relu+pool.
- Bad: fork a second relu quantization rule for fourth layer because the input source is `l3` instead of `l1`.

### 6. Tests Required
- `l4_top_tb` must verify:
  - all `12` source buffers become frame-valid before start
  - one full fourth-layer pass completes and `done` pulses
  - all `12 * 4 * 4` readback points match TB-side software relu+pool
- Assertion points:
  - `SUMMARY: err_cnt=0`
  - `rd_cnt=16`
  - completion pulse observed once

### 7. Wrong vs Correct
#### Wrong
```text
Because fourth layer follows l3, it needs a brand-new relu+pool module with a different quantization rule.
```

#### Correct
```text
Fourth layer still uses the same relu clamp + >>10 + 2x2 stride2 max-pool rule, so reuse the verified single-channel wrapper and scale it to 12 parallel lanes.
```

---

## Scenario: Third-Layer `l3_top` Must Support PC + RTL Numerical Cross-Check

### 1. Scope / Trigger
- Trigger: third-layer outer wrapper `l3_top` is behaviorally stable, but the user requires one more truth check: a PC-side generated full `12 x 8x8` convolution golden result must be compared against `l3_top_tb` readback output.

### 2. Signatures
- PC script:
  - `my_cnnV4/my_cnnV4_PCtest/l3_top12_pc_check.py`
- PC artifacts:
  - `l3_top12_global_weights.txt`
  - `l3_top12_feature_map_all.txt`
  - `l3_top12_console_lines.txt`
- RTL testbench:
  - `l3_top_tb`
- RTL console trace:
  - `RTL_L3 idx=<idx> row=<row> col=<col> out0=<v0> ... out11=<v11>`
- PC console trace:
  - `PC_L3 idx=<idx> row=<row> col=<col> out0=<v0> ... out11=<v11>`

### 3. Contracts
- PC side owns the numerical golden truth for the current directed third-layer case.
- `l3_top_tb` must not re-derive the expected full-map result locally once the PC golden contract is introduced.
- The PC script must generate:
  - one full global preload file matching the current synthetic third-layer test pattern
  - one full `12 x 8x8` output feature-map file
  - one line-by-line console-style text file in raster order
- `l3_top_tb` must read:
  - global preload data from `l3_top12_global_weights.txt`
  - expected output map from `l3_top12_feature_map_all.txt`
- `l3_top_tb` must print its own readback results in the same raster-order line format so the user can directly compare PC and RTL outputs.
- Line-format field order must stay aligned:
  - `idx`
  - `row`
  - `col`
  - `out0 .. out11`

### 4. Validation & Error Matrix
- TB computes local expected map while PC script also exists -> duplicated truth source, future drift risk
- PC and TB use different synthetic weight stream construction -> false mismatch
- PC and RTL print different output ordering -> user cannot compare line-by-line
- PC updates golden files but TB still points at old paths -> stale verification

### 5. Good/Base/Bad Cases
- Good: run the PC script first, then run `l3_top_tb`, then compare `PC_L3` and `RTL_L3` lines by `idx,row,col`.
- Base: the current directed third-layer case uses synthetic `6 x 12x12` inputs and synthetic `1950` global preload weights that exactly match the TB preload stream.
- Bad: declare `l3_top` correct only because `err_cnt=0` from a TB-side self-computed model, without a separate PC golden source.

### 6. Tests Required
- Run `l3_top12_pc_check.py` and confirm it emits:
  - `l3_top12_global_weights.txt`
  - `l3_top12_feature_map_all.txt`
  - `l3_top12_console_lines.txt`
- Run `l3_top_tb` and confirm:
  - `SUMMARY: err_cnt=0`
  - `rd_cnt=64`
  - `cfg_last_err_seen=0`
  - one `RTL_L3` line is printed for every `8x8` output coordinate
- Manual or scripted comparison must confirm `PC_L3` and `RTL_L3` lines match on all `64` coordinates.

### 7. Wrong vs Correct
#### Wrong
```text
l3_top_tb already computes the expected map internally, so a PC golden check is unnecessary.
```

#### Correct
```text
Use the PC script as the golden source, let l3_top_tb read the same weight/result files, and compare PC_L3 versus RTL_L3 line by line.
```

---

## Scenario: Fourth-Layer `l4_top` Must Support PC + RTL Numerical Cross-Check

### 1. Scope / Trigger
- Trigger: fourth-layer outer wrapper `l4_top` is behaviorally stable, and the verification route must match the third-layer rule: a PC-side generated full `12 x 4x4` relu+pool golden result is compared against `l4_top_tb` readback output.

### 2. Signatures
- PC script:
  - `my_cnnV4/my_cnnV4_PCtest/l4_top12_pc_check.py`
- PC artifacts:
  - `l4_top12_feature_map_all.txt`
  - `l4_top12_console_lines.txt`
- RTL testbench:
  - `l4_top_tb`
- RTL console trace:
  - `RTL_L4 idx=<idx> row=<row> col=<col> out0=<v0> ... out11=<v11>`
- PC console trace:
  - `PC_L4 idx=<idx> row=<row> col=<col> out0=<v0> ... out11=<v11>`

### 3. Contracts
- PC side owns the numerical golden truth for the current directed fourth-layer case.
- `l4_top_tb` must not re-derive the expected full-map result locally once the PC golden contract is introduced.
- The PC script must generate:
  - one full `12 x 4x4` output feature-map file
  - one line-by-line console-style text file in raster order
- `l4_top_tb` must read expected output data from `l4_top12_feature_map_all.txt`.
- `l4_top_tb` must print its own readback results in the same raster-order line format so the user can directly compare PC and RTL outputs.
- Line-format field order must stay aligned:
  - `idx`
  - `row`
  - `col`
  - `out0 .. out11`
- The current directed case uses the same synthetic input-map pattern already embedded in `l4_top_tb`, so the PC script must mirror that exact source-map construction.

### 4. Validation & Error Matrix
- TB computes local expected pool map while PC script also exists -> duplicated truth source, future drift risk
- PC and TB use different synthetic source-map construction -> false mismatch
- PC and RTL print different output ordering -> user cannot compare line-by-line
- PC updates golden files but TB still points at old paths -> stale verification

### 5. Good/Base/Bad Cases
- Good: run the PC script first, then run `l4_top_tb`, then compare `PC_L4` and `RTL_L4` lines by `idx,row,col`.
- Base: the current directed fourth-layer case uses synthetic `12 x 8x8` signed source maps and one full `12 x 4x4` pooled readback.
- Bad: declare `l4_top` correct only because `err_cnt=0` from a TB-side self-computed model, without a separate PC golden source.

### 6. Tests Required
- Run `l4_top12_pc_check.py` and confirm it emits:
  - `l4_top12_feature_map_all.txt`
  - `l4_top12_console_lines.txt`
- Run `l4_top_tb` and confirm:
  - `SUMMARY: err_cnt=0`
  - `rd_cnt=16`
  - `done_seen=1`
  - one `RTL_L4` line is printed for every `4x4` output coordinate
- Manual or scripted comparison must confirm `PC_L4` and `RTL_L4` lines match on all `16` coordinates.

### 7. Wrong vs Correct
#### Wrong
```text
l4_top_tb already computes the expected pool map internally, so a PC golden check is unnecessary.
```

#### Correct
```text
Use the PC script as the golden source, let l4_top_tb read the same result file, and compare PC_L4 versus RTL_L4 line by line.
```

---

## Scenario: `my_cnnV4` Five-Top Bring-Up Path Must Be Preserved Before Building The Global CNN Top

### 1. Scope / Trigger
- Trigger: `l1_top` ~ `l5_top` have all been separately brought up and behaviorally verified, and the next step is to build the final CNN-level wrapper without collapsing the layer boundaries back into one monolithic controller.

### 2. Signatures
- First-layer top:
  - `l1_top`
  - owns image input load, first-layer weight preload, `1in6out` convolution run, and `6` output feature-map buffer writes
- First relu+pool top:
  - `l2_top`
  - reads `6` first-layer output buffers and produces `6` pooled `12x12` maps
- Third-layer conv top:
  - `l3_top`
  - reads `6` pooled `12x12` maps, accepts global third-layer weights, and produces `12` convolution output maps
- Fourth-layer relu+pool top:
  - `l4_top`
  - reads `12` third-layer output buffers and produces `12` pooled `4x4` maps
- FC top:
  - `l5_top`
  - reads `12` pooled `4x4` maps, accepts FC global weights, and produces `10` final scores

### 3. Contracts
- The bring-up order is architectural, not accidental:
  - `l1_top` is the first V4 baseline and defines the reusable contracts for image input buffering, shared window address generation, convolution run handshake, and output feature-map writeback into ping-pong buffers.
  - `l2_top` proves that relu+pool is a separate next-stage boundary and must consume only the completed first-layer feature maps, not first-layer internal timing.
  - `l3_top` proves that the reused `conv_core` slice must scale through logical output grouping:
    - one logical output channel = `6` reused `conv_core` slices + one local accumulation boundary
    - the top then replicates that logical-output unit to `12` outputs
  - `l4_top` proves that the relu+pool path is reusable again at a different map size and lane count, without creating a new quantization rule.
  - `l5_top` proves that the FC stage is a separate contract:
    - upstream data source is `12 x 4x4`
    - runtime input beat format is `32` beats, each beat carrying `6` signed `8bit` values
    - downstream result is `10` parallel neuron scores
- Dependency ownership must stay layered:
  - `l2_top` depends on `l1_top` output buffer format, but not on `l1_top` internal cycle counts
  - `l3_top` depends on `l2_top` output feature-map layout and on the first-layer-style `conv_core` slice contract
  - `l4_top` depends on `l3_top` output buffer format, but reuses the same relu+pool wrapper rule already proven by `l2_top`
  - `l5_top` depends on `l4_top` output buffer format and on the FC preload contract from `wgt_dist_global`
- The future global CNN top must only own:
  - global preload ordering
  - layer start / busy / done sequencing
  - inter-layer ping-pong bank role hand-off
  - final result collection
- The future global CNN top must not reopen layer-local scheduling that already belongs inside the five verified tops.

### 4. Validation & Error Matrix
- rebuild the global design by wiring raw cores directly and bypassing the five tops -> layer ownership becomes unclear again and V1/V3-style coupling returns
- make a downstream top depend on upstream internal cycle timing instead of buffer-valid / handshake status -> integration becomes timing-fragile
- treat `l3_top` as `12` bare convolution instances instead of `12` logical outputs each built from `6` slices -> `6in12out` math and weight ownership both become wrong
- change relu quantization or pool traversal only because the map size changes from `l2_top` to `l4_top` -> stage-to-stage functional drift
- let `l5_top` consume pooled data without the fixed `32`-beat FC runtime contract -> FC weights and runtime indexing drift apart

### 5. Good/Base/Bad Cases
- Good: each top is treated as a stable layer-boundary block, and the next integration step composes those five tops rather than replacing them.
- Base: verification follows the same order as development: `l1_top -> l2_top -> l3_top -> l4_top -> l5_top`, with each later stage reusing already-proven lower-stage contracts.
- Bad: the five tops are treated as temporary TB wrappers only, and the final CNN top is rebuilt from raw address managers, raw conv slices, raw pool cores, and raw FC neurons.

### 6. Tests Required
- Keep one regression entry per major stage:
  - `l1_top_tb`: first-layer image load, preload, `6`-lane convolution, and output-buffer writeback
  - `l1l2_top_tb`: first convolution plus first relu+pool integration
  - `l3_top_tb`: third-layer global-weight translation, `6in12out` grouped convolution, and PC golden comparison
  - `l4_top_tb`: `12`-lane relu+pool reuse and PC golden comparison
  - `l5_top_tb`: FC preload plus `12 x 4x4 -> 10` classification result check
- Cleanup rules before global top integration:
  - keep handwritten RTL, top-level TBs, and PC check scripts
  - simulator-generated work libraries, temporary waveform databases, and PC-generated intermediate `.txt` outputs may be deleted because they are reproducible
- Before starting the global CNN top, verify:
  - all five tops still build from source directories only
  - no required source file exists only inside simulator work directories or generated output directories

### 7. Wrong vs Correct
#### Wrong
```text
The final CNN top should ignore l1_top~l5_top and directly reconnect all raw submodules, because those tops were only temporary simulation shells.
```

#### Correct
```text
The final CNN top should treat l1_top~l5_top as stable layer-boundary blocks, because each top already locked one reusable interface and one verified stage behavior.
```

---

## Scenario: Final `CNN.v` Must Use Real Split Preload Streams And Real `28x28` Image Files

### 1. Scope / Trigger
- Trigger: after `l1_top ~ l5_top` are separately verified, the final V4 CNN-level wrapper is introduced and must run against the user's real preload files instead of synthetic stage-local data.

### 2. Signatures
- Final top:
  - `CNN`
- External preload side:
  - `weight_tvalid`
  - `weight_tready`
  - `weight_tdata`
  - `weightfc_tvalid`
  - `weightfc_tready`
  - `weightfc_tdata`
- External image side:
  - `image_tvalid`
  - `image_tready`
  - `image_tdata`
- Final result side:
  - `result_tvalid`
  - `result_tready`
  - `result_tdata`
  - `cnn_done`

### 3. Contracts
- Final V4 preload is split into two physical streams:
  - `weight_t*` carries the real convolution preload stream for `l1_top + l3_top`
  - `weightfc_t*` carries the real FC preload stream for the final FC stage
- The final preload order is fixed:
  1. full convolution preload
  2. full FC preload
  3. one full `28x28` image frame
  4. `l1 -> l2 -> l3 -> l4 -> l5`
  5. serialize `10` final scores
- Real-file mapping for the current project:
  - convolution weights: `C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt`
  - FC weights: `C:/Users/28010/Desktop/my_cnn/sim/cnn_test/fcw.txt`
  - valid `28x28` image example: `C:/Users/28010/Desktop/my_cnn/test/0.txt`
- `C:/Users/28010/Desktop/my_cnn/sim/cnn_test/0.txt` is not a valid first-layer image source for V4 full-CNN integration, because it contains only `576` points, not `784`.
- The final top must not expose image-ready too early:
  - image feeding must start only after the image address path has been armed for the current frame
  - otherwise the first few pixels may be consumed before `frame_start` is aligned
- The final top must keep the layer-boundary ownership rule:
  - layer-local scheduling remains inside `l1_top ~ l5_top`
  - `CNN.v` owns only global preload ordering, layer starts, layer-done sequencing, and result serialization

### 4. Validation & Error Matrix
- use `sim/cnn_test/0.txt` directly as first-layer image input -> first layer sees undersized frame, whole-CNN check is invalid
- start image streaming before `frame_start` / image-path arm cycle -> first pixels may be dropped
- start downstream layer based on guessed cycle count instead of `ready/done` -> integration becomes timing-fragile
- force FC stage to consume a padded fake global stream when a real dedicated `fcw.txt` stream already exists -> top-level preload contract becomes harder to verify and maintain

### 5. Good/Base/Bad Cases
- Good: run `CNN_tb` with `test/0.txt`, `cw.txt`, and `fcw.txt`, then compare `RTL_SCORE` against PC-generated `cnn_scores.txt`.
- Base: preload all weights first, then feed one real `28x28` frame, then wait for `cnn_done`.
- Bad: reuse stage-local synthetic image files or synthetic weight streams in the final whole-CNN regression.

### 6. Tests Required
- Run `my_cnnV4/my_cnnV4_PCtest/cnn_pc_check.py` and confirm it emits:
  - `cnn_scores.txt`
  - `cnn_console_lines.txt`
- Run `my_cnnV4/my_cnnV4.sim/CNN_tb.v` and confirm:
  - all three real files are opened successfully
  - `RTL_SCORE idx=0..9` are printed
  - `EXP_SCORE idx=0..9` are printed
  - `SUMMARY err_cnt=0`
  - `RTL_PREDICT digit=<n>` is printed
- Manual or scripted comparison must confirm PC and RTL scores match exactly on all `10` outputs.

### 7. Wrong vs Correct
#### Wrong
```text
The final whole-CNN TB can keep using sim/cnn_test/0.txt because it already exists next to cw.txt and fcw.txt.
```

#### Correct
```text
Use a real 784-line image file such as test/0.txt for first-layer input, keep cw.txt and fcw.txt split, and let CNN.v preload conv, then FC, then image.
```

---

## Scenario: Vivado Project Source Lists Must Stay In Sync With RTL Renames And Cleanup

### 1. Scope / Trigger
- Trigger: reusable RTL modules were renamed or split out during `my_cnnV4` integration, and Vivado simulation failed at `xelab elaborate` even though the `.v` files existed on disk.

### 2. Signatures
- Project file:
  - `my_cnnV4/my_cnnV4.xpr`
- Generated simulation compile list:
  - `my_cnnV4/my_cnnV4.sim/sim_1/behav/xsim/*_vlog.prj`
- Typical failure log:
  - `my_cnnV4/my_cnnV4.sim/sim_1/behav/xsim/elaborate.log`

### 3. Contracts
- Handwritten RTL existing on disk is not enough; the file must also be present in Vivado `sources_1` to be compiled into simulation.
- After module renames or wrapper splits, `sources_1` must contain the new files:
  - example: `conv_core.v`
  - example: `win_addr_mgr.v`
  - example: `fc_wgt_dist_raw.v`
- Stale project entries that point to deleted files must be removed from `my_cnnV4.xpr`.
- Stale simulation view artifacts such as deleted `.wcfg` references should also be removed from `sim_1`, otherwise GUI simulation startup may keep warning or fail.

### 4. Validation & Error Matrix
- RTL file exists on disk but is not listed in `sources_1` -> `VRFC 10-2063 Module <...> not found`
- deleted old file still referenced in `xpr` -> project open emits critical warnings and compile order may stay dirty
- stale `.wcfg` path referenced by `sim_1` -> simulation launch may warn or bind to a dead waveform config

### 5. Good/Base/Bad Cases
- Good: after a rename or split, update `my_cnnV4.xpr`, then regenerate compile order so the generated `*_vlog.prj` contains the new RTL file.
- Base: inspect `elaborate.log` first when `Run Simulation` fails at elaborate stage.
- Bad: only copy the new `.v` file into the RTL folder and assume Vivado will pick it up automatically.

### 6. Tests Required
- Confirm `my_cnnV4.xpr` contains every active handwritten RTL file needed by the selected top.
- Confirm removed legacy files are no longer referenced in `my_cnnV4.xpr`.
- After reopening or refreshing the project, confirm generated `*_vlog.prj` includes the expected new files.
- Re-run simulation and verify `elaborate.log` no longer reports `Module <...> not found`.

### 7. Wrong vs Correct
#### Wrong
```text
Rename l1_addr_mgr -> win_addr_mgr on disk, but do not update my_cnnV4.xpr because the RTL folder already contains the new file.
```

#### Correct
```text
After RTL rename/cleanup, update my_cnnV4.xpr sources_1 and sim_1 references, then refresh compile order before rerunning simulation.
```

---

## Scenario: Parallel Testbench Drivers Must Not Share One Global Loop Counter

### 1. Scope / Trigger
- Trigger: `CNN_tb` uses `fork ... join` to send convolution weights, FC weights, and image pixels in parallel, and simulation appears to stall right after preload even though several handshake signals toggled.

### 2. Signatures
- Testbench tasks:
  - `send_conv_weights`
  - `send_fc_weights`
  - `send_image`
- Shared control pattern:
  - `fork ... join`
  - `while(<counter> < limit>)`

### 3. Contracts
- When multiple TB driver tasks run in parallel, each task must own its own local loop counter.
- A global integer such as `idx` must not be reused by multiple concurrent sender tasks.
- Each task must index only its own memory stream:
  - conv preload task -> local `conv_idx`
  - FC preload task -> local `fc_idx`
  - image task -> local `img_idx`

### 4. Validation & Error Matrix
- three forked tasks share one global counter -> one task may advance another task's loop termination condition, causing premature stop or deadlock
- preload handshake appears to complete but top state does not progress -> first suspect concurrent TB counter aliasing before blaming RTL

### 5. Good/Base/Bad Cases
- Good: each parallel sender task declares and uses its own local integer counter.
- Base: parallel stimulus is acceptable only if task-local state is fully separated.
- Bad: `send_conv_weights`, `send_fc_weights`, and `send_image` all read and write one shared `idx`.

### 6. Tests Required
- Review every forked TB sender task and confirm loop counters are task-local.
- If simulation stalls after preload, inspect whether any forked task still depends on shared mutable state.
- After fixing counters, rerun the whole-CNN TB and verify state progresses past preload into image load and layer execution.

### 7. Wrong vs Correct
#### Wrong
```verilog
integer idx;

fork
    send_conv_weights(); // uses idx
    send_fc_weights();   // also uses idx
    send_image();        // also uses idx
join
```

#### Correct
```verilog
task send_conv_weights;
    integer conv_idx;
endtask

task send_fc_weights;
    integer fc_idx;
endtask

task send_image;
    integer img_idx;
endtask
```

---

## Scenario: Third-Layer Weight Translator Must Be Pipelined Before Fanout

### 1. Scope / Trigger
- Trigger: routed timing for `my_cnnV4` at `50MHz` showed the worst setup path inside `l3_top`, from `u_wgt_dist_global` state registers into third-layer weight-routing control and then into many downstream convolution-slice weight enables.

### 2. Signatures
- Source stage:
  - `gw_weight_valid`
  - `gw_weight_data`
  - `gw_weight_idx`
  - `gw_weight_dst2d`
- Translator outputs:
  - `l3_cfg_weight_out`
  - `l3_cfg_weight_cin`
  - `l3_cfg_weight_last`
  - `l3_cfg_weight_valid`
- Recommended pipeline registers:
  - `l3_weight_pipe_valid_reg`
  - `l3_weight_pipe_data_reg`
  - `l3_weight_pipe_out_reg`
  - `l3_weight_pipe_cin_reg`
  - `l3_weight_pipe_last_reg`

### 3. Contracts
- Third-layer raw-weight translation must not remain one long combinational path from `wgt_dist_global` directly into `l3_core` / `l3_out_core` / `conv_core` fanout.
- At least one local register stage in `l3_top` must buffer translated weight-routing fields before they fan out to the `12 x 6` downstream slice network.
- The translator-side upstream ready must be derived from the local pipeline slot, not directly from the fully expanded downstream weight-enable tree.
- If timing still fails after one buffer stage and the endpoint moves onto the new local pipeline registers, the next optimization target is the translation arithmetic itself, especially constant multiply/divide/modulo logic.

### 4. Validation & Error Matrix
- direct `gw_* -> l3_core` combinational fanout remains -> routed setup path can land on deep `conv_core weight_mem_reg[*]/CE` endpoints with large net delay
- add one local pipeline stage and worst path moves to `l3_weight_pipe_*_reg/D` -> fanout cut succeeded, remaining issue is translator arithmetic depth
- add local buffering but leave upstream ready chained through the full downstream tree -> limited benefit, route delay may remain dominant
- replace one timing bottleneck with a new stale ordering bug -> preload sequence no longer matches PC / RTL golden order

### 5. Good/Base/Bad Cases
- Good: `l3_top` accepts translated raw weight info into local regs, then `l3_core` consumes from those regs on the next cycle.
- Base: one extra preload cycle is acceptable because third-layer weight loading is an offline pre-run phase.
- Bad: a third-layer translator computes raw-stream remap and drives all downstream slice enables in the same cycle.

### 6. Tests Required
- Re-run routed timing after adding the local translator pipeline and confirm:
  - WNS improves materially versus the unbuffered version
  - failing endpoints collapse significantly
  - the worst path endpoint moves from downstream `conv_core weight_mem_reg[*]` controls toward the new local pipe registers if translation arithmetic is now the next bottleneck
- Re-run existing `l3_top_tb` / whole-CNN regression and confirm weight order and final scores remain unchanged.

### 7. Wrong vs Correct
#### Wrong
```verilog
assign l3_cfg_weight_valid = gw_weight_valid && gw_is_l3_target;
assign l3_cfg_weight_last  = gw_weight_valid && gw_is_l3_target && l3_cfg_weight_last_sel_reg;
assign l3_cfg_weight_out   = l3_cfg_weight_out_reg;
assign l3_cfg_weight_cin   = l3_cfg_weight_cin_reg;
```

#### Correct
```verilog
assign l3_pipe_accept = !l3_weight_pipe_valid_reg || l3_cfg_weight_ready;
assign gw_weight_ready = !gw_is_l3_target || l3_pipe_accept;

assign l3_cfg_weight_valid = l3_weight_pipe_valid_reg;
assign l3_cfg_weight_out   = l3_weight_pipe_out_reg;
assign l3_cfg_weight_cin   = l3_weight_pipe_cin_reg;
assign l3_cfg_weight_last  = l3_weight_pipe_last_reg;
```

---

## Scenario: Third-Layer Raw Weight Translation Should Use Local Counters Instead Of Divide/Modulo

### 1. Scope / Trigger
- Trigger: after one preload-side pipeline cut was added in `l3_top`, routed timing at `50MHz` still failed on the local translation path from `l3_weight_decode_*` into `l3_weight_pipe_*`, with the endpoint already moved onto the local pipe registers.

### 2. Signatures
- Global preload input context:
  - `gw_weight_valid`
  - `gw_weight_data`
  - `gw_weight_dst2d`
- Local translator state:
  - `l3_route_cin_reg`
  - `l3_route_out_reg`
  - `l3_route_tap_reg`
- Local translated outputs:
  - `l3_weight_pipe_out_reg`
  - `l3_weight_pipe_cin_reg`
  - `l3_weight_pipe_last_reg`

### 3. Contracts
- For the current V4 third-layer preload contract, `l3_top` must assume the raw stream order is fixed:
  - `cin-major -> out 0..11 -> tap 0..24`
- When this order is fixed and already validated against `my_cnnV1`, `l3_top` must not reconstruct `cfg_weight_cin` / `cfg_weight_out` / `cfg_weight_last` through runtime `*`, `/`, or `%` arithmetic on `kernel_id` and `weight_idx`.
- Instead, `l3_top` should advance local counters only on accepted local decode-to-pipe transfers.
- Counter advance must remain handshake-owned:
  - if decode beat is not accepted into the local pipe stage, local route counters must not advance
  - non-third-layer global beats may still be skipped locally without affecting the third-layer route counters

### 4. Validation & Error Matrix
- keep `kernel_id * 150`, `% 300`, `/ 25` style translation in one combinational block -> timing hotspot remains inside `l3_top`, often with large carry-chain depth
- local counters advance on `gw_weight_valid` instead of local accept -> preload order can drift under backpressure
- local counters reset or wrap at the wrong boundary -> one logical output kernel may receive another kernel's slice weights
- local counter translation matches the accepted raw stream order -> preload behavior stays stable while timing depth drops materially

### 5. Good/Base/Bad Cases
- Good: `l3_top` buffers one accepted third-layer beat, sends current `cin/out/tap` route tags to the pipe stage, then advances counters for the next accepted beat.
- Base: one more cycle of preload latency is acceptable because all third-layer weights are loaded before run phase begins.
- Bad: `l3_top` uses arithmetic reconstruction from `gw_kernel_id` and `gw_weight_idx` every cycle even after timing reports show that translator arithmetic is the remaining bottleneck.

### 6. Tests Required
- Re-run routed timing after replacing arithmetic translation with local counters and confirm:
  - the previous `l3_weight_decode_* -> l3_weight_pipe_*` worst path improves
  - logic level count on the worst remaining path drops materially
- Re-run at least:
  - `l3_top_tb`
  - whole-CNN regression / score check
- Confirm the third-layer preload order still matches the validated PC/RTL expectation.

### 7. Wrong vs Correct
#### Wrong
```verilog
l3_raw_weight_idx_int = (l3_weight_decode_kernel_reg * L1_WEIGHT_NUM) + l3_weight_decode_idx_reg;
l3_raw_block_idx_int = l3_raw_weight_idx_int % (L1_KERNEL_NUM * L0_WEIGHT_NUM);
l3_raw_group_idx_int = l3_raw_block_idx_int / (L0_KERNEL_NUM * L0_WEIGHT_NUM);
l3_raw_lane_idx_int = (l3_raw_block_idx_int % (L0_KERNEL_NUM * L0_WEIGHT_NUM)) / L0_WEIGHT_NUM;
l3_raw_tap_idx_int = l3_raw_block_idx_int % L0_WEIGHT_NUM;
```

#### Correct
```verilog
if(l3_weight_decode_valid_reg && l3_pipe_accept)
begin
    l3_weight_pipe_out_reg <= l3_route_out_reg;
    l3_weight_pipe_cin_reg <= l3_route_cin_reg;
    l3_weight_pipe_last_reg <= (l3_route_tap_reg == (L0_WEIGHT_NUM - 1));

    if(l3_route_tap_reg == (L0_WEIGHT_NUM - 1))
    begin
        l3_route_tap_reg <= '0;
        if(l3_route_out_reg == (OUT_NUM - 1))
        begin
            l3_route_out_reg <= '0;
            l3_route_cin_reg <= (l3_route_cin_reg == (SRC_NUM - 1)) ? '0
                                                                     : (l3_route_cin_reg + 1'b1);
        end
        else
        begin
            l3_route_out_reg <= l3_route_out_reg + 1'b1;
        end
    end
    else
    begin
        l3_route_tap_reg <= l3_route_tap_reg + 1'b1;
    end
end
```

---

## Scenario: Low-Bit Serial Convolution May Stay In LUTs While Parallel FC Uses DSPs

### 1. Scope / Trigger
- Trigger: after `my_cnnV4` reached `50MHz`, synthesis showed only `50` DSP48E1 blocks used, while most convolution logic still consumed LUT / CARRY resources.

### 2. Signatures
- Current convolution core:
  - `conv_core`
  - one serial multiply-accumulate per accepted pixel
- Current FC core:
  - `fc_neuron`
  - multiple same-cycle lane multiplies inside one combinational sum

### 3. Contracts
- Do not assume every `a * b` in RTL will automatically map into DSP48.
- In this project, the current `conv_core` style is a low-bit, single-lane, serial MAC:
  - one 8-bit pixel
  - one 8-bit weight
  - one multiply result added into a fabric accumulator
- Vivado may keep this style in LUT/CARRY fabric because:
  - operand width is small
  - only one multiply is active per core per cycle
  - the arithmetic is wrapped inside surrounding fabric accumulation/control
- In contrast, `fc_neuron` performs several same-cycle lane multiplies and is much more likely to infer DSP48 blocks.
- Asynchronous-reset datapath registers reduce DSP register merging opportunities, because DSP48 internal pipeline registers prefer synchronous-reset or no-reset style.

### 4. Validation & Error Matrix
- RTL contains small serial multiply only -> DSP usage can remain low even though arithmetic exists
- RTL contains parallel lane multiplies in one cycle -> DSP inference becomes much more likely
- datapath source regs use asynchronous reset -> methodology report may warn that DSP input pipelining / register merging is blocked
- designer interprets low DSP count as synthesis failure -> wrong conclusion; it may simply reflect current micro-architecture and inference heuristics

### 5. Good/Base/Bad Cases
- Good: treat DSP count as an architecture outcome first, not a pass/fail metric by itself.
- Base: current V4 can meet timing with LUT-based serial convolution and DSP-based FC.
- Bad: chase higher DSP count blindly before deciding whether the real bottleneck is LUT pressure, throughput, or timing margin.

### 6. Tests Required
- Check synthesis utilization and confirm whether DSPs are concentrated in `fc_neuron` / `l5_top_raw`.
- Check methodology / DRC reports for DSP messages about:
  - unpipelined DSP inputs
  - asynchronous-reset registers preventing DSP register merging
- When converting `conv_core` to DSP-first style later, rerun:
  - utilization
  - timing summary
  - at least one conv regression and whole-CNN score regression

### 7. Wrong vs Correct
#### Wrong
```verilog
// 只要写了乘法, 综合一定会自动吃 DSP
assign mult_term = in_data_ext * cur_weight;
```

#### Correct
```verilog
// DSP 是否被用上, 取决于并行度、位宽、流水级和复位风格
// 当前串行 conv_core 可能留在 LUT/CARRY
// 当前并行 fc_neuron 更容易推成 DSP48
```

---

## Scenario: DSP-Packing Must Be Demonstrated On A DSP-Hungry Baseline, Not On The Current Serial Conv Core

### 1. Scope / Trigger
- Trigger: the project already completed the first supervisor task by removing window-internal parallelism and moving to input/output-dimension parallelism, but a second task requires a visible DSP-packing demonstration inspired by the paper `DSP-Packing: Squeezing Low-precision Arithmetic into FPGA DSP Blocks`.

### 2. Signatures
- Current baseline modules:
  - `conv_core`
  - `fc_neuron`
- Candidate demonstration modules:
  - packed / unpacked low-bit convolution micro-kernel
  - packed / unpacked low-bit FC micro-kernel

### 3. Contracts
- Do not try to justify DSP-packing on the current serial `conv_core` alone.
- The current `conv_core` performs only one small multiply per cycle, so it does not create enough DSP pressure to make packing visually meaningful.
- A DSP-packing experiment in this project should be built as a paired comparison:
  - **baseline A**: low-bit parallel arithmetic mapped to normal DSP usage
  - **baseline B**: same arithmetic throughput mapped to packed DSP usage
- The comparison should preserve:
  - same mathematical task
  - same input/output contract
  - same effective throughput target
- The main evaluation dimensions should be:
  - DSP count
  - LUT / FF count
  - BRAM count if affected
  - achieved timing / Fmax
  - numerical correctness, or bounded error if using approximate overpacking

### 4. Validation & Error Matrix
- try to demonstrate DSP-packing on a serial low-DSP kernel -> no convincing resource delta, weak thesis evidence
- compare a packed kernel against a slower or functionally different baseline -> result is not academically fair
- use approximate overpacking without explicitly stating the error model -> experiment becomes hard to defend
- first create a DSP-hungry unpacked baseline, then compare against a packed version -> resource benefit becomes visible and explainable

### 5. Good/Base/Bad Cases
- Good: create a dedicated low-bit parallel MAC kernel whose unpacked version already consumes many DSPs, then show packing reduces DSP usage at similar throughput.
- Base: keep the existing V4 CNN as the functional system, but build a side experiment module for the DSP-packing study.
- Bad: force a packing narrative onto the existing serial convolution core even though its DSP usage is naturally low.

### 6. Tests Required
- For the unpacked baseline and packed version, collect:
  - synthesis utilization
  - post-route timing summary
  - functional simulation logs
- If the packed version is approximate, add:
  - absolute error / mean absolute error check
  - representative vector comparison against PC golden output

### 7. Wrong vs Correct
#### Wrong
```verilog
// 当前 conv_core DSP 用量不高, 也直接拿它证明 DSP packing
// 这样通常看不出明显差异
```

#### Correct
```verilog
// 先做一个会明显吃 DSP 的低比特并行 MAC 基线
// 再做 packed 版本, 对比 DSP/LUT/时序/精度
// 把 packing 当成“对照实验”, 而不是硬塞进当前串行卷积核
```

---

## Scenario: Interpret Current V4 DSP Usage By Distinguishing DSP Port Width From Effective Arithmetic Width

### 1. Scope / Trigger
- Trigger: after a long pause, the developer needs to answer two concrete questions about the current `my_cnnV4` implementation:
  - overall DSP utilization
  - how many bits a single inferred DSP is effectively using

### 2. Signatures
- Reports:
  - `my_cnnV4.runs/synth_1/CNN_utilization_synth.rpt`
  - `my_cnnV4.runs/impl_1/CNN_methodology_drc_routed.rpt`
- Relevant RTL:
  - `fc_neuron.v`
  - `conv_core.v`

### 3. Contracts
- Overall DSP count must be read from utilization reports, not guessed from RTL multiply count.
- For the current V4 snapshot:
  - total DSP usage is `50 / 220`
  - DSP usage is concentrated in `l5_top_raw -> fc_neuron`
  - current serial `conv_core` is still mostly LUT/CARRY based
- Do not confuse:
  - **DSP port width** seen in methodology reports, for example `A[29:0]` and `B[17:0]`
  - with **effective arithmetic width** coming from the RTL operands
- In the current `fc_neuron` implementation:
  - each input sample is sign-extended from `8` bits to `16` bits
  - each weight is sign-extended from `8` bits to `16` bits
  - the effective multiply is therefore about `16 x 16`
  - the accumulation result is held in `32` bits
- In the current `conv_core` implementation:
  - the pixel side is effectively `9` bits (`1'b0` + `8`-bit pixel)
  - the weight side is `8` bits signed
  - the effective multiply is therefore about `9 x 8`

### 4. Validation & Error Matrix
- read only DSP port widths from methodology report -> may wrongly conclude the design is fully using all multiplier precision
- read only RTL operand widths -> may wrongly conclude Vivado must have inferred DSPs for that arithmetic
- separate report-level DSP port width from RTL effective operand width -> current resource behavior becomes explainable

### 5. Good/Base/Bad Cases
- Good: answer both “用了多少个 DSP” and “单颗 DSP 实际承载了多宽的数据”.
- Base: current V4 uses DSP mainly in FC, not in convolution.
- Bad: state that all convolution multiplies are already充分利用 DSP just because the design contains `*`.

### 6. Tests Required
- Check `CNN_utilization_synth.rpt` for total DSP count.
- Check `CNN_methodology_drc_routed.rpt` for inferred DSP port naming and width hints.
- Cross-check those findings against operand sign extension in `fc_neuron.v` and `conv_core.v`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 报告里出现 A[29:0] / B[17:0], 就说明当前乘法真的吃满了 30x18
```

#### Correct
```verilog
// A[29:0] / B[17:0] 是 DSP 端口宽度
// 当前 fc_neuron 真正有效参与运算的大约是 16x16
// 当前 conv_core 真正有效参与运算的大约是 9x8
```

---

## Convention: Start DSP-Packing Exploration In A V5 Side Directory Instead Of Modifying The Stable V4 System First

**What**: When beginning the dedicated DSP-packing study, create a new experiment workspace at the same hierarchy level as `my_cnnV4`, and start with a minimal RTL-only directory layout under `my_cnnV5/rtl`.

**Why**:
- `my_cnnV4` already serves as the stable reference implementation for the first supervisor task.
- DSP-packing exploration changes numeric format, arithmetic structure, and evaluation method; it should not destabilize the validated V4 baseline too early.
- A side-by-side V5 experiment directory makes it easier to compare unpacked vs packed kernels cleanly.

**Required Initial Layout**:
```text
my_cnnV5/
└── rtl/
```

**Initial Rule**:
- First create only the directory skeleton.
- Do not copy the whole `my_cnnV4` tree into `my_cnnV5` at the start.
- Add DSP-packing experiment modules incrementally inside `my_cnnV5/rtl`.

**Good Pattern**:
```text
my_cnnV4/        # 稳定基线
my_cnnV5/rtl/    # DSP packing 实验起点
```

**Wrong Pattern**:
```text
my_cnnV5/        # 一开始就整份复制 V4, 混入大量无关文件
```

---

## Convention: V5 May Keep Two Parallel RTL Roots For Different Purposes

**What**: Under `my_cnnV5`, keep the validated `my_cnnV4` network RTL as one template root, while DSP-packing micro-experiments live in a separate lightweight root.

**Why**:
- The full CNN accelerator template and the DSP-packing study serve different goals.
- The template root preserves the already validated V4 architecture for staged V5 evolution.
- The lightweight experiment root avoids mixing small packing kernels into the main CNN source tree too early.

**Required Layout**:
```text
my_cnnV5/
├── cnn_rtl/   # 从 my_cnnV4_rtl 整体平移过来的模板版网络 RTL
├── rtl/       # DSP packing 等小型独立实验 RTL
├── reports/   # 独立实验综合报告
└── scripts/   # 独立实验脚本
```

**Contracts**:
- `cnn_rtl/` is the baseline template root for the next full-network V5 development.
- `rtl/` is reserved for small self-contained arithmetic experiments such as DSP packing.
- Do not mix the full CNN files into `rtl/`.
- Do not point packing experiment scripts at `cnn_rtl/` unless the experiment is intentionally upgraded into the main V5 architecture.

**Good Pattern**:
```text
my_cnnV5/cnn_rtl/CNN.v
my_cnnV5/cnn_rtl/conv_core.v
my_cnnV5/rtl/ref_mul2_int4.v
my_cnnV5/rtl/pack_mul2_int4.v
```

**Wrong Pattern**:
```text
my_cnnV5/rtl/CNN.v
my_cnnV5/rtl/l1_top.v
my_cnnV5/rtl/l5_top.v
my_cnnV5/rtl/pack_mul2_int4.v
```

---

## Convention: DSP-Packing First Bring-Up Starts From Exact 2-Lane Unsigned INT4 Packing

**What**: The first RTL bring-up inside `my_cnnV5/rtl` should start from an exact `2-lane` unsigned `INT4` packing experiment, not from `4-lane`, signed packing, or direct CNN integration.

**Why**:
- `2-lane` exact packing is the smallest case that still demonstrates the core idea of packing multiple low-bit multiplies into one wider multiply.
- It is much easier to verify mathematically and in simulation.
- It gives a stable baseline before attempting more aggressive `4-lane` or approximate overpacking.

**Required First Modules**:
- `ref_mul2_int4.v`
  - plain reference implementation
  - computes `a0*b0` and `a1*b1` directly
- `pack_mul2_int4.v`
  - exact packing implementation
  - packs two unsigned `4bit` lanes into one wider multiply

**Exact Packing Rule For First Bring-Up**:
- Use unsigned `4bit` inputs first.
- Use:
  - `pack_a = a0 + (a1 << 9)`
  - `pack_b = b0 + (b1 << 9)`
- Then:
  - low product is taken from `prod[7:0]`
  - high product is taken from `prod[25:18]`
- The `9bit` lane separation is chosen so that the middle cross-term band does not corrupt the high packed result.

**Good Pattern**:
```verilog
assign pack_a = {a1, 5'b0, a0};
assign pack_b = {b1, 5'b0, b0};
assign prod_full = pack_a * pack_b;
assign p0 = prod_full[7:0];
assign p1 = prod_full[25:18];
```

**Wrong Pattern**:
```verilog
// 仅留很小空隙就直接取高位结果
// 交叉项可能串入高路乘积, 不能作为精确 packing 基线
assign pack_a = {a1, 4'b0, a0, 4'b0};
assign pack_b = {b1, 4'b0, b0, 4'b0};
```

---

## Scenario: DSP-Packing Comparison Should Use DSP48E1 Primitives And Standalone OOC Synthesis

### 1. Scope / Trigger
- Trigger: a low-bit DSP-packing experiment in `my_cnnV5` showed misleading utilization because Vivado GUI project state and inferred arithmetic did not produce a trustworthy packed-vs-unpacked comparison.

### 2. Signatures
- Primitive wrapper:
  - `dsp48e1_mul_u.v`
  - input: `a`, `b`
  - output: `p`
- Baseline top:
  - `ref_mul2_int4.v`
- Packed top:
  - `pack_mul2_int4.v`
- Batch comparison entry:
  - `my_cnnV5/scripts/run_compare_synth.tcl`

### 3. Contracts
- For DSP-packing evaluation, do not rely on plain `*` inference when the goal is to prove DSP occupancy.
- The arithmetic core used for comparison must instantiate `DSP48E1` directly, so the baseline and packed versions are both pinned onto DSP resources.
- The baseline and packed versions must be synthesized as two independent out-of-context tops.
- The comparison script must read:
  - `dsp48e1_mul_u.v`
  - `ref_mul2_int4.v`
  - `pack_mul2_int4.v`
- Do not trust a GUI `synth_1` report if:
  - the project top is fixed to only one variant
  - the other variant is auto-disabled
  - stale incremental DCPs are still attached

### 4. Validation & Error Matrix
- use inferred multiply only -> Vivado may optimize the design back into LUT logic, DSP comparison becomes invalid
- synthesize only one top in GUI -> no packed-vs-unpacked conclusion can be drawn
- reuse stale incremental checkpoint from another top -> report may complete but comparison is not trustworthy
- run standalone OOC TCL for both tops -> DSP count becomes directly comparable

### 5. Good/Base/Bad Cases
- Good: `ref_mul2_int4` uses 2 `DSP48E1`, `pack_mul2_int4` uses 1 `DSP48E1`, both generated by the same standalone TCL flow.
- Base: keep the GUI project only as a container, but use batch TCL reports as the authoritative packing comparison result.
- Bad: quote one old GUI utilization report with `DSP=0` as the conclusion of the packing experiment.

### 6. Tests Required
- Run `my_cnnV5/scripts/run_compare_synth.tcl`.
- Check `ref_mul2_int4_summary.txt` and assert `dsp48e1_count=2`.
- Check `pack_mul2_int4_summary.txt` and assert `dsp48e1_count=1`.
- Check both utilization reports and confirm `DSP48E1 only` matches the summary count.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 只写 a * b, 然后希望 Vivado 自动帮你做成可控的 DSP packing 对照
assign p = a * b;
```

#### Correct
```verilog
// 对照实验直接例化 DSP48E1 原语
// 再用独立 OOC TCL 分别综合 baseline 和 packed 两个顶层
DSP48E1 u_dsp48e1_mul (...);
```
