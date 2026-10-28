/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off IMPLICITSTATIC */
`timescale 1ns/1ps

module systolic_top_tb;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter ADDR_WIDTH = 10;
    parameter N          = 4;
    parameter M          = 4;

    localparam int unsigned A_ROWS    = 32;
    localparam int unsigned A_COLUMNS = 16;
    localparam int unsigned B_ROWS    = 16;
    localparam int unsigned B_COLUMNS = 24;

    localparam int TOTAL_ROW_TILES = A_ROWS / N;       // 32 / 4 = 8
    localparam int TOTAL_COL_TILES = B_COLUMNS / M;    // 24 / 4 = 6
    localparam int TOTAL_TILES     = TOTAL_ROW_TILES * TOTAL_COL_TILES; // 48

    localparam CLK_PERIOD = 10;
    localparam TIMEOUT_CYCLES = 10000;

    logic clk_i;
    logic rst_n_i;
    logic start_i;
    // FIX 1: was [ACC_WIDTH-29:0] (=4 bits/lane, 16b total) but DUT c_o is M*ACC_WIDTH = 128b
    logic [M-1:0][ACC_WIDTH-1:0] c_o;

    // Instantiate DUT with full N=4, M=4 configuration
    systolic_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .N(N),
        .M(M)
    ) dut (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .start_i(start_i),
        .c_o    (c_o)
    );

    // Clock generator
    initial clk_i = 1'b0;
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // Watchdog
    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES);
        $display("\n[ERROR] TIMEOUT: Simulation reached %0d cycles without completing.", TIMEOUT_CYCLES);
        $finish;
    end

    // Golden reference matrix C = A x B (32 x 24)
    int expected_C [A_ROWS][B_COLUMNS];
    int actual_C   [A_ROWS][B_COLUMNS];

    int total_errors = 0;
    int passed_elements = 0;

    // Task to load golden reference
    task automatic load_golden();
        int fd;
        int val;
        fd = $fopen("systolic_mem_files/c_golden.txt", "r");
        if (fd == 0) begin
            // FIX 2: a missing golden file used to silently become an all-zero reference
            $display("[ERROR] Could not open systolic_mem_files/c_golden.txt (run from the dir that contains systolic_mem_files/)");
            $fatal(1, "golden file missing");
        end else begin
            for (int r = 0; r < A_ROWS; r++) begin
                for (int c = 0; c < B_COLUMNS; c++) begin
                    if ($fscanf(fd, "%d", val) == 1) begin
                        expected_C[r][c] = val;
                    end else begin
                        expected_C[r][c] = 0;
                    end
                end
            end
            $fclose(fd);
            $display("  Loaded 32x24 golden reference matrix from systolic_mem_files/c_golden.txt");
        end
    endtask

    // Main test sequence
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, systolic_top_tb);

        start_i = 1'b0;
        rst_n_i = 1'b0;

        $display("==========================================================================");
        $display("         %0dx%0d SYSTOLIC ARRAY FULL TILING TESTBENCH (32x16 * 16x24)", N, M);
        $display("         Total tiles: %0d (%0d row tiles x %0d col tiles)",
                 TOTAL_TILES, TOTAL_ROW_TILES, TOTAL_COL_TILES);
        $display("         (Probing PE array outputs dut.c_w[%0d] directly during drain)", N);
        $display("==========================================================================");

        load_golden();

        // Reset sequence
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_n_i = 1'b1;
        $display("[%0t ns] Reset deasserted.", $time);

        // Pulse start_i
        @(posedge clk_i);
        start_i = 1'b1;
        $display("[%0t ns] Asserted start_i.", $time);
        @(posedge clk_i);
        start_i = 1'b0;
        $display("[%0t ns] Deasserted start_i. Beginning tile execution...\n", $time);

        // Monitor tiles as they execute and drain
        for (int r_tile = 0; r_tile < TOTAL_ROW_TILES; r_tile++) begin
            for (int c_tile = 0; c_tile < TOTAL_COL_TILES; c_tile++) begin
                automatic int tile_errors = 0;
                automatic int base_row = r_tile * N;
                automatic int base_col = c_tile * M;

                // FIX 3: poll 1 ns AFTER each clock edge so we see the settled (post-NBA) value.
                // Before, the poll saw the pre-edge value, detected drain one cycle late and
                // then the extra @(posedge) pushed every sample one more cycle late.
                while (dut.drain[0][0] !== 1'b1) begin
                    @(posedge clk_i);
                    #1;
                end

                // drain is visible now; the PEs latch the result into c_w[N] on the NEXT edge
                @(posedge clk_i);

                // Drain phase:
                // Cycle 0: row N-1 exits at dut.c_w[N]
                #1;
                for (int j = 0; j < M; j++) begin
                    automatic int r = base_row + (N - 1);
                    automatic int c = base_col + j;
                    actual_C[r][c] = dut.c_w[N][j];
                    if (actual_C[r][c] === expected_C[r][c]) begin
                        passed_elements++;
                    end else begin
                        tile_errors++;
                        total_errors++;
                    end
                end

                // Subsequent cycles: rows N-2 down to 0 shift out
                for (int row_offset = N - 2; row_offset >= 0; row_offset--) begin
                    @(posedge clk_i);
                    #1;
                    for (int j = 0; j < M; j++) begin
                        automatic int r = base_row + row_offset;
                        automatic int c = base_col + j;
                        actual_C[r][c] = dut.c_w[N][j];
                        if (actual_C[r][c] === expected_C[r][c]) begin
                            passed_elements++;
                        end else begin
                            tile_errors++;
                            total_errors++;
                        end
                    end
                end

                if (tile_errors == 0) begin
                    $display("[%0t ns] Tile [%0d,%0d] (rows %0d..%0d, cols %0d..%0d): PASS",
                             $time, r_tile, c_tile, base_row, base_row+N-1, base_col, base_col+M-1);
                end else begin
                    $display("[%0t ns] Tile [%0d,%0d] (rows %0d..%0d, cols %0d..%0d): FAIL (%0d errors)",
                             $time, r_tile, c_tile, base_row, base_row+N-1, base_col, base_col+M-1, tile_errors);
                    for (int r = base_row; r < base_row + N; r++) begin
                        $write("      Row %2d: ", r);
                        for (int c = base_col; c < base_col + M; c++) begin
                            $write("got %4d (exp %4d) ", actual_C[r][c], expected_C[r][c]);
                        end
                        $write("\n");
                    end
                end

                // drain is a 1-cycle pulse and we are already past it; resync to a clock edge + 1ns
                @(posedge clk_i);
                #1;
            end
        end

        // Final verification summary
        $display("\n==========================================================================");
        $display("                          TEST SUMMARY");
        $display("==========================================================================");
        $display("  Total elements checked: %0d", A_ROWS * B_COLUMNS);
        $display("  Passed elements       : %0d", passed_elements);
        $display("  Failed elements       : %0d", total_errors);
        $display("==========================================================================");

        if (total_errors == 0) begin
            $display("               *** ALL 48 TILES PASSED SUCCESSFULLY! ***");
        end else begin
            $display("               *** TEST FINISHED WITH %0d ERRORS ***", total_errors);
            $error("systolic_top_tb FAILED");
        end
        $display("==========================================================================");

        repeat (5) @(posedge clk_i);
        $finish;
    end

endmodule
