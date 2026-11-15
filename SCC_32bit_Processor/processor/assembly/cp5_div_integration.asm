; cp5_div_integration.asm
; Full SCC DIV/DIVS functional integration regression.
; Checks all four operand/flag forms, signed remainder, R12, and
; successful execution of the instruction immediately after DIVS.
; Only R0-R12 are used; R14 is the architectural zero register.

    ORG #0x0;

    ;========================================
    ; INITIALIZE SIGNED DIVISION OPERANDS
    ;========================================
    ; MOV loads the 16-bit immediate into the
    ; lower half of the destination register.
    ;
    ; MOVT supplies the upper 16 bits while
    ; preserving the existing lower 16 bits.
    ;
    ; Together these instructions construct
    ; 0xFFFFFFEF, the signed 32-bit value -17.

    MOV R1, #0xFFEF;
    MOVT R1, #0xFFFF;

    ; Initialize the positive divisor (+5).
    MOV R2, #0x5;
    SUBS R9, R14, #0x1;     ; Establish N=1 before ordinary DIV

    DIV R3, R1, R2;          ; register DIV: -17 / 5 = -3, rem -2
    MOV R8, R12;             ; Preserve DIV remainder
    MOVF R10;                ; DIV should preserve prior NZCV = 1000

    DIV R4, R2, #0x2;        ; immediate DIV: 5 / 2 = 2, rem 1
    MOV R9, R12;             ; Preserve second remainder

    DIVS R5, R1, #0x5;       ; immediate DIVS: -17 / 5 = -3, rem -2
    MOVF R6;                 ; DIVS should set NZCV = 1000

    DIVS R7, R2, R2;         ; register DIVS: 5 / 5 = 1, rem 0
    MOVF R11;                ; DIVS should set NZCV = 0000

    ADD R0, R7, #0x1;        ; Must execute exactly once after DIVS
    HALT;
