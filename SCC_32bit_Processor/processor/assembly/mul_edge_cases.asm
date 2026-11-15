
; mul_edge_cases.asm
; SCC CP4 signed multiplication edge-case verification.
;
; Tests:
; - A signed product requiring a nonzero upper 32-bit word
; - MULS register/register with a zero result
; - MULS register/register with a negative result
; - MULS register/immediate with zero
; - MULS register/immediate with -1
; - Preservation of an unrelated sentinel register
;
; Rd receives product[31:0].
; R12 receives product[63:32].

    ORG #0x0;

    ; R1 = 2
    MOV R1, #0x2;

    ; R2 = 0x80000000 (-2147483648)
    MOV R2, #0x0;
    MOVT R2, #0x8000;

    ; Unrelated register used to detect clobbering.
    MOV R9, #0x1234;

    ; Test 1: -2147483648 * 2 = -4294967296
    ; R3 = 0x00000000
    ; R12 = 0xFFFFFFFF
    MUL R3, R2, R1;

    ; R5 = -1
    SET R5;

    ; Test 2: MULS register/register, -1 * 0 = 0
    ; R4 = 0, R12 = 0, NZCV = 0100
    MULS R4, R5, R14;

    ; Test 3: MULS register/register, -1 * 2 = -2
    ; R6 = 0xFFFFFFFE, R12 = 0xFFFFFFFF
    ; NZCV = 1000
    MULS R6, R5, R1;

    ; Test 4: MULS register/immediate, -1 * 0 = 0
    ; R7 = 0, R12 = 0, NZCV = 0100
    MULS R7, R5, #0x0;

    ; Test 5: MULS register/immediate, -1 * -1 = 1
    ; R8 = 1, R12 = 0, NZCV = 0000
    MULS R8, R5, #0xFFFF;

    HALT;
