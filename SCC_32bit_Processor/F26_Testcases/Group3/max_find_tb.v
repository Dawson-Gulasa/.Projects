`timescale 1ns/1ns
//
// Group 3 testcase: max_find.asm (max, index of max, min and sum of a signed
// array, in one pass), self-checking.
//
// What: runs max_find on scc_f26_top and checks the results the memory model
// writes to scc_out.txt on HALT.
// Why: the four results are checked against the class emulator's values, and
// again against values this testbench works out from the array itself, so a
// wrong compare or a wrong add shows up even if the expected table were off.
// How: uses only the top-level ports, so it runs on any group's SCC. Assemble
// max_find.asm to output.mem first, as for the other group testcases:
//   python assembler.py max_find.asm instructions.json
// The SCC's own microcode ROM file must also be where its simulation reads it.
// To load a different file name, define SCC_MEM_FILE, for example
//   iverilog -DSCC_MEM_FILE=\"max_find.mem\" ...
//
// Array at 0x400: 23 -5 42 8 -31 99 0 15 -2 61
// Results at 0x800 (class emulator):
//   max = 99, index of max = 5, min = -31, sum = 210
//
// Checks:
//   - the program reaches HALT (halt_f) with err_f = 2'b01
//   - the four results match the class emulator
//   - the same four results, recomputed here from the array in scc_out.txt
//   - the array in scc_out.txt is the array the program started with
// inst_mem_v is not checked after HALT. The class memory model drives it to
// 0xFFFFFFFF once inst_mem_en drops, and the ISA leaves it open.
//
// Group 3's own copy (testbenches/max_find_tb.v) also defines GROUP3_PROBES,
// which adds wires on Group 3's register file so GTKWave shows the loop:
// i, a[i], max, max index, min and sum. Those paths exist only in Group 3's
// SCC, so they are off by default.

module max_find_tb;
    reg clk = 0;
    reg clk_en = 1;
    reg rst = 1;

    wire        halt_f;
    wire [1:0]  err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

`ifdef SCC_MEM_FILE
    scc_f26_top #(.MEM_FILE(`SCC_MEM_FILE)) dut (
