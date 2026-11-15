; ucode_mul.asm
; SCC CP4 multiplication microprogram.
;
; This program is assembled using the class ISA assembler.
; The generated machine code is loaded into ucode_rom.v.
;
; These instructions are interpreted by the microcode
; controller, not executed as an ordinary CPU program
;
; The original MUL instruction supplies:
;   - Destination register
;   - Operand 1
;   - Operand 2 (register or signed immediate)
;   - Whether architectural NZCV flags should be updated
;
; The microcode controller preserves these values throughout
; execution.

    CLR R12 ; Microstep 0: Prepare upper-result register
    MUL R0, R0, R0 ; Microstep 1: Execute signed multiplication
    NOP ; Microstep 2: Complete result writeback
    HALT ; Microprogram termination marker