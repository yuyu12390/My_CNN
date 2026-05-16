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
