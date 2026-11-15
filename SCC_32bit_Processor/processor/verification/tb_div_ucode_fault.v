`timescale 1ns/1ps
// tb_div_ucode_fault.v
// CP5 negative test: deliberately corrupt one division microinstruction.
//
// The normal ROM file is never changed. Instead, a testbench-only mux
// substitutes an illegal word at a chosen micro-PC address. This proves
// that the controller CONSUMES and validates the assembled ROM contents.
//
// Compile with div_controller.v, div_datapath.v and div_ucode_rom.v.

module tb_div_ucode_fault;
    reg clk;
    reg rst;
    reg clk_en;
    reg is_div;
    reg div_set_flags;
    reg [3:0] div_rd_addr_v;
    reg [31:0] div_operand_a_v;
    reg [31:0] div_operand_b_v;

    wire [1:0] div_ucode_addr_v;
    wire [31:0] rom_inst_v;
    wire [31:0] div_ucode_inst_v;
    reg corrupt_en;
    reg [1:0] corrupt_addr_v;

    wire div_stall;
    wire div_error;
    wire div_reg_write_en;
    wire [3:0] div_reg_write_addr_v;
    wire [31:0] div_reg_write_data_v;
    wire div_flags_write_en;
    wire div_n_f, div_z_f, div_c_f, div_v_f;

    integer checks;
    integer errors;
    integer quotient_writes;
    integer remainder_writes;
    integer fault_step;

    // Read the real assembled division microcode from disk.
    div_ucode_rom DIV_UCODE_ROM (
        .div_ucode_addr_v(div_ucode_addr_v),
        .div_ucode_inst_v(rom_inst_v)
    );

    // Fault injection exists ONLY in this verification module.
    // 32'hFFFF_FFFF is not one of the four accepted microinstructions.
    assign div_ucode_inst_v = (corrupt_en && (div_ucode_addr_v == corrupt_addr_v)) ? 32'hFFFF_FFFF : rom_inst_v;

    div_controller DUT (
        .clk(clk), 
        .rst(rst), 
        .clk_en(clk_en),
        .is_div(is_div), 
        .div_set_flags(div_set_flags),
        .div_rd_addr_v(div_rd_addr_v),
        .div_operand_a_v(div_operand_a_v),
        .div_operand_b_v(div_operand_b_v),
        .div_ucode_addr_v(div_ucode_addr_v),
        .div_ucode_inst_v(div_ucode_inst_v),
        .div_stall(div_stall), .div_error(div_error),
        .div_reg_write_en(div_reg_write_en),
        .div_reg_write_addr_v(div_reg_write_addr_v),
        .div_reg_write_data_v(div_reg_write_data_v),
        .div_flags_write_en(div_flags_write_en),
        .div_n_f(div_n_f), 
        .div_z_f(div_z_f),
        .div_c_f(div_c_f), 
        .div_v_f(div_v_f)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Count actual writes at the active clock edge, not combinational
    // requests that might temporarily change during a delta cycle.
    always @(posedge clk) begin
        if (rst) begin
            quotient_writes <= 0;
            remainder_writes <= 0;
        end else if (clk_en && div_reg_write_en) begin
            if (div_reg_write_addr_v == 4'd3)
                quotient_writes <= quotient_writes + 1;
            if (div_reg_write_addr_v == 4'd12)
                remainder_writes <= remainder_writes + 1;
        end
    end

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [8*80-1:0] description;
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

    // One clean, synchronous reset before every independent fault case.
    task prepare_case;
        input [1:0] bad_address;
        begin
            @(negedge clk);
            rst = 1'b1;
            
            clk_en = 1'b1;
            is_div = 1'b0;
            
            corrupt_en = 1'b0;
            corrupt_addr_v = bad_address;
            
            div_set_flags = 1'b1;
            div_rd_addr_v = 4'd3;
            
            div_operand_a_v = -32'sd17;
            div_operand_b_v = 32'd5;
            
            @(posedge clk);
            #1;
            
            check32({31'd0, div_error}, 32'd0, "Reset clears prior ROM fault");
            @(negedge clk);
            
            rst = 1'b0;
            corrupt_en = 1'b1;
            is_div = 1'b1;
            #1;
        end
    endtask

    // At address 3, the quotient has already been legally written,
    // but the bad remainder marker must suppress the R12 and flag writes.
    task run_fault_case;
        input [1:0] bad_address;
        input integer expected_quot_writes;
        begin
            prepare_case(bad_address);
            $display("\n--- Injecting invalid ROM word at address %0d ---", bad_address);
            check32({30'd0, div_ucode_addr_v}, 32'd0, "Initial micro-PC is zero");

            // Allow up to five clock edges to reach sticky ERROR.
            // A valid controller must enter ERROR by the first edge
            // after attempting the corrupted microinstruction.
            for (fault_step = 0; fault_step < 5 && div_error !== 1'b1; fault_step = fault_step + 1) begin
                @(posedge clk);
                #1;
            end

            check32({31'd0, div_error}, 32'd1, "Bad microinstruction raises controller error");
            check32({31'd0, div_stall}, 32'd1, "Fault holds instruction fetch");
            check32({31'd0, div_reg_write_en}, 32'd0, "Fault suppresses register write request");
            check32({31'd0, div_flags_write_en}, 32'd0, "Fault suppresses flag write request");
            check32(quotient_writes, expected_quot_writes, "Only prior authorized quotient writes occur");
            check32(remainder_writes, 32'd0, "No remainder write after corrupt microcode");

            // Confirm that fault status cannot self-clear on later edges.
            repeat (2) @(posedge clk);
            #1;
            check32({31'd0, div_error}, 32'd1,
                    "ROM fault remains sticky until reset");
        end
    endtask

    initial begin
        $dumpfile("tb_div_ucode_fault.vcd");
        $dumpvars(0, tb_div_ucode_fault);

        rst = 1'b1;
        clk_en = 1'b1;
        is_div = 1'b0;
        div_set_flags = 1'b0;
        div_rd_addr_v = 4'd0;
        div_operand_a_v = 32'd0;
        div_operand_b_v = 32'd1;
        corrupt_en = 1'b0;
        corrupt_addr_v = 2'd0;
        checks = 0;
        errors = 0;
        quotient_writes = 0;
        remainder_writes = 0;

        // Four independent faults cover capture, calculate,
        // quotient writeback and remainder/flags writeback.
        run_fault_case(2'd0, 0);
        run_fault_case(2'd1, 0);
        run_fault_case(2'd2, 0);
        run_fault_case(2'd3, 1);

        $display("\nCP5 DIV UCODE FAULT: checks=%0d errors=%0d", checks, errors);
        if (checks == 36 && errors == 0)
            $display("CP5 DIV UCODE FAULT TEST PASSED");
        else
            $display("CP5 DIV UCODE FAULT TEST FAILED");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: CP5 DIV UCODE FAULT timeout");
        $finish;
    end
endmodule
