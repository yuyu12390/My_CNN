# Develop my_cnnV4 from my_cnnV1 baseline

## Goal

Develop `my_cnnV4` using `my_cnn` as the functional baseline, with the first priority being a precise understanding of the existing `my_cnnV1` RTL architecture, control flow, and module boundaries before any structural changes are made.

## What I already know

* The baseline `my_cnnV1` code is in `my_cnn/`, not in a separately named `my_cnnV1/` directory.
* The main RTL entry is `my_cnn/my_cnn_rtl/CNN.v`.
* The top-level simulation entry is `my_cnn/my_cnn.sim/top_tb.v`.
* `my_cnnV1` is a streaming design with separate input channels for image data, convolution weights, and FC weights, plus a streamed result output.
* The architecture is a hand-scheduled CNN pipeline built from custom RTL blocks: `window`, `conv`, `add`, `relu`, `maxpooling`, `FIFO_fmap`, `fc`, and AXIS FIFO IP instances.
* There are six parallel convolution lanes and ten parallel FC output neurons in the top-level design.
* `my_cnnV4/` already exists as a Vivado project skeleton with `my_cnnV4_rtl/`, but the new task is still in planning and requirements are not fixed yet.
* The user confirmed `my_cnnV4` should keep route `1`: preserve the existing external input-read behavior and mainly change the internal compute architecture.
* New RTL files should be written under `my_cnnV4/my_cnnV4_rtl/`.
* New simulation files should be written under `my_cnnV4/my_cnnV4.sim/`.
* The user wants comments written in Chinese with GBK-compatible encoding expectations.
* The first major V4 change target is convolution parallelism at the output-channel level, rather than further increasing window-internal parallelism first.
* `my_cnnV3` contains relevant experimental modules: `conv_pin2.v` and `conv2_pin2_pout6_pk1.v`, which are useful references for alternative parallelization strategies.
* The user explicitly judged `my_cnnV3` as unsuccessful because it became too tightly coupled.
* The user expects `my_cnnV4` to make a substantial internal structural redesign rather than only patching the V1/V3 control path.
* The user wants a layer-specific architecture first, with reuse/generalization considered only after the V4 baseline structure is stable.
* The intended V4 network decomposition is now explicit:
  * layer1: `in1 -> out6`, instantiate 6 convolution kernels
  * then `relu + pooling`
  * layer2: `in6 -> out12`, instantiate 12 convolution kernels and output 12 channels in parallel
  * then 12-channel pooling
  * then fully connected classification

## Assumptions (temporary)

* `my_cnnV4` will reuse the existing top-level input protocol and most non-convolution downstream stages unless the user later narrows or expands scope.
* The user wants a deep code-reading and architecture-understanding phase first, before implementation.
* The first useful outcome of this task is a stable baseline understanding plus a clear V4 convolution redesign target.
* `my_cnnV3` should be treated as a design reference, not automatically as the V4 baseline.
* `my_cnnV4` should reduce top-level coupling by separating scheduling responsibilities from compute datapaths more cleanly than V1/V3.
* The first V4 milestone is a clean layer-specific implementation, not a maximally generic engine.

## Open Questions

* In layer2 (`in6 -> out12`), should each of the 12 output kernels accumulate its 6 input channels fully in parallel, or should the 12 output channels be parallel while the 6-channel accumulation inside each output is time-multiplexed?

## Requirements (evolving)

* Build a reliable architectural understanding of `my_cnnV1` before modifying `my_cnnV4`.
* Identify the real top-level control flow, not just the file list.
* Identify where image data, weights, intermediate feature maps, and final outputs are stored, buffered, and sequenced.
* Distinguish reusable modules from hard-coded scheduling logic that may need redesign in `V4`.
* Keep the external input-read behavior unchanged from the current design.
* Place all new RTL code under `my_cnnV4/my_cnnV4_rtl/`.
* Place all new simulation code under `my_cnnV4/my_cnnV4.sim/`.
* Prioritize output-channel parallelism inside the convolution architecture.
* Preserve comment style compatibility with the user's GBK-based workflow.
* Avoid repeating the V3 mistake of embedding architecture experiments directly into a still highly coupled top-level controller.
* Redesign internal module boundaries so compute, buffering, and scheduling can evolve more independently.
* Implement V4 first as a layer-specific architecture:
  * layer1 convolution block for `1 -> 6`
  * layer1 activation/pooling block
  * layer2 convolution block for `6 -> 12`
  * layer2 pooling block
  * fully connected block
* Make output-channel parallelism explicit in layer2 by targeting 12 simultaneous output channels.
* Consider generic/reusable compute units only after the first layer-specific V4 structure is working and understandable.

## Acceptance Criteria (evolving)

* [ ] `my_cnnV1` top-level module responsibilities are summarized clearly.
* [ ] Core dataflow from input image to final FC output is summarized clearly.
* [ ] Major module roles (`window`, `conv`, `add`, `relu`, `maxpooling`, `FIFO_fmap`, `fc`) are identified.
* [ ] The V4 scope is confirmed as "same external input path, internal compute refactor".
* [ ] The target output-channel parallelization scope is clarified before implementation starts.
* [ ] Target file locations for RTL and simulation are fixed before implementation starts.
* [ ] The intended V4 architecture decomposition strategy is clarified before implementation starts.
* [ ] The layer structure `1->6`, `relu/pool`, `6->12`, `pool`, `fc` is captured as the V4 baseline.
* [ ] The layer2 accumulation strategy is clarified before implementation starts.

