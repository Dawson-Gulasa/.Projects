`timescale 1ns/1ps
// tb_cp5_stack_boundary.v
// Complete SCC stack-capacity, overwrite, and S-flag verification.
// Program: assembly/cp5_stack_boundary.asm
// Uses the course instruction/data memory model and assembled instructions.
// Checks individual memory write transactions as well as final state

module tb_cp5_stack_boundary;

    localparam integer EXPECTED_WRITES = 17;
    localparam integer EXPECTED_CHECKS = 50;


    //========================================
    // ARCHITECTURAL STACK ADDRESSES
    //========================================
    // The sixteen 32-bit stack entries occupy byte addresses 0xFFC0 through 0xFFFF.
    //
    // R13 advances to 0x10000 when full, but no memory access may use that
    // one-past-the-end pointer directly.

    localparam [31:0] STACK_BASE_ADDR = 32'h0000_FFC0;
    localparam [31:0] STACK_LAST_ADDR = 32'h0000_FFFC;
    localparam [31:0] STACK_FULL_SP = 32'h0001_0000;
    localparam [31:0] STACK_WORD_BYTES = 32'd4;


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
    reg saw_full;

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),
        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    // Ten-nanosecond clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Use case inequality to detect incorrect or unknown values
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


    //====================================
    // STACK MEMORY WRITE VERIFICATION
    //========================================
    // Every rising edge of the architectural memory-write strobe represents one write.
    // PUSH operations 1 through 16 must write consecutive words from 0xFFC0 to 0xFFFC.
    //
    // PUSH operation 17 occurs with the stack already full. It must overwrite 0xFFFC
    // instead of accessing R13 = 0x10000.
    //
    // Every transaction checks both its byte address and its corresponding write data.

    always @(posedge DUT.data_mem_wr_en) begin

        // Ignore memory events while reset is
        // asserted. Only count valid execution
        if (!rst) begin

            write_count = write_count + 1;

            if (write_count <= 16) begin

                // The first sixteen writes fill
                // the architectural stack region.
                //
                // Each successive PUSH advances
                // the memory address by four bytes.
                check_word(
                    DUT.data_mem_addr_v,
                    STACK_BASE_ADDR + (write_count - 1) * STACK_WORD_BYTES,
                    "PUSH stack address"
                );

                // The first sixteen PUSH operations
                // store the same source value.
                check_word(
                    DUT.data_mem_out_v,
                    32'h0000_1111,
                    "PUSH source value"
                );

            end
            else if (write_count == EXPECTED_WRITES) begin

                // The seventeenth PUSH must
                // overwrite the last valid word.
                //
                // This prevents memory access
                // outside the 64 KB address space.
                check_word(
                    DUT.data_mem_addr_v,
                    STACK_LAST_ADDR,
                    "Full PUSH overwrites top address"
                );

                // Verify that the overwrite uses
                // the new source-register value.
                check_word(
                    DUT.data_mem_out_v,
                    32'h0000_2222,
                    "Full PUSH overwrites top data"
                );

            end
            else begin

                // More than seventeen writes is
                // an unexpected memory transaction.
                //
                // Count the violation as a failure
                // rather than silently ignoring it.
                errors = errors + 1;
                $display( "FAIL: Unexpected memory write #%0d", write_count);

            end
        end
    end


    //======================================
    // COMMITTED STACK STATE VERIFICATION
    //========================================
    // Sample after the rising clock edge and the nonblocking register updates.
    //
    // The full-stack condition must produce:
    // - Occupancy of exactly sixteen words.
    // - Architectural S flag asserted.
    // - R13 pointing to 0x00010000.
    //
    // The pointer must never remain at 0xFFFC when occupancy reaches sixteen.

    always @(posedge clk) begin
        #1;

        if (!rst && DUT.scc.stack_depth_v === 5'd16) begin

            // Record that the test reached
            // the fully occupied stack state.
            saw_full = 1'b1;

            // Verify the architectural full-stack
            // pointer and S-flag behavior.
            if ((DUT.scc.s_f !== 1'b1) || (DUT.scc.stack_sp_v !== STACK_FULL_SP)) begin
                errors = errors + 1;
                $display( "FAIL: Full stack requires S=1 and R13=0x10000");
                $display(
                    "Observed S=%b R13=%08h",
                    DUT.scc.s_f,
                    DUT.scc.stack_sp_v
                );

            end
        end

        // The stack controller must never allow
        // occupancy to exceed sixteen entries.
        if (!rst && DUT.scc.stack_depth_v > 5'd16) begin
            errors = errors + 1;
            $display("FAIL: Stack depth exceeded 16");
        end
    end


    initial begin
        $dumpfile("tb_cp5_stack_boundary.vcd");
        $dumpvars(0, tb_cp5_stack_boundary);

        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        write_count = 0;
        saw_full = 1'b0;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        wait (halt_f === 1'b1);
        #2;

        // These MOVF instructions sample S before/after full-stack POP.
        // No arithmetic flag-setting instruction occurs in this program
        check_word({30'b0, err_f}, 32'd1, "HALT status");
        check_word(DUT.scc.REGS.registers[6], 32'h0000_0010, "MOVF after sixteenth PUSH observes S=1");
        check_word(DUT.scc.REGS.registers[9], 32'h0000_0010, "MOVF after full-stack overwrite observes S=1");
        check_word(DUT.scc.REGS.registers[7], 32'h0000_0000, "MOVF after first POP observes S=0");
        check_word(DUT.scc.REGS.registers[10], 32'h0000_0000, "MOVF after emptying stack observes S=0");

        // Verify full-top overwrite, LIFO behavior, and empty POP.
        check_word(DUT.scc.REGS.registers[3], 32'h0000_2222, "POP from full returns overwritten top");
        check_word(DUT.scc.REGS.registers[4], 32'h0000_1111, "Next POP returns original stack data");
        check_word(DUT.scc.REGS.registers[8], 32'h0000_1111, "Final nonempty POP returns bottom word");
        check_word(DUT.scc.REGS.registers[5], 32'h0000_0000, "Empty POP returns zero");

        // Stack state returns to the reset condition after sixteen POPs.
        // After all sixteen valid entries are removed,
        // R13 must return to its architectural reset value.
        check_word( DUT.scc.stack_sp_v, STACK_BASE_ADDR, "R13 returns to stack base");
        check_word({27'b0, DUT.scc.stack_depth_v}, 32'd0, "Final stack depth is zero");
        check_word({31'b0, DUT.scc.s_f}, 32'd0, "Final S flag is clear");
        check_word(write_count, EXPECTED_WRITES, "Exactly seventeen PUSH writes");
        check_word({31'b0, saw_full}, 32'd1, "Stack reached full occupancy");

        // POP must not erase stored data in the backing memory.

        //===============================
        // FINAL STACK MEMORY CONTENTS
        //=============================
        // POP removes entries logically but must not erase their backing memory contents.
        // The original bottom word remains 0x1111 at 0xFFC0 after the entire stack is popped.
        // The seventeenth PUSH overwrites 0xFFFC with 0x2222, which must remain stored.
        //
        // The memory model stores individual bytes,
        // so concatenate four consecutive bytes
        // to reconstruct each 32-bit word.

        check_word(
            {DUT.memory.memory[16'hFFC0],
             DUT.memory.memory[16'hFFC1],
             DUT.memory.memory[16'hFFC2],
             DUT.memory.memory[16'hFFC3]},
            32'h0000_1111,
            "Bottom stack word retained"
        );

        check_word(
            {DUT.memory.memory[16'hFFFC],
             DUT.memory.memory[16'hFFFD],
             DUT.memory.memory[16'hFFFE],
             DUT.memory.memory[16'hFFFF]},
            32'h0000_2222,
            "Overwritten top word retained"
        );


        $display("\nCP5 STACK BOUNDARY: checks=%0d errors=%0d", checks, errors);

        //========================================
        // FINAL SELF-CHECKING VERDICT
        //========================================
        // PASS requires the expected number of
        // comparisons and zero detected errors.
        //
        // A failed verification must terminate
        // with a nonzero simulator exit status.

        if ((checks == EXPECTED_CHECKS) && (errors == 0)) begin
            $display("CP5 STACK BOUNDARY TEST PASSED");
        end
        else begin
            $display("CP5 STACK BOUNDARY TEST FAILED");
            $fatal(1, "Stack boundary verification failed");
        end
        $finish;

    end

    // A stalled or nonterminating processor must fail
    // verification rather than finish successfully.
    initial begin
        #5000;
        $fatal(1, "CP5 stack boundary test timeout");
    end
endmodule
