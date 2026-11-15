// Group 4 copy: only the R0-R15 debug wires were remapped to our hierarchy
// (scc.REGS.registers; R14 = 0, R15 = PC). Checks are unchanged.
`timescale 1ns / 1ps

/*
 * This testbench self-checks the results of the bit_packed_physics_updater.asm file by calculating
 * the ideal values for the updated words and then comparing them to the memory values within the 
 * scc_out.txt files. Results are self checking and correspond directly to the values set in memory 
 * within the assembly file. 
 * Gemini was used to assist with the writing of this testbench by giving it the .asm file and asking
 * it to create a behavioral emulator for it, in addition to assisting with some of the code for reading 
 * scc_out.txt. 
 * Critique: The AI did a good job of analyzing the behavior of the assembly file and writing an emulator that
 * fully matches its behavior using behavioral Verilog. 
 */
module bit_packed_physics_updater_tb;

    // TB Inputs
    reg clk_tb;
    reg clk_en_tb;
    reg rst_tb;

    // TB Outputs
    wire halt_f_tb;
    wire [1:0] err_f_tb;
    wire [31:0] inst_mem_v_tb;
    wire [31:0] data_mem_in_v_tb;

    // Register file aliases for waveforms
    wire [31:0] R0  = scc_f26_top.scc.REGS.registers[0];
    wire [31:0] R1  = scc_f26_top.scc.REGS.registers[1];
    wire [31:0] R2  = scc_f26_top.scc.REGS.registers[2];
    wire [31:0] R3  = scc_f26_top.scc.REGS.registers[3];
    wire [31:0] R4  = scc_f26_top.scc.REGS.registers[4];
    wire [31:0] R5  = scc_f26_top.scc.REGS.registers[5];
    wire [31:0] R6  = scc_f26_top.scc.REGS.registers[6];
    wire [31:0] R7  = scc_f26_top.scc.REGS.registers[7];
    wire [31:0] R8  = scc_f26_top.scc.REGS.registers[8];
    wire [31:0] R9  = scc_f26_top.scc.REGS.registers[9];
    wire [31:0] R10 = scc_f26_top.scc.REGS.registers[10];
    wire [31:0] R11 = scc_f26_top.scc.REGS.registers[11];
    wire [31:0] R12 = scc_f26_top.scc.REGS.registers[12];
    wire [31:0] R13 = scc_f26_top.scc.REGS.registers[13];
    wire [31:0] R14 = 32'd0;
    wire [31:0] R15 = scc_f26_top.scc.pc_v;

    // Instantiate top level module
    scc_f26_top scc_f26_top(
        .clk(clk_tb),
        .clk_en(clk_en_tb),
        .rst(rst_tb),
        .halt_f(halt_f_tb),
        .err_f(err_f_tb),
        .inst_mem_v(inst_mem_v_tb),
        .data_mem_in_v(data_mem_in_v_tb)
    );

    // Physics info verification values
    reg [31:0] initial_entities [0:9];
    reg [31:0] expected_entities[0:9];
    reg [31:0] actual_entities  [0:9];
    reg        entity_found      [0:9];

    // Signals for file parsing
    integer fd, matched, idx, total_errors;
    reg [31:0] addr, value;
    reg [255:0] dummy_line;

    // 10 ns period clock
    always begin
        clk_tb <= 0;
        #5;
        clk_tb <= 1;
        #5;
    end

    reg [2:0] reset_cycle_count;
    integer execute_count;   

    // Track resets
    always @(posedge clk_tb) begin
        if (rst_tb) begin
            reset_cycle_count <= reset_cycle_count + 1;
        end
    end

    // Verify 3 clock cycles high reset
    always @(negedge rst_tb) begin
        if (reset_cycle_count == 4) begin
            $display("[PASS] Reset asserted for exactly %0d clock cycles.", reset_cycle_count);
        end else begin
            $error("[FAIL] Reset assertion mismatch! Expected 3 cycles, got %0d.", reset_cycle_count);
        end
    end

    // Ideal physics calculations emulator
    function [31:0] calculate_expected_entity;
        input [31:0] word;
        reg active;
        reg [7:0] x, y;
        reg [3:0] vx_raw, vy_raw;
        integer vx, vy;
        reg [31:0] result;
        begin
            active = (word >> 24) & 1'b1;
            if (!active) begin
                calculate_expected_entity = word; // Inactive entities are skipped
            end else begin
                // Unpack
                x = word[7:0];
                y = word[15:8];
                vx_raw = word[19:16];
                vy_raw = word[23:20];

                // Sign-extend velocities
                vy = (vy_raw ^ 4'h8) - 8;
                vx = (vx_raw ^ 4'h8) - 8;

                // Apply gravity and grounded clamping
                vy = vy + 1;
                if (vy > 7) vy = 7;

                // Apply movement
                x = x + vx[7:0];
                y = y + vy[7:0];

                // Clear grounded bit
                result = word & ~(32'h1 << 25);

                // Collision detection against the floor
                if (y >= 224) begin
                    y = 224;
                    vy = 0;
                    result = result | (32'h1 << 25); // Set grounded
                end

                // Repack data
                result = result & 32'hFF000000; // Retain flags [31:24]
                result = result | x;
                result = result | (y << 8);
                result = result | ((vx & 4'hF) << 16);
                result = result | ((vy & 4'hF) << 20);

                calculate_expected_entity = result;
            end
        end
    endfunction

    // Perform Verification
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, bit_packed_physics_updater_tb);

        // Initial memory values
        initial_entities[0] = 32'h0300E032;
        initial_entities[1] = 32'h01E16450;
        initial_entities[2] = 32'h00000000;
        initial_entities[3] = 32'h016FDC78;
        initial_entities[4] = 32'h0112320A;
        initial_entities[5] = 32'h03C3E040;
        initial_entities[6] = 32'h01707896;
        initial_entities[7] = 32'h030EE001;
        initial_entities[8] = 32'h0151DD64;
        initial_entities[9] = 32'h024C5014;

        // Calculate ideal values
        for (idx = 0; idx < 10; idx = idx + 1) begin
            expected_entities[idx] = calculate_expected_entity(initial_entities[idx]);
            actual_entities[idx]   = 32'hXXXXXXXX;
            entity_found[idx]      = 1'b0;
        end

        // Signal setup
        reset_cycle_count = 0;
        execute_count = 0;
        clk_en_tb = 1'b1;
        rst_tb = 1'b1;

        // 3 clock cycle reset
        repeat (4) @(posedge clk_tb);
        #1; 
        rst_tb = 1'b0;

        // Run to completion
        wait (halt_f_tb == 1'b1);
        $display("Apollo has landed");
        #1; // Allow scc_out.txt to properly fill

        // Check that execution is complete
        if (halt_f_tb !== 1'b1) begin
            $error("[FAIL] Program failed to reach HALT condition.");
        end else begin
            $display("[PASS] Program successfully reached HALT.");
        end

        // Parse scc_out.txt
        fd = $fopen("scc_out.txt", "r");
        if (fd == 0) begin
            $display("[ERROR] Unable to open scc_out.txt");
            $finish;
        end

        dummy_line = $fgets(dummy_line, fd);

        while ($fgets(dummy_line, fd)) begin
            matched = $sscanf(dummy_line, "0x%h,0x%h", addr, value);
            if (matched == 2) begin
                if (addr >= 32'h00001000 && addr <= 32'h00001024) begin
                    idx = (addr - 32'h00001000) / 4;
                    actual_entities[idx] = value;
                    entity_found[idx] = 1'b1;
                end
            end
        end
        $fclose(fd);

        total_errors = 0;
        $display(" ");
        $display("Starting Memory Value Verification: ");
        $display(" ");

        // Self-checking verification loop
        for (idx = 0; idx < 10; idx = idx + 1) begin
            if (!entity_found[idx]) begin
                $display("[FAIL] Entity %0d @ 0x%08X: NOT FOUND in scc_out.txt", idx, 32'h1000 + (idx * 4));
                total_errors = total_errors + 1;
            end else if (actual_entities[idx] !== expected_entities[idx]) begin
                $display("[FAIL] Entity %0d @ 0x%08X: Expected = 0x%08X, Actual = 0x%08X",
                         idx, 32'h1000 + (idx * 4), expected_entities[idx], actual_entities[idx]);
                total_errors = total_errors + 1;
            end else begin
                $display("[PASS] Entity %0d @ 0x%08X: Expected = 0x%08X, Actual = 0x%08X",
                         idx, 32'h1000 + (idx * 4), expected_entities[idx], actual_entities[idx]);
            end
        end

        // Final results
        $display(" ");
        if (total_errors == 0) begin
            $display("[PASS] ALL 10 ENTITY MEMORY RESULTS MATCHED PERFECTLY!");
        end else begin
            $display("[FAIL] TEST FAILED with %0d entity state mismatch(es).", total_errors);
        end
        $display(" ");

        $finish;
    end

endmodule