`timescale 1ns / 1ns

// FC neuron INT4 packed wrapper
(* keep_hierarchy = "yes" *)
module fc_neuron_pack_sint4
(
    input  clk,                       // clock
    input  rstn,                      // active-low reset
    input  cfg_weight_valid,          // weight valid
    input  signed [3:0] cfg_weight_data, // weight data
    input  cfg_weight_last,           // last weight beat
    input  in_valid,                  // input valid
    input  signed [23:0] in_data,     // 6-lane input
    input  in_last,                   // last input beat
    input  out_ready,                 // result ready

    output cfg_weight_ready,          // weight ready
    output cfg_weight_done,           // weight done pulse
    output in_ready,                  // input ready
    output out_valid,                 // result valid
    output signed [19:0] out_data,    // result data
    output busy,                      // busy flag
    output weight_loaded              // weight loaded flag
);

    fc_neuron_sint4_core #(
        .USE_PACKED(1)
    ) u_fc_neuron_sint4_core (
        .clk(clk),
        .rstn(rstn),
        .cfg_weight_valid(cfg_weight_valid),
        .cfg_weight_data(cfg_weight_data),
        .cfg_weight_last(cfg_weight_last),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_last(in_last),
        .out_ready(out_ready),
        .cfg_weight_ready(cfg_weight_ready),
        .cfg_weight_done(cfg_weight_done),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .busy(busy),
        .weight_loaded(weight_loaded)
    );

endmodule
