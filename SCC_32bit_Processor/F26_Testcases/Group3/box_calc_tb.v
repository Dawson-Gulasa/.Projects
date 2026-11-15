`timescale 1ns/1ns
//
// Group 3 CP5 testcase: box_calc.asm (box calculator, self-checking).
//
// What: runs box_calc on scc_f26_top and checks the results the memory model
// writes to scc_out.txt on HALT.
// Why: the program checks itself and stores 0x600D (pass) or 0x0BAD (fail)
// at 0x1328. This testbench reads that word and every result word, so a
// failure shows exactly which value is wrong.
// How: uses only the top-level ports, so it runs on any group's SCC. Assemble
// box_calc.asm to output.mem first, as for the other group testcases:
//   python assembler.py box_calc.asm instructions.json
// The SCC's own microcode ROM file must also be where its simulation reads it.
// To load a different file name, define SCC_MEM_FILE, for example
//   iverilog -DSCC_MEM_FILE=\"box_calc.mem\" ...

module box_calc_tb;
    reg clk = 0;
    reg clk_en = 1;
    reg rst = 1;

    wire        halt_f;
    wire [1:0]  err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

`ifdef SCC_MEM_FILE
    scc_f26_top #(.MEM_FILE(`SCC_MEM_FILE)) DUT (
`else
    scc_f26_top DUT (
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

    // Expected values, from the class emulator. Results start at 0x1200
    // (volume, area, weight, status per box) and the summary at 0x1300.
    reg [31:0] expected [0:34];
    reg [31:0] actual   [0:34];
    reg        found    [0:34];
    reg [31:0] exp_addr [0:34];
    reg [8*40-1:0] name [0:34];

    integer k, fd, matched, fails, cycles;
    reg [31:0] addr, value;
    reg [8*80-1:0] line;

    task want;
        input integer idx;
        input [31:0] a;
        input [31:0] v;
        input [8*40-1:0] n;
        begin
            exp_addr[idx] = a; expected[idx] = v; name[idx] = n; found[idx] = 0;
        end
    endtask

    always @(posedge clk) if (!rst && !halt_f) cycles = cycles + 1;

    initial begin
        $dumpfile("box_calc_dump.vcd");
        $dumpvars(0, box_calc_tb);
        cycles = 0;

        // per box: volume, area, weight, status
        want( 0, 32'h1200, 32'h00000018, "box 0 volume");
        want( 1, 32'h1204, 32'h00000034, "box 0 area");
        want( 2, 32'h1208, 32'h00000048, "box 0 weight");
        want( 3, 32'h120C, 32'h00000000, "box 0 status");
        want( 4, 32'h1210, 32'h0000007D, "box 1 volume");
        want( 5, 32'h1214, 32'h00000096, "box 1 area");
        want( 6, 32'h1218, 32'h00000177, "box 1 weight");
        want( 7, 32'h121C, 32'h00000001, "box 1 status (cube)");
        want( 8, 32'h1220, 32'h00000046, "box 2 volume");
        want( 9, 32'h1224, 32'h000000AE, "box 2 area");
        want(10, 32'h1228, 32'h000000D2, "box 2 weight");
        want(11, 32'h122C, 32'h00000000, "box 2 status");
        want(12, 32'h1230, 32'h002DC6C0, "box 3 volume");
        want(13, 32'h1234, 32'h001EB360, "box 3 area");
        want(14, 32'h1238, 32'h00895440, "box 3 weight");
        want(15, 32'h123C, 32'h00000004, "box 3 status (large area)");
        want(16, 32'h1240, 32'h8F0D1800, "box 4 volume");
        want(17, 32'h1244, 32'h00C35000, "box 4 area");
        want(18, 32'h1248, 32'hAD274800, "box 4 weight");
        want(19, 32'h124C, 32'h0000000E, "box 4 status (ovf, area, bit 31)");
        want(20, 32'h1250, 32'h861C4680, "box 5 volume");
        want(21, 32'h1254, 32'h01406F40, "box 5 area");
        want(22, 32'h1258, 32'h9254D380, "box 5 weight");
        want(23, 32'h125C, 32'h0000000E, "box 5 status (ovf, area, bit 31)");
        // summary
        want(24, 32'h1300, 32'h8F0D1800, "largest volume");
        want(25, 32'h1304, 32'h00000004, "box with largest volume");
        want(26, 32'h1308, 32'h00000018, "smallest volume");
        want(27, 32'h130C, 32'h00000000, "box with smallest volume");
        want(28, 32'h1310, 32'h1557261B, "total volume (low 32 bits)");
        want(29, 32'h1314, 32'h00000001, "carries out of the total");
        want(30, 32'h1318, 32'h00000003, "boxes with area > 1000");
        want(31, 32'h131C, 32'h00000003, "boxes with volume > 1,000,000");
        want(32, 32'h1320, 32'h375BDA67, "checksum");
        want(33, 32'h1324, 32'h00000000, "program's mismatch count");
        want(34, 32'h1328, 32'h0000600D, "program's self-check (600D = pass)");

        repeat (3) @(posedge clk);
        #1;   // release reset just after the edge
        rst = 1'b0;

        fork : run
            begin wait (halt_f === 1'b1); disable run; end
            begin
                repeat (200000) @(posedge clk);
                $display("[FAIL] no HALT within 200000 cycles");
                $finish;
            end
        join
        #1;   // the memory model writes scc_out.txt on the rising edge of halt_f
        $display("[PASS] reached HALT after %0d cycles", cycles);

        fd = $fopen("scc_out.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] cannot open scc_out.txt (the memory model writes it on HALT)");
            $finish;
        end
        matched = $fgets(line, fd);       // header line
        while ($fgets(line, fd)) begin
            matched = $sscanf(line, "0x%h,0x%h", addr, value);
            if (matched == 2 && addr >= 32'h1200 && addr <= 32'h1328)
                for (k = 0; k < 35; k = k + 1)
                    if (exp_addr[k] == addr) begin
                        actual[k] = value; found[k] = 1;
                    end
        end
        $fclose(fd);

        fails = 0;
        for (k = 0; k < 35; k = k + 1) begin
            if (!found[k]) begin
                $display("[FAIL] %0s @ 0x%h: not in scc_out.txt", name[k], exp_addr[k]);
                fails = fails + 1;
            end else if (actual[k] !== expected[k]) begin
                $display("[FAIL] %0s @ 0x%h: expected 0x%h, got 0x%h", name[k], exp_addr[k], expected[k], actual[k]);
                fails = fails + 1;
            end else
                $display("[PASS] %0s @ 0x%h = 0x%h", name[k], exp_addr[k], actual[k]);
        end

        if (fails == 0)
            $display("[PASS] BOX CALCULATOR: all 35 words match, program self-check = 0x600D");
        else
            $display("[FAIL] BOX CALCULATOR: %0d of 35 words wrong", fails);
        $finish;
    end
endmodule