`else
    scc_f26_top dut (
`endif
        .clk           (clk),
        .clk_en        (clk_en),
        .rst           (rst),
        .halt_f        (halt_f),
        .err_f         (err_f),
        .inst_mem_v    (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    always #5 clk = ~clk;

`ifdef GROUP3_PROBES
    // Group 3's SCC only: the PC and the loop state, for GTKWave
    wire [31:0] pc      = dut.u_scc.inst_mem_addr_v;
    wire [31:0] i_idx   = dut.u_scc.u_regs.u_register_file.regs[7];
    wire [31:0] a_i     = dut.u_scc.u_regs.u_register_file.regs[8];
    wire [31:0] max     = dut.u_scc.u_regs.u_register_file.regs[3];
    wire [31:0] max_idx = dut.u_scc.u_regs.u_register_file.regs[6];
    wire [31:0] min     = dut.u_scc.u_regs.u_register_file.regs[4];
    wire [31:0] sum     = dut.u_scc.u_regs.u_register_file.regs[5];
`endif

    integer passes = 0, fails = 0;
    task check;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s: expected %0d (0x%h), got %0d (0x%h)", name,
                         $signed(expected), expected, $signed(actual), actual);
                fails = fails + 1;
            end else begin
                $display("[PASS] %0s = %0d (0x%h)", name, $signed(actual), actual);
                passes = passes + 1;
            end
        end
    endtask

    // The array as max_find.asm loads it (FCB at 0x400)
    reg signed [31:0] start [0:9];
    initial begin
        start[0] = 23;  start[1] = -5; start[2] = 42; start[3] = 8;  start[4] = -31;
        start[5] = 99;  start[6] = 0;  start[7] = 15; start[8] = -2; start[9] = 61;
    end

    // Words read back from scc_out.txt. A word the dump leaves out is 0.
    reg signed [31:0] arr [0:9];
    reg        [31:0] res [0:3];
    reg               res_found [0:3];

    integer k, fd, matched, cycles = 0, same;
    reg [31:0] addr, value;
    reg [8*80-1:0] line;
    reg signed [31:0] ref_max, ref_min, ref_sum;
    reg [31:0] ref_idx;

    always @(posedge clk) if (!rst && !halt_f) cycles = cycles + 1;

    initial begin
        $dumpfile("max_find_dump.vcd");
        $dumpvars(0, max_find_tb);

        repeat (3) @(posedge clk);
        #1;   // release reset just after the edge, never on it
        rst = 1'b0;

        fork : run
            begin wait (halt_f === 1'b1); disable run; end
            begin
                repeat (2000) @(posedge clk);
                $display("[FAIL] no HALT within 2000 cycles");
                $display("[FAIL] MAX FIND TEST FAILED");
                $finish;
            end
        join
        #1;   // the memory model writes scc_out.txt on the rising edge of halt_f
        $display("-- reached HALT after %0d cycles --", cycles);
        check("err_f (01 = HALT)", err_f, 2'b01);

        for (k = 0; k < 10; k = k + 1) arr[k] = 0;
        for (k = 0; k < 4; k = k + 1) begin res[k] = 0; res_found[k] = 0; end

        fd = $fopen("scc_out.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] cannot open scc_out.txt (the memory model writes it on HALT)");
            $display("[FAIL] MAX FIND TEST FAILED");
            $finish;
        end
        matched = $fgets(line, fd);       // header line
        while ($fgets(line, fd)) begin
            matched = $sscanf(line, "0x%h,0x%h", addr, value);
            if (matched == 2) begin
                if (addr >= 32'h400 && addr <= 32'h424 && addr[1:0] == 2'b00)
                    arr[(addr - 32'h400) >> 2] = value;
                if (addr >= 32'h800 && addr <= 32'h80C && addr[1:0] == 2'b00) begin
                    res[(addr - 32'h800) >> 2] = value;
                    res_found[(addr - 32'h800) >> 2] = 1;
                end
            end
        end
        $fclose(fd);

        $display("-- results at 0x800, against the class emulator --");
        check("max at 0x800 found in scc_out.txt",          res_found[0], 1'b1);
        check("index of max at 0x804 found in scc_out.txt", res_found[1], 1'b1);
        check("min at 0x808 found in scc_out.txt",          res_found[2], 1'b1);
        check("sum at 0x80C found in scc_out.txt",          res_found[3], 1'b1);
        check("max",          res[0], 32'd99);
        check("index of max", res[1], 32'd5);
        check("min",          res[2], -32'sd31);
        check("sum",          res[3], 32'd210);

        // the same results, worked out here from the array in scc_out.txt
        ref_max = arr[0]; ref_min = arr[0]; ref_sum = arr[0]; ref_idx = 0;
        for (k = 1; k < 10; k = k + 1) begin
            ref_sum = ref_sum + arr[k];
            if (arr[k] > ref_max) begin ref_max = arr[k]; ref_idx = k; end
            if (arr[k] < ref_min) ref_min = arr[k];
        end
        $display("-- results at 0x800, against values recomputed from the array --");
        check("max vs recomputed",          res[0], ref_max);
        check("index of max vs recomputed", res[1], ref_idx);
        check("min vs recomputed",          res[2], ref_min);
        check("sum vs recomputed",          res[3], ref_sum);

        same = 1;
        for (k = 0; k < 10; k = k + 1)
            if (arr[k] !== start[k]) begin
                $display("[FAIL] a[%0d] at 0x%h: expected %0d, got %0d", k, 32'h400 + 4*k, start[k], arr[k]);
                same = 0;
            end
        check("array at 0x400 unchanged", same, 1);

        $display("%0d passed, %0d failed", passes, fails);
        if (fails == 0)
            $display("[PASS] MAX FIND TEST PASSED");
        else
            $display("[FAIL] MAX FIND TEST FAILED");
        $finish;
    end
endmodule
