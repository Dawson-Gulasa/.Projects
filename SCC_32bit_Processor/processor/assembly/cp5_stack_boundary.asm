; CP5 stack boundary and S-flag instruction-level verification.
; Sixteen PUSHes fill the stack; the seventeenth overwrites the top.
; POP from full must read the overwritten word and clear S.
; After all sixteen POPs, an empty POP must produce zero.

    ORG #0x0;

    MOV R1, #0x1111;
    MOV R2, #0x2222;

    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;
    PUSH R1;

    MOVF R6;
    PUSH R2;
    MOVF R9;
    POP R3;
    MOVF R7;
    POP R4;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R8;
    POP R5;
    MOVF R10;
    HALT;
