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
- Trigger: `my_cnnV4` first-layer convolution is refactored so `conv_l1` only consumes a pixel stream during run phase and no longer owns image-cache addressing.

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
- Trigger: `my_cnnV4` first-layer arithmetic core is split from BRAM addressing and implemented as `conv_l1`, a stream-fed serial convolution kernel.

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
  - `conv_l1_case0.py`
  - `conv_l1_case0_pixels.txt`
  - `conv_l1_case0_weights.txt`
  - `conv_l1_case0_result.txt`
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
  - `conv_l1_case0_feature_map.txt`
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

**What**: The first bring-up top for `my_cnnV4` may keep the data path simple by allowing only one outstanding read from `img_in_buf` at a time before feeding `conv_l1`.

**Why**:
- `img_in_buf` returns one pixel per accepted read address.
- `conv_l1` consumes one pixel stream beat at a time and may stall on output hold.
- A single-outstanding-read bridge is the lowest-risk way to verify the full layer boundary before introducing a richer reader or pipelined prefetch.

### Required Behavior

- The top may issue a new window address only when:
  - scan is active
  - source frame is valid
  - no prior read response is pending
  - no buffered pixel is waiting for `conv_l1`
  - `conv_l1.in_ready=1`
- After one read request is accepted, the top must remember whether that request was the window-last beat.
- When `img_in_buf.rd_valid=1`, the returned pixel is buffered into one local register stage and then forwarded to `conv_l1`.
- The top must not start the next read request until the buffered pixel has been consumed by `conv_l1`.

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
- Do not feed `conv_l1` directly from `img_in_buf.rd_data` without a valid-holding stage.
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
- Keeping this relation in one first-layer controller reduces top-level glue without pushing address ownership back into `conv_l1`.

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

l1_addr_mgr u_l1_addr_mgr(
    .rd_addr_ready(l1_rd_addr_ready),
    .out_fire(ofmap_out_fire),
    .wr_addr2d(l1_wr_addr2d),
    .wr_last(l1_wr_last)
);
```

### Wrong Pattern

- Do not increment the output write address immediately after the `25th` read beat if the convolution result has not been written yet.
- Do not make `conv_l1` count full-map output coordinates by itself.
- Do not reuse the generic `win_addr_mgr` unchanged when the design also needs output-write hold behavior.

### Tests Required

- Standalone `l1_addr_mgr_tb` must verify `25` reads followed by one held write address for each output point.
- Full-chain `l1_top_tb` must verify output write coordinates match the expected output-map traversal.
- Final write must assert `wr_last` on output point `(23,23)` for the `28x28`, `K=5`, `stride=1` first-layer case.

---

## Convention: First-Layer Output Ping-Pong Buffer Stores 32bit Convolution Sums

**What**: Before ReLU / quantization / pooling are inserted, the first-layer output ping-pong buffer stores raw `32bit signed` convolution sums.

**Why**:
- `conv_l1` currently exports signed `32bit` accumulation results.
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

**What**: The current first-layer top may use one shared image-read path and one shared spatial address manager, then broadcast the same `5x5` pixel stream to `6` parallel `conv_l1` lanes.

**Why**:
- First-layer `Cin=1`, so every output channel reads the same input window coordinates.
- Broadcasting one spatial stream removes duplicated read-control logic.
- The top still keeps output-channel parallelism explicit by giving each lane its own weight state and its own output ping-pong buffer.

### Required Interface Contract

- Shared image side:
  - one `img_in_buf`
  - one `l1_addr_mgr`
- Weight side:
  - one serialized weight input stream
  - one lane-select input `cfg_weight_lane`
- Compute side:
  - `6` instances of `conv_l1`
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

l1_addr_mgr u_l1_addr_mgr(
    .out_fire(all_lane_commit_fire)
);
```

### Wrong Pattern

