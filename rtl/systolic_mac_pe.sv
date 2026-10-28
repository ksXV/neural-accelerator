module systolic_mac_pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)
(
    input logic clk_i,
    input logic rst_n_i,
    input logic rst_i,

    input logic [DATA_WIDTH-1:0] a_i,
    input logic [DATA_WIDTH-1:0] b_i,
    input logic [ACC_WIDTH-1:0] c_i,

    input logic en_i,
    input logic drain_i,

    output logic [DATA_WIDTH-1:0] a_o,
    output logic [DATA_WIDTH-1:0] b_o,
    output logic [ACC_WIDTH-1:0] c_o
);
    logic [ACC_WIDTH-1:0] m_result;
    logic [ACC_WIDTH-1:0] result;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            a_o <= 'd0;
            b_o <= 'd0;
            c_o <= 'd0;
        end else begin
            a_o <= a_i;
            b_o <= b_i;
            c_o <= drain_i ? result : c_i;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            result <= 'd0;
            m_result <= 'd0;
        end else if (en_i) begin
            m_result <= a_i * b_i;
            result <= m_result + result;
        end else if (rst_i) begin
            result <= 'd0;
            m_result <= 'd0;
        end
    end

endmodule
