read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/add.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/FIFO_fmap.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/fc.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/relu.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/window.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/maxpooling_24X24.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/conv_pin2.v"
read_verilog "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/my_cnn_rtl/CNN.v"
read_ip "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/user_fifo_ip/user_fifo_ip.xci"
synth_design -top CNN -part xc7z020clg400-1
report_utilization -file "C:/Users/28010/Desktop/my_cnn/vivado_prj/my_cnnV2/check_synth_util.rpt"
exit