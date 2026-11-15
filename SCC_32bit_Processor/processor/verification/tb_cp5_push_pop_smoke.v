`timescale 1ns/1ps
// tb_cp5_push_pop_smoke.v
// End-to-end PUSH/POP smoke test using the real SCC and memory model.
// Program source: assembly/cp5_push_pop_smoke.asm
// Checks architectural results after HALT, not internal control only.

module tb_cp5_push_pop_smoke;
    reg clk;
    reg rst;
    reg clk_en;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer checks;
    integer errors;
    integer write_count;


    //========================================
    // ARCHITECTURAL STACK CONSTANTS
    //========================================
    // R13 resets to 0x0000FFC0.
    //
    // Each stack word occupies four bytes.
    // The smoke test PUSHes exactly two words,
    // so the expected addresses are 0xFFC0
    // and 0xFFC4.
    //
    // Use named constants to make the required
    // architectural addresses easy to identify.

    localparam [31:0] STACK_BASE_ADDR = 32'h0000_FFC0;
    localparam [31:0] STACK_WORD_BYTES = 32'd4;
    localparam integer EXPECTED_CHECKS = 15;


    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),
        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Compare values using case inequality to detect unknown bits
    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*64-1:0] description;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s expected=%08h actual=%08h", description, expected, actual);
            end else begin
                $display("PASS: %0s = %08h", description, actual);
            end
        end
    endtask

    // Count every write-enable rising edge and validate the write address/data.
    // This detects extra transactions even if memory contents ultimately match
    always @(posedge DUT.data_mem_wr_en) begin
        if (!rst) begin
            write_count = write_count + 1;

            //========================================
            // VERIFY INDIVIDUAL PUSH TRANSACTIONS
            //=====================================
            // Each valid PUSH must produce exactly
            // one architectural memory write.
            //
            // Check the address and source data
            // independently for each transaction.
            //
            // Any additional write is unexpected
            // and must be reported as an error.

            case (write_count)

                1: begin
                    // First PUSH:
                    // Store R1 at the initial R13
                    // address, 0x0000FFC0.
                    check_word(DUT.data_mem_addr_v, STACK_BASE_ADDR, "First PUSH address" );

                    check_word(DUT.data_mem_out_v, 32'h0000_1234, "First PUSH data");
                end

                2: begin
                    // Second PUSH:
                    // R13 has advanced by one word.
                    // Store R2 at address 0x0000FFC4.
                    check_word(DUT.data_mem_addr_v, STACK_BASE_ADDR + STACK_WORD_BYTES, "Second PUSH address");
                    check_word(DUT.data_mem_out_v, 32'h0000_5678,"Second PUSH data");
                end

                default: begin
                    // Only two PUSH instructions
                    // should generate memory writes.
                    // Any additional write is a
                    // functional verification failure.
                    errors = errors + 1;
                    $display("FAIL: Unexpected memory write #%0d", write_count);
                end
            endcase
        end
    end

    initial begin
        $dumpfile("tb_cp5_push_pop_smoke.vcd");
        $dumpvars(0, tb_cp5_push_pop_smoke);

        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        write_count = 0;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        // HALT is decoded from the fetched instruction.
        // Sample after a short delay to allow combinational logic to settle
        wait (halt_f === 1'b1);
        #2;

        check_word({30'b0, err_f}, 32'd1, "HALT status");
        check_word(DUT.scc.REGS.registers[3], 32'h0000_5678, "First POP restores R2 value to R3");
        check_word(DUT.scc.REGS.registers[4], 32'h0000_1234, "Second POP restores R1 value to R4");
        check_word(DUT.scc.REGS.registers[5], 32'h0000_0000, "Empty POP writes zero to R5");
        check_word(DUT.scc.REGS.registers[6], 32'h0000_0000, "MOVF reads cleared SNZCV");
        // After two successful PUSH and POP operations,
        // R13 must return to the fixed ISA stack base.
        check_word( DUT.scc.stack_sp_v, STACK_BASE_ADDR, "R13 returns to stack base");
        check_word({27'b0, DUT.scc.stack_depth_v}, 32'd0, "Stack depth returns to zero");
        check_word({31'b0, DUT.scc.s_f}, 32'd0, "Stack-full S flag clears");
        check_word(write_count, 32'd2, "Exactly two PUSH writes");


        //========================================
        // VERIFY RETAINED STACK MEMORY CONTENTS
        //========================================
        // POP removes entries from the logical stack but does not erase memory contents.
        // The first word must retain 0x00001234 at addresses 0xFFC0 through 0xFFC3.
        // The second word must retain 0x00005678 at addresses 0xFFC4 through 0xFFC7.
        //
        // The memory model stores individual bytes in big-endian order. Reconstruct each
        // complete word from four adjacent bytes.

        check_word(
            {
                DUT.memory.memory[16'hFFC0],
                DUT.memory.memory[16'hFFC1],
                DUT.memory.memory[16'hFFC2],
                DUT.memory.memory[16'hFFC3]
            },
            32'h0000_1234,
            "First stack word retained"
        );

        check_word(
            {
                DUT.memory.memory[16'hFFC4],
                DUT.memory.memory[16'hFFC5],
                DUT.memory.memory[16'hFFC6],
                DUT.memory.memory[16'hFFC7]
            },
            32'h0000_5678,
            "Second stack word retained"
        );



        //========================================
        // FINAL SELF-CHECKING VERDICT
        //========================================
        // A passing test must:
        // - Execute all fifteen expected checks.
        // - Detect zero functional errors.
        //
        // Use $fatal for failures so the simulator
        // returns a nonzero exit status to the
        // automated regression script.

        $display( "\nCP5 PUSH/POP SMOKE: checks=%0d errors=%0d", checks, errors );
        if ((checks == EXPECTED_CHECKS) && (errors == 0)) begin
            // All expected results match.
            $display("CP5 PUSH/POP SMOKE TEST PASSED");
        end
        else begin
            // At least one assertion failed or
            // the expected check count is wrong.
            $display("CP5 PUSH/POP SMOKE TEST FAILED");
            $fatal(1, "PUSH/POP smoke verification failed");
        end

        $finish;

    end

    //========================
    // VERIFICATION WATCHDOG
    //======================
    // If the processor fails to reach HALT within the expected simulation window,
    // terminate with a nonzero exit status.
    //
    // This prevents a stalled SCC from being incorrectly classified as passing.

    initial begin
        #2000;
        $fatal(1, "CP5 PUSH/POP smoke-test timeout");
    end
endmodule
