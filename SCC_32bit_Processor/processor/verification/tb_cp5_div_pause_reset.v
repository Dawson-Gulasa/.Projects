`timescale 1ns/1ps
// tb_cp5_div_pause_reset.v
// CP5 full-processor division clock-enable and synchronous-reset regression.
//
// Program: assembly/cp5_div_integration.asm, assembled into output.mem.
// The test intentionally pauses execution while the first DIV quotient is
// ready to commit, then resets the processor before that write takes place.
// After reset, the program must restart and complete normally.
//
// This group-local verification bench probes internal SCC signals to check
// architectural commits. It does NOT add or modify SCC top-level ports.
module tb_cp5_div_pause_reset;
    reg clk;
    reg rst;
    reg clk_en;
    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer checks;
    integer errors;
    integer div_writes_after_reset;
    reg count_post_reset;
    reg [31:0] held_pc;
    reg [31:0] held_rd;

    scc_f26_top DUT (
        .clk(clk), .clk_en(clk_en), .rst(rst),
        .halt_f(halt_f), .err_f(err_f),
        .inst_mem_v(inst_mem_v), .data_mem_in_v(data_mem_in_v)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*72-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s expected=%08h actual=%08h", label, expected, actual);
            end else begin
                $display("PASS: %0s = %08h", label, actual);
            end
        end
    endtask

    // Count committed DIV writes after reset only. The write request is
    // sampled at the same rising edge that REGS consumes it.
    always @(posedge clk) begin
        if (!rst && clk_en && count_post_reset && DUT.scc.div_reg_write_en)
            div_writes_after_reset = div_writes_after_reset + 1;
    end

    initial begin
        $dumpfile("tb_cp5_div_pause_reset.vcd");
        $dumpvars(0, tb_cp5_div_pause_reset);
        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        div_writes_after_reset = 0;
        count_post_reset = 1'b0;
        held_pc = 32'd0;
        held_rd = 32'd0;

        // Initial synchronous reset.
        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        // Wait until the controller offers its first quotient write.
        // Use a negative edge so clk_en can be disabled safely before
        // the architectural register-file rising edge.
        @(negedge clk);
        while (DUT.scc.div_reg_write_en !== 1'b1)
            @(negedge clk);

        check_word({31'd0, DUT.scc.div_stall}, 32'd1, "First quotient pending while fetch stalled");
        check_word({28'd0, DUT.scc.div_reg_write_addr_v}, 32'd3, "First quotient destination is R3");
        check_word(DUT.scc.REGS.registers[3], 32'd0, "R3 not written before quotient edge");

        // Halt architectural progress in WRITE_QUOT; the controller should
        // neither change state nor generate a register write enable.
        held_pc = DUT.scc.inst_mem_addr_v;
        held_rd = DUT.scc.REGS.registers[3];
        clk_en = 1'b0;
        #1;
        check_word({31'd0, DUT.scc.div_reg_write_en}, 32'd0, "Disabled clock suppresses DIV write request");

        repeat (3) begin
            @(posedge clk);
            #1;
            check_word(DUT.scc.inst_mem_addr_v, held_pc, "PC holds while clk_en is low");
            check_word(DUT.scc.REGS.registers[3], held_rd, "R3 unchanged while clk_en is low");
            check_word({31'd0, DUT.scc.div_reg_write_en}, 32'd0, "No DIV write while clock disabled");
            check_word({31'd0, DUT.scc.div_stall}, 32'd1, "DIV remains stalled while clock disabled");
        end

        // Synchronous reset must override clk_en=0 for the controller,
        // architectural registers, and IF. Assert away from a rising edge
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        check_word(DUT.scc.inst_mem_addr_v, 32'd0, "Reset overrides disabled clock for PC");
        check_word(DUT.scc.REGS.registers[3], 32'd0, "Reset restores R3");
        check_word({31'd0, DUT.scc.div_reg_write_en}, 32'd0, "Reset suppresses incomplete quotient write");
        check_word({31'd0, DUT.scc.div_error}, 32'd0, "Reset clears division error");

        // Resume from address zero. Count all division commits on replay.
        @(negedge clk);
        rst = 1'b0;
        clk_en = 1'b1;
        count_post_reset = 1'b1;

        wait (halt_f === 1'b1);
        #2;
        check_word({30'd0, err_f}, 32'd1, "Normal HALT after reset");
        check_word(DUT.scc.REGS.registers[3], 32'hFFFF_FFFD, "First quotient recomputed after reset");
        check_word(DUT.scc.REGS.registers[4], 32'd2, "Immediate DIV recomputed after reset");
        check_word(DUT.scc.REGS.registers[5], 32'hFFFF_FFFD, "DIVS immediate recomputed after reset");
        check_word(DUT.scc.REGS.registers[7], 32'd1, "DIVS register recomputed after reset");
        check_word(DUT.scc.REGS.registers[8], 32'hFFFF_FFFE, "Signed remainder preserved after reset replay");
        check_word(DUT.scc.REGS.registers[0], 32'd2, "Instruction following DIVS executes after reset");
        check_word(div_writes_after_reset, 32'd8, "Exactly eight DIV register writes after reset");

        $display("\nCP5 DIV PAUSE/RESET: checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("CP5 DIV PAUSE/RESET TEST PASSED");
        else
            $display("CP5 DIV PAUSE/RESET TEST FAILED");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: CP5 DIV PAUSE/RESET timeout");
        $finish;
    end
endmodule
