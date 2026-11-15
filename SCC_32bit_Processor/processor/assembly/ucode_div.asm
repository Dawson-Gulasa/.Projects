
; ucode_div.asm
; SCC CP5 signed division microprogram.
;
; This program is assembled using the class ISA assembler.
; The resulting machine-code image will be loaded into a
; dedicated division microcode ROM.
;
; These instructions are microcode markers interpreted by
; div_controller.v, not ordinary architectural instructions.
;
; The original DIV/DIVS instruction supplies:
; - Signed 32-bit dividend and divisor
; - Destination register Rd
; - Whether NZCV must be updated
;
; The controller stores these inputs in local registers.
; The dummy R0 operands below do not replace them.
;
; Division writes:
; - Quotient to the original destination Rd
; - Remainder to architectural R12
;
; Divide-by-zero handling remains inside the controller.
; The architectural register file and flags module retain
; sole ownership of their stored state.

    ; Microstep 0: Initialize division sequence.
    CLR R12;

    ; Microstep 1: Request signed division.
    ; The division datapath uses captured operands.
    DIV R0, R0, R0;

    ; Microstep 2: Quotient writeback.
    NOP;

    ; Microstep 3: Remainder writeback and completion.
    HALT;
