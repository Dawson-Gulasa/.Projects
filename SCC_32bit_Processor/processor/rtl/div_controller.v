// div_controller.v
// Sequential control for signed DIV and DIVS instructions.
//
// Responsibilities:
// - Capture signed operands, Rd, and the DIVS flag-update request.
// - Stall instruction fetch while division is in progress.
// - Register quotient, remainder, and candidate NZCV values.
// - Write quotient to Rd and remainder to R12 on separate clocks.
// - Request NZCV updates only for DIVS.
// - Latch a terminal divide-by-zero or invalid-microcode error without writes.
// - Fetch assembled microinstructions that authorize each execution step.
//
// Architectural register and flag storage remains in regs.v and flags.v.
// This module does not drive the class-defined top-level interface.

module div_controller (
    input  wire clk,
    input  wire rst,
    input  wire clk_en,

    // Decoded division operation and live source operands
    input  wire is_div,
    input  wire div_set_flags,
    input  wire [3:0] div_rd_addr_v,
    input  wire [31:0] div_operand_a_v,
    input  wire [31:0] div_operand_b_v,

    // Assembled ROM word for the current microstep.
    // The controller owns the ROM address; the ROM owns instruction storage
    output reg [1:0] div_ucode_addr_v,
    input  wire [31:0] div_ucode_inst_v,

    // Multicycle fetch and exception control.
    output reg div_stall,
    output reg div_error,

    // Requests to the existing architectural register-file write port.
    output reg  div_reg_write_en,
    output reg  [3:0] div_reg_write_addr_v,
    output reg  [31:0] div_reg_write_data_v,

    // Flag candidates and commit enable for DIVS
    output reg div_flags_write_en,
    output wire div_n_f,
    output wire div_z_f,
    output wire div_c_f,
    output wire div_v_f
);

//===================================
// CONTROLLER STATE DEFINITIONS
//===================================
// IDLE: Detect DIV/DIVS and capture instruction operands.
// CALCULATE: Register signed quotient, remainder, and NZCV candidates.
// WRITE_QUOT: Write the quotient into the captured Rd.
// WRITE_REM: Write the remainder into architectural R12; commit flags only for DIVS.
// RELEASE: Release fetch to advance past the DIV instruction.
// ERROR: Hold fetch and retain the divide-by-zero error until the architectural reset is asserted.
//
// The instruction remains at the fetch address until RELEASE.
// Separate write states accommodate the single ordinary write port.

localparam [2:0] STATE_IDLE = 3'd0;
localparam [2:0] STATE_CALCULATE = 3'd1;
localparam [2:0] STATE_WRITE_QUOT = 3'd2;
localparam [2:0] STATE_WRITE_REM = 3'd3;
localparam [2:0] STATE_RELEASE = 3'd4;
localparam [2:0] STATE_ERROR = 3'd5;

reg [2:0] state;
reg [2:0] next_state;

// Encodings are assembler-generated markers from assembly/ucode_div.asm.
// These values are checked during execution, not merely stored in a ROM
localparam [31:0] UC_INIT = 32'h0580_0000; // CLR R12
localparam [31:0] UC_DIV = 32'h6E00_0000; // DIV R0,R0,R0
localparam [31:0] UC_QUOT = 32'hC800_0000; // NOP
localparam [31:0] UC_REM = 32'hD000_0000; // HALT

// An invalid microinstruction enters the same sticky terminal error state;
// it must never result in an unintended architectural register write
wire rom_init_ok;
wire rom_div_ok;
wire rom_quot_ok;
wire rom_rem_ok;
assign rom_init_ok = (div_ucode_inst_v === UC_INIT);
assign rom_div_ok = (div_ucode_inst_v === UC_DIV);
assign rom_quot_ok = (div_ucode_inst_v === UC_QUOT);
assign rom_rem_ok = (div_ucode_inst_v === UC_REM);

//======================================
// COMBINATIONAL MICROCODE ROM ADDRESS
//=====================================
// Select the microinstruction associated with the current FSM state.
//
// The controller uses a combinational address output; the ROM itself
// supplies the corresponding assembled microinstruction.
//
// STATE_IDLE and STATE_RELEASE use address zero because neither
// requires a separate execution microinstruction.
//
// A default address is assigned before the case to avoid latches.
// Blocking assignments are used for combinational logic.

