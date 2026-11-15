`timescale 1ns/1ps
// Group 4 shared-bank bench. Icarus Verilog 0.9.7, Verilog-2005 (-g2005).
// Only public scc_f26_top ports are used. No register/memory hierarchy required.
module tb_receipt_calculator;
    reg clk = 0, clk_en = 1, rst = 1;
    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v, data_mem_in_v;
    scc_f26_top DUT (
        .clk(clk), .clk_en(clk_en), .rst(rst), .halt_f(halt_f),
        .err_f(err_f), .inst_mem_v(inst_mem_v), .data_mem_in_v(data_mem_in_v)
    );
    always #5 clk = ~clk;

    localparam integer N = 9, WORDS = 581;
    reg [31:0] qa[0:N-1], pa[0:N-1], qb[0:N-1], pb[0:N-1];
    reg fee[0:N-1];
    reg [31:0] expected[0:WORDS-1], actual[0:WORDS-1], addresses[0:WORDS-1];
    reg found[0:WORDS-1];
    reg [63:0] product_a, product_b, total;
    integer i, j, k, base, status, fd, matched, failures, cycles, scanned;
    integer max_cycles = 200000;
    reg [31:0] addr, value;
    reg [8*256-1:0] line;
    reg [8*16-1:0] text;

    // Uses the simulator's formatting, independently of the assembly's stack
    // algorithm and the independently computed expected table.
    task expect_money;
        input integer offset;
        input [31:0] cents;
        reg [8*16-1:0] formatted;
        integer c, length;
        begin
            formatted = 0;
            $sformat(formatted, "$%0d.%02d", cents / 100, cents % 100);
            length = 0;
            for (c = 0; c < 16; c = c + 1)
                if (formatted[c*8 +: 8] != 0) length = c + 1;
            for (c = 0; c < length; c = c + 1)
                expected[offset+c] = {24'b0, formatted[(length-1-c)*8 +: 8]};
        end
    endtask

    // Standard Verilog failure reporting; require the final PASS marker.
    task fail;
        input [8*160-1:0] message;
        begin
            $display("RECEIPT TEST FAILED: %0s", message);
            $finish;
        end
    endtask

    initial begin
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 200000;
        $dumpfile("receipt_calculator.vcd");
        $dumpvars(0, tb_receipt_calculator);
        cycles = 0;
        failures = 0;
        // Clear an earlier run's dump before the processor starts.
        fd = $fopen("scc_out.txt", "w");
        if (!fd) fail("cannot clear scc_out.txt");
        $fclose(fd);
        for (i = 0; i < WORDS; i = i + 1) begin
            expected[i] = 0;
            actual[i] = 32'hxxxxxxxx;
            found[i] = 0;
            addresses[i] = 32'h2000 + 4*i;
        end
        // Independent inputs: quantities and unit prices in integer cents; fee=25 cents.
        qa[0]=3; pa[0]=2499; qb[0]=2; pb[0]=450; fee[0]=0;
        qa[1]=0; pa[1]=2499; qb[1]=0; pb[1]=450; fee[1]=0;
        qa[2]=1; pa[2]=1205; qb[2]=0; pb[2]=999; fee[2]=0;
        qa[3]=2; pa[3]=75; qb[3]=3; pb[3]=50; fee[3]=1;
        qa[4]=1; pa[4]=2147483647; qb[4]=0; pb[4]=1; fee[4]=0;
        qa[5]=1; pa[5]=2000000000; qb[5]=1; pb[5]=1000000000; fee[5]=0;
        qa[6]=1; pa[6]=2147483640; qb[6]=0; pb[6]=1; fee[6]=1;
        qa[7]=65536; pa[7]=65536; qb[7]=0; pb[7]=1; fee[7]=0;
        qa[8]=3; pa[8]=1000000000; qb[8]=0; pb[8]=1; fee[8]=0;
        for (i = 0; i < N; i = i + 1) begin
            base = i*64;
            product_a = {32'b0,qa[i]} * {32'b0,pa[i]};
            product_b = {32'b0,qb[i]} * {32'b0,pb[i]};
            expected[base]   = product_a[31:0];
            expected[base+1] = product_a[63:32];
            expected[base+2] = product_b[31:0];
            expected[base+3] = product_b[63:32];
            total = 0;
            status = 0;
            if (product_a > 64'h7fffffff || product_b > 64'h7fffffff)
                status = 3;
            else begin
                total = product_a + product_b;
                expected[base+56] = (total == 0) ? 4 : (total > 64'h7fffffff) ? 9 : 0;
                if (total > 64'h7fffffff) status = 1;
                else if (fee[i]) begin
                    total = total + 25;
                    expected[base+57] = (total > 64'h7fffffff) ? 9 : 0;
                    if (total > 64'h7fffffff) status = 2;
                end
            end
            expected[base+4] = total[31:0];
            expected[base+5] = status;
            if (status == 0) begin
                expected[base+7] = 3;
                expect_money(base+8, product_a[31:0]);
                expect_money(base+24, product_b[31:0]);
                expect_money(base+40, total[31:0]);
            end else begin
                text = "OVERFLOW";
                for (j = 0; j < 8; j = j + 1)
                    expected[base+40+j] = {24'b0,text[(7-j)*8 +: 8]};
            end
        end
        addresses[576]=32'h2f04; expected[576]=0;
        addresses[577]=32'h2f08; expected[577]=32'h600d;
        addresses[578]=32'h2f0c; expected[578]=9;
        addresses[579]=32'h2f10; expected[579]=15;
        addresses[580]=32'h2f14; expected[580]=0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst = 0;
        // Sample settled status rather than responding to combinational glitches.
        begin : execution
            repeat (max_cycles) begin
                @(negedge clk); #1;
                cycles = cycles + 1;
                if (err_f === 2'b10 || err_f === 2'b11) begin
                    $display("Processor error: %b", err_f);
                    fail("processor error");
                end
                if (err_f === 2'b01 && halt_f === 1'b1) disable execution;
            end
            $display("Timeout after %0d cycles", max_cycles);
            fail("timeout");
        end
        #3; // Allow the class memory model's HALT dump to finish.
        fd = $fopen("scc_out.txt","r");
        if (!fd) fail("missing scc_out.txt");
        scanned = $fgets(line,fd);
        while ($fgets(line,fd)) begin
            matched = $sscanf(line,"0x%h,0x%h",addr,value);
            if (matched != 2) fail("malformed dump line");
            for (k = 0; k < WORDS; k = k + 1) if (addresses[k] == addr) begin
                if (found[k]) begin
                    $display("Duplicate address: %h", addr);
                    fail("duplicate address");
                end
                actual[k] = value;
                found[k] = 1;
            end
        end
        $fclose(fd);
        for (k = 0; k < WORDS; k = k + 1)
            if (!found[k] || actual[k] !== expected[k]) begin
                $display("FAIL @%08h expected=%08h actual=%08h found=%b",
                         addresses[k],expected[k],actual[k],found[k]);
                failures = failures + 1;
            end
        for (i = 0; i < N; i = i + 1) begin
            text = 0;
            for (j = 0; j < 16 && actual[i*64+40+j] != 0; j = j + 1)
                text = {text[8*15-1:0],actual[i*64+40+j][7:0]};
            $display("Receipt %0d: status=%0d total=%0s",i,actual[i*64+5],text);
        end
        if (failures) begin
            $display("Mismatched or missing words: %0d of %0d", failures, WORDS);
            fail("result mismatch");
        end
        $display("RECEIPT TEST PASSED: 9 cases, 581 words, cycles=%0d",cycles);
        $finish;
    end
endmodule
