
`timescale 1ns/1ps
// tb_mul_integration.v
// Full-processor SCC CP4 multiplication verification
//
// Executes assembly/mul_forms.asm using the real:
// - Instruction memory
// - Instruction decoder
// - Register file
// - Microcode ROM and controller
// - Register writeback and architectural flags
//
// Verifies all four MUL/MULS forms, both product words,
// PC stalls, preserved flags, and unrelated registers.

module tb_mul_integration;

    //===================
    // TESTBENCH SIGNALS
    //===================

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer test_errors;
    integer check_count;
    integer low_write_count;
    integer high_write_count;
    integer cycle_count;

    //===================
    // DEVICE UNDER TEST
    //====================

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),

        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    //===================
    // CLOCK GENERATION
    //====================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //===============
    // CHECK TASKS
    //=================

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] name;

        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s expected=%08h actual=%08h", name, expected, actual);
                test_errors = test_errors + 1;
            end else begin
                $display("PASS: %0s = %08h", name, actual);
            end
        end
    endtask

    task check_flags;
        input [3:0] expected;
        input [8*48-1:0] name;

        reg [3:0] actual;

        begin
            actual = {
                DUT.scc.n_f,
                DUT.scc.z_f,
                DUT.scc.c_f,
                DUT.scc.v_f
            };

            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s expected=%04b actual=%04b", name, expected, actual);
                test_errors = test_errors + 1;
            end else begin
                $display("PASS: %0s = %04b", name, actual);
            end
        end
    endtask

    //======================
    // CLOCK CYCLE MONITOR
    //========================

    always @(posedge clk) begin
        if (rst) begin
            cycle_count = 0;
        end else if (clk_en)
            cycle_count = cycle_count + 1;
    end

    //===========================
    // MICROCODE WRITE MONITOR
    //==========================
    // Sample writeback requests at the rising edge.
    //
    // After #1, nonblocking register-file updates have completed, allowing the 
    // architectural register contents to be checked directly.
    //
    // Four MUL instructions must produce:
    // - Four low-word writes to Rd
    // - Four high-word writes to R12

    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.ucode_reg_write_en) begin

            // No microcode write should occur unless normal instruction fetch is stalled.
            if (DUT.scc.ucode_stall !== 1'b1) begin
                $display("FAIL: Microcode write without IF stall");
                test_errors = test_errors + 1;
            end

            // Confirm that microcode is selected by the architectural writeback interface.
            if (DUT.scc.arch_reg_write_en !== 1'b1) begin
                $display("FAIL: Microcode writeback not selected");
                test_errors = test_errors + 1;
            end

            if (DUT.scc.ucode_reg_write_addr_v == 4'd12) begin
                // Upper 32-bit writeback to R12
                high_write_count = high_write_count + 1;
                #1;

                case (high_write_count)
                    1: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MUL reg/reg high word");
                        check_flags(4'b1000, "MUL preserves initial flags");
                    end

                    2: begin
                        check_word(DUT.scc.REGS.registers[12], 32'hFFFF_FFFF, "MUL immediate high word");
                        check_flags(4'b1000, "MUL immediate preserves flags");
                    end

                    3: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MULS reg/reg high word");
                        check_flags(4'b0000, "MULS positive-product flags");
                    end

                    4: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MULS immediate high word");
                        check_flags(4'b0100, "MULS zero-product flags");
                    end

                    default: begin
                        $display("FAIL: Unexpected R12 write");
                        test_errors = test_errors + 1;
                    end
                endcase

            end else begin
                // Lower 32-bit writeback to destination Rd
                low_write_count = low_write_count + 1;
                #1;

                case (low_write_count)
                    1: check_word(
                           DUT.scc.REGS.registers[3],
                           32'h0000_002A,
                           "MUL reg/reg low word"
                       );

                    2: check_word(
                           DUT.scc.REGS.registers[4],
                           32'hFFFF_FFEE,
                           "MUL immediate low word"
                       );

                    3: check_word(
                           DUT.scc.REGS.registers[5],
                           32'h0000_002A,
                           "MULS reg/reg low word"
                       );

                    4: check_word(
                           DUT.scc.REGS.registers[6],
                           32'h0000_0000,
                           "MULS immediate low word"
                       );

                    default: begin
                        $display("FAIL: Unexpected low-word write");
                        test_errors = test_errors + 1;
                    end
                endcase
            end
        end
    end

    //====================
    // MAIN TEST SEQUENCE
    //=====================

    initial begin
        $dumpfile("tb_mul_integration.vcd");
        $dumpvars(0, tb_mul_integration);

        clk_en = 1'b1;
        rst = 1'b1;

        test_errors = 0;
        check_count = 0;
        low_write_count = 0;
        high_write_count = 0;
        cycle_count = 0;

        $display("");
        $display("========================================");
        $display("SCC CP4 MULTIPLICATION INTEGRATION");
        $display("========================================");

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        // Wait until the architectural HALT instruction.
        @(posedge halt_f);
        #2;

        //==================
        // EXECUTION COUNTS
        //================

        check_word(low_write_count, 32'd4, "Low-word write count");

        check_word(high_write_count, 32'd4, "High-word write count");

        //=======================
        // FINAL REGISTER VALUES
        //========================

        check_word(DUT.scc.REGS.registers[1], 32'd6, "R1 preserved");

        check_word(DUT.scc.REGS.registers[2], 32'd7, "R2 preserved");

        check_word(DUT.scc.REGS.registers[3], 32'h0000_002A, "Final R3");

        check_word(DUT.scc.REGS.registers[4], 32'hFFFF_FFEE, "Final R4");

        check_word(DUT.scc.REGS.registers[5], 32'h0000_002A, "Final R5");

        check_word(DUT.scc.REGS.registers[6], 32'h0000_0000, "Final R6");

        check_word(DUT.scc.REGS.registers[9], 32'h0000_1234, "Sentinel R9 preserved");

        check_word(DUT.scc.REGS.registers[10], 32'hFFFF_FFFF, "SUBS result R10");

        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "Final upper product R12");

        check_flags(4'b0100, "Final NZCV");

        check_word(DUT.scc.pc_v, 32'h0000_0020, "HALT instruction address");

        check_word({30'd0, err_f}, 32'd1, "Processor HALT status");

        //=================
        // FINAL RESULTS
        //====================

        $display("");
        $display("========================================");
        $display("MULTIPLICATION INTEGRATION RESULTS");
        $display("========================================");

        $display("HALT time           = %0t", $time);
        $display("Clock cycles        = %0d", cycle_count);
        $display("Low-word writes     = %0d", low_write_count);
        $display("High-word writes    = %0d", high_write_count);
        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0)
            $display("MULTIPLICATION INTEGRATION TEST PASSED");
        else
            $display("MULTIPLICATION INTEGRATION TEST FAILED");

        $display("========================================");
        $finish;
    end

    //==========================
    // ILLEGAL INSTRUCTION MONITOR
    //===============================

    always @(posedge clk) begin
        if (!rst && err_f === 2'b10) begin
            $display("FAIL: Illegal instruction encountered");
            $display("PC=%08h instruction=%08h", DUT.scc.pc_v, inst_mem_v);
            $finish;
        end
    end

    //===========
    // TIMEOUT
    //===============

    initial begin
        #100000;

        $display("FAIL: Multiplication test timeout");
        $display("PC=%08h instruction=%08h",
                 DUT.scc.pc_v, inst_mem_v);
        $display("Low writes=%0d high writes=%0d",
                 low_write_count, high_write_count);

        $finish;
    end

endmodule
