/*
 * This testbench is used to verify the results of sensor_log_analyzer.asm. It first allows the SCC dut to run with the assembly code
 * compiled, then compares the results in scc_out.txt with those in a golden model to verify the results. 
 */
module sensor_log_analyzer_tb;

    // Inputs
    reg clk = 0;
    reg clk_en = 1;
    reg rst = 1;

    // Outputs
    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    // DUT
    scc_f26_top DUT (
        .clk(clk),
        .clk_en(clk_en),
        .rst(rst),
        .halt_f(halt_f),
        .err_f(err_f),
        .inst_mem_v(inst_mem_v),
        .data_mem_in_v(data_mem_in_v)
    );

    // 10 ns period clock
    always #5 clk = ~clk;


    // Verification regs and ints
    reg [31:0] expected [0:24];
    reg [31:0] actual   [0:24];
    reg    found    [0:24];

    integer k;
    integer fd;
    integer matched;
    integer errors;
    integer cycles;

    reg [31:0] addr;
    reg [31:0] value;
    reg [1023:0] line;

    // Automatically determine the memory address for each result.
    function [31:0] result_addr;
        input integer index;
        begin
            if (index < 11)
                result_addr = 32'h1100 + (index * 4);
            else if (index < 19)
                result_addr = 32'h1140 + ((index - 11) * 4);
            else
                result_addr = 32'h1180 + ((index - 19) * 4);
        end
    endfunction

    // Count cycles
    always @(posedge clk) begin
        if (!rst && !halt_f)
            cycles = cycles + 1;
    end

    // Run tests
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, sensor_log_analyzer_tb);

        cycles = 0;
        errors = 0;

        // Main results: 0x1100 through 0x1128.
        expected[0]  = 32'h00000064; // Mean
        expected[1]  = 32'h00000005; // Remainder
        expected[2]  = 32'h00004546; // Variance
        expected[3]  = 32'h00000091; // Alarm mask
        expected[4]  = 32'h0000006E; // OK mask
        expected[5]  = 32'h0000000C; // Hours
        expected[6]  = 32'h00000022; // Minutes
        expected[7]  = 32'h00000038; // Seconds
        expected[8]  = 32'h0000161E; // Average interval
        expected[9]  = 32'h00000001; // Status
        expected[10] = 32'h00000005; // Digit count

        // Fahrenheit results: 0x1140 through 0x115C.
        expected[11] = 32'h000002C3;
        expected[12] = 32'h00000101;
        expected[13] = 32'h00000218;
        expected[14] = 32'h0000012E;
        expected[15] = 32'h0000035C;
        expected[16] = 32'h00000191;
        expected[17] = 32'h000000B0;
        expected[18] = 32'h00000302;

        // ASCII "17734" and null: 0x1180 through 0x1194.
        expected[19] = 32'h00000031;
        expected[20] = 32'h00000037;
        expected[21] = 32'h00000037;
        expected[22] = 32'h00000033;
        expected[23] = 32'h00000034;
        expected[24] = 32'h00000000;

        // Initialize reset values
        for (k = 0; k < 25; k = k + 1) begin
            found[k] = 1'b0;
            actual[k] = 32'b0;
        end

        // Reset.
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        // Wait for HALT or timeout.
        fork : run
            begin
                wait (halt_f === 1'b1);
                $display("Apollo has landed");
                disable run;
            end
            begin
                repeat (20000) @(posedge clk);
                $display("[FAIL] Timeout: program did not reach HALT");
                $finish;
            end
        join

        #1;

        // Fail
        if (err_f !== 2'b01) begin
                $display(
                        "[FAIL] CPU reported err_f = %b instead of normal HALT",
                        err_f
                );
                $finish;
        end

        $display("[PASS] Reached HALT after %0d cycles", cycles);

        // Read final memory values.
        fd = $fopen("scc_out.txt", "r");

        if (fd == 0) begin
            $display("[FAIL] Unable to open scc_out.txt");
            $finish;
        end

        matched = $fgets(line, fd); // Skip header.

        while ($fgets(line, fd)) begin
            matched = $sscanf(line, "0x%h,0x%h", addr, value);

            if (matched == 2) begin
                for (k = 0; k < 25; k = k + 1) begin
                    if (addr == result_addr(k)) begin
                        actual[k] = value;
                        found[k] = 1'b1;
                    end
                end
            end
        end

        $fclose(fd);

        // Compare results.
        for (k = 0; k < 25; k = k + 1) begin
            if (!found[k]) begin
                $display(
                    "[FAIL] Address 0x%h was not found",
                    result_addr(k)
                );
                errors = errors + 1;
            end
            else if (actual[k] !== expected[k]) begin
                $display(
                    "[FAIL] Address 0x%h: expected 0x%h, got 0x%h",
                    result_addr(k), expected[k], actual[k]
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "[PASS] Address 0x%h = 0x%h",
                    result_addr(k), actual[k]
                );
            end
        end

        // Final check
        if (errors == 0)
            $display("[PASS] SENSOR LOG ANALYZER: all 25 results matched");
        else
            $display("[FAIL] SENSOR LOG ANALYZER: %0d result(s) failed", errors);

        $finish;
    end

endmodule