set_param general.maxThreads 2
set_property include_dirs [list C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl] [current_fileset]
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/axis_infrastructure_v1_1_vl_rfs.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/axis_data_fifo_v2_0_vl_rfs.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/user_fifo_ip.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/add.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/FIFO_fmap.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/fc.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/relu.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/window.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/maxpooling_24X24.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/conv_pin2.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/CNN.v"
synth_design -top CNN -part xc7z020clg400-1
report_utilization -file "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/check_synth_rtlonly_util.rpt"
exit