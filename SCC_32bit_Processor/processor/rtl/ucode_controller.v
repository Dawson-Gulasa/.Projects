// ucode_controller.v
// Sequential microcode controller for signed multiplication
// instructions in the SCC processor
//
// Supported Instructions:
// - MUL  register/register
// - MUL  register/immediate
// - MULS register/register
// - MULS register/immediate
//
// Architectural Behavior:
// - Multiply two signed 32-bit operands.
// - Produce a full signed 64-bit product.
// - Write the lower 32 product bits to Rd
// - Write the upper 32 product bits to R12.
// - For MULS, update architectural NZCV from the 64-bit product
// - For ordinary MUL, preserve the existing architectural flags.
//
// Responsibilities:
// - Detect and capture a decoded multiplication instruction.
// - Store source operands and destination register information.
// - Address and interpret the external microcode ROM.
// - Stall instruction fetch during multicycle execution.
// - Capture the signed multiplication result produced by mul_datapath.v.
// - Retain the full 64-bit result for two architectural writeback cycles.
// - Generate two separate register-file writeback requests.
// - Generate the optional MULS architectural flag update.
// - Release instruction fetch after multiplication completes
//
// Design Notes:
// - State and instruction data are stored on rising clock edges.
// - State storage uses a synchronous active-high reset.
// - The microcode ROM is instantiated outside this module.
// - The controller provides combinational ROM address/control.
// - The register file and flags module own architectural storage.
// - No additional architectural registers are defined here.

module ucode_controller (
    // System control inputs
    input wire clk,
    input wire rst,
    input wire clk_en,

    // Decoded architectural multiplication instruction
    input wire is_mul,
    input wire mul_set_flags,
    input wire [3:0] mul_rd_addr_v,
    input wire [31:0] mul_operand_a_v,
    input wire [31:0] mul_operand_b_v,

    // External microcode ROM interface
    output reg [1:0] ucode_addr_v,
    input wire [31:0] ucode_inst_v,

    // Instruction-fetch stall control
    output reg ucode_stall,

    // Microcode register-file writeback interface
    output reg ucode_reg_write_en,
    output reg [3:0] ucode_reg_write_addr_v,
    output reg [31:0] ucode_reg_write_data_v,

    // Microcode architectural flag-update interface
    output reg ucode_set_flags,
    output wire ucode_n_f,
    output wire ucode_z_f,
    output wire ucode_c_f,
    output wire ucode_v_f
);

//=================================
// FINITE-STATE MACHINE DEFINITIONS
//===================================
// The controller uses six states:
//
// IDLE:
//   Wait for a decoded MUL or MULS instruction.
// INIT:
//   Wait for the expected initialization microinstruction.
// CALCULATE:
//   Execute signed multiplication and capture the product.
// WRITE_LOW:
//   Request writeback of product[31:0] into Rd.
// WRITE_HIGH:
//   Request writeback of product[63:32] into R12.
//   Request architectural NZCV update for MULS only.
// RELEASE:
//   Deassert the fetch stall so the PC can advance.
//
// The next-state logic is combinational, while the current
// state register updates synchronously when clk_en is high

localparam [2:0] STATE_IDLE = 3'd0;
localparam [2:0] STATE_INIT = 3'd1;
localparam [2:0] STATE_CALCULATE = 3'd2;
localparam [2:0] STATE_WRITE_LOW = 3'd3;
localparam [2:0] STATE_WRITE_HIGH = 3'd4;
localparam [2:0] STATE_RELEASE = 3'd5;

reg [2:0] state;
reg [2:0] next_state;

//==================================
// MICROCODE INSTRUCTION CONSTANTS
//===================================
// The external ROM stores 32-bit words corresponding to
// the micro-operations required for multiplication.
//
// These values use the existing class-ISA instruction
// encodings, but the controller interprets them internally.
//
// Each execution state checks its expected microinstruction
// before proceeding to the next state
//
// If the ROM output does not match the expected value,
// the current state is retained until a match occurs

localparam [31:0] UCODE_INIT = 32'h0580_0000;
localparam [31:0] UCODE_MUL = 32'h6000_0000;
localparam [31:0] UCODE_WB = 32'hC800_0000;
localparam [31:0] UCODE_END = 32'hD000_0000;

//=========================================
// CAPTURED ARCHITECTURAL INSTRUCTION DATA
//===========================================
// Source operands and control information are captured
// before executing the multicycle multiplication sequence.
//
// The signed declarations ensure that multiplication treats
// both 32-bit source operands as two's-complement values.
//
// These registers retain their contents throughout the
// microcode sequence while instruction fetch is stalled.

