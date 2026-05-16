module CNN
(
    input wire clk,
    input wire resetn,
    
    input wire start_cnn,
    
    input wire image_tvalid,                  
    output wire image_tready,
    input wire signed [7:0] image_tdata,
    
    input wire weight_tvalid,                 
    output wire weight_tready,
    input wire signed [7:0] weight_tdata,
    
    input wire weightfc_tvalid,               
    output wire weightfc_tready,
    input wire signed [7:0] weightfc_tdata,
    
    output wire cnn_done,
   
    input wire result_tready,
    output wire result_tvalid,
    output wire result_tlast,
    output wire signed [31:0] result_tdata,

    output wire [3:0] conv_cnt
);
	reg image_ready;
	reg weight_ready;
	reg weightfc_ready;
	reg result_valid_r;
	reg weight_rerd_r;
	reg cnn_done_r;
	reg signed [31:0] result_data;
	wire weight_rerd;
	wire conv_start;
	wire window_start;
	wire [5:0] done_conv;
	assign image_tready = image_ready;
	assign weight_tready = weight_ready;
	assign weightfc_tready = weightfc_ready;
	assign result_tvalid = result_valid_r;
	assign cnn_done = cnn_done_r;
	assign weight_rerd = weight_rerd_r;
	
	assign result_tdata = result_data;


	reg start_window;
	reg start_conv;

	wire [5:0] conv_wren;
	wire [5:0] conv_wren_l1;
	wire [5:0] conv_wren_l2;
	wire [5:0] add_wren;
	wire [5:0] relu_wren;
	wire [5:0] pooling_wren;
	wire [9:0] fc_wren;

	// 卷积完成标志
	wire [5:0] conv_done;
	wire [5:0] conv_done_l1;
	wire [5:0] conv_done_l2;

	// 模块内部数据端口
	// taps_0 为当前实际参与卷积的数据窗，taps_1 为 Pin=2 预留的第二路数据窗
	wire [39:0] taps_0;
	wire [39:0] taps_1;
	reg signed [31:0] add_data [0:5];
	reg signed [31:0] relu_data [0:5];
	
	// 模块输出数据端口
	wire signed [31:0] conv_result [0:5];
	wire signed [31:0] conv_result_l1 [0:5];
	wire signed [31:0] conv_result_l2 [0:5];
	wire signed [31:0] add_result [0:5];
	wire signed [7:0] relu_result [0:5];
	wire signed [7:0] pooling_result [0:5];
	wire signed [31:0] fc_result [0:9];
	reg signed [31:0] result_r0 [0:9];
	reg signed [31:0] result_r1 [0:9];


// 卷积轮次计数
reg [3:0] conv_counter = 4'd0;

// 第一层 feature map 读控制
reg [5:0] fmap_rdrst;
reg [5:0] fmap_rden;

// 双滑窗输入端口
// image_in_0 保持当前单通道卷积路径，image_in_1 为未来 Pin=2 的第二输入通道预留
reg [7:0] image_in_0;
reg [7:0] image_in_1;                      

// 状态控制：0 表示第一层，1 表示第二层
reg state; 

// 卷积权重计数
reg [10:0] weight_counter;
reg [10:0] weight_stream_cnt;
reg signed [7:0] conv_weight_mem [0:1949];

// 卷积层与全连接层权重缓存
reg signed [7:0] weight_c [0:5];
reg signed [7:0] weight_l2;
reg signed [7:0] weight_fc [0:9];
integer weight_pe_idx;
integer weight_pair_idx;
integer weight_out_base;
integer weight_local_idx;
integer weight_mem_addr;

// 当前卷积轮次内部时钟计数
reg [11:0] cnt;
reg [7:0] conv2_fmap_req_cnt;
reg conv2_fmap_valid_r;
reg conv2_fmap_valid_d1;
reg conv2_fmap_valid_d2;
reg conv2_fmap_valid_d3;
wire conv2_fmap_valid_aligned;
wire conv2_fmap_rd_active;
wire conv2_ovalid;
wire conv2_done;

// 第一层 feature map 写端口
reg [5:0] fmap_wren;
wire signed [7:0] fmap_dout [0:5];

// 第二层中间部分和 FIFO 接口（12 路 FIFO 分别保存 12 个输出通道的部分和）
reg [11:0] s_fifo_valid;
reg signed [31:0] s_fifo_data [0:11];
wire [11:0] s_fifo_ready;
wire [11:0] m_fifo_valid;
wire signed [31:0] m_fifo_data [0:11];
reg [11:0] m_fifo_ready;

wire start_conv_r;



	reg [10:0] cnt_fc;
	reg [9:0] weight_fc_en;

	assign conv_cnt = conv_counter;

reg start_cnn_delay;

always@(posedge clk or negedge resetn)
if(!resetn)
    start_cnn_delay <= 0;
else
    start_cnn_delay <= start_cnn;

 // 各级结果计数器：卷积输出、加法输出、池化输出
reg [9:0] conv_result_cnt;
always@(posedge clk)
if(!start_conv)
    conv_result_cnt <= 0;
else
    if(conv_wren == 6'b111111)
        conv_result_cnt <= conv_result_cnt + 1;
    else
        conv_result_cnt <= conv_result_cnt;

reg [6:0] add_result_cnt;
always@(posedge clk)
begin
    case(conv_counter)
    4'd3,4'd4,4'd5,4'd6,4'd7:begin
        if(add_result_cnt == 7'd64)
            add_result_cnt <= 7'd0;
        else
            if(add_wren == 6'b111111)
                add_result_cnt <= add_result_cnt + 7'd1;
            else
                add_result_cnt <= add_result_cnt;
          end
    default:add_result_cnt <= 7'd0;
    endcase
end

reg [7:0] pooling_result_cnt;
always@(posedge clk)
begin
    case(conv_counter)
    4'd1:begin
        if(pooling_result_cnt == 8'd144)
            pooling_result_cnt <= 8'd0;
        else
            if(pooling_wren == 6'b111111)
                pooling_result_cnt <= pooling_result_cnt + 8'd1;
            else
                pooling_result_cnt <= pooling_result_cnt;
         end
    4'd6,4'd7:begin
        if(pooling_result_cnt == 8'd16)
            pooling_result_cnt <= 8'd0;
        else
            if(pooling_wren == 6'b111111)
                pooling_result_cnt <= pooling_result_cnt + 8'd1;
            else
                pooling_result_cnt <= pooling_result_cnt;
          end
    default:pooling_result_cnt <= 8'd0;
    endcase
end

 // 全连接层权重装载计数与使能控制
always@(posedge clk or negedge resetn)
begin
    if(!resetn)
        cnt_fc <= 0;
    else
    begin
        if(cnt_fc == 11'd1923)
            cnt_fc <= cnt_fc;
        else if(start_cnn_delay)
            cnt_fc <= cnt_fc + 1'b1;
    end
end

always@(*)
if(cnt_fc <= 10'd1)
    weight_fc_en <= 10'b0000000000;
else if(cnt_fc <= 11'd193)
    weight_fc_en <= 10'b0000000001;
else if(cnt_fc <= 10'd385)
    weight_fc_en <= 10'b0000000010;
else if(cnt_fc <= 11'd577)
    weight_fc_en <= 10'b0000000100;
else if(cnt_fc <= 11'd769)
    weight_fc_en <= 10'b0000001000;
else if(cnt_fc <= 11'd961)
    weight_fc_en <= 10'b0000010000;
else if(cnt_fc <= 11'd1153)
    weight_fc_en <= 10'b0000100000;
else if(cnt_fc <= 11'd1345)
    weight_fc_en <= 10'b0001000000;
else if(cnt_fc <= 11'd1537)
    weight_fc_en <= 10'b0010000000;
else if(cnt_fc <= 11'd1729)
    weight_fc_en <= 10'b0100000000;
else if(cnt_fc <= 11'd1921)
    weight_fc_en <= 10'b1000000000;
else
    weight_fc_en <= 10'b0000000000;

always@(posedge clk or negedge resetn)
if(!resetn)
    weightfc_ready <= 1'b0;
else
    begin
        if(cnt_fc >= 11'd1921)
            weightfc_ready <= 1'b0;
        else if(cnt_fc == 11'd0)
            weightfc_ready <= 1'b0;
        else
            weightfc_ready <= 1'b1;
    end

//**********************卷积循环控制***********************// 
reg start_conv_delay;
   
always@(posedge clk or negedge resetn)
if(!resetn)
    start_conv_delay <= 0;
else
    start_conv_delay <= start_conv;

assign start_conv_r = start_conv && (~start_conv_delay);
 
always@(posedge clk) 
if(cnn_done)
    conv_counter <= 4'd0;
else if(start_conv_r)
    conv_counter <= conv_counter + 1;

	//**********state=0：第一层，输入 28x28，卷积后 24x24，池化后 12x12；state=1：第二层，输入 12x12，卷积后 8x8，池化后 4x4************//                      
	always@(*)
		case(conv_counter)
		4'd0,4'd1:state <= 0;
		default:state <= 1;
	endcase

//********************卷积层权重读取***********************// 
always@(posedge clk or negedge resetn)
if(!resetn)
    weight_ready <= 1'b0;
else
    begin
        if(!start_cnn_delay)
            weight_ready <= 1'b0;
        else if(weight_stream_cnt >= 11'd1950)
            weight_ready <= 1'b0;
        else
            weight_ready <= 1'b1;
    end                      
    
always@(posedge clk or negedge resetn)
if(!resetn)
    weight_rerd_r <= 0;
else
    if(cnn_done)
        weight_rerd_r <= 1;
    else
        weight_rerd_r <= 0;   

always@(posedge clk or negedge resetn)
if(!resetn)
    weight_stream_cnt <= 0;
else if(!start_cnn_delay)
    weight_stream_cnt <= 0;
else if(weight_tvalid && weight_tready)
    begin
        conv_weight_mem[weight_stream_cnt] <= weight_tdata;
        weight_stream_cnt <= weight_stream_cnt + 1'b1;
    end

always@(posedge clk or negedge resetn)
if(!resetn)
    weight_counter <= 0;
else if(!start_conv)
    weight_counter <= 0;
else
    case(conv_counter)
        4'd0:
            begin
                if(weight_tvalid && weight_tready && weight_counter < 11'd150)
                    weight_counter <= weight_counter + 1'b1;
                else
                    weight_counter <= weight_counter;
            end
        4'd1:
            begin
                if((!start_conv_r) && weight_tvalid && weight_tready && weight_counter < 11'd150)
                    weight_counter <= weight_counter + 1'b1;
                else
                    weight_counter <= weight_counter;
            end
        4'd2,4'd3,4'd4,4'd5,4'd6,4'd7:
            begin
                if(weight_counter < 11'd300)
                    weight_counter <= weight_counter + 1'b1;
                else
                    weight_counter <= weight_counter;
            end
        default:
            weight_counter <= weight_counter;
    endcase  
    
	// 当前拍送入的卷积权重数据广播到 6 个卷积 PE，
	// 具体由 weight_en 的 one-hot 选择哪一个 PE 在该拍真正装载它。
	always@(*)
	begin
		weight_l2 = 8'sd0;
		if(!state)
			begin
				weight_c[0] = weight_tdata;
				weight_c[1] = weight_tdata;
				weight_c[2] = weight_tdata;
				weight_c[3] = weight_tdata;
				weight_c[4] = weight_tdata;
				weight_c[5] = weight_tdata;
			end
		else
			begin
				weight_pair_idx = (conv_counter - 4'd2) >> 1;
				if(conv_counter[0])
					weight_out_base = 6;
				else
					weight_out_base = 0;
				for(weight_pe_idx=0;weight_pe_idx<=5;weight_pe_idx=weight_pe_idx+1)
					begin
						if(weight_counter >= weight_pe_idx*50 && weight_counter < weight_pe_idx*50 + 50)
							begin
								weight_local_idx = weight_counter - weight_pe_idx*50;
								if(weight_local_idx < 25)
									weight_mem_addr = 150 + (((weight_pair_idx << 1) * 12) + weight_out_base + weight_pe_idx) * 25 + weight_local_idx;
								else
									weight_mem_addr = 150 + ((((weight_pair_idx << 1) + 1) * 12) + weight_out_base + weight_pe_idx) * 25 + (weight_local_idx - 25);
								weight_c[weight_pe_idx] = conv_weight_mem[weight_mem_addr];
							end
						else
							weight_c[weight_pe_idx] = 8'sd0;
					end

				case(weight_en)
					6'b000001: weight_l2 = weight_c[0];
					6'b000010: weight_l2 = weight_c[1];
					6'b000100: weight_l2 = weight_c[2];
					6'b001000: weight_l2 = weight_c[3];
					6'b010000: weight_l2 = weight_c[4];
					6'b100000: weight_l2 = weight_c[5];
					default:   weight_l2 = 8'sd0;
				endcase
			end
	end

// 全连接层开始前，需要先装载 1920 个全连接权重
always@(*)
begin
//**********************全连接权重装载*********************//
    if(cnt_fc <= 11'd1)
        begin
            weight_fc[0] <= 0;
            weight_fc[1] <= 0;
            weight_fc[2] <= 0;
            weight_fc[3] <= 0;
            weight_fc[4] <= 0;
            weight_fc[5] <= 0;
            weight_fc[6] <= 0;
            weight_fc[7] <= 0;
            weight_fc[8] <= 0;
            weight_fc[9] <= 0;
        end    
// 按 10 个输出神经元顺序装载各自的 192 个权重
    else if(cnt_fc <= 11'd193)
        weight_fc[0] <= weightfc_tdata;
    else if(cnt_fc <= 11'd385)
        weight_fc[1] <= weightfc_tdata;
    else if(cnt_fc <= 11'd577)
        weight_fc[2] <= weightfc_tdata;
    else if(cnt_fc <= 11'd769)
        weight_fc[3] <= weightfc_tdata;
    else if(cnt_fc <= 11'd961)
        weight_fc[4] <= weightfc_tdata;
    else if(cnt_fc <= 11'd1153)
        weight_fc[5] <= weightfc_tdata;
    else if(cnt_fc <= 11'd1345)
        weight_fc[6] <= weightfc_tdata;
    else if(cnt_fc <= 11'd1537)
        weight_fc[7] <= weightfc_tdata;
    else if(cnt_fc <= 11'd1729)
        weight_fc[8] <= weightfc_tdata;
    else if(cnt_fc <= 11'd1921)
        weight_fc[9] <= weightfc_tdata;
end   

//***********************输入数据读取控制*******************//
always@(posedge clk)
    case(conv_counter)
        4'd1:if(!start_window) image_ready <= 1'b0;
             else image_ready <= 1'b1;
        4'd2,4'd3:if(!conv2_fmap_rd_active) fmap_rden <= 6'b000000;
             else fmap_rden <= 6'b000011;              
        4'd4,4'd5:if(!conv2_fmap_rd_active) fmap_rden <= 6'b000000;
             else fmap_rden <= 6'b001100;
        4'd6,4'd7:if(!conv2_fmap_rd_active) fmap_rden <= 6'b000000;
             else fmap_rden <= 6'b110000;
        default:begin
                image_ready <= 1'b0;
                fmap_rden <= 6'b000000;
                end
    endcase

always@(posedge clk)
    begin
        case(conv_counter)
            4'd2:if(conv_done == 6'b111111) fmap_rdrst <= 6'b000011;
                 else fmap_rdrst <= 6'b000000;            
            4'd4:if(conv_done == 6'b111111) fmap_rdrst <= 6'b001100;
                 else fmap_rdrst <= 6'b000000;
            4'd6:if(conv_done == 6'b111111) fmap_rdrst <= 6'b110000;
                 else fmap_rdrst <= 6'b000000;
            default:fmap_rdrst <= 6'b000000;
        endcase
end

//*********************双滑窗输入端口（Pin=2 预留）***********************//
always@(*)
begin
    case(conv_counter)
        4'd1:begin
            image_in_0 <= image_tdata;
            image_in_1 <= 8'b00000000;
        end
        4'd2,4'd3:begin
            image_in_0 <= fmap_dout[0];
            image_in_1 <= fmap_dout[1];
        end
        4'd4,4'd5:begin
            image_in_0 <= fmap_dout[2];
            image_in_1 <= fmap_dout[3];
        end
        4'd6,4'd7:begin
            image_in_0 <= fmap_dout[4];
            image_in_1 <= fmap_dout[5];
        end
        default:begin
            image_in_0 <= 8'b00000000;
            image_in_1 <= 8'b00000000;
        end
    endcase
end
//*****************卷积启动后的时钟计数****************//
always@(posedge clk or negedge resetn)
begin
if(!resetn)
    cnt <= 12'd0;
else
    if(!start_conv)
        cnt <= 12'd0;
    else 
        cnt <= cnt + 10'd1;
end

//*************************滑窗启动控制***********************//
always@(posedge clk or negedge resetn)
begin
    if(!resetn)
        start_window <= 0;
    else
        if(conv_done == 6'b111111)
            start_window <= 0;
        else
            case(state)
            1'b0:if(cnt == 12'd11) start_window <= 1;
            1'b1:if(cnt == 12'd241) start_window <= 1;
            endcase
end

// 先把双 window 结构搭起来：
// window_inst_0 对应当前已使用的数据通路；
// window_inst_1 是未来 Pin=2 时给第二输入通道使用的数据通路。
window window_inst_0(.clk(clk),.rstn(resetn),.start(start_window),.state(state),.din(image_in_0),.taps(taps_0));
window window_inst_1(.clk(clk),.rstn(resetn),.start(start_window),.state(state),.din(image_in_1),.taps(taps_1));

//*******************卷积模块启动控制*****************//
always@(posedge clk or negedge resetn)
begin
if(!resetn)
    start_conv <= 0;
else
    case(conv_counter)
        4'd0:begin
             if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                start_conv <= 0;
             else 
                if(start_cnn_delay && ~cnn_done)
                    start_conv <= 1;
                else
                    start_conv <= start_conv;
             end
        4'd1:begin
             if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                 start_conv <= 0;
             else 
                 if(pooling_result_cnt == 8'd144)
                     start_conv <= 1;
                 else
                     start_conv <= start_conv;
             end
        4'd2,4'd3:begin
                  if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                      start_conv <= 0;
                  else
                      if(conv_result_cnt == 10'd64)
                          start_conv <= 1;
                      else
                          start_conv <= start_conv;
                  end
        4'd4,4'd5:begin
                  if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                      start_conv <= 0;
                  else
                      if(add_result_cnt == 7'd64)
                          start_conv <= 1;
                      else
                          start_conv <= start_conv;
                  end
        4'd6:begin
              if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                  start_conv <= 0; 
              else
                  if(fc_wren == 10'b1111111111)
                      start_conv <= 1;
                  else
                      start_conv <= start_conv;
              end
        4'd7:begin
              if(conv_done[0] && conv_done[1] && conv_done[2] && conv_done[3] && conv_done[4] && conv_done[5])
                  start_conv <= 0;
              else
                  if(fc_wren == 10'b1111111111)
                      start_conv <= start_conv;
              end
        default:start_conv <= 0;      
    endcase
end

reg [5:0] weight_en = 6'b000000;

always@(*)
begin
    if(!start_conv)
        weight_en <= 6'b000000;
    else if(!state)
        begin
            if(!(weight_tvalid && weight_tready))
                weight_en <= 6'b000000;
            else if(weight_counter < 11'd25)
                weight_en <= 6'b000001;
            else if(weight_counter < 11'd50)
                weight_en <= 6'b000010;
            else if(weight_counter < 11'd75)
                weight_en <= 6'b000100;
            else if(weight_counter < 11'd100)
                weight_en <= 6'b001000;
            else if(weight_counter < 11'd125)
                weight_en <= 6'b010000;
            else if(weight_counter < 11'd150)
                weight_en <= 6'b100000;
            else
                weight_en <= 6'b000000;
        end
    else
        begin
            if(weight_counter < 11'd50)
                weight_en <= 6'b000001;
            else if(weight_counter < 11'd100)
                weight_en <= 6'b000010;
            else if(weight_counter < 11'd150)
                weight_en <= 6'b000100;
            else if(weight_counter < 11'd200)
                weight_en <= 6'b001000;
            else if(weight_counter < 11'd250)
                weight_en <= 6'b010000;
            else if(weight_counter < 11'd300)
                weight_en <= 6'b100000;
            else
                weight_en <= 6'b000000;
        end
    end

//********************卷积模块实例化*********************//
genvar i;
generate
    for(i=0;i<=5;i=i+1)
        begin:conv_inst
            conv_pin2 u_conv(.clk(clk),
                             .rstn(resetn),
                             .start(start_conv && !state),
                             .weight_en(weight_en[i]),
                             .weight(weight_c[i]),
                             .taps_0(taps_0),
                             .taps_1(taps_1),
                             .state(state),
                             .dout(conv_result_l1[i]),
                             .ovalid(conv_wren_l1[i]),
                             .done(conv_done_l1[i]));
              end
endgenerate

assign conv2_fmap_rd_active = start_conv && state && start_window && (conv2_fmap_req_cnt < 8'd144);

always@(posedge clk or negedge resetn)
if(!resetn)
    begin
        conv2_fmap_req_cnt <= 8'd0;
        conv2_fmap_valid_r <= 1'b0;
    end
else if(!start_conv || !state)
    begin
        conv2_fmap_req_cnt <= 8'd0;
        conv2_fmap_valid_r <= 1'b0;
    end
else if(|fmap_rden && conv2_fmap_req_cnt < 8'd144)
    begin
        conv2_fmap_req_cnt <= conv2_fmap_req_cnt + 1'b1;
        conv2_fmap_valid_r <= |fmap_rden;
    end
else
    begin
        conv2_fmap_req_cnt <= conv2_fmap_req_cnt;
        conv2_fmap_valid_r <= |fmap_rden;
    end

always@(posedge clk or negedge resetn)
if(!resetn)
    begin
        conv2_fmap_valid_d1 <= 1'b0;
        conv2_fmap_valid_d2 <= 1'b0;
        conv2_fmap_valid_d3 <= 1'b0;
    end
else if(!start_conv || !state)
    begin
        conv2_fmap_valid_d1 <= 1'b0;
        conv2_fmap_valid_d2 <= 1'b0;
        conv2_fmap_valid_d3 <= 1'b0;
    end
else
    begin
        conv2_fmap_valid_d1 <= conv2_fmap_valid_r;
        conv2_fmap_valid_d2 <= conv2_fmap_valid_d1;
        conv2_fmap_valid_d3 <= conv2_fmap_valid_d2;
    end

assign conv2_fmap_valid_aligned = conv2_fmap_valid_r;

conv2_pin2_pout6_pk1 u_conv2_l2(
    .clk(clk),
    .rstn(resetn),
    .start(start_conv && state),
    .fmap_valid(conv2_fmap_valid_aligned),
    .fmap_0(image_in_0),
    .fmap_1(image_in_1),
    .weight(weight_l2),
    .weight_en(weight_en),
    .ovalid(conv2_ovalid),
    .done(conv2_done),
    .dout_0(conv_result_l2[0]),
    .dout_1(conv_result_l2[1]),
    .dout_2(conv_result_l2[2]),
    .dout_3(conv_result_l2[3]),
    .dout_4(conv_result_l2[4]),
    .dout_5(conv_result_l2[5])
);

assign conv_wren = (!state) ? conv_wren_l1 : {6{conv2_ovalid}};
assign conv_done = (!state) ? conv_done_l1 : {6{conv2_done}};
assign conv_wren_l2 = {6{conv2_ovalid}};
assign conv_done_l2 = {6{conv2_done}};

genvar conv_sel_idx;
generate
    for(conv_sel_idx=0;conv_sel_idx<=5;conv_sel_idx=conv_sel_idx+1)
        begin:conv_result_mux
            assign conv_result[conv_sel_idx] = (!state) ? conv_result_l1[conv_sel_idx] : conv_result_l2[conv_sel_idx];
        end
endgenerate

//*******************第二层中间结果写入 FIFO****************//

always@(*)
case(conv_counter)
    4'd2:if(conv_wren == 6'b111111) s_fifo_valid <= 12'b000000111111;
         else s_fifo_valid <= 12'b000000000000;
    4'd3:if(conv_wren == 6'b111111) s_fifo_valid <= 12'b111111000000;
         else s_fifo_valid <= 12'b000000000000;
    4'd4:if(add_wren == 6'b111111) s_fifo_valid <= 12'b000000111111;
         else s_fifo_valid <= 12'b000000000000;
    4'd5:if(add_wren == 6'b111111) s_fifo_valid <= 12'b111111000000;
         else s_fifo_valid <= 12'b000000000000;
    default:s_fifo_valid <= 12'b000000000000;     
endcase

integer j;

always@(*)
case(conv_counter)
    4'd2:for(j=0;j<=5;j=j+1)
                 s_fifo_data[j] <= conv_result[j];
    4'd3:for(j=0;j<=5;j=j+1)
                 s_fifo_data[j+6] <= conv_result[j];                     
    4'd4:for(j=0;j<=5;j=j+1)
                              s_fifo_data[j] <= add_result[j]; 
    4'd5:for(j=0;j<=5;j=j+1)
                              s_fifo_data[j+6] <= add_result[j];                                                      
    default:for(j=0;j<=11;j=j+1)
                s_fifo_data[j] <= 0;
           
endcase
//****************第二层中间部分和从 FIFO 读出******************//
always@(*)
case(conv_counter)
    4'd4,4'd6:if(conv_wren == 6'b111111) m_fifo_ready <= 12'b000000111111;
         else if(conv_wren == 6'b000000) m_fifo_ready <= 12'b000000000000;
    4'd5,4'd7:if(conv_wren == 6'b111111) m_fifo_ready <= 12'b111111000000;
         else if(conv_wren == 6'b000000) m_fifo_ready <= 12'b000000000000;
    default:m_fifo_ready <= 12'b000000000000;     
endcase

//********************加法模块输入（add_data）**********************//
integer k;
always@(posedge clk)
begin
    case(conv_counter)
    4'd4,4'd6:begin
         for(k=0;k<=5;k=k+1)
             if(m_fifo_valid[k] && m_fifo_ready[k])
                 add_data[k] <= m_fifo_data[k];
             else 
                 add_data[k] <= 0;
         end
    4'd5,4'd7:begin
         for(k=0;k<=5;k=k+1)
             if(m_fifo_valid[k+6] && m_fifo_ready[k+6])
                 add_data[k] <= m_fifo_data[k+6];
             else 
                 add_data[k] <= 0;
         end
    default:begin
            for(k=0;k<=5;k=k+1)
                add_data[k] <= 0;
            end
    endcase
end

reg reset_fifo;

always@(posedge clk or negedge resetn)
if(!resetn)
    reset_fifo <= 0;
else
    if(cnn_done)
        reset_fifo <= 0;
    else
        reset_fifo <= 1;
   
//*****************第二层部分和 FIFO 实例化******************//
genvar a;
generate
    for(a=0;a<=11;a=a+1)
        begin:fifo_inst
            user_fifo_ip your_instance_name(
              .s_axis_aresetn(reset_fifo),          // FIFO 低有效复位
              .s_axis_aclk(clk),                // FIFO 写入时钟
              .s_axis_tvalid(s_fifo_valid[a]),            // 写入有效
              .s_axis_tready(s_fifo_ready[a]),            // FIFO 可写就绪
              .s_axis_tdata(s_fifo_data[a]),              // 写入的部分和数据
              .m_axis_tvalid(m_fifo_valid[a]),            // 读出有效
              .m_axis_tready(m_fifo_ready[a]),            // 读出就绪
              .m_axis_tdata(m_fifo_data[a])             // 读出的部分和数据
            );
        end
endgenerate

//********************加法模块****************//
reg ivalid_add;
always@(*)
case(conv_counter)
4'd4,4'd5,4'd6,4'd7:if(conv_wren == 6'b111111) ivalid_add <= 1'b1;
                                                        else ivalid_add <= 1'b0;
default:ivalid_add <= 1'b0;
endcase

genvar b;
generate
    for(b=0;b<=5;b=b+1)
        begin:add_inst 
            add u_add(
                .clk(clk),
                .ivalid(ivalid_add),
                .din_0(conv_result[b]),
                .din_1(add_data[b]),
                .ovalid(add_wren[b]),
                .dout(add_result[b])
            );    
        end
endgenerate
    
//******************ReLU 模块使能控制**************//
reg ivalid_relu;
always@(*)
case(conv_counter)
4'd1:if(conv_wren == 6'b111111) ivalid_relu <= 1'b1;
     else ivalid_relu <= 1'b0;
4'd6,4'd7:if(add_wren == 6'b111111) ivalid_relu <= 1'b1;
     else ivalid_relu <= 1'b0;
default:ivalid_relu <= 1'b0;
endcase

//******************ReLU 模块输入端口（relu_data）******************//
integer m;
always@(*)
case(conv_counter)
    4'd1:for(m=0;m<=5;m=m+1)
             relu_data[m] <= conv_result[m];
    4'd6,4'd7:for(m=0;m<=5;m=m+1)
             relu_data[m] <= add_result[m];    
    default:for(m=0;m<=5;m=m+1)
             relu_data[m] <= 0;
           
endcase

//********************ReLU 模块*******************//
genvar c;
generate
    for(c=0;c<=5;c=c+1)
        begin:relu_inst 
            relu u_relu(
                .clk(clk),
                .ivalid(ivalid_relu),
                .state(state),
                .din(relu_data[c]),
                .ovalid(relu_wren[c]),
                .dout(relu_result[c])
            );    
        end
endgenerate

//******************池化模块******************//
	reg ivalid_pooling;
	always@(*)begin
		case(conv_counter)
			4'd1,4'd6,4'd7:
				if(relu_wren == 6'b111111) 
					ivalid_pooling <= 1'b1;
				else 
					ivalid_pooling <= 1'b0;
			default:ivalid_pooling <= 1'b0;
			endcase
	end
	
	genvar d;
	generate
		for(d=0;d<=5;d=d+1)
			begin:pooling_inst
				maxpooling u_pooling(
					.clk(clk),
					.rstn(resetn),
					.ivalid(ivalid_pooling),
					.state(state),
					.din(relu_result[d]),
					.ovalid(pooling_wren[d]),
					.dout(pooling_result[d])                                     
				);
			end
	endgenerate

//************第一层 feature map 写入控制**************//
always@(*)
if(conv_counter == 4'd1 && pooling_wren == 6'b111111)
    fmap_wren <= 6'b111111;
else
    fmap_wren <= 6'b000000;

reg reset_fmap;

always@(posedge clk or negedge resetn)
if(!resetn)
    reset_fmap <= 0;
else
    if(cnn_done)
        reset_fmap <= 0;
    else
        reset_fmap <= 1;

genvar e;
generate
    for(e=0;e<=5;e=e+1)
        begin:fmap_inst
            FIFO_fmap u_FIFO_fmap (
              .clk(clk),
              .rstn(reset_fmap),
              .din(pooling_result[e]),
              .wr_en(fmap_wren[e]),
              .rd_en(fmap_rden[e]),
              .rd_rst(fmap_rdrst[e]),     // 读地址回到起始位置
              .dout(fmap_dout[e]),
              .full(),
              .empty()
            );
        end
endgenerate

//***************全连接层*****************//
reg ivalid_fc;
always@(*)
case(conv_counter)
4'd6,4'd7:if(pooling_wren == 6'b111111) ivalid_fc <= 1;
      else ivalid_fc <= 0;
default:ivalid_fc <= 0;
endcase

genvar f;
generate
    for(f=0;f<10;f=f+1)
        begin:fullconnect_inst
            fc u_fullconnect(
                .clk(clk),
                .rstn(resetn),
                .ivalid(ivalid_fc),
                .din_0(pooling_result[0]),
                .din_1(pooling_result[1]),
                .din_2(pooling_result[2]),
                .din_3(pooling_result[3]),
                .din_4(pooling_result[4]),
                .din_5(pooling_result[5]),
                .weight(weight_fc[f]),
                .weight_en(weight_fc_en[f]),
                .ovalid(fc_wren[f]),
                .dout(fc_result[f])
            );
        end
endgenerate

//*************全连接层结果拼接*****************//
integer r;
always@(posedge clk)
case(conv_counter)
4'd6:if(fc_wren == 10'b1111111111)
      begin
          result_r0[0] <= fc_result[0];
          result_r0[1] <= fc_result[1];
          result_r0[2] <= fc_result[2];
          result_r0[3] <= fc_result[3];
          result_r0[4] <= fc_result[4];
          result_r0[5] <= fc_result[5];
          result_r0[6] <= fc_result[6];
          result_r0[7] <= fc_result[7];
          result_r0[8] <= fc_result[8];
          result_r0[9] <= fc_result[9];
      end
4'd7:if(fc_wren == 10'b1111111111)
      begin
          result_r1[0] <= fc_result[0] + result_r0[0];
          result_r1[1] <= fc_result[1] + result_r0[1];
          result_r1[2] <= fc_result[2] + result_r0[2];
          result_r1[3] <= fc_result[3] + result_r0[3];
          result_r1[4] <= fc_result[4] + result_r0[4];
          result_r1[5] <= fc_result[5] + result_r0[5];
          result_r1[6] <= fc_result[6] + result_r0[6];
          result_r1[7] <= fc_result[7] + result_r0[7];
          result_r1[8] <= fc_result[8] + result_r0[8];
          result_r1[9] <= fc_result[9] + result_r0[9];
      end
default:begin
          result_r0[0] <= 0;
          result_r0[1] <= 0;
          result_r0[2] <= 0;
          result_r0[3] <= 0;
          result_r0[4] <= 0;
          result_r0[5] <= 0;
          result_r0[6] <= 0;
          result_r0[7] <= 0;
          result_r0[8] <= 0;
          result_r0[9] <= 0;
          result_r1[0] <= 0;
          result_r1[1] <= 0;
          result_r1[2] <= 0;
          result_r1[3] <= 0;
          result_r1[4] <= 0;
          result_r1[5] <= 0;
          result_r1[6] <= 0;
          result_r1[7] <= 0;
          result_r1[8] <= 0;
          result_r1[9] <= 0;
        end
endcase

reg result_valid;
reg result_last_r;
reg [3:0] cnt4;

// 结果输出控制：依次送出 10 个全连接结果，并在最后一拍拉高 tlast

always@(posedge clk or negedge resetn)
begin
if(!resetn)
    result_valid <= 0;
else
    if(!start_cnn_delay)
        result_valid <= 0;
    else if(cnt4 > 4'd10)
        result_valid <= 0; 
    else if(conv_counter == 4'd7 && fc_wren == 10'b1111111111)
        result_valid <= 1;    
end

wire start_cnn_r;

assign start_cnn_r = start_cnn && ~start_cnn_delay;

always@(posedge clk or negedge resetn)
begin
if(!resetn)
    cnn_done_r <= 0;
else
    if(start_cnn_r)
        cnn_done_r <= 0;
    else if(cnt4 == 4'd10)
        cnn_done_r <= 1;
end
   
always@(posedge clk or negedge resetn)
begin
if(!resetn)
    cnt4 <= 0;
else
    if(!result_valid)
        cnt4 <= 0;
    else
        cnt4 <= cnt4 + 1;
end

always@(posedge clk or negedge resetn)
begin
if(!resetn)
    result_valid_r <= 1'b0;
else    
    if(cnt4 == 4'd0)
        result_valid_r <= 1'b0;
    else if(cnt4 <= 4'd10)
        result_valid_r <= 1'b1;
    else
        result_valid_r <= 1'b0;
end

always@(posedge clk or negedge resetn)
begin
if(!resetn)
    result_last_r <= 1'b0;
else
    if(cnt4 == 4'd10)
        result_last_r <= 1'b1;
    else
        result_last_r <= 1'b0;
end

always@(posedge clk)
begin
if(cnt4 > 4'd0 && cnt4 <= 4'd10)
    result_data <= result_r1[cnt4-1];
else
    result_data <= 0;
end

assign conv_start = start_conv;
assign window_start = start_window;
assign done_conv = conv_done;
assign result_tlast = result_last_r;
 
endmodule
