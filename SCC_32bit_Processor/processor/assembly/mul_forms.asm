; mul_forms.asm
;
; SCC CP4 integration test for four multiplication forms.
;
; Covers:
; - MUL  register/register
; - MUL  register/immediate
; - MULS register/register
; - MULS register/immediate
;
; Signed 32-bit operands produce a signed 64-bit result:
;   Rd  = product[31:0]
;   R12 = product[63:32]
;
; R9 is a sentinel used to check register preservation.

    ORG #0x0;

    MOV R1, #0x6;
    MOV R2, #0x7;
    MOV R9, #0x1234;

    ; Establish negative flags before ordinary MUL
    ; 0 - 1 = -1, setting N=1 and Z=0
    ; MUL must preserve these flags
    SUBS R10, R14, #0x1;

    ; Form 1: Register/register MUL
    ; 6 * 7 = 42
    ; R3=0x0000002A, R12=0x00000000
    MUL R3, R1, R2;

    ; Form 2: Register/immediate MUL
    ; 6 * (-3) = -18
    ; R4=0xFFFFFFEE, R12=0xFFFFFFFF
    MUL R4, R1, #0xFFFD;

    ; Form 3: Register/register MULS
    ; 7 * 6 = 42
    ; R5=0x0000002A, R12=0x00000000
    ; NZCV=0000
    MULS R5, R2, R1;

    ; Form 4: Register/immediate MULS
    ; 6 * 0 = 0
    ; R6=0x00000000, R12=0x00000000
    ; NZCV=0100
    MULS R6, R1, #0x0;

    HALT;
