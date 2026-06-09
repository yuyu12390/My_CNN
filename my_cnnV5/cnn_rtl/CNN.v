`timescale 1ns / 1ns

// CNN总顶层
// 1. 先装第一层和第三层卷积权重
// 2. 再装第五层FC权重
// 3. 再装一帧28x28图像
// 4. 依次启动L1到L5
// 5. 最后串行输出10个分类分数
module CNN
(
    input  clk,                                          // 时钟
    input  resetn,                                       // 低有效复位
    input  start_cnn,                                    // 启动一次完整推理
    input  image_tvalid,                                 // 图像输入有效
    input  signed [7:0] image_tdata,                     // 图像输入数据
    input  weight_tvalid,                                // 卷积权重输入有效
    input  signed [7:0] weight_tdata,                    // 卷积权重输入数据
    input  weightfc_tvalid,                              // FC权重输入有效
    input  signed [7:0] weightfc_tdata,                  // FC权重输入数据
    input  result_tready,                                // 结果接收准备好

    output image_tready,                                 // 图像输入准备好
    output weight_tready,                                // 卷积权重输入准备好
    output weightfc_tready,                              // FC权重输入准备好
    output reg cnn_done,                                 // 推理完成脉冲
    output result_tvalid,                                // 结果输出有效
    output signed [31:0] result_tdata                    // 串行结果输出
);

    localparam integer L1_LANE_NUM = 6;
    localparam integer L3_OUT_NUM = 12;
    localparam integer L5_OUT_NUM = 10;
    localparam integer DATA_WIDTH = 8;
    localparam integer WEIGHT_WIDTH = 8;
    localparam integer OUT_WIDTH = 32;
    localparam integer ROW_ADDR_WIDTH = 5;
    localparam integer COL_ADDR_WIDTH = 5;
    localparam integer ADDR2D_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH;
    localparam integer CONV_WEIGHT_TOTAL = 1950;
    localparam integer FC_WEIGHT_TOTAL = 1920;
    localparam integer IMAGE_TOTAL = 784;

    localparam [4:0] ST_IDLE          = 5'd0;
    localparam [4:0] ST_LOAD_CONV     = 5'd1;
    localparam [4:0] ST_LOAD_FC       = 5'd2;
    localparam [4:0] ST_IMG_START     = 5'd3;
    localparam [4:0] ST_IMG_ARM       = 5'd4;
    localparam [4:0] ST_LOAD_IMG      = 5'd5;
    localparam [4:0] ST_L1_WAIT_READY = 5'd6;
    localparam [4:0] ST_L1_WAIT_DONE  = 5'd7;
    localparam [4:0] ST_L2_WAIT_READY = 5'd8;
    localparam [4:0] ST_L2_WAIT_DONE  = 5'd9;
    localparam [4:0] ST_L3_WAIT_READY = 5'd10;
    localparam [4:0] ST_L3_WAIT_DONE  = 5'd11;
    localparam [4:0] ST_L4_WAIT_READY = 5'd12;
    localparam [4:0] ST_L4_WAIT_DONE  = 5'd13;
    localparam [4:0] ST_L5_WAIT_READY = 5'd14;
    localparam [4:0] ST_L5_WAIT_DONE  = 5'd15;
    localparam [4:0] ST_RESULT_RELEASE= 5'd16;
    localparam [4:0] ST_RESULT_SEND   = 5'd17;

    reg [4:0] state;
    reg [10:0] conv_weight_cnt;
    reg [10:0] fc_weight_cnt;
    reg [9:0] image_cnt;
    reg [3:0] result_idx;

    reg l1_frame_start;
    reg l1_scan_start;
    reg l1_frame_release;
    reg l2_start;
    reg l3_start;
    reg l4_start;
    reg l5_start;
    reg l5_score_ready;

    reg signed [31:0] result_buf [0:L5_OUT_NUM-1];

    integer score_idx;

    wire conv_weight_fire;
    wire fc_weight_fire;
    wire image_fire;

    wire l1_cfg_weight_ready;
    wire l1_image_tready;
    wire l1_scan_ready;
    wire l1_img_frame_valid;
    wire l1_scan_busy;
    wire l1_scan_done;
    wire [L1_LANE_NUM-1:0] l1_ofmap_frame_valid;
    wire signed [L1_LANE_NUM*OUT_WIDTH-1:0] l1_ofmap_rd_data;
    wire [L1_LANE_NUM-1:0] l1_ofmap_rd_valid;

    wire l2_ready;
    wire l2_busy;
    wire l2_done;
    wire [L1_LANE_NUM-1:0] l2_src_rd_en;
    wire [L1_LANE_NUM*ADDR2D_WIDTH-1:0] l2_src_rd_addr2d;
    wire [L1_LANE_NUM-1:0] l2_src_rd_done;
    wire [L1_LANE_NUM-1:0] l2_dst_frame_valid;
    wire signed [L1_LANE_NUM*DATA_WIDTH-1:0] l2_dst_rd_data;
    wire [L1_LANE_NUM-1:0] l2_dst_rd_valid;

    wire l3_cfg_weight_ready;
    wire l3_ready;
    wire l3_busy;
    wire l3_done;
    wire [L1_LANE_NUM-1:0] l3_src_rd_en;
    wire [L1_LANE_NUM*ADDR2D_WIDTH-1:0] l3_src_rd_addr2d;
    wire [L1_LANE_NUM-1:0] l3_src_rd_done;
    wire [L3_OUT_NUM-1:0] l3_dst_frame_valid;
    wire signed [L3_OUT_NUM*OUT_WIDTH-1:0] l3_dst_rd_data;
    wire [L3_OUT_NUM-1:0] l3_dst_rd_valid;

    wire l4_ready;
    wire l4_busy;
    wire l4_done;
    wire [L3_OUT_NUM-1:0] l4_src_rd_en;
    wire [L3_OUT_NUM*ADDR2D_WIDTH-1:0] l4_src_rd_addr2d;
    wire [L3_OUT_NUM-1:0] l4_src_rd_done;
    wire [L3_OUT_NUM-1:0] l4_dst_frame_valid;
    wire signed [L3_OUT_NUM*DATA_WIDTH-1:0] l4_dst_rd_data;
    wire [L3_OUT_NUM-1:0] l4_dst_rd_valid;

    wire l5_cfg_weight_ready;
    wire l5_ready;
    wire l5_busy;
    wire l5_done;
    wire [L3_OUT_NUM-1:0] l5_src_rd_en;
    wire [L3_OUT_NUM*ADDR2D_WIDTH-1:0] l5_src_rd_addr2d;
    wire [L3_OUT_NUM-1:0] l5_src_rd_done;
    wire l5_score_valid;
    wire signed [L5_OUT_NUM*OUT_WIDTH-1:0] l5_score_data;

    assign weight_tready = (state == ST_LOAD_CONV) && l1_cfg_weight_ready && l3_cfg_weight_ready;
    assign weightfc_tready = (state == ST_LOAD_FC) && l5_cfg_weight_ready;
    assign image_tready = (state == ST_LOAD_IMG) && l1_image_tready;

    assign conv_weight_fire = (state == ST_LOAD_CONV) && weight_tvalid && weight_tready;
    assign fc_weight_fire = (state == ST_LOAD_FC) && weightfc_tvalid && weightfc_tready;
    assign image_fire = (state == ST_LOAD_IMG) && image_tvalid && image_tready;

    assign result_tvalid = (state == ST_RESULT_SEND);
    assign result_tdata = result_buf[result_idx];

    l1_top u_l1_top (
        .clk(clk),
        .rstn(resetn),
        .frame_start(l1_frame_start),
        .image_tdata(image_tdata),
        .image_tvalid(image_fire),
        .cfg_weight_valid(conv_weight_fire),
        .cfg_weight_data(weight_tdata),
        .cfg_weight_last(conv_weight_fire && (conv_weight_cnt == (CONV_WEIGHT_TOTAL - 1))),
        .scan_start(l1_scan_start),
        .frame_release(l1_frame_release),
        .ofmap_rd_en(l2_src_rd_en),
        .ofmap_rd_addr2d(l2_src_rd_addr2d),
        .ofmap_rd_done(l2_src_rd_done),
        .cfg_weight_ready(l1_cfg_weight_ready),
        .cfg_weight_done(),
        .cfg_last_err(),
        .image_tready(l1_image_tready),
        .scan_ready(l1_scan_ready),
        .img_frame_valid(l1_img_frame_valid),
        .weight_loaded(),
        .scan_busy(l1_scan_busy),
        .scan_done(l1_scan_done),
        .ofmap_frame_valid(l1_ofmap_frame_valid),
        .ofmap_rd_data(l1_ofmap_rd_data),
        .ofmap_rd_valid(l1_ofmap_rd_valid)
    );

    l2_top u_l2_top (
        .clk(clk),
        .rstn(resetn),
        .start(l2_start),
        .src_frame_valid(l1_ofmap_frame_valid),
        .src_rd_data(l1_ofmap_rd_data),
        .src_rd_valid(l1_ofmap_rd_valid),
        .dst_rd_en(l3_src_rd_en),
        .dst_rd_addr2d(l3_src_rd_addr2d),
        .dst_rd_done(l3_src_rd_done),
        .ready(l2_ready),
        .busy(l2_busy),
        .done(l2_done),
        .src_rd_en(l2_src_rd_en),
        .src_rd_addr2d(l2_src_rd_addr2d),
        .src_rd_done(l2_src_rd_done),
        .dst_frame_valid(l2_dst_frame_valid),
        .dst_rd_data(l2_dst_rd_data),
        .dst_rd_valid(l2_dst_rd_valid)
    );

    l3_top u_l3_top (
        .clk(clk),
        .rstn(resetn),
        .start(l3_start),
        .src_frame_valid(l2_dst_frame_valid),
        .src_rd_data(l2_dst_rd_data),
        .src_rd_valid(l2_dst_rd_valid),
        .cfg_weight_valid(conv_weight_fire),
        .cfg_weight_data(weight_tdata),
        .cfg_weight_last(conv_weight_fire && (conv_weight_cnt == (CONV_WEIGHT_TOTAL - 1))),
        .dst_rd_en(l4_src_rd_en),
        .dst_rd_addr2d(l4_src_rd_addr2d),
        .dst_rd_done(l4_src_rd_done),
        .cfg_weight_ready(l3_cfg_weight_ready),
        .cfg_weight_done(),
        .cfg_last_err(),
        .ready(l3_ready),
        .busy(l3_busy),
        .done(l3_done),
        .weight_loaded(),
        .src_rd_en(l3_src_rd_en),
        .src_rd_addr2d(l3_src_rd_addr2d),
        .src_rd_done(l3_src_rd_done),
        .dst_frame_valid(l3_dst_frame_valid),
        .dst_rd_data(l3_dst_rd_data),
        .dst_rd_valid(l3_dst_rd_valid)
    );

    l4_top u_l4_top (
        .clk(clk),
        .rstn(resetn),
        .start(l4_start),
        .src_frame_valid(l3_dst_frame_valid),
        .src_rd_data(l3_dst_rd_data),
        .src_rd_valid(l3_dst_rd_valid),
        .dst_rd_en(l5_src_rd_en),
        .dst_rd_addr2d(l5_src_rd_addr2d),
        .dst_rd_done(l5_src_rd_done),
        .ready(l4_ready),
        .busy(l4_busy),
        .done(l4_done),
        .src_rd_en(l4_src_rd_en),
        .src_rd_addr2d(l4_src_rd_addr2d),
        .src_rd_done(l4_src_rd_done),
        .dst_frame_valid(l4_dst_frame_valid),
        .dst_rd_data(l4_dst_rd_data),
        .dst_rd_valid(l4_dst_rd_valid)
    );

    l5_top_raw u_l5_top_raw (
        .clk(clk),
        .rstn(resetn),
        .start(l5_start),
        .src_frame_valid(l4_dst_frame_valid),
        .src_rd_data(l4_dst_rd_data),
        .src_rd_valid(l4_dst_rd_valid),
        .cfg_weight_valid(fc_weight_fire),
        .cfg_weight_data(weightfc_tdata),
        .cfg_weight_last(fc_weight_fire && (fc_weight_cnt == (FC_WEIGHT_TOTAL - 1))),
        .score_ready(l5_score_ready),
        .cfg_weight_ready(l5_cfg_weight_ready),
        .cfg_weight_done(),
        .cfg_last_err(),
        .ready(l5_ready),
        .busy(l5_busy),
        .done(l5_done),
        .weight_loaded(),
        .src_rd_en(l5_src_rd_en),
        .src_rd_addr2d(l5_src_rd_addr2d),
        .src_rd_done(l5_src_rd_done),
        .score_valid(l5_score_valid),
        .score_data(l5_score_data)
    );

    always @(posedge clk or negedge resetn)
    begin
        if(!resetn)
        begin
            state <= ST_IDLE;
            conv_weight_cnt <= 11'd0;
            fc_weight_cnt <= 11'd0;
            image_cnt <= 10'd0;
            result_idx <= 4'd0;
            l1_frame_start <= 1'b0;
            l1_scan_start <= 1'b0;
            l1_frame_release <= 1'b0;
            l2_start <= 1'b0;
            l3_start <= 1'b0;
            l4_start <= 1'b0;
            l5_start <= 1'b0;
            l5_score_ready <= 1'b0;
            cnn_done <= 1'b0;
            for(score_idx = 0; score_idx < L5_OUT_NUM; score_idx = score_idx + 1)
            begin
                result_buf[score_idx] <= 32'sd0;
            end
        end
        else
        begin
            l1_frame_start <= 1'b0;
            l1_scan_start <= 1'b0;
            l1_frame_release <= 1'b0;
            l2_start <= 1'b0;
            l3_start <= 1'b0;
            l4_start <= 1'b0;
            l5_start <= 1'b0;
            l5_score_ready <= 1'b0;
            cnn_done <= 1'b0;

            case(state)
                ST_IDLE:
                begin
                    conv_weight_cnt <= 11'd0;
                    fc_weight_cnt <= 11'd0;
                    image_cnt <= 10'd0;
                    result_idx <= 4'd0;

                    if(start_cnn)
                    begin
                        state <= ST_LOAD_CONV;
                    end
                end

                ST_LOAD_CONV:
                begin
                    if(conv_weight_fire)
                    begin
                        if(conv_weight_cnt == (CONV_WEIGHT_TOTAL - 1))
                        begin
                            conv_weight_cnt <= 11'd0;
                            state <= ST_LOAD_FC;
                        end
                        else
                        begin
                            conv_weight_cnt <= conv_weight_cnt + 1'b1;
                        end
                    end
                end

                ST_LOAD_FC:
                begin
                    if(fc_weight_fire)
                    begin
                        if(fc_weight_cnt == (FC_WEIGHT_TOTAL - 1))
                        begin
                            fc_weight_cnt <= 11'd0;
                            state <= ST_IMG_START;
                        end
                        else
                        begin
                            fc_weight_cnt <= fc_weight_cnt + 1'b1;
                        end
                    end
                end

                ST_IMG_START:
                begin
                    l1_frame_start <= 1'b1;
                    image_cnt <= 10'd0;
                    state <= ST_IMG_ARM;
                end

                ST_IMG_ARM:
                begin
                    state <= ST_LOAD_IMG;
                end

                ST_LOAD_IMG:
                begin
                    if(image_fire)
                    begin
                        if(image_cnt == (IMAGE_TOTAL - 1))
                        begin
                            image_cnt <= 10'd0;
                            state <= ST_L1_WAIT_READY;
                        end
                        else
                        begin
                            image_cnt <= image_cnt + 1'b1;
                        end
                    end
                end

                ST_L1_WAIT_READY:
                begin
                    if(l1_scan_ready)
                    begin
                        l1_scan_start <= 1'b1;
                        state <= ST_L1_WAIT_DONE;
                    end
                end

                ST_L1_WAIT_DONE:
                begin
                    if(l1_scan_done)
                    begin
                        l1_frame_release <= 1'b1;
                        state <= ST_L2_WAIT_READY;
                    end
                end

                ST_L2_WAIT_READY:
                begin
                    if(l2_ready)
                    begin
                        l2_start <= 1'b1;
                        state <= ST_L2_WAIT_DONE;
                    end
                end

                ST_L2_WAIT_DONE:
                begin
                    if(l2_done)
                    begin
                        state <= ST_L3_WAIT_READY;
                    end
                end

                ST_L3_WAIT_READY:
                begin
                    if(l3_ready)
                    begin
                        l3_start <= 1'b1;
                        state <= ST_L3_WAIT_DONE;
                    end
                end

                ST_L3_WAIT_DONE:
                begin
                    if(l3_done)
                    begin
                        state <= ST_L4_WAIT_READY;
                    end
                end

                ST_L4_WAIT_READY:
                begin
                    if(l4_ready)
                    begin
                        l4_start <= 1'b1;
                        state <= ST_L4_WAIT_DONE;
                    end
                end

                ST_L4_WAIT_DONE:
                begin
                    if(l4_done)
                    begin
                        state <= ST_L5_WAIT_READY;
                    end
                end

                ST_L5_WAIT_READY:
                begin
                    if(l5_ready)
                    begin
                        l5_start <= 1'b1;
                        state <= ST_L5_WAIT_DONE;
                    end
                end

                ST_L5_WAIT_DONE:
                begin
                    if(l5_done)
                    begin
                        for(score_idx = 0; score_idx < L5_OUT_NUM; score_idx = score_idx + 1)
                        begin
                            result_buf[score_idx] <= l5_score_data[((score_idx + 1) * OUT_WIDTH) - 1 -: OUT_WIDTH];
                        end
                        result_idx <= 4'd0;
                        state <= ST_RESULT_RELEASE;
                    end
                end

                ST_RESULT_RELEASE:
                begin
                    l5_score_ready <= 1'b1;
                    state <= ST_RESULT_SEND;
                end

                ST_RESULT_SEND:
                begin
                    if(result_tvalid && result_tready)
                    begin
                        if(result_idx == (L5_OUT_NUM - 1))
                        begin
                            cnn_done <= 1'b1;
                            result_idx <= 4'd0;
                            state <= ST_IDLE;
                        end
                        else
                        begin
                            result_idx <= result_idx + 1'b1;
                        end
                    end
                end

                default:
                begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