reg signed [31:0] operand_a_reg;
reg signed [31:0] operand_b_reg;

// Destination register for the lower half of the product
reg [3:0] destination_reg;

// Captured instruction flag-update request:
// 0 for MUL; 1 for MULS
reg update_flags_reg;

// Full signed 64-bit multiplication result.
// This register is calculated during STATE_CALCULATE
// and supplies both register-file writeback cycles
reg signed [63:0] product_reg;

//========================================
// MULTIPLICATION DATAPATH RESULT
//========================================
// The combinational datapath operates on the operands previously
// captured by the controller.
//
// The result is registered only when the correct multiplication
// microinstruction is present during STATE_CALCULATE.

wire signed [63:0] product_calc_v;

mul_datapath MUL_DATAPATH (
    .operand_a_v (operand_a_reg),
    .operand_b_v (operand_b_reg),
    .product_v (product_calc_v)
);

//=====================================
// MICROCODE ARCHITECTURAL FLAG VALUES
//======================================
// MULS flag values follow the class emulator (golden model)
// and the ISA's definition of V for a 32-bit architecture.
// N and Z describe the 32-bit value written to Rd, as DIVS
// does for its stored quotient.
//
// N = Bit 31 of the lower word written to Rd.
// Z = 1 when the lower word written to Rd equals zero.
// C = 1 when the upper word written to R12 is nonzero.
// V = 1 when the signed product does not fit in 32 bits,
//     i.e. the upper word is not the sign extension of
//     the lower word.
//
// These are candidate values only.
//
// The controller's ucode_set_flags signal determines
// whether the architectural flags module captures them.
//
// Ordinary MUL preserves flags because its captured
// update_flags_reg value is zero.

