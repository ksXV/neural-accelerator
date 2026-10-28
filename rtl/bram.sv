module bram #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 16,
    parameter BRAM_ELEMENT = 0
)
(
    input logic clk_i,
    input logic [ADDR_WIDTH-1:0] addr_i,
    input logic wr_en_i,
    input logic [DATA_WIDTH-1:0] wr_data_i,
    output logic [DATA_WIDTH-1:0] rd_data_o
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] internal_data [0:DEPTH-1];

    generate
           if (BRAM_ELEMENT == 0) begin : init_a0
               initial $readmemh("systolic_mem_files/a0.mem", internal_data);
           end else if (BRAM_ELEMENT == 1) begin : init_a1
               initial $readmemh("systolic_mem_files/a1.mem", internal_data);
           end else if (BRAM_ELEMENT == 2) begin : init_b0
               initial $readmemh("systolic_mem_files/b0.mem", internal_data);
           end else if (BRAM_ELEMENT == 3) begin : init_b1
               initial $readmemh("systolic_mem_files/b1.mem", internal_data);
           end
       endgenerate

    //use always instead of always_ff so sv-lang doesn't complain about multiple drivers here
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            internal_data[addr_i] <= wr_data_i;
        end
        rd_data_o <= internal_data[addr_i];
    end

endmodule
