`timescale 1ns/1ps
// tb_cp5_flags_div_stack.v
// Self-checking combined ISA verification: SAVF, MOVF, DIV, DIVS, PUSH, POP.
//
// Portability:
// - Instantiates only the published scc_f26_top ports.
// - Observes architectural results through the standard scc_out.txt memory dump.
// - Does not inspect private SCC registers, internal flags, or controller states.
//
// Assemble assembly/cp5_flags_div_stack.asm into output.mem before simulating.

module tb_cp5_flags_div_stack;
    localparam [31:0] RESULT_BASE = 32'h0000_D740;
    localparam integer RESULT_COUNT = 8;
    localparam integer TIMEOUT_NS = 20000;

    reg clk;
    reg clk_en;
    reg rst;
    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer checks;
    integer errors;
    integer cycles;
    integer dump_file;
    integer scan_result;
    integer i;
    reg [8*128-1:0] header_line;
    reg [31:0] scanned_addr;
    reg [31:0] scanned_data;
    reg [31:0] expected [0:RESULT_COUNT-1];
    reg [31:0] observed [0:RESULT_COUNT-1];
    reg found [0:RESULT_COUNT-1];

    scc_f26_top DUT (
        .clk(clk), .clk_en(clk_en), .rst(rst),
        .halt_f(halt_f), .err_f(err_f),
        .inst_mem_v(inst_mem_v), .data_mem_in_v(data_mem_in_v)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (rst)
            cycles <= 0;
        else if (clk_en && !halt_f)
            cycles <= cycles + 1;
    end

    // Compare with case inequality so X/Z values cannot accidentally pass.
    task check32;
        input [31:0] actual;
        input [31:0] wanted;
        input [8*64-1:0] description;
        begin
            checks = checks + 1;
            if (actual !== wanted) begin
                errors = errors + 1;
                $display("FAIL: %0s expected=%08h actual=%08h",
                         description, wanted, actual);
            end else begin
                $display("PASS: %0s = %08h", description, actual);
            end
        end
    endtask

    // Parse standard memory dump without relying on memory model internals.
    // For malformed lines, terminate the scan instead of looping indefinitely.
    task read_result_dump;
        begin
            for (i = 0; i < RESULT_COUNT; i = i + 1) begin
                observed[i] = 32'hxxxx_xxxx;
                found[i] = 1'b0;
            end

            dump_file = $fopen("scc_out.txt", "r");
            if (dump_file == 0) begin
                $display("FAIL: Could not open scc_out.txt");
                errors = errors + 1;
            end else begin
                scan_result = $fgets(header_line, dump_file);
                while (!$feof(dump_file)) begin
                    scan_result = $fscanf(dump_file, "0x%h,0x%h\n", scanned_addr, scanned_data);
                    if (scan_result == 2) begin
                        if ((scanned_addr >= RESULT_BASE) && (scanned_addr < RESULT_BASE + RESULT_COUNT*4) && (scanned_addr[1:0] == 2'b00)) begin
                            observed[(scanned_addr - RESULT_BASE)/4] = scanned_data;
                            found[(scanned_addr - RESULT_BASE)/4] = 1'b1;
                        end
                    end else if (!$feof(dump_file)) begin
                        $display("FAIL: Malformed memory dump entry");
                        errors = errors + 1;
                        // Closing file and leaving task prevents repeated bad reads.
                        $fclose(dump_file);
                        disable read_result_dump;
                    end
                end
                $fclose(dump_file);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cp5_flags_div_stack.vcd");
        $dumpvars(0, tb_cp5_flags_div_stack);
        rst = 1'b1;
        clk_en = 1'b1;
        checks = 0;
        errors = 0;
        cycles = 0;

        expected[0] = 32'h0000_0015;
        expected[1] = 32'h0000_0015;
        expected[2] = 32'h0000_0018;
        expected[3] = 32'h0000_0008;
        expected[4] = 32'h0000_0008;
        expected[5] = 32'h0000_000A;
        expected[6] = 32'h0000_000A;
        expected[7] = 32'h0000_002A;

        repeat (3) @(negedge clk);
        #1 rst = 1'b0;

        @(posedge halt_f);
        #1;
        check32({30'd0,err_f}, 32'd1, "Normal architectural HALT");
        #20;  // Let the memory model finish its HALT-triggered CSV dump.

        read_result_dump;
        for (i = 0; i < RESULT_COUNT; i = i + 1) begin
            checks = checks + 1;
            if (!found[i]) begin
                errors = errors + 1;
                $display("FAIL: Missing result address %08h", RESULT_BASE + i*4);
            end else begin
                $display("PASS: Found result address %08h", RESULT_BASE + i*4);
                check32(observed[i], expected[i], "Architectural status/data snapshot");
            end
        end

        $display("\nCP5 COMBINED FLAGS: checks=%0d errors=%0d cycles=%0d", checks, errors, cycles);
        if (errors == 0 && checks == 17)
            $display("CP5 COMBINED FLAGS TEST PASSED");
        else
            $display("CP5 COMBINED FLAGS TEST FAILED");
        $finish;
    end

    initial begin
        #TIMEOUT_NS;
        $display("FAIL: CP5 combined flags test timed out");
        $display("CP5 COMBINED FLAGS TEST FAILED");
        $finish;
    end
endmodule
