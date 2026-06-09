set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set rtl_dir    [file join $root_dir rtl]
set report_dir [file join $root_dir reports]

file mkdir $report_dir

proc run_one {top rtl_dir report_dir root_dir} {
    set out_dir [file join $report_dir $top]
    file mkdir $out_dir

    create_project -in_memory ${top}_ooc -part xc7z020clg400-1
    set_property target_language Verilog [current_project]

    read_verilog [file join $rtl_dir ref_mul2_int4.v]
    read_verilog [file join $rtl_dir pack_mul2_int4.v]
    read_verilog [file join $rtl_dir ref_mul2_sint4.v]
    read_verilog [file join $rtl_dir pack_mul2_sint4.v]
    read_verilog [file join $rtl_dir fc_lane6_ref_sint4.v]
    read_verilog [file join $rtl_dir fc_lane6_pack_sint4.v]
    read_verilog [file join $rtl_dir fc_neuron_sint4_core.v]
    read_verilog [file join $rtl_dir fc_neuron_ref_sint4.v]
    read_verilog [file join $rtl_dir fc_neuron_pack_sint4.v]
    read_verilog [file join $root_dir cnn_rtl fc_addr_mgr.v]
    read_verilog [file join $root_dir cnn_rtl fc_wgt_dist_raw.v]
    read_verilog [file join $root_dir cnn_rtl fc_neuron_int4_core.v]
    read_verilog [file join $root_dir cnn_rtl fc_neuron_int4_ref.v]
    read_verilog [file join $root_dir cnn_rtl fc_neuron_int4_pack.v]
    read_verilog [file join $root_dir cnn_rtl l5_top_raw_int4_core.v]
    read_verilog [file join $root_dir cnn_rtl l5_top_raw_int4_ref.v]
    read_verilog [file join $root_dir cnn_rtl l5_top_raw_int4_pack.v]

    synth_design -top $top -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy none

    report_utilization -file [file join $out_dir "${top}_utilization.rpt"]
    report_utilization -hierarchical -file [file join $out_dir "${top}_utilization_hier.rpt"]

    set dsp_cells [lsort [get_cells -hier -filter {REF_NAME == DSP48E1}]]
    set fp [open [file join $out_dir "${top}_summary.txt"] w]
    puts $fp "top=$top"
    puts $fp "dsp48e1_count=[llength $dsp_cells]"
    foreach cell $dsp_cells {
        puts $fp $cell
    }
    close $fp

    write_checkpoint -force [file join $out_dir "${top}.dcp"]
    close_project
}

foreach top {ref_mul2_int4 pack_mul2_int4 ref_mul2_sint4 pack_mul2_sint4 fc_lane6_ref_sint4 fc_lane6_pack_sint4 fc_neuron_ref_sint4 fc_neuron_pack_sint4 fc_neuron_int4_ref fc_neuron_int4_pack l5_top_raw_int4_ref l5_top_raw_int4_pack} {
    run_one $top $rtl_dir $report_dir $root_dir
}

exit