always @(*) begin
    div_ucode_addr_v = 2'd0;

    case (state)
        STATE_CALCULATE: begin
            // Fetch the instruction authorizing signed division.
            div_ucode_addr_v = 2'd1;
        end
        STATE_WRITE_QUOT: begin
            // Fetch the quotient-write authorization marker.
            div_ucode_addr_v = 2'd2;
        end
        STATE_WRITE_REM: begin
            // Fetch the remainder-write/completion marker.
            div_ucode_addr_v = 2'd3;
        end
        default: begin
            // IDLE, RELEASE, ERROR, and invalid states select address zero.
            div_ucode_addr_v = 2'd0;
        end
    endcase
end

// Captured instruction fields and signed source operands
reg signed [31:0] dividend_reg;
reg signed [31:0] divisor_reg;
reg [3:0] destination_reg;
reg update_flags_reg;

// Registered division results and DIVS candidate flags
reg [31:0] quotient_reg;
reg [31:0] remainder_reg;
reg overflow_reg;

wire [31:0] quotient_calc_v;
wire [31:0] remainder_calc_v;

// The datapath also exposes a divide-by-zero indication and NZCV
// candidates. These are currently retained for interface completeness.
//
// Divide-by-zero is checked using the live divisor before operand capture.
// Architectural DIVS flags are derived from the registered quotient and
// overflow result, ensuring stable values during final writeback.
wire divide_by_zero_calc;
wire signed_overflow_calc;
wire div_n_calc;
wire div_z_calc;
wire div_c_calc;
wire div_v_calc;

//===========================
// SIGNED DIVISION DATAPATH
//==============================
// Division operates on captured operands, never on register-file
// inputs that might change after a clock edge.
// The datapath is combinational; results are stored in CALCULATE.

div_datapath DIV_DATAPATH (
    .dividend_v (dividend_reg),
    .divisor_v (divisor_reg),
    .quotient_v (quotient_calc_v),
    .remainder_v (remainder_calc_v),
    .divide_by_zero (divide_by_zero_calc),
    .signed_overflow (signed_overflow_calc),
    .div_n_f (div_n_calc),
    .div_z_f (div_z_calc),
    .div_c_f (div_c_calc),
    .div_v_f (div_v_calc)
);

