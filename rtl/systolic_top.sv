`default_nettype none

module systolic_top #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter N = 4,
    parameter M = 4
)
(
    input logic clk_i,
    input logic rst_n_i,
    input logic start_i,

    output logic [M-1:0][ACC_WIDTH-29:0] c_o
);

localparam int unsigned BIAS_ADDR_WIDTH = 9;
localparam int unsigned BIAS_DATA_WIDTH = 32;

logic [DATA_WIDTH-1:0] a_w      [N][M+1];
logic [DATA_WIDTH-1:0] b_w      [N+1][M];
logic [ACC_WIDTH-1:0]  c_w      [N+1][M];
logic [ACC_WIDTH-1:0]  acc_w    [M+1];
logic [N+M-2:0]        en_pes_w;
logic [M-1:0]          en_acc_w;

logic [DATA_WIDTH-1:0] bram_data_out [N + M];

logic [(M/2)-1:0][ADDR_WIDTH-1:0] cols_addrs;
logic [(N/2)-1:0][ADDR_WIDTH-1:0] row_addrs;
logic [BIAS_ADDR_WIDTH-1:0] b_addr;

logic [N-1:0][M-1:0] drain;
logic [N-1:0][M-1:0] rst_pes;

systolic_control_unit #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .N         (N),
    .M         (M)
) systolic_control_unit (
    .clk_i    (clk_i),
    .rst_n_i  (rst_n_i),
    .start_i  (start_i),
    .cols_addrs_o(cols_addrs),
    .row_addrs_o(row_addrs),
    .en_pes_o(en_pes_w),
    .en_acc_o(en_acc_w),
    .drain_o(drain),
    .rst_pes_o(rst_pes),
    .bias_addr_o(b_addr)
);

bram #(
	.ADDR_WIDTH  (BIAS_ADDR_WIDTH),
	.DATA_WIDTH  (BIAS_DATA_WIDTH),
	.BRAM_ELEMENT(4)
 ) bias_bram (
	.clk_i    (clk_i),
	.addr_i   (b_addr),
	.wr_en_i  ('b0),
	.wr_data_i('d0),
	.rd_data_o(acc_w[0])
);

genvar i, j;
generate
    for (i = 0; i < N; ++i) begin: a_for
        shift_register #(
        	.DATA_WIDTH (DATA_WIDTH),
        	.SHIFT_WIDTH(i+1)
         ) shift_register (
        	.clk_i  (clk_i),
        	.rst_n_i(rst_n_i),
        	.data_i (bram_data_out[i]),
        	.data_o (a_w[i][0])
        );
    end

    for (j = 0; j < M; ++j) begin: b_for
        shift_register #(
        	.DATA_WIDTH (DATA_WIDTH),
        	.SHIFT_WIDTH(j+1)
         ) shift_register (
        	.clk_i  (clk_i),
        	.rst_n_i(rst_n_i),
        	.data_i (bram_data_out[N+j]),
        	.data_o (b_w[0][j])
        );

        systolic_accumulator #(
           	.ACC_WIDTH(ACC_WIDTH)
         ) accumulator (
        	.clk_i  (clk_i),
        	.rst_n_i(rst_n_i),
        	.c_i    (c_w[N][j]),
        	.acc_i  (acc_w[j]),
        	.en_i   (en_acc_w[j]),
           	.c_o    (c_o[j]),
        	.acc_o  (acc_w[j+1])
        );
    end


    for (i = 0; i < N; i = i + 2) begin: bram_for_N
        bram
        #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH * 2),
            .BRAM_ELEMENT(i / 2)
        )
        bram (
            .clk_i(clk_i),
            .addr_i(row_addrs[i/2]),
            .wr_en_i(1'b0),
            .wr_data_i('d0),
            .rd_data_o({bram_data_out[i+1], bram_data_out[i]})
        );
    end

    for (j = 0; j < M; j = j + 2) begin: bram_for_M
        bram
        #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH * 2),
            .BRAM_ELEMENT(N/2 + j / 2)
        )
        bram
        (
            .clk_i(clk_i),
            .addr_i(cols_addrs[j/2]),
            .wr_en_i(1'b0),
            .wr_data_i('d0),
            .rd_data_o({bram_data_out[j+N+1], bram_data_out[j+N]})
        );
    end

    for (i = 0; i < N; ++i) begin: for_i
        for (j = 0; j < M; ++j) begin: for_j
            systolic_mac_pe #(
               	.DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH(ACC_WIDTH)
             ) mac_pe (
            	.clk_i  (clk_i),
            	.rst_n_i(rst_n_i),
            	.a_i(a_w[i][j]),
            	.b_i(b_w[i][j]),
                .c_i(c_w[i][j]),
                .en_i(en_pes_w[i+j]),
                .drain_i(drain[i][j]),
                .rst_i(rst_pes[i][j]),
            	.a_o(a_w[i][j+1]),
            	.b_o(b_w[i+1][j]),
                .c_o(c_w[i+1][j])
            );
        end
    end
endgenerate

endmodule
