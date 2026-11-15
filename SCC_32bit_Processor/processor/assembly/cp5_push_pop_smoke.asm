; CP5 PUSH/POP instruction smoke test.
; R1 and R2 are saved and restored in LIFO order.
; A third POP tests empty-stack zero behavior.

    ORG #0x0;

    MOV R1, #0x1234;
    MOV R2, #0x5678;
    PUSH R1;
    PUSH R2;
    POP R3;
    POP R4;
    POP R5;
    MOVF R6;
    HALT;
