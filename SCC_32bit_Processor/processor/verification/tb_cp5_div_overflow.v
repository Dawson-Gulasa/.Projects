`timescale 1ns/1ps
// tb_cp5_div_overflow.v
// Full-processor signed-overflow DIVS test.
// Assemble assembly/cp5_div_overflow.asm into output.mem first.
// This bench is for group-local debugging of architectural state.

module tb_cp5_div_overflow;
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
                $display("FAIL: %0s expected=%08h actual=%08h", description, expected, actual);
            end else begin
                $display("PASS: %0s = %08h", description, actual);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.div_reg_write_en)
            div_writes = div_writes + 1;
    end

    initial begin
        $dumpfile("tb_cp5_div_overflow.vcd");
        $dumpvars(0, tb_cp5_div_overflow);
        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        div_writes = 0;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;
        wait (halt_f === 1'b1);
        #2;

        check32({30'd0, err_f}, 32'd1, "Normal HALT after overflow");
        check32(DUT.scc.REGS.registers[1], 32'h80000000, "Minimum signed dividend");
        check32(DUT.scc.REGS.registers[2], 32'hFFFFFFFF, "Negative-one divisor");
        check32(DUT.scc.REGS.registers[3], 32'h80000000, "Overflow quotient");
        check32(DUT.scc.REGS.registers[12], 32'h00000000, "Overflow remainder");
        check32(DUT.scc.REGS.registers[4], 32'h00000009, "MOVF SNZCV after DIVS");
        check32(DUT.scc.REGS.registers[5], 32'h80000001, "Instruction after DIVS");
        // The ADD following DIVS does not request flag updates.
        check32({28'd0, DUT.scc.n_f, DUT.scc.z_f, DUT.scc.c_f, DUT.scc.v_f}, 32'h9, "Final NZCV overflow flags");
        check32({31'd0, DUT.scc.s_f}, 32'd0, "Stack S unaffected");
        check32(div_writes, 32'd2, "One quotient and remainder write each");

        $display("\nCP5 DIV OVERFLOW: checks=%0d errors=%0d", checks, errors);
        if (checks == 10 && errors == 0)
            $display("CP5 DIV OVERFLOW TEST PASSED");
        else
            $display("CP5 DIV OVERFLOW TEST FAILED");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: CP5 DIV OVERFLOW timeout");
        $finish;
    end
endmodule
