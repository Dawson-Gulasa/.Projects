`timescale 1ns/1ps
// tb_cp5_div_zero.v
// Full-processor divide-by-zero exception test.
// Assemble assembly/cp5_div_zero.asm into output.mem first.
// Hierarchical observations are intentional for local RTL debugging;
// they must not be used in the cross-group portable testbenches.

module tb_cp5_div_zero;
    reg clk;
    reg rst;
    reg clk_en;
    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;
    integer checks;
    integer errors;
    integer div_writes;

    scc_f26_top DUT (
        .clk(clk), .clk_en(clk_en), .rst(rst),
        .halt_f(halt_f), .err_f(err_f),
        .inst_mem_v(inst_mem_v), .data_mem_in_v(data_mem_in_v)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [8*64-1:0] description;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s expected=%08h actual=%08h",
                         description, expected, actual);
            end else begin
                $display("PASS: %0s = %08h", description, actual);
            end
        end
    endtask

    // A divide-by-zero exception must never issue quotient or remainder
    // writeback at any rising architectural clock edge.
    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.div_reg_write_en)
            div_writes = div_writes + 1;
    end

    initial begin
        $dumpfile("tb_cp5_div_zero.vcd");
        $dumpvars(0, tb_cp5_div_zero);
        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        div_writes = 0;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        // Wait for the architectural exception, not a normal HALT.
        wait (err_f === 2'b10);
        #2;
        check32({30'd0, err_f}, 32'd2, "Divide-by-zero status");
        check32({31'd0, halt_f}, 32'd1, "Exception requests HALT");
        check32({31'd0, DUT.scc.div_stall}, 32'd1, "Exception stalls fetch");
        check32({31'd0, DUT.scc.div_error}, 32'd1, "Sticky divide error");
        check32(DUT.scc.REGS.registers[3], 32'h00001234, "Rd sentinel preserved");
        check32(DUT.scc.REGS.registers[12], 32'h00005678, "R12 sentinel preserved");
        check32(DUT.scc.REGS.registers[10], 32'h00000008, "NZCV before fault");
        check32({28'd0, DUT.scc.n_f, DUT.scc.z_f,
                       DUT.scc.c_f, DUT.scc.v_f}, 32'h8,
                "NZCV preserved by fault");
        check32(DUT.scc.REGS.registers[4], 32'h0, "Following MOV not executed");
        check32(div_writes, 32'd0, "No division writeback transactions");

        // Confirm error is terminal: the next few clocks must not
        // execute the following instruction or modify either result.
        repeat (4) @(posedge clk);
        #2;
        check32({30'd0, err_f}, 32'd2, "Error remains asserted");
        check32(DUT.scc.REGS.registers[4], 32'h0, "Following MOV still suppressed");
        check32(div_writes, 32'd0, "No late division writeback");

        $display("\nCP5 DIV ZERO: checks=%0d errors=%0d", checks, errors);
        if (checks == 13 && errors == 0)
            $display("CP5 DIV ZERO TEST PASSED");
        else
            $display("CP5 DIV ZERO TEST FAILED");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: CP5 DIV ZERO timeout");
        $finish;
    end
endmodule
