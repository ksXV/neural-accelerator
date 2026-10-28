module shift_register #(
    parameter DATA_WIDTH  = 8,
    parameter SHIFT_WIDTH = 1
)
(
    input  logic                  clk_i,
    input  logic                  rst_n_i,

    input  logic [DATA_WIDTH-1:0] data_i,
    output logic [DATA_WIDTH-1:0] data_o
);

    genvar i;
    generate
        begin : gen_shift
            logic [DATA_WIDTH-1:0] shift_reg [SHIFT_WIDTH];

            always_ff @(posedge clk_i or negedge rst_n_i) begin
                if (~rst_n_i) begin
                    shift_reg[0] <= '0;
                end else begin
                    shift_reg[0] <= data_i;
                end
            end

            for (i = 1; i < SHIFT_WIDTH; i++) begin : gen_stages
                always_ff @(posedge clk_i or negedge rst_n_i) begin
                    if (~rst_n_i) begin
                        shift_reg[i] <= '0;
                    end else begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                end
            end

            assign data_o = shift_reg[SHIFT_WIDTH-1];
        end
    endgenerate

endmodule