- Do not instantiate `6` separate spatial window address managers for first-layer `Cin=1`.
- Do not allow lane 0 to advance the output write address before the other `5` lanes commit the same output point.
- Do not couple output-channel counting into `conv_l1`.
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
- `l1_addr_mgr.out_fire` is driven by this aggregate commit, not by any single lane.
- Each lane output buffer stores one full `24x24` feature map for that lane.

### 4. Validation & Error Matrix
- advance address manager after only one lane commits -> lane-to-lane output coordinate skew
- duplicate `l1_addr_mgr` per lane -> architectural duplication and control drift
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
- It keeps `conv_l1` unchanged and preserves the existing lane-local weight ownership.
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
- Do not merge weight-stream distribution into `conv_l1`.

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
- `weight_loaded` at wrapper level still means all six `conv_l1` lanes report loaded.

### 4. Validation & Error Matrix
- wrapper bypasses distributor and still requires manual `cfg_weight_lane` externally -> wrong integration boundary
- `cfg_weight_done` pulses after only one lane group -> premature start hazard
- wrong external `cfg_weight_last` is silently ignored with no visibility -> debug blind spot

### 5. Good/Base/Bad Cases
- Good: upstream sends the same `25`-weight file six times in sequence and wrapper produces the same six feature maps.
- Base: current TB reuses `conv_l1_case0_weights.txt` for all six lanes and verifies lane 0 against the PC golden map.
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
- This matches the current `conv_l1` contract: compute waits for weight-ready state.
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

## Scenario: First-Layer Minimal Full-Chain Top

### 1. Scope / Trigger
- Trigger: `my_cnnV4` now needs a first-layer bring-up top that connects image load, image buffer, spatial window scan, and serial convolution into one verifiable chain.

### 2. Signatures
- Top control inputs:
  - `frame_start`, `scan_start`, `frame_release`
- Top data inputs:
  - `image_tdata`, `image_tvalid`
  - `cfg_weight_valid`, `cfg_weight_data`, `cfg_weight_last`
- Top result outputs:
  - `out_valid`, `out_data`
- Top status outputs:
  - `scan_ready`, `scan_busy`, `scan_done`, `img_frame_valid`, `weight_loaded`

### 3. Contracts
- `img_in_addr_mgr` owns only external image write traversal.
- `img_in_buf` owns image storage and 2D-to-1D RAM translation.
- `win_addr_mgr` owns only convolution spatial read traversal.
- `l1_top` owns the handshake glue between `win_addr_mgr`, `img_in_buf`, and `conv_l1`.
- `l1_top` may buffer one returned pixel before feeding `conv_l1`.
- `scan_done` is asserted only after:
  - the final window address stream has completed
  - no read response remains pending
  - no buffered pixel remains unconsumed
  - `conv_l1` is idle and no held output remains

### 4. Validation & Error Matrix
- top exposes `image_tready=1` while write address path is not aligned -> image/address beat mismatch bug
- top issues multiple read addresses while only one response slot exists -> pixel ordering corruption
- top marks scan complete before buffered pixel or held result drains -> truncated layer output

### 5. Good/Base/Bad Cases
- Good: one top file contains only glue logic and keeps ownership boundaries of the four base modules intact.
- Base: current TB loads the real image file, loads one weight set, scans the full `24x24` output map, and checks the directed golden window.
- Bad: duplicate address generation inside the top or move BRAM ownership out of `img_in_buf`.

### 6. Tests Required
- Full-chain `l1_top_tb` behavioral simulation.
- Assertions/checks for image load completion, weight load completion, `scan_ready`, `scan_done`, total output count `576`, and directed result `1158`.

### 7. Wrong vs Correct
#### Wrong
```verilog
// 顶层直接把窗口地址持续推进, 不管读回应和卷积接收
assign win_addr_ready = scan_running;
```

#### Correct
```verilog
// 顶层在读回应和像素消费之间做单拍缓冲和流控
assign win_addr_ready = scan_running
                     && buf_frame_valid
                     && !rd_pending
                     && !pix_valid_reg
                     && conv_in_ready;
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