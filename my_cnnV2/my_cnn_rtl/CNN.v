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
	reg cnn_done_r;
	reg signed [31:0] result_data;
	assign image_tready = image_ready;
	assign weight_tready = weight_ready;
	assign weightfc_tready = weightfc_ready;
	assign result_tvalid = result_valid_r;
	assign cnn_done = cnn_done_r;
	assign result_tdata = result_data;


	reg start_window;
	reg start_conv;

	wire [5:0] conv_wren;
	wire [5:0] add_wren;
	wire [5:0] relu_wren;
	wire [5:0] pooling_wren;
	wire [9:0] fc_wren;

	// 鍗风Н瀹屾垚鏍囧織
	wire [5:0] conv_done;

	// 妯″潡鍐呴儴鏁版嵁绔彛
	// taps_0 涓哄綋鍓嶅疄闄呭弬涓庡嵎绉殑鏁版嵁绐楋紝taps_1 涓? Pin=2 棰勭暀鐨勭浜岃矾鏁版嵁绐?
	wire [39:0] taps_0;
	wire [39:0] taps_1;
	reg signed [31:0] add_data [0:5];
	reg signed [31:0] relu_data [0:5];
	
	// 妯″潡杈撳嚭鏁版嵁绔彛
	wire signed [31:0] conv_result [0:5];
	wire signed [31:0] add_result [0:5];
	wire signed [7:0] relu_result [0:5];
	wire signed [7:0] pooling_result [0:5];
	wire signed [31:0] fc_result [0:9];
	reg signed [31:0] result_r0 [0:9];
	reg signed [31:0] result_r1 [0:9];


// 鍗风Н杞璁℃暟
reg [3:0] conv_counter = 4'd0;

// 绗竴灞? feature map 璇绘帶鍒?
reg [5:0] fmap_rdrst;
reg [5:0] fmap_rden;

// 鍙屾粦绐楄緭鍏ョ鍙?
// image_in_0 淇濇寔褰撳墠鍗曢?氶亾鍗风Н璺緞锛宨mage_in_1 涓烘湭鏉? Pin=2 鐨勭浜岃緭鍏ラ?氶亾棰勭暀
reg [7:0] image_in_0;
reg [7:0] image_in_1;                      

// 鐘舵?佹帶鍒讹細0 琛ㄧず绗竴灞傦紝1 琛ㄧず绗簩灞?
reg state; 

// 鍗风Н鏉冮噸璁℃暟
reg [10:0] weight_counter;
reg [10:0] weight_stream_cnt;
reg signed [7:0] conv_weight_mem [0:1949];

// 鍗风Н灞備笌鍏ㄨ繛鎺ュ眰鏉冮噸缂撳瓨
reg signed [7:0] weight_c [0:5];
reg signed [7:0] weight_fc [0:9];
integer weight_pe_idx;
integer weight_pair_idx;
integer weight_out_base;
integer weight_local_idx;
integer weight_mem_addr;

// 褰撳墠鍗风Н杞鍐呴儴鏃堕挓璁℃暟
reg [9:0] cnt;

// 绗竴灞? feature map 鍐欑鍙?
reg [5:0] fmap_wren;
wire signed [7:0] fmap_dout [0:5];

// 绗簩灞備腑闂撮儴鍒嗗拰 FIFO 鎺ュ彛锛?12 璺? FIFO 鍒嗗埆淇濆瓨 12 涓緭鍑洪?氶亾鐨勯儴鍒嗗拰锛?
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

 // 鍚勭骇缁撴灉璁℃暟鍣細鍗风Н杈撳嚭銆佸姞娉曡緭鍑恒?佹睜鍖栬緭鍑?
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

 // 鍏ㄨ繛鎺ュ眰鏉冮噸瑁呰浇璁℃暟涓庝娇鑳芥帶鍒?
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

//**********************鍗风Н寰幆鎺у埗***********************// 
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

	//**********state=0锛氱涓?灞傦紝杈撳叆 28x28锛屽嵎绉悗 24x24锛屾睜鍖栧悗 12x12锛泂tate=1锛氱浜屽眰锛岃緭鍏? 12x12锛屽嵎绉悗 8x8锛屾睜鍖栧悗 4x4************//                      
	always@(*)
		case(conv_counter)
		4'd0,4'd1:state <= 0;
		default:state <= 1;
	endcase

