; cp5_div_zero.asm
; Full SCC divide-by-zero architectural exception regression.
; A faulting DIVS must halt with err_f=2'b10 without committing
; quotient, remainder, NZCV, or any following instruction.

    ORG #0x0;

    MOV R1, #0x7B;       ; Dividend = 123.
    MOV R2, #0x0;        ; Divisor = zero.
    MOV R3, #0x1234;     ; Destination sentinel.
    MOV R12, #0x5678;   ; Remainder-register sentinel.
    SUBS R9, R14, #0x1;  ; Establish NZCV = 1000.
    MOVF R10;            ; Capture the original flags.

    DIVS R3, R1, R2;     ; Must raise error 10, without writeback.
    MOV R4, #0x7777;     ; Must never execute.
    HALT;               ; Must never be reached.
