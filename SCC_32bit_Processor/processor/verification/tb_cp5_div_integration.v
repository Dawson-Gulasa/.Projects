`timescale 1ns/1ps
// tb_cp5_div_integration.v
// Full-processor DIV/DIVS integration regression.
// Loads output.mem assembled from assembly/cp5_div_integration.asm.
//
// Checks the instruction decoder, operand selection, IF stall,
// controller result commits, R12 remainder, MOVF flags, and HALT.
// Internal SCC references are intentional for this *group-local*
// debugging bench. The cross-group Bubble Sort and Array Statistics
// testbenches will be converted to class-defined top-level ports only.

module tb_cp5_div_integration;
    localparam integer EXPECTED_DIV_WRITES = 8;
    localparam integer EXPECTED_CHECKS = 18;

    reg clk;
    reg rst;
    reg clk_en;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer checks;
    integer errors;
    integer div_write_count;
    integer quotient_write_count;
    integer remainder_write_count;

    scc_f26_top DUT (
        .clk(clk),
        .clk_en(clk_en),
        .rst(rst),
        .halt_f(halt_f),
        .err_f(err_f),
        .inst_mem_v(inst_mem_v),
        .data_mem_in_v(data_mem_in_v)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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

    // Check every division write at the architectural clock edge.
    // Capture pre-NBA control signals; register updates commit on this edge.
    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.div_reg_write_en) begin
            div_write_count = div_write_count + 1;

            if (DUT.scc.div_stall !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: Division write without fetch stall");
            end

            // Verify that every division result reaches the architectural register file.
            // WB_STAGE now owns the final writeback multiplexer, replacing the old SCC mux.
            //
            // The write enable, destination, and data must all match the active
            // division-controller request before REGS commits the value.

            if ((DUT.scc.arch_reg_write_en !== 1'b1) ||
                (DUT.scc.arch_reg_write_addr_v !== DUT.scc.div_reg_write_addr_v) ||
                (DUT.scc.arch_reg_write_data_v !== DUT.scc.div_reg_write_data_v)) begin

                // A mismatch indicates that WB_STAGE failed to select the division
                // transaction correctly before the rising-edge register update.
                errors = errors + 1;
                $display("FAIL: Division write not selected at REGS");
            end

            if (DUT.scc.div_reg_write_addr_v == 4'd12)
                remainder_write_count = remainder_write_count + 1;
            else
                quotient_write_count = quotient_write_count + 1;
        end
    end

    initial begin
        $dumpfile("tb_cp5_div_integration.vcd");
        $dumpvars(0, tb_cp5_div_integration);
        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        div_write_count = 0;
        quotient_write_count = 0;
        remainder_write_count = 0;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        wait (halt_f === 1'b1);
        #2; // Observe all committed register and flag updates.

        check_word({30'd0, err_f}, 32'd1, "Normal HALT status");
        check_word(DUT.scc.REGS.registers[1], 32'hFFFF_FFEF, "Signed source R1");
        check_word(DUT.scc.REGS.registers[2], 32'd5, "Positive source R2");
        check_word(DUT.scc.REGS.registers[3], 32'hFFFF_FFFD, "DIV reg quotient");
        check_word(DUT.scc.REGS.registers[4], 32'd2, "DIV imm quotient");
        check_word(DUT.scc.REGS.registers[5], 32'hFFFF_FFFD, "DIVS imm quotient");
        check_word(DUT.scc.REGS.registers[7], 32'd1, "DIVS reg quotient");
        check_word(DUT.scc.REGS.registers[8], 32'hFFFF_FFFE, "DIV reg signed remainder");
        check_word(DUT.scc.REGS.registers[9], 32'd1, "DIV imm remainder");
        check_word(DUT.scc.REGS.registers[10], 32'h0000_0008, "DIV preserves NZCV");
        check_word(DUT.scc.REGS.registers[6], 32'h0000_0008, "DIVS imm MOVF NZCV");
        check_word(DUT.scc.REGS.registers[11], 32'h0000_0000, "DIVS reg MOVF NZCV");
        check_word(DUT.scc.REGS.registers[12], 32'd0, "Final R12 remainder");
        check_word(DUT.scc.REGS.registers[0], 32'd2, "Instruction following DIVS");
        check_word(div_write_count, EXPECTED_DIV_WRITES, "Eight division writes");
        check_word(quotient_write_count, 4, "Four quotient writes");
        check_word(remainder_write_count, 4, "Four remainder writes");
        check_word({28'd0, DUT.scc.n_f, DUT.scc.z_f, DUT.scc.c_f, DUT.scc.v_f}, 4'd0, "Final architectural NZCV");

        $display("\nCP5 DIV INTEGRATION: checks=%0d errors=%0d", checks, errors);

        //================================
        // FINAL SELF-CHECKING VERDICT
        //================================
        // All expected comparisons must execute without errors.
        // A failed test must return a nonzero exit status to the regression script.

        if ((checks == EXPECTED_CHECKS) && (errors == 0)) begin
            $display("CP5 DIV INTEGRATION TEST PASSED");
        end
        else begin
            $display("CP5 DIV INTEGRATION TEST FAILED");
            $fatal(1, "Division integration verification failed");
        end

        $finish;
    end

        //=========================
        // SIMULATION TIMEOUT
        //===================
        // A stalled processor or missing HALT must cause an explicit test failure.

        initial begin
            #5000;
            $fatal(1, "CP5 DIV integration verification timeout");
        end
endmodule