// N and Z are derived from the registered quotient.
// C is architecturally cleared; V records signed overflow.
// DIV (without S) never asserts div_flags_write_en.
assign div_n_f = quotient_reg[31];
assign div_z_f = (quotient_reg == 32'd0);
assign div_c_f = 1'b0;
assign div_v_f = overflow_reg;

// Detect zero divisor from live operands before any writeback.
// The controller transitions to a sticky ERROR state on the
// first enabled edge; the integration layer must encode 2'b10.
wire divide_by_zero_request;
assign divide_by_zero_request = is_div && (div_operand_b_v == 32'd0);


    //===============================
    // COMBINATIONAL NEXT-STATE LOGIC
    //==================================
    // Select the next controller state using the current state,
    // decoded DIV/DIVS request, and assembled microcode ROM word.
    //
    // All state transitions are combinational. The state register is
    // updated only on an enabled rising clock edge.
    //
    // A failed microinstruction check enters STATE_ERROR, preventing
    // further architectural writes until the processor is reset.
    //
    // The default assignment holds the current state unless a valid
    // state transition is explicitly requested.

    always @(*) begin
        next_state = state;

        case (state)

            //====================================
            // IDLE: DETECT AND VALIDATE DIV/DIVS
            //===================================
            // A DIV/DIVS instruction starts a new division sequence.
            //
            // Reject the instruction if the divisor is zero or the
            // initialization microinstruction is incorrect.
            // Otherwise, advance to the calculation state.
            STATE_IDLE: begin
                if (is_div) begin
                    if (divide_by_zero_request || !rom_init_ok) begin
                        // An invalid operation or ROM word enters
                        // the sticky terminal error state.
                        next_state = STATE_ERROR;
                    end
                    else begin
                        // Both operands are valid and initialization
                        // microcode matches the expected instruction.
                        next_state = STATE_CALCULATE;
                    end
                end
                // No DIV/DIVS request: remain in STATE_IDLE.
            end

            //========================================
            // CALCULATE: VALIDATE DIVISION MICROCODE
            //========================================
            // A valid microinstruction permits the signed quotient,
            // remainder, and overflow information to be captured.
            STATE_CALCULATE: begin
                if (rom_div_ok) begin
                    next_state = STATE_WRITE_QUOT;
                end
                else begin
                    // Invalid calculation microcode must prevent
                    // quotient and remainder writeback.
                    next_state = STATE_ERROR;
                end
            end

            //====================================
            // WRITE_QUOT: AUTHORIZE QUOTIENT WRITE
            //======================================
            // The writeback control block separately checks the
            // microinstruction, clock enable, and reset before
            // asserting the actual architectural write request.
            STATE_WRITE_QUOT: begin
                if (rom_quot_ok) begin
                    next_state = STATE_WRITE_REM;
                end
                else begin
                    // Corrupt quotient-write microcode prevents
                    // progression to the remainder write state.
                    next_state = STATE_ERROR;
                end
            end

            //========================================
            // WRITE_REM: AUTHORIZE REMAINDER WRITE
            //=======================================
            // Valid completion microcode permits the R12 update
            // and optional DIVS flags to commit before release.
            STATE_WRITE_REM: begin
                if (rom_rem_ok) begin
                    next_state = STATE_RELEASE;
                end
                else begin
                    // Suppress the final write and enter the
                    // terminal error state on an invalid ROM word.
                    next_state = STATE_ERROR;
                end
            end

            //======================================
            // RELEASE: RESUME ARCHITECTURAL FETCH
            //======================================
            // Both result writeback states have completed.
            // Return to IDLE so the next instruction can execute.
            STATE_RELEASE: begin
                next_state = STATE_IDLE;
            end

            //=====================================
            // ERROR: PRESERVE TERMINAL FAULT STATE
            //=====================================
            // The processor remains halted after a divide-by-zero
            // or invalid-microcode fault until synchronous reset.
            STATE_ERROR: begin
                next_state = STATE_ERROR;
            end

            //==========================================
            // DEFAULT: RECOVER FROM INVALID FSM STATE
            //=========================================
            // An unrecognized state encoding must not authorize
            // any arithmetic result or architectural write.
            default: begin
                next_state = STATE_IDLE;
            end

        endcase
    end



    //========================================
    // COMBINATIONAL CONTROL AND WRITEBACK
    //======================================
    // Generate division fetch-stall, exception, register-writeback,
    // and optional DIVS flag-update requests.
    //
    // All control outputs receive safe defaults before the case statement.
    // This provides complete combinational assignments and avoids latches.
    //
    // The register file and flags module perform actual architectural
    // updates on rising clock edges. This block only generates requests.

    always @(*) begin

        //==========================
        // DEFAULT CONTROL OUTPUTS
        //==========================
        // Ordinary fetch is permitted unless an active division state
        // requests a stall. No exception or architectural write is
        // requested by default.

        div_stall = 1'b0;
        div_error = 1'b0;

        div_reg_write_en = 1'b0;
        div_reg_write_addr_v = 4'd0;
        div_reg_write_data_v = 32'd0;

        div_flags_write_en = 1'b0;

        case (state)

            //=========================
            // IDLE: DETECT DIV/DIVS
            //========================
            // Stall immediately when DIV/DIVS is decoded so the current
            // instruction remains available while operands are captured.
            //
            // Without a division request, the default stall value is zero.
            STATE_IDLE: begin
                if (is_div) begin
                    div_stall = 1'b1;
                end
            end

            //=====================================
            // CALCULATE: HOLD INSTRUCTION FETCH
            //========================================
            // Keep the current instruction in fetch while the signed
            // quotient and remainder are calculated and registered.
            //
            // No architectural register or flag updates occur here.
            STATE_CALCULATE: begin
                div_stall = 1'b1;
            end

            //==================================
            // WRITE_QUOT: COMMIT QUOTIENT TO Rd
            //====================================
            // Hold fetch during the quotient writeback cycle.
            //
            // A write is allowed only when:
            // - The processor clock is enabled.
            // - Reset is inactive.
            // - The expected quotient microinstruction is present.
            //
            // If any condition fails, the default write enable remains
            // zero and no architectural register update is requested.
            STATE_WRITE_QUOT: begin
                div_stall = 1'b1;
                if (clk_en && !rst && rom_quot_ok) begin
                    div_reg_write_en = 1'b1;
                    div_reg_write_addr_v = destination_reg;
                    div_reg_write_data_v = quotient_reg;
                end
            end

            //=========================================
            // WRITE_REM: COMMIT REMAINDER AND FLAGS
            //========================================
            // Hold fetch during the final division writeback cycle.
            //
            // The architectural remainder is written into R12.
            // DIVS updates NZCV using the registered quotient result,
            // while ordinary DIV preserves the existing flag values.
            //
            // A missing microinstruction, disabled clock, or reset
            // suppresses both register and flag write requests.
            STATE_WRITE_REM: begin
                div_stall = 1'b1;

                if (clk_en && !rst && rom_rem_ok) begin
                    div_reg_write_en = 1'b1;
                    div_reg_write_addr_v = 4'd12;
                    div_reg_write_data_v = remainder_reg;

                    // Captured instruction control is one for DIVS
                    // and zero for ordinary DIV.
                    div_flags_write_en = update_flags_reg;
                end
            end

            //========================================
            // RELEASE: RESUME INSTRUCTION FETCH
            //========================================
            // Quotient and remainder writeback have completed.
            // Deassert the stall and allow the PC to advance.
            //
            // All architectural write enables remain inactive.
            STATE_RELEASE: begin
                div_stall = 1'b0;
            end

            //========================================
            // ERROR: HOLD TERMINAL EXCEPTION
            //========================================
            // Divide-by-zero or invalid microcode produces a sticky
            // controller error until the sequential state is reset.
            //
            // Keep fetch stalled and report the error. Register and
            // flag writes remain disabled by their default assignments.
            STATE_ERROR: begin
                div_stall = 1'b1;
                div_error = 1'b1;
            end

            //========================================
            // DEFAULT: INVALID STATE ENCODING
            //========================================
            // An unrecognized state must not request any
            // architectural writeback or exception.
            //
            // The next-state block separately recovers to IDLE.
            default: begin
                div_stall = 1'b0;
            end

        endcase
    end


    //===========================================
    // SEQUENTIAL STATE AND RESULT REGISTERS
    //==========================================
    // This block owns all registered division-controller state:
    // - Current FSM state.
    // - Captured signed operands and destination register.
    // - Captured DIVS flag-update request.
    // - Registered quotient, remainder, and overflow result.
    //
    // All registers update on the rising clock edge.
    // Synchronous reset has priority over clk_en.
    // Nonblocking assignments are used for every registered update.
    //
    // When clk_en is low, all registers retain their existing values.

    always @(posedge clk) begin

        //=====================
        // SYNCHRONOUS RESET
        //====================
        // Return the controller to IDLE and clear all saved data.
        // Reset is effective even when clk_en is deasserted.
        if (rst) begin
            state <= STATE_IDLE;

            dividend_reg <= 32'sd0;
            divisor_reg <= 32'sd0;
            destination_reg <= 4'd0;
            update_flags_reg <= 1'b0;

            quotient_reg <= 32'd0;
            remainder_reg <= 32'd0;
            overflow_reg <= 1'b0;
        end

        //======================================
        // CLOCK-ENABLED CONTROLLER OPERATION
        //========================================
        // Advance the FSM and capture data only on enabled clock edges.
        // If clk_en is low, no assignments execute and state is retained.
        else if (clk_en) begin

            // Commit the next-state decision calculated by the
            // separate combinational FSM block.
            state <= next_state;

            //=========================================
            // CAPTURE DIV/DIVS INSTRUCTION OPERANDS
            //========================================
            // Capture source operands, destination Rd, and the S-bit
            // request when a valid division begins in STATE_IDLE.
            //
            // Do not capture an instruction with a zero divisor or
            // an invalid initialization microinstruction.
            //
            // Clear previous results so the new operation cannot
            // accidentally use quotient, remainder, or overflow
            // information from an earlier division.
            if ((state == STATE_IDLE) && is_div && !divide_by_zero_request && rom_init_ok) begin
                dividend_reg <= $signed(div_operand_a_v);
                divisor_reg <= $signed(div_operand_b_v);
                destination_reg <= div_rd_addr_v;
                update_flags_reg <= div_set_flags;

                quotient_reg <= 32'd0;
                remainder_reg <= 32'd0;
                overflow_reg <= 1'b0;
            end

            //=====================================
            // REGISTER SIGNED DIVISION RESULTS
            //====================================
            // After operands have been captured, store the quotient,
            // remainder, and overflow indication produced by DIV_DATAPATH.
            //
            // The calculation microinstruction must be valid before
            // any result is stored. Otherwise, the combinational
            // next-state logic transitions to STATE_ERROR.
            //
            // These registered results remain stable during the
            // following quotient and remainder writeback cycles.
            if ((state == STATE_CALCULATE) && rom_div_ok) begin
                quotient_reg <= quotient_calc_v;
                remainder_reg <= remainder_calc_v;
                overflow_reg <= signed_overflow_calc;
            end
        end

        // No final else is necessary: clocked registers automatically
        // retain their values when neither reset nor clk_en is active.

    end


endmodule