//********************鍗风Н灞傛潈閲嶈鍙?***********************// 
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
    if(!state)
        begin
            if(weight_tvalid && weight_tready && weight_counter < 11'd150)
                weight_counter <= weight_counter + 1'b1;
            else
                weight_counter <= weight_counter;
        end
    else
        begin
            if(weight_counter < 11'd300)
                weight_counter <= weight_counter + 1'b1;
            else
                weight_counter <= weight_counter;
        end  
    
	// 褰撳墠鎷嶉?佸叆鐨勫嵎绉潈閲嶆暟鎹箍鎾埌 6 涓嵎绉? PE锛?
	// 鍏蜂綋鐢? weight_en 鐨? one-hot 閫夋嫨鍝竴涓? PE 鍦ㄨ鎷嶇湡姝ｈ杞藉畠銆?
	always@(*)
	begin
		if(!state)
			begin
				weight_c[0] <= weight_tdata;
				weight_c[1] <= weight_tdata;
				weight_c[2] <= weight_tdata;
				weight_c[3] <= weight_tdata;
				weight_c[4] <= weight_tdata;
				weight_c[5] <= weight_tdata;
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
								weight_c[weight_pe_idx] <= conv_weight_mem[weight_mem_addr];
							end
						else
							weight_c[weight_pe_idx] <= 0;
					end
			end
	end

// 鍏ㄨ繛鎺ュ眰寮?濮嬪墠锛岄渶瑕佸厛瑁呰浇 1920 涓叏杩炴帴鏉冮噸
always@(*)
begin
//**********************鍏ㄨ繛鎺ユ潈閲嶈杞?*********************//
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
// 鎸? 10 涓緭鍑虹缁忓厓椤哄簭瑁呰浇鍚勮嚜鐨? 192 涓潈閲?
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

//***********************杈撳叆鏁版嵁璇诲彇鎺у埗*******************//
always@(posedge clk)
    case(conv_counter)
        4'd1:if(!start_window) image_ready <= 1'b0;
             else image_ready <= 1'b1;
        4'd2,4'd3:if(!start_window) fmap_rden <= 6'b000000;
             else fmap_rden <= 6'b000011;              
        4'd4,4'd5:if(!start_window) fmap_rden <= 6'b000000;
             else fmap_rden <= 6'b001100;
        4'd6,4'd7:if(!start_window) fmap_rden <= 6'b000000;
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

//*********************鍙屾粦绐楄緭鍏ョ鍙ｏ紙Pin=2 棰勭暀锛?***********************//
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
//*****************鍗风Н鍚姩鍚庣殑鏃堕挓璁℃暟****************//
always@(posedge clk or negedge resetn)
begin
if(!resetn)
    cnt <= 10'd0;
else
    if(!start_conv)
        cnt <= 10'd0;
    else 
        cnt <= cnt + 10'd1;
end

//*************************婊戠獥鍚姩鎺у埗***********************//
always@(posedge clk or negedge resetn)
begin
    if(!resetn)
        start_window <= 0;
    else
        if(conv_done == 6'b111111)
            start_window <= 0;
        else
            case(state)
            1'b0:if(cnt == 10'd11) start_window <= 1;
            1'b1:if(cnt == 10'd241) start_window <= 1;
            endcase
end

// 鍏堟妸鍙? window 缁撴瀯鎼捣鏉ワ細
// window_inst_0 瀵瑰簲褰撳墠宸蹭娇鐢ㄧ殑鏁版嵁閫氳矾锛?
// window_inst_1 鏄湭鏉? Pin=2 鏃剁粰绗簩杈撳叆閫氶亾浣跨敤鐨勬暟鎹?氳矾銆?
window window_inst_0(.clk(clk),.rstn(resetn),.start(start_window),.state(state),.din(image_in_0),.taps(taps_0));
window window_inst_1(.clk(clk),.rstn(resetn),.start(start_window),.state(state),.din(image_in_1),.taps(taps_1));

//*******************鍗风Н妯″潡鍚姩鎺у埗*****************//
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

//********************鍗风Н妯″潡瀹炰緥鍖?*********************//
genvar i;
generate
    for(i=0;i<=5;i=i+1)
        begin:conv_inst
            conv_pin2 u_conv(.clk(clk),
                             .rstn(resetn),
                             .start(start_conv),
                             .weight_en(weight_en[i]),
                             .weight(weight_c[i]),
                             .taps_0(taps_0),
                             .taps_1(taps_1),
                             .state(state),
                             .dout(conv_result[i]),
                             .ovalid(conv_wren[i]),
                             .done(conv_done[i]));
             end
endgenerate

//*******************绗簩灞備腑闂寸粨鏋滃啓鍏? FIFO****************//

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
//****************绗簩灞備腑闂撮儴鍒嗗拰浠? FIFO 璇诲嚭******************//
always@(*)
case(conv_counter)
    4'd4,4'd6:if(conv_wren == 6'b111111) m_fifo_ready <= 12'b000000111111;
         else if(conv_wren == 6'b000000) m_fifo_ready <= 12'b000000000000;
    4'd5,4'd7:if(conv_wren == 6'b111111) m_fifo_ready <= 12'b111111000000;
         else if(conv_wren == 6'b000000) m_fifo_ready <= 12'b000000000000;
    default:m_fifo_ready <= 12'b000000000000;     
endcase

//********************鍔犳硶妯″潡杈撳叆锛坅dd_data锛?**********************//
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
   
//*****************绗簩灞傞儴鍒嗗拰 FIFO 瀹炰緥鍖?******************//
genvar a;
generate
    for(a=0;a<=11;a=a+1)
        begin:fifo_inst
            user_fifo_ip your_instance_name(
              .s_axis_aresetn(reset_fifo),          // FIFO 浣庢湁鏁堝浣?
              .s_axis_aclk(clk),                // FIFO 鍐欏叆鏃堕挓
              .s_axis_tvalid(s_fifo_valid[a]),            // 鍐欏叆鏈夋晥
              .s_axis_tready(s_fifo_ready[a]),            // FIFO 鍙啓灏辩华
              .s_axis_tdata(s_fifo_data[a]),              // 鍐欏叆鐨勯儴鍒嗗拰鏁版嵁
              .m_axis_tvalid(m_fifo_valid[a]),            // 璇诲嚭鏈夋晥
              .m_axis_tready(m_fifo_ready[a]),            // 璇诲嚭灏辩华
              .m_axis_tdata(m_fifo_data[a])             // 璇诲嚭鐨勯儴鍒嗗拰鏁版嵁
            );
        end
endgenerate

//********************鍔犳硶妯″潡****************//
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
    
//******************ReLU 妯″潡浣胯兘鎺у埗**************//
reg ivalid_relu;
always@(*)
case(conv_counter)
4'd1:if(conv_wren == 6'b111111) ivalid_relu <= 1'b1;
     else ivalid_relu <= 1'b0;
4'd6,4'd7:if(add_wren == 6'b111111) ivalid_relu <= 1'b1;
     else ivalid_relu <= 1'b0;
default:ivalid_relu <= 1'b0;
endcase

//******************ReLU 妯″潡杈撳叆绔彛锛坮elu_data锛?******************//
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

//********************ReLU 妯″潡*******************//
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

//******************姹犲寲妯″潡******************//
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

//************绗竴灞? feature map 鍐欏叆鎺у埗**************//
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
              .rd_rst(fmap_rdrst[e]),     // 璇诲湴鍧?鍥炲埌璧峰浣嶇疆
              .dout(fmap_dout[e]),
              .full(),
              .empty()
            );
        end
endgenerate

//***************鍏ㄨ繛鎺ュ眰*****************//
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

//*************鍏ㄨ繛鎺ュ眰缁撴灉鎷兼帴*****************//
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

// 缁撴灉杈撳嚭鎺у埗锛氫緷娆￠?佸嚭 10 涓叏杩炴帴缁撴灉锛屽苟鍦ㄦ渶鍚庝竴鎷嶆媺楂? tlast

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

assign result_tlast = result_last_r;
 
endmodule
