set srcset [get_filesets sources_1]
set simset [get_filesets sim_1]

set old_l1_addr [get_files -quiet */my_cnnV4_rtl/l1_addr_mgr.v]
if {[llength $old_l1_addr] > 0} {
    remove_files -fileset $srcset $old_l1_addr
}

set old_conv_l1 [get_files -quiet */my_cnnV4_rtl/conv_l1.v]
if {[llength $old_conv_l1] > 0} {
    remove_files -fileset $srcset $old_conv_l1
}

set old_wcfg [get_files -quiet */sim_artifacts/l3_out_core_tb_behav.wcfg]
if {[llength $old_wcfg] > 0} {
    remove_files -fileset $simset $old_wcfg
}

set need_files [list \
    {C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_rtl/conv_core.v} \
    {C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_rtl/win_addr_mgr.v} \
    {C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV4/my_cnnV4_rtl/fc_wgt_dist_raw.v} \
]

foreach f $need_files {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $srcset $f
    }
}

set_property top CNN $srcset
set_property top CNN_tb $simset
catch {reset_property xsim.view $simset}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
save_project

puts "my_cnnV4 sources_1 and sim_1 have been refreshed."
