# Journal - yuyu (Part 1)

> AI development session journal
> Started: 2026-05-14

---



## Session 1: my_cnnV4 l1 global weight and bram buffer

**Date**: 2026-05-16
**Task**: my_cnnV4 l1 global weight and bram buffer
**Branch**: `master`

### Summary

Integrated first-layer 6-lane top with global weight distribution, switched ofmap pingpong buffer to inferred BRAM, and kept top-level simulation aligned with real image/weight files.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0af1f9b` | (see git log) |
| `213bd6c` | (see git log) |
| `b89a588` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Complete my_cnnV4 end-to-end CNN integration

**Date**: 2026-05-19
**Task**: Complete my_cnnV4 end-to-end CNN integration
**Branch**: `master`

### Summary

Integrated the full five-stage my_cnnV4 pipeline, aligned third-layer raw-stream weight ordering with the V1 baseline, added whole-CNN RTL and PC cross-check flows, and reached correct digit recognition on the 28x28 test image.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b63fef8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: my_cnnV4整网打通并完成收尾上传

**Date**: 2026-05-19
**Task**: my_cnnV4整网打通并完成收尾上传
**Branch**: `master`

### Summary

完成my_cnnV4整网CNN集成与正确识别，修复第三层权重顺序对齐问题，补齐PC与RTL交叉验证链路，并修复Trellis归档收尾与中文提交说明约定。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b63fef8` | (see git log) |
| `9bb0924` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: my_cnnV4板级联调与IP封装排障

**Date**: 2026-06-11
**Task**: my_cnnV4板级联调与IP封装排障
**Branch**: `master`

### Summary

确认my_cnnV4单独工程与cnn_prj系统工程的时钟上下文差异，补齐IP封装时钟关联元数据，定位Vitis硬件平台漂移与FC权重重装载契约，并将这些结论沉淀到Trellis规范中。

### Main Changes

- ????????????`my_cnnV4` ?????RTL?`my_cnnipV4_0` ??AXI/IP???`cnn_prj` ?????????
- ??? 50MHz / 100MHz ???????? `my_cnnV4` ?? 20ns ??????????? 10ns????????? BD ???? 50MHz?
- ????? IP ????? `ASSOCIATED_BUSIF` ??????? AXI/?????????????????????
- ??? Vitis ???? bit/xsa ?? `xparameters.h` ?????????????? `XPAR_MYCNN_V4_0_BASEADDR` ??????
- ????????????????????? FC ????? `CNN.v` ???????? `start_cnn` ????? FC ?????
- ???????????? bring-up ????????? `my_cnn` ??????????? V4 ?????????????


### Git Commits

| Hash | Message |
|------|---------|
| `9a68924` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
