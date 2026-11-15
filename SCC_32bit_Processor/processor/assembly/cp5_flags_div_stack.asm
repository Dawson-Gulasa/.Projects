; cp5_flags_div_stack.asm
; Combined architectural SNZCV regression for SAVF, DIV/DIVS, PUSH/POP.
; Each MOVF snapshot is stored in data memory for portable top-level checking.
;
; Expected output words starting at 0xD740:
; 0: 0x15  SAVF initial S=1, NZCV=0101
; 1: 0x15  DIV preserves all five status bits
; 2: 0x18  DIVS sets NZCV=1000, preserves S=1
; 3: 0x08  PUSH updates S=0 while preserving NZCV=1000
; 4: 0x08  POP keeps S=0 while preserving NZCV=1000
; 5: 0x0A  SAVF explicitly restores NZCV=1010, S=0
; 6: 0x0A  ordinary DIV preserves restored SNZCV
; 7: 0x0000002A  POP retrieves the pushed value 42
;
; The S flag restored by SAVF is a deliberate architectural flags test.
; Stack occupancy remains empty until the PUSH below.

    ORG #0xD740;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;

    ORG #0x0;

    MOV R10, #0xD740;         ; Result-buffer base address
    MOV R1, #0xFFEF;          ; Construct -17 in two halves
    MOVT R1, #0xFFFF;
    MOV R2, #0x5;             ; Positive divisor +5
    MOV R3, #0x15;            ; SNZCV = 10101
    SAVF R3;
    MOVF R4;
    STOR R4, R10;            ; Snapshot 0: 0x15

    DIV R5, R1, R2;           ; -17 / 5 = -3, remainder -2
    MOVF R4;
    STOR R4, R10, #0x4;      ; Snapshot 1: DIV preserved 0x15

    DIVS R6, R1, R2;          ; Set NZCV=1000, preserve S=1
    MOVF R4;
    STOR R4, R10, #0x8;      ; Snapshot 2: 0x18

    MOV R7, #0x2A;            ; Stack payload = 42
    PUSH R7;                  ; Depth 0 -> 1, S becomes 0
    MOVF R4;
    STOR R4, R10, #0xC;      ; Snapshot 3: 0x08

    POP R8;                   ; Restore 42; depth 1 -> 0
    MOVF R4;
    STOR R4, R10, #0x10;     ; Snapshot 4: 0x08

    MOV R3, #0x0A;            ; SNZCV = 01010
    SAVF R3;
    MOVF R4;
    STOR R4, R10, #0x14;     ; Snapshot 5: 0x0A

    DIV R9, R2, #0x2;         ; 5 / 2 = 2; flags unchanged
    MOVF R4;
    STOR R4, R10, #0x18;     ; Snapshot 6: 0x0A

    STOR R8, R10, #0x1C;     ; Snapshot 7: popped payload = 42
    HALT;
