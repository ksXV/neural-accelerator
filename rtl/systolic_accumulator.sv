module systolic_accumulator #(parameter ACC_WIDTH = 32)
(
    input logic clk_i,
    input logic rst_n_i,

    input logic [ACC_WIDTH-1:0] c_i,
    input logic [ACC_WIDTH-1:0] acc_i,
    input logic en_i,

    output logic [ACC_WIDTH-1:0] c_o,
    output logic [ACC_WIDTH-1:0] acc_o
);


    logic [ACC_WIDTH-1:0] acc;

    assign acc_o = acc;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            acc <= 'd0;
        end else if (en_i) begin
            acc <= acc_i;
        end

    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
       if (~rst_n_i) begin
           c_o <= 'd0;
       end else begin
           c_o <= acc + c_i;
       end
    end
endmodule