## Definition of Done (team quality bar)

* Requirements are written down in `prd.md`
* Key baseline architecture facts are captured in the task, not only in chat
* V4 scope is explicit enough to begin implementation safely
* Any later implementation step can point back to this baseline summary

## Technical Approach

Current planning approach:

1. Read `my_cnnV1` top-level RTL and testbench
2. Read each core compute/storage module
3. Inspect `my_cnnV3` for prior parallel-convolution experiments that may inform V4
4. Summarize the actual scheduling/dataflow behavior
5. Treat `my_cnnV3` as a negative reference where it increases coupling
6. Lock the V4 baseline layer structure (`1->6`, `relu/pool`, `6->12`, `pool`, `fc`)
7. Clarify the layer2 accumulation/parallelism boundary
8. Only then activate the task and start implementation

## Decision (ADR-lite)

**Context**: `my_cnnV4` depends on an existing RTL baseline that contains significant hand-written scheduling logic and implicit architectural assumptions.

**Decision**: Treat `my_cnnV1` comprehension as a required planning artifact before any V4 implementation work.

**Consequences**: This slows the first step slightly, but reduces the risk of rewriting broken assumptions into `V4` or making changes without understanding which parts are algorithmic versus purely scheduling glue.

## Out of Scope

* Immediate inline RTL edits before V4 scope is clarified
* Premature optimization of modules not yet confirmed to be reused
* Treating generated Vivado collateral as the primary design source

## Technical Notes

Files inspected so far:

* `my_cnn/my_cnn_rtl/CNN.v`
* `my_cnn/my_cnn_rtl/conv.v`
* `my_cnn/my_cnn_rtl/window.v`
* `my_cnn/my_cnn_rtl/add.v`
* `my_cnn/my_cnn_rtl/relu.v`
* `my_cnn/my_cnn_rtl/maxpooling_24X24.v`
* `my_cnn/my_cnn_rtl/FIFO_fmap.v`
* `my_cnn/my_cnn_rtl/fc.v`
* `my_cnn/my_cnn.sim/top_tb.v`

Current architecture summary:

* `CNN.v` is a manually scheduled controller plus datapath integrator.
* `conv_counter` sequences multiple convolution/aggregation stages rather than representing one simple layer loop.
* `window.v` creates a 5x5 sliding-column tap bundle from either the raw image stream or stored feature-map data.
* `conv.v` implements one 5x5 MAC engine with a fixed seven-stage reduction pipeline and hard-coded timing for `28x28` and `12x12` inputs.
* `add.v` is used to accumulate later convolution passes with buffered partial sums.
* AXIS FIFO IP instances are used to shuttle partial sums between alternating convolution stages.
* `relu.v` clips negative values and scales down by arithmetic right shift.
* `maxpooling_24X24.v` performs 2x2-style pooling with internal line buffering and different behavior for the `24x24` and `8x8` style phases.
* `FIFO_fmap.v` stores pooled feature maps so later stages can reread them.
* `fc.v` contains per-neuron local weight storage for 192 weights and accumulates 16 groups of 6 pooled inputs.
* The final classification result is formed by two FC accumulation rounds (`result_r0` then `result_r1`) and streamed out as 10 outputs.

Additional V4 direction notes from the user:

* External input-read behavior should stay unchanged.
* The first redesign priority is output-channel-level convolution parallelism.
* New source locations are fixed to `my_cnnV4/my_cnnV4_rtl/` and `my_cnnV4/my_cnnV4.sim/`.
* V4 should first be built as a layer-specific structure rather than a generic engine.
* Baseline layer breakdown:
  * layer1 convolution: input 1 channel, output 6 channels
  * layer1 activation + pooling
  * layer2 convolution: input 6 channels, output 12 channels
  * layer2 pooling on 12 channels
  * fully connected output stage
* Reuse/generalized compute units can be considered later, after the baseline architecture is stable.
* `my_cnnV3` already contains exploratory output-channel-parallel ideas, especially:
  * `conv_pin2.v`
  * `conv2_pin2_pout6_pk1.v`
  * modified `my_cnnV3_rtl/CNN.v`
* But `my_cnnV3` is not considered successful, because it became too coupled and therefore should not be adopted as the architectural template for `V4`.

Observed risks / likely V4 redesign pressure:

* Extensive hard-coded counters and phase-specific constants inside `CNN.v`
* Implicit timing coupling between top-level control and submodule valid generation
* Weight-loading and compute scheduling are tightly intertwined
* Module naming and state semantics reflect implementation history more than stable architecture
* `my_cnnV3` shows partial architectural experimentation, but the resulting control path is still tightly coupled and may not be the clean V4 target directly
* If V4 only swaps in a new convolution module without redefining control boundaries, it will likely repeat the V3 failure mode
* Layer2 resource cost can explode depending on whether `12` output channels also implies fully parallel accumulation across `6` input channels
