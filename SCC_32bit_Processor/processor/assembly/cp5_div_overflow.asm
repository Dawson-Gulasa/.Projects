; cp5_div_overflow.asm
; Full SCC signed division overflow regression.
; -2147483648 / -1 produces quotient 0x80000000,
; remainder 0, and DIVS NZCV = 1001 (S remains zero).

    ORG #0x0;

    MOV R1, #0x0000;
    MOVT R1, #0x8000;   ; R1 = 0x80000000 (-2147483648).
    MOV R2, #0xFFFF;
    MOVT R2, #0xFFFF;   ; R2 = 0xFFFFFFFF (-1).

    DIVS R3, R1, R2;     ; Quotient R3, remainder R12.
    MOVF R4;            ; Snapshot DIVS SNZCV = 0b01001.
    ADD R5, R3, #0x1;   ; Confirm execution resumes after DIVS.
    HALT;
