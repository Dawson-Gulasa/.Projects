
`timescale 1ns/1ps
// tb_mul_edge_cases.v
// Self-checking full-SCC multiplication edge-case test.
//
// Verifies signed 64-bit products, MULS zero/negative
// flags, both writeback destinations, and register preservation.

module tb_mul_edge_cases;

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer test_errors;
    integer check_count;
    integer low_count;
    integer high_count;

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),
        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    // 10 ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Compare a 32-bit architectural value
    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] description;
        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s expected=%08h actual=%08h", description, expected, actual);
                test_errors = test_errors + 1;
            end else begin
                $display("PASS: %0s = %08h", description, actual);
            end
        end
    endtask

    // Verify architectural NZCV, ordered N Z C V
    task check_flags;
        input [3:0] expected;
        input [8*48-1:0] description;
        reg [3:0] actual;
        begin
            actual = {DUT.scc.n_f, DUT.scc.z_f, DUT.scc.c_f, DUT.scc.v_f};

            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s expected=%04b actual=%04b", description, expected, actual);
                test_errors = test_errors + 1;
            end else begin
                $display("PASS: %0s = %04b", description, actual);
            end
        end
    endtask

    // Monitor actual microcode register-write requests.
    // Check the register file after the active write edge,
    // allowing nonblocking assignments to settle
    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.ucode_reg_write_en) begin

            if (DUT.scc.ucode_stall !== 1'b1 ||
                DUT.scc.arch_reg_write_en !== 1'b1) begin
                $display("FAIL: Invalid microcode write control");
                test_errors = test_errors + 1;
            end

            if (DUT.scc.ucode_reg_write_addr_v == 4'd12) begin
                high_count = high_count + 1;
                #1;

                case (high_count)
                    1: begin
                        check_word(DUT.scc.REGS.registers[12], 32'hFFFF_FFFF, "64-bit MUL upper result");
                    end

                    2: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MULS register zero upper");
                        check_flags(4'b0100,"MULS register zero flags");
                    end

                    3: begin
                        check_word(DUT.scc.REGS.registers[12], 32'hFFFF_FFFF, "MULS negative upper");
                        check_flags(4'b1010, "MULS negative flags"); // -2: upper word 0xFFFFFFFF sets C
                    end

                    4: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MULS immediate zero upper");
                        check_flags(4'b0100, "MULS immediate zero flags");
                    end

                    5: begin
                        check_word(DUT.scc.REGS.registers[12], 32'h0000_0000, "MULS immediate -1 upper");
                        check_flags(4'b0000, "MULS immediate -1 flags");
                    end

                    default: begin
                        $display("FAIL: Unexpected extra R12 write");
                        test_errors = test_errors + 1;
                    end
                endcase

            end else begin
                low_count = low_count + 1;
                #1;

                case (low_count)
                    1: check_word(DUT.scc.REGS.registers[3], 32'h0000_0000, "64-bit MUL low result");

                    2: check_word(DUT.scc.REGS.registers[4], 32'h0000_0000, "MULS register zero low");

                    3: check_word(DUT.scc.REGS.registers[6], 32'hFFFF_FFFE, "MULS negative low");

                    4: check_word(DUT.scc.REGS.registers[7], 32'h0000_0000, "MULS immediate zero low");

                    5: check_word(DUT.scc.REGS.registers[8], 32'h0000_0001, "MULS immediate -1 low");

                    default: begin
                        $display("FAIL: Unexpected extra low write");
                        test_errors = test_errors + 1;
                    end
                endcase
            end
        end
    end

    // Main simulation
    initial begin
        $dumpfile("tb_mul_edge_cases.vcd");
        $dumpvars(0, tb_mul_edge_cases);

        rst = 1'b1;
        clk_en = 1'b1;
        test_errors = 0;
        check_count = 0;
        low_count = 0;
        high_count = 0;

        $display("");
        $display("========================================");
        $display("SCC CP4 MUL EDGE-CASE VERIFICATION");
        $display("========================================");

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(posedge halt_f);
        #2;

        // Five instructions, each with two microcode writes.
        check_word(low_count, 32'd5, "Low-word write count");
        check_word(high_count, 32'd5, "Upper-word write count");

        // Check architectural registers after HALT.
        check_word(DUT.scc.REGS.registers[1], 32'd2, "R1 preserved");
        check_word(DUT.scc.REGS.registers[2], 32'h8000_0000, "R2 preserved");
        check_word(DUT.scc.REGS.registers[5], 32'hFFFF_FFFF, "R5 preserved");
        check_word(DUT.scc.REGS.registers[9], 32'h0000_1234, "Sentinel R9 preserved");

        check_word(DUT.scc.pc_v, 32'h0000_0028, "HALT PC");
        check_word({30'd0, err_f}, 32'd1, "HALT status");
        check_flags(4'b0000, "Final NZCV");

        $display("");
        $display("========================================");
        $display("MUL EDGE-CASE FINAL RESULTS");
        $display("========================================");
        $display("Low writes          = %0d", low_count);
        $display("High writes         = %0d", high_count);
        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0)
            $display("MUL EDGE-CASE TEST PASSED");
        else
            $display("MUL EDGE-CASE TEST FAILED");

        $display("========================================");
        $finish;
    end

    // Stop on an illegal architectural instruction
    always @(posedge clk) begin
        if (!rst && err_f === 2'b10) begin
            $display("FAIL: Illegal instruction at PC=%08h", DUT.scc.pc_v);
            $finish;
        end
    end

    // Prevent an infinite simulation on a stalled processor
    initial begin
        #100000;
        $display("FAIL: MUL edge-case timeout");
        $display("PC=%08h", DUT.scc.pc_v);
        $finish;
    end

endmodule
