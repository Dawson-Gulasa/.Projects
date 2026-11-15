
; movf_savf.asm
;
; SCC CP5 — Architectural Flag Transfer Verification
;
; Purpose:
; Verify that SAVF restores the five architectural
; SNZCV flags and MOVF copies them into a register.
;
; Two distinct flag patterns are saved into memory
; so a self-checking top-level testbench can verify
; the program without accessing internal SCC signals.
;
; Expected results:
; 0xD700 = 0x00000015 (SNZCV = 10101)
; 0xD704 = 0x0000000A (SNZCV = 01010)
;
; Instructions exercised:
; MOV immediate, SAVF, MOVF, STOR, HALT.
;
; MOVF and SAVF should not change the stored NZCV
; values except when SAVF explicitly restores them.

    ;=====================
    ; RESULT MEMORY
    ;=====================
    ; Reserve two 32-bit words for flag snapshots.

    ORG #0xD700;

    FCB #0x0;
    FCB #0x0;

    ;=====================
    ; PROGRAM START
    ;=====================

    ORG #0x0;

start:
    ; R10 points to the output memory region.

    MOV R10, #0xD700;

    ;====================================
    ; TEST 1: SAVE AND READ 10101
    ;====================================
    ; Bits [4:0] represent S, N, Z, C, V.
    ;
    ; 10101 sets S, Z, and V.
    ;
    ; SAVF copies those bits into the
    ; architectural status storage.
    ;
    ; MOVF copies all five stored flags
    ; into R2 and zero-extends the result.

    MOV R1, #0x15;
    SAVF R1;
    MOVF R2;

    ; Preserve the first flag snapshot.

    STOR R2, R10;

    ;====================================
    ; TEST 2: SAVE AND READ 01010
    ;====================================
    ; 01010 sets N and C while clearing
    ; S, Z, and V.
    ;
    ; This opposite pattern helps verify
    ; that all five flag positions are
    ; independently writable and readable.

    MOV R3, #0xA;
    SAVF R3;
    MOVF R4;

    ; Store the second snapshot at
    ; the next 32-bit memory location.

    STOR R4, R10, #0x4;

    ;=====================
    ; PROGRAM COMPLETE
    ;=====================

    HALT;
