module systolic_control_unit #(
    parameter ADDR_WIDTH = 10,
    parameter byte unsigned N = 4,
    parameter byte unsigned M = 4,
    parameter BIAS_ADDR_WIDTH = 9
)
(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic start_i,

    output logic [(M/2)-1:0][ADDR_WIDTH-1:0] cols_addrs_o,
    output logic [(N/2)-1:0][ADDR_WIDTH-1:0] row_addrs_o,

    output logic [N-1:0][M-1:0] drain_o,
    output logic [N+M-2:0] en_pes_o,
    output logic [N-1:0][M-1:0] rst_pes_o,

    output logic [BIAS_ADDR_WIDTH-1:0] bias_addr_o,
    output logic [M-1:0] en_acc_o
);
    // Start the tilling algortithm
    localparam int unsigned A_ROWS = 32;
    localparam int unsigned A_COLUMNS = 16;

    localparam int unsigned B_ROWS = 16;
    localparam int unsigned B_COLUMNS = 24;

    logic en_addr;
    logic en_pes;

    logic rst_addrs;
    logic rst_col_offset;
    logic rst_row_offset;

    logic add_row_offset;
    logic add_col_offset;

    logic en_element_counter;

    logic [ADDR_WIDTH-1:0] row_offset;
    logic [ADDR_WIDTH-1:0] column_offset;

    logic [16-1:0] rows_processed;
    logic [16-1:0] cols_processed;

    logic [16-1:0] elements_proccessed;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            elements_proccessed <= 'd0;
        end else if (rst_addrs) begin
            elements_proccessed <= 'd0;
        end else if (en_element_counter) begin
            elements_proccessed <= elements_proccessed + 'b1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            rows_processed <= 'd0;
        end else if (rst_row_offset) begin
            rows_processed <= 'd0;
        end else if (add_row_offset) begin
            rows_processed <= rows_processed + 16'(N);
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            cols_processed <= 'd0;
        end else if (rst_col_offset) begin
            cols_processed <= 'd0;
        end else if (add_col_offset) begin
            cols_processed <= cols_processed + 16'(M);
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            row_offset <= 'd0;
        end else if (rst_row_offset) begin
            row_offset <= 'd0;
        end else if (add_row_offset) begin
            row_offset <= row_offset + A_COLUMNS;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            column_offset <= 'd0;
        end else if (rst_col_offset) begin
            column_offset <= 'd0;
        end else if (add_col_offset) begin
            column_offset <= column_offset + B_COLUMNS;
        end
    end

    typedef enum logic [2:0] {
        INITIAL,
        START,
        LOAD_ROW_OFFSET,
        PROCESSING,
        PRE_DRAIN,
        DRAIN,
        END
    } states_t;

    states_t state, next_state;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
            state <= INITIAL;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = INITIAL;
        en_addr = 0;
        en_pes = 0;
        rst_addrs = 0;
        rst_col_offset = 0;
        rst_row_offset = 0;
        drain_o = 0;
        add_col_offset = 0;
        add_row_offset = 0;
        bias_addr_o = 'd0;
        en_element_counter = 0;
        en_acc_o = 'b1;

        for (byte unsigned i = 0; i < N; i++) begin
            for (byte unsigned j = 0; j < N; j++) begin
                rst_pes_o[i][j] = 0;
            end
        end

        case (state)
            INITIAL: begin
                if (start_i) begin
                    rst_addrs      = 1'b1;
                    rst_col_offset = 1'b1;
                    rst_row_offset = 1'b1;
                    next_state = START;
                    en_addr = 'd1;
                end else begin
                    next_state = INITIAL;
                end
            end
            START: begin
                en_pes = 'd1;
                en_addr = 'd1;
                en_element_counter = 'd1;
                for (byte unsigned i = 0; i < N; i++) begin
                    for (byte unsigned j = 0; j < M; j++) begin
                        rst_pes_o[i][j] = 1;
                    end
                end
                next_state = PROCESSING;
            end
            PROCESSING: begin
                en_pes = 'd1;
                en_addr = 'd1;
                en_element_counter = 'd1;
                if (elements_proccessed % (B_ROWS+1) == 0) begin // find a way to remove this cause its slowing us by a lot
                    next_state = PRE_DRAIN;
                    add_col_offset = 1;
                    en_pes = 'd0;
                end else begin
                    next_state = PROCESSING;
                end
            end
            LOAD_ROW_OFFSET: begin
               // wait for the row offset to propagate correctly
               rst_addrs = 1'b1;
               next_state = START;
            end
            PRE_DRAIN: begin
               en_pes = 'd1;
               next_state = DRAIN;
            end
            DRAIN: begin
                en_addr = 'd0;
                if (~en_pes_o[N+M-2]) begin
                    drain_o = '1;
                    if (cols_processed == B_COLUMNS) begin
                        if (rows_processed + N >= A_ROWS) begin
                            next_state = END;
                        end else begin
                            add_row_offset = 1'b1;
                            rst_addrs      = 1'b1;
                            rst_col_offset = 1'b1;
                            next_state = LOAD_ROW_OFFSET;
                        end
                    end else begin
                        rst_addrs = 1'b1;
                        next_state = START;
                    end
                end else begin
                    next_state = DRAIN;
                end
            end
            END: begin
                rst_addrs      = 1'b1;
                rst_col_offset = 1'b1;
                rst_row_offset = 1'b1;
                next_state = END;
            end
            default:;
        endcase

    end


    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (~rst_n_i) begin
           en_pes_o <= 'd0;
        end else if (rst_addrs) begin
           en_pes_o <= 'd0;
        end else if (en_pes) begin
           en_pes_o <= {en_pes_o[N+M-3:0], 1'b1};
        end else begin
           en_pes_o <= {en_pes_o[N+M-3:0], 1'b0};
        end
    end

    genvar i;
    generate
        for (i = 0; i < N/2; ++i) begin: addrs_row
            logic [ADDR_WIDTH-1:0] addr;

            always_ff @(posedge clk_i or negedge rst_n_i) begin
                if (~rst_n_i) begin
                    addr <= 'd0;
                end else if (rst_addrs) begin
                    addr <= 'd0 + row_offset;
                end else if (en_addr) begin
                    addr <= addr + 1'b1;
                end
            end

            assign row_addrs_o[i] = addr;
        end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < M/2; ++j) begin: addrs_cols
            logic [ADDR_WIDTH-1:0] addr;

            always_ff @(posedge clk_i or negedge rst_n_i) begin
                if (~rst_n_i) begin
                    addr <= 'd0;
                end else if (rst_addrs) begin
                    addr <= 'd0 + column_offset;
                end else if (en_addr) begin
                    addr <= addr + 1'b1;
                end
            end

            assign cols_addrs_o[j] = addr;
        end
    endgenerate

endmodule
