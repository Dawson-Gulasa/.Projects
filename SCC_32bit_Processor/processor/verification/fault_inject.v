// fault_inject.v
// Testbench-side fault injection for the SCC CP5 "force an error" demonstration.
//
// Compiled as a second top-level module next to any testbench. It does not
// modify a single RTL or testbench file. One fault is selected at compile
// time with a define; DUTP gives the hierarchical path of the target block:
//
//   iverilog -g2005 -s <tb> -s fault_inject -DFAULT_DIV -DDUTP=<tb>.DUT.scc ...
//
// Each fault overrides one net with a Verilog force, so the processor really
// produces a wrong architectural result; the testbench must catch it on its
// own (missing PASS marker, FAIL line, or timeout).
//
// Writeback faults rebuild the final register-file mux in 2-state logic
// (=== comparisons) so an unknown select during reset cannot turn the
// injected value into X; only the targeted instruction class is corrupted.

`ifndef DUTP
  `define DUTP tb.DUT.scc
`endif

module fault_inject;

    // Corrupted copy of the final writeback data (driven only by writeback faults).
    reg [31:0] fault_data_v;

`ifdef FAULT_ALU
  `define WB_FAULT
  `define CORRUPT_ALU 1'b1
`endif
`ifdef FAULT_MUL
  `define WB_FAULT
  `define CORRUPT_MUL 1'b1
`endif
`ifdef FAULT_DIV
  `define WB_FAULT
  `define CORRUPT_DIV 1'b1
`endif
`ifdef FAULT_POP
  `define WB_FAULT
  `define CORRUPT_POP 1'b1
`endif
`ifdef FAULT_LOAD
  `define WB_FAULT
  `define CORRUPT_LOAD 1'b1
`endif
`ifndef CORRUPT_LOAD
  `define CORRUPT_LOAD 1'b0
`endif
`ifndef CORRUPT_ALU
  `define CORRUPT_ALU 1'b0
`endif
`ifndef CORRUPT_MUL
  `define CORRUPT_MUL 1'b0
`endif
`ifndef CORRUPT_DIV
  `define CORRUPT_DIV 1'b0
`endif
`ifndef CORRUPT_POP
  `define CORRUPT_POP 1'b0
`endif

`ifdef WB_FAULT
    // Same priority as WB_STAGE: DIV, then POP, then ordinary/MUL writeback.
    // Read only upstream candidate signals to avoid a feedback loop when the
    // final writeback data net is forced by this testbench module.
    // The selected class has its bit 0 inverted.
    always @(*) begin
        if (`DUTP.WB_STAGE.select_div_writeback === 1'b1) begin
            fault_data_v = `DUTP.div_reg_write_data_v ^ {31'd0, `CORRUPT_DIV};
        end else if (`DUTP.WB_STAGE.select_pop_writeback === 1'b1) begin
            fault_data_v = `DUTP.stack_pop_data_v ^ {31'd0, `CORRUPT_POP};
        end else if (`DUTP.ucode_reg_write_en === 1'b1) begin
            fault_data_v = `DUTP.WB_STAGE.base_reg_write_data_v ^ {31'd0, `CORRUPT_MUL};
        end else if (`DUTP.is_load_store === 1'b1) begin
            fault_data_v = `DUTP.WB_STAGE.base_reg_write_data_v ^ {31'd0, `CORRUPT_LOAD};
        end else if (`DUTP.is_alu === 1'b1) begin
            fault_data_v = `DUTP.WB_STAGE.base_reg_write_data_v ^ {31'd0, `CORRUPT_ALU};
        end else begin
            fault_data_v = `DUTP.WB_STAGE.base_reg_write_data_v;
        end
    end
`endif

    initial begin
`ifdef WB_FAULT
  `ifdef FAULT_ALU
        $display("*** FAULT INJECTED: ALU result bit 0 inverted at writeback ***");
  `elsif FAULT_MUL
        $display("*** FAULT INJECTED: MUL/MULS result bit 0 inverted at writeback ***");
  `elsif FAULT_LOAD
        $display("*** FAULT INJECTED: LOAD data bit 0 inverted at writeback ***");
  `elsif FAULT_DIV
        $display("*** FAULT INJECTED: DIV/DIVS quotient/remainder bit 0 inverted at writeback ***");
  `else
        $display("*** FAULT INJECTED: POP data bit 0 inverted at writeback ***");
  `endif
        force `DUTP.arch_reg_write_data_v = fault_data_v;
`elsif FAULT_BRANCH
        $display("*** FAULT INJECTED: B.cond condition_met stuck at 0 (never taken) ***");
        force `DUTP.condition_met = 1'b0;
`elsif FAULT_UBRANCH
        $display("*** FAULT INJECTED: IF stage ignores unconditional B (is_branch_imm stuck at 0) ***");
        force `DUTP.IF.is_branch_imm = 1'b0;
`elsif FAULT_NOHALT
        $display("*** FAULT INJECTED: HALT indication suppressed (halt_f stuck at 0) ***");
        force `DUTP.halt_f = 1'b0;
`elsif FAULT_SFLAG
        $display("*** FAULT INJECTED: S (stack-full) flag stuck at 0 ***");
        force `DUTP.s_f = 1'b0;
`elsif FAULT_DIVZERO
        $display("*** FAULT INJECTED: divide-by-zero error output suppressed ***");
        force `DUTP.div_error = 1'b0;
`elsif FAULT_ROM
        $display("*** FAULT INJECTED: division microcode ROM output bit 31 stuck at 1 ***");
        force `DUTP.div_ucode_inst_v[31] = 1'b1;
`elsif FAULT_DIVCTL
        $display("*** FAULT INJECTED: division controller write data bit 0 stuck at 1 ***");
        force `DUTP.div_reg_write_data_v[0] = 1'b1;
`else
        $display("fault_inject: no FAULT_* define given, nothing injected");
`endif
    end

endmodule
