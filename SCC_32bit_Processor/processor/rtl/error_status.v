// error_status.v
// Combinational processor status and error encoding
// for the SCC processor.
//
// Responsibilities:
// - Receive the illegal-instruction indication from decode.
// - Receive the processor HALT indication.
// - Generate the 2-bit architectural status output.
// - Prioritize illegal instructions over normal HALT.
//
// Status Encoding:
// - 2'b00: Normal operation; no error or HALT.
// - 2'b01: HALT instruction encountered.
// - 2'b10: Undefined or illegal instruction encountered.
// - 2'b11: Reserved for future processor status conditions.
//
// Priority:
// 1. Illegal instruction: err_f = 2'b10.
// 2. HALT instruction:    err_f = 2'b01.
// 3. Otherwise:           err_f = 2'b00.
//
// Design Notes:
// - This module implements combinational logic only.
// - No architectural status register is stored here.
// - The output responds directly to its input controls.
// - Illegal-instruction detection occurs in id_stage.v.
// - The processor supplies the HALT control signal.
// - Additional status conditions may be added in later
//   checkpoints if required by the SCC architecture.

module error_status (
    // Asserted when the current instruction is illegal
    input wire illegal_instr,

    // Asserted when the current instruction requests HALT
    input wire halt_f,

    // Encoded processor error/status output
    output wire [1:0] err_f
);

//==================================================
// COMBINATIONAL ERROR / STATUS PRIORITY ENCODING
//===================================================
// The status output is generated from the current decode
// and HALT indications without storing additional state.
//
// A conditional (ternary) operator creates a priority
// selection between the supported status conditions
//
// If illegal_instr is asserted, report an illegal
// instruction regardless of the HALT indication
//
// Otherwise, if halt_f is asserted, report HALT.
//
// Otherwise, return normal-operation status.
//
// The final default explicitly handles the case in
// which neither input is asserted
//
// Because this is a continuous assignment, err_f
// updates when either input changes and no clocked
// storage or combinational latch is required.

assign err_f = illegal_instr ? 2'b10 : halt_f ? 2'b01 : 2'b00;

endmodule