assign ucode_n_f = product_reg[31];
assign ucode_z_f = (product_reg[31:0] == 32'd0);
assign ucode_c_f = (product_reg[63:32] != 32'd0);
assign ucode_v_f = (product_reg[63:32] != {32{product_reg[31]}});

//================================================
// COMBINATIONAL MICROCODE ROM ADDRESS SELECTION
//==================================================
// The current FSM state selects which word the external
// microcode ROM presents to the controller
//
// ROM address mapping:
// - STATE_INIT: Address 0, UCODE_INIT.
// - STATE_CALCULATE: Address 1, UCODE_MUL.
// - STATE_WRITE_LOW: Address 2, UCODE_WB.
// - STATE_WRITE_HIGH: Address 3, UCODE_END.
//
// STATE_IDLE and STATE_RELEASE use the default address
// because they do not require a separate ROM operation.
//
// Blocking assignments are used because ROM address
// selection is entirely combinational.

always @(*) begin

    // Safe default: first microcode ROM location
    ucode_addr_v = 2'd0;

    case (state)

        // Fetch the initialization microinstruction
        STATE_INIT: begin
            ucode_addr_v = 2'd0;
        end

        // Fetch the signed multiplication microinstruction
        STATE_CALCULATE: begin
            ucode_addr_v = 2'd1;
        end

        // Fetch the low-result writeback microinstruction
        STATE_WRITE_LOW: begin
            ucode_addr_v = 2'd2;
        end

        // Fetch the final writeback/completion instruction
        STATE_WRITE_HIGH: begin
            ucode_addr_v = 2'd3;
        end

        // IDLE, RELEASE, and invalid states retain address 0
        default: begin
            ucode_addr_v = 2'd0;
        end

    endcase

end

//=========================================
// COMBINATIONAL MICROCODE OUTPUT CONTROL
//==========================================
// Generate the current stall, register-writeback, and
// architectural flag-update requests.
//
// Every output is given an inactive default value before
// evaluating the current FSM state.
//
// This prevents an unintended register write when the
// controller is idle, initializing, calculating, or releasing.
//
// Write enables are additionally gated by clk_en and !rst
// so an inactive processor or asserted reset cannot issue
// a microcoded architectural write request.
//
// These outputs are combinational. The register file and
// flags module perform the actual updates on clock edges.

always @(*) begin

    //------------------------
    // DEFAULT FETCH CONTROL
    //-------------------------
    // Do not stall ordinary instruction fetch by default.
    ucode_stall = 1'b0;

    //------------------------------------
    // DEFAULT REGISTER-WRITEBACK SIGNALS
    //------------------------------------
    // Disable microcode register writing until a valid
    // writeback state and microinstruction are selected
    ucode_reg_write_en = 1'b0;
    ucode_reg_write_addr_v = 4'd0;
    ucode_reg_write_data_v = 32'd0;

    //-----------------------------------
    // DEFAULT ARCHITECTURAL FLAG CONTROL
    //------------------------------------
    // Preserve existing NZCV unless MULS requests an update
    // during the final microcoded writeback state
    ucode_set_flags = 1'b0;

    //-----------------------------------------
    // GENERATE STATE-SPECIFIC CONTROL OUTPUTS
    //-----------------------------------------

    case (state)

        //==============================
        // IDLE: DETECT MULTIPLICATION
        //===============================
        // If the current architectural instruction is MUL
        // or MULS, immediately stall instruction fetch.
        //
        // The sequential block captures the instruction
        // operands on the next enabled rising clock edge

        STATE_IDLE: begin
            if (is_mul) begin
                ucode_stall = 1'b1;
            end
        end

        //===================================================
        // INIT: WAIT FOR INITIALIZATION MICROINSTRUCTION
        //=================================================
        // Keep fetch stalled while the microcode controller
        // waits for the initialization ROM word.

        STATE_INIT: begin
            ucode_stall = 1'b1;
        end

        //==============================================
        // CALCULATE: EXECUTE SIGNED MULTIPLICATION
        //===============================================
        // Keep fetch stalled while the calculation state
        // processes the multiplication microinstruction.
        //
        // The product register is updated in the
        // sequential controller at the enabled clock edge

        STATE_CALCULATE: begin
            ucode_stall = 1'b1;
        end

        //======================================
        // WRITE_LOW: WRITE LOWER PRODUCT WORD
        //=======================================
        // Keep fetch stalled during the first register write.
        //
        // Only assert writeback if:
        // 1. The ROM supplies UCODE_WB.
        // 2. The processor clock enable is asserted.
        // 3. Reset is inactive.
        //
        // Write product[31:0] into the captured Rd register

        STATE_WRITE_LOW: begin

            ucode_stall = 1'b1;

            if (ucode_inst_v == UCODE_WB && clk_en && !rst) begin
                ucode_reg_write_en = 1'b1;
                ucode_reg_write_addr_v = destination_reg;
                ucode_reg_write_data_v = product_reg[31:0];
            end

        end

        //=================================================
        // WRITE_HIGH: WRITE UPPER PRODUCT WORD AND FLAGS
        //=================================================
        // Keep fetch stalled during the final register write.
        //
        // Only assert writeback when the completion ROM
        // instruction is valid, the clock is enabled,
        // and reset is inactive.
        //
        // Write product[63:32] to the architectural R12.
        //
        // For MULS, request architectural NZCV storage
        // using the previously captured flag-update bit.
        //
        // For ordinary MUL, update_flags_reg is zero,
        // so existing architectural NZCV values are retained.

        STATE_WRITE_HIGH: begin

            ucode_stall = 1'b1;

            if (ucode_inst_v == UCODE_END && clk_en && !rst) begin
                ucode_reg_write_en = 1'b1;
                ucode_reg_write_addr_v = 4'd12;
                ucode_reg_write_data_v = product_reg[63:32];

                // Only MULS requests a flag update
                ucode_set_flags = update_flags_reg;
            end

        end

        //===============================================
        // RELEASE: ALLOW INSTRUCTION FETCH TO ADVANCE
        //==============================================
        // Release the PC stall after both register writes.
        //
        // No microcode register or flag write is requested.
        // The normal instruction stream can resume

        STATE_RELEASE: begin
            ucode_stall = 1'b0;
        end

        //=========================================
        // INVALID STATE: SAFE CONTROL DEFAULTS
        //=========================================
        // An unrecognized state must not issue a writeback
        // or request an unintended architectural flag update.

        default: begin
            ucode_stall = 1'b0;
        end

    endcase

end

//==================================
// COMBINATIONAL NEXT-STATE LOGIC
//====================================
// Determine the next FSM state using the current state,
// decoded multiplication request, and microcode ROM output.
//
// Each state advances only when its required condition is met.
// Otherwise, next_state retains the current state.
//
// This default assignment eliminates the need for redundant
// else branches and prevents unintended combinational latches.
//
// Invalid state encodings recover to STATE_IDLE.
//
// The sequential state register updates only when clk_en is high.
// Reset has priority over clock enable in the clocked block below.

always @(*) begin

    // Hold the current state unless a transition is requested
    next_state = state;

    case (state)

        // IDLE -> INIT:
        // Start the microcode sequence when MUL/MULS is
        // recognized by the architectural instruction decoder
        STATE_IDLE: begin
            if (is_mul) begin
                next_state = STATE_INIT;
            end
        end

        // INIT -> CALCULATE:
        // Continue when the ROM presents UCODE_INIT
        STATE_INIT: begin
            if (ucode_inst_v == UCODE_INIT) begin
                next_state = STATE_CALCULATE;
            end
        end

        // CALCULATE -> WRITE_LOW:
        // Continue when the ROM presents UCODE_MUL
        STATE_CALCULATE: begin
            if (ucode_inst_v == UCODE_MUL) begin
                next_state = STATE_WRITE_LOW;
            end
        end

        // WRITE_LOW -> WRITE_HIGH:
        // Continue when the ROM presents UCODE_WB
        STATE_WRITE_LOW: begin
            if (ucode_inst_v == UCODE_WB) begin
                next_state = STATE_WRITE_HIGH;
            end
        end

        // WRITE_HIGH -> RELEASE:
        // Continue when the ROM presents UCODE_END
        STATE_WRITE_HIGH: begin
            if (ucode_inst_v == UCODE_END) begin
                next_state = STATE_RELEASE;
            end
        end

        // RELEASE -> IDLE:
        // Return to the idle state after allowing the
        // normal instruction-fetch path to advance
        STATE_RELEASE: begin
            next_state = STATE_IDLE;
        end

        // Recover from an undefined FSM state encoding.
        default: begin
            next_state = STATE_IDLE;
        end

    endcase

end

//===============================================
// SEQUENTIAL MICROCODE STATE AND RESULT STORAGE
//===============================================
// Store FSM state, captured instruction data, and product.
//
// This block is triggered only by the rising clock edge.
// Reset is synchronous and has priority over clock enable.
//
// Update priority:
// 1. If rst is high, reset all controller registers.
// 2. Otherwise, if clk_en is high:
//    - Update the current FSM state.
//    - Capture a newly detected multiplication instruction.
//    - Capture the combinational datapath result in STATE_CALCULATE.
// 3. Otherwise, preserve all stored register values.
//
// All registered assignments use nonblocking
//
// Operand capture and multiplication calculations occur
// in separate states, ensuring the multiplication uses
// the previously captured operand register values.

always @(posedge clk) begin

    //--------------------
    // SYNCHRONOUS RESET
    //--------------------
    // Clear the FSM state, stored operands, destination,
    // captured flags control, and product on reset

    if (rst) begin

        state <= STATE_IDLE;

        operand_a_reg <= 32'sd0;
        operand_b_reg <= 32'sd0;

        destination_reg <= 4'd0;
        update_flags_reg <= 1'b0;

        product_reg <= 64'sd0;

    end

    //-----------------------------------
    // CLOCK-ENABLED MICROCODE EXECUTION
    //-------------------------------------
    // Change stored controller state only when clk_en is high

    else if (clk_en) begin

        // Advance or hold the FSM according to the
        // combinational next-state decision
        state <= next_state;

        //------------------------------------------------------
        // CAPTURE ARCHITECTURAL MULTIPLICATION INSTRUCTION
        //----------------------------------------------------
        // When MUL/MULS is first recognized in STATE_IDLE,
        // capture the signed input operands and destination.
        //
        // Preserve the instruction's flag-update request
        // for use after multiplication has completed.
        //
        // Clear the previous product before starting
        // a new microcode multiplication sequence

        if (state == STATE_IDLE && is_mul) begin

            operand_a_reg <= $signed(mul_operand_a_v);
            operand_b_reg <= $signed(mul_operand_b_v);

            destination_reg <= mul_rd_addr_v;
            update_flags_reg <= mul_set_flags;

            product_reg <= 64'sd0;

        end

        //-----------------------------------------------
        // CALCULATE FULL SIGNED MULTIPLICATION PRODUCT
        //------------------------------------------------
        // Once the controller reaches STATE_CALCULATE and
        // the ROM supplies UCODE_MUL, multiply the stored
        // signed operands and retain the full 64-bit result
        //
        // The product is available for the subsequent
        // lower-word and upper-word writeback states.

        if (state == STATE_CALCULATE && ucode_inst_v == UCODE_MUL) begin
            // Capture the completed signed multiplication result.
            // The separate datapath performs arithmetic combinationally;
            // this controller stores the result on an enabled rising edge.
            product_reg <= product_calc_v;

        end

    end

    // When reset and clk_en are both low, all stored
    // controller registers retain their existing values

end

endmodule
