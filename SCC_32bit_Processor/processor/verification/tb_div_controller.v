`timescale 1ns/1ps
// tb_div_controller.v
// CP5 division-controller unit test.
// Checks the clock-by-clock FSM, signed results, DIVS flag request,
// clock-enable hold, release timing, divide-by-zero, and reset recovery.
// Run with div_controller.v, div_datapath.v, and div_ucode_rom.v.

module tb_div_controller;
    reg clk;
    reg rst;
    reg clk_en;
    reg is_div;
    reg div_set_flags;
    reg [3:0] div_rd_addr_v;
    reg [31:0] div_operand_a_v;
    reg [31:0] div_operand_b_v;

    // ROM address comes from the DUT; ROM returns the selected microinstruction.
    wire [1:0] div_ucode_addr_v;
    wire [31:0] div_ucode_inst_v;

    div_ucode_rom DIV_UCODE_ROM (
        .div_ucode_addr_v(div_ucode_addr_v),
        .div_ucode_inst_v(div_ucode_inst_v)
    );

    wire div_stall;
    wire div_error;
    wire div_reg_write_en;
    wire [3:0] div_reg_write_addr_v;
    wire [31:0] div_reg_write_data_v;
    wire div_flags_write_en;
    wire div_n_f, div_z_f, div_c_f, div_v_f;

    integer checks;
    integer errors;

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
        .div_stall(div_stall), 
        .div_error(div_error),
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

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [8*64-1:0] what;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s expected=%08h actual=%08h", what, expected, actual);
            end else begin
                $display("PASS: %0s = %08h", what, actual);
            end
        end
    endtask

    task next_edge;
        begin
            @(posedge clk);
            #1; // Observe results after clocked nonblocking assignments
        end
    endtask

    task reset_controller;
        begin
            // Apply synchronous reset away from a clock edge
            @(negedge clk);
            rst = 1'b1;
            clk_en = 1'b1;
            is_div = 1'b0;
            div_set_flags = 1'b0;
            div_rd_addr_v = 4'd0;
            div_operand_a_v = 32'd0;
            div_operand_b_v = 32'd1;
            next_edge();
            check32({31'd0, div_reg_write_en}, 0, "Reset suppresses register write");
            check32({31'd0, div_error}, 0, "Reset clears division error");
            @(negedge clk);
            rst = 1'b0;
            #1;
        end
    endtask

    initial begin
        $dumpfile("tb_div_controller.vcd");
        $dumpvars(0, tb_div_controller);
        rst = 1'b1;
        clk_en = 1'b1;
        is_div = 1'b0;
        div_set_flags = 1'b0;
        div_rd_addr_v = 4'd0;
        div_operand_a_v = 32'd0;
        div_operand_b_v = 32'd1;
        checks = 0;
        errors = 0;

        //============================================
        // TEST 1: DIVS -17 / 5 = -3, remainder -2
        //============================================
        reset_controller();
        is_div = 1'b1;
        div_set_flags = 1'b1;
        div_rd_addr_v = 4'd3;
        div_operand_a_v = -32'sd17;
        div_operand_b_v = 32'd5;
        #1;
        check32({31'd0, div_stall}, 1, "DIVS stalls immediately in IDLE");
        check32({31'd0, div_reg_write_en}, 0, "No early write in IDLE");

        next_edge(); // IDLE -> CALCULATE; operands captured.
        check32({31'd0, div_stall}, 1, "CALCULATE holds fetch");
        // Change live operands to prove they were captured.
        div_operand_a_v = 32'd99;
        div_operand_b_v = 32'd3;
        div_rd_addr_v = 4'd9;

       
        next_edge(); // CALCULATE -> WRITE_QUOT; results registered.
        check32({31'd0, div_reg_write_en}, 1, "Quotient write enabled");
        check32({28'd0, div_reg_write_addr_v}, 3, "Quotient destination is captured Rd");
        check32(div_reg_write_data_v, 32'hFFFF_FFFD, "Signed quotient is -3");
        check32({31'd0, div_flags_write_en}, 0, "No early DIVS flag commit");

        // Pause the controller in WRITE_QUOT.
        clk_en = 1'b0;
        #1;
        check32({31'd0, div_reg_write_en}, 0, "Clock enable disables write");
       
        next_edge();
       
        check32({31'd0, div_reg_write_en}, 0, "Clock disable holds write state");
        
        clk_en = 1'b1;
        #1;
        
        check32({31'd0, div_reg_write_en}, 1, "Quotient write resumes with clock enable");

       
        next_edge(); // WRITE_QUOT -> WRITE_REM.
        check32({31'd0, div_reg_write_en}, 1, "Remainder write enabled");
        check32({28'd0, div_reg_write_addr_v}, 12, "Remainder targets R12");
        check32(div_reg_write_data_v, 32'hFFFF_FFFE, "Signed remainder is -2");
        check32({31'd0, div_flags_write_en}, 1, "DIVS commits flags with remainder");
        check32({28'd0, div_n_f, div_z_f, div_c_f, div_v_f}, 4'b1000, "DIVS negative quotient NZCV");

        next_edge(); // WRITE_REM -> RELEASE.
        
        check32({31'd0, div_stall}, 0, "RELEASE permits PC advance");
        check32({31'd0, div_reg_write_en}, 0, "No duplicate write in RELEASE");
        
        next_edge(); // RELEASE -> IDLE; instruction has advanced.
        
        is_div = 1'b0;
        
        #1;
        
        check32({31'd0, div_stall}, 0, "IDLE after release");

        //==============================================
        // TEST 2: DIV (not DIVS), positive quotient
        //=============================================
        reset_controller();
        is_div = 1'b1;
        div_set_flags = 1'b0;
        div_rd_addr_v = 4'd4;
        div_operand_a_v = 32'd20;
        div_operand_b_v = 32'd6;
        
        next_edge(); // CALCULATE
        next_edge(); // WRITE_QUOT
        
        check32(div_reg_write_data_v, 3, "DIV quotient 20 / 6");
        
        next_edge(); // WRITE_REM
        
        check32(div_reg_write_data_v, 2, "DIV remainder 20 % 6");
        check32({31'd0, div_flags_write_en}, 0, "DIV preserves NZCV");
        
        next_edge(); // RELEASE
        next_edge(); // IDLE
        
        is_div = 1'b0;

        //============================================
        // TEST 3: signed overflow (-2^31)/(-1)
        //============================================
        reset_controller();
        is_div = 1'b1;
        div_set_flags = 1'b1;
        div_rd_addr_v = 4'd5;
        div_operand_a_v = 32'h8000_0000;
        div_operand_b_v = 32'hFFFF_FFFF;
        
        next_edge(); // CALCULATE
        next_edge(); // WRITE_QUOT
        
        check32(div_reg_write_data_v, 32'h8000_0000, "Overflow wrapped quotient");
        
        next_edge(); // WRITE_REM
        check32(div_reg_write_data_v, 0, "Overflow remainder zero");
        check32({28'd0, div_n_f, div_z_f, div_c_f, div_v_f}, 4'b1001, "Overflow NZCV = 1001");
        
        next_edge(); // RELEASE
        next_edge(); // IDLE

        is_div = 1'b0;

        //==============================================
        // TEST 4: divide-by-zero, sticky until reset
        //=============================================
        reset_controller();

        is_div = 1'b1;
        div_set_flags = 1'b1;
        div_rd_addr_v = 4'd6;
        div_operand_a_v = 32'd123;
        div_operand_b_v = 32'd0;

        #1;

        check32({31'd0, div_stall}, 1, "Zero divisor stalls in IDLE");

        next_edge(); // IDLE -> ERROR.

        check32({31'd0, div_error}, 1, "Divide-by-zero latches error");
        check32({31'd0, div_stall}, 1, "ERROR holds fetch");
        check32({31'd0, div_reg_write_en}, 0, "ERROR suppresses register writes");
        check32({31'd0, div_flags_write_en}, 0, "ERROR suppresses flag writes");

        div_operand_b_v = 32'd7; // Changing live input cannot clear error.
        
        next_edge();
        check32({31'd0, div_error}, 1, "Error remains sticky");

        reset_controller();

        check32({31'd0, div_stall}, 0, "Reset restores idle fetch");

        $display("\nCP5 DIV CONTROLLER: checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("CP5 DIV CONTROLLER TEST PASSED");
        else
            $display("CP5 DIV CONTROLLER TEST FAILED");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: CP5 DIV controller timeout");
        $finish;
    end
endmodule
