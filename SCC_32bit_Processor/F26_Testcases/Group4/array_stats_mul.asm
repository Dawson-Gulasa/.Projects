; array_stats_mul.asm
;
; SCC CP4 Meaningful Program
; Array Statistics and Weighted Checksum
;
; Processes eight unsigned positive 32-bit integers.
;
; Calculates:
;   1. Sum of all elements
;   2. Minimum element
;   3. Maximum element
;   4. Number of even elements
;   5. Position-weighted checksum
;
; Weighted checksum = SUM(array[i] * (i + 1))
;
; Input array begins at 0xD600
; Results begin at 0xD640
;
; Instructions exercised:
; MOV, MOVR, CLR, LOAD, STOR, ADD, CMP, AND,
; B, B.eq, B.mi, B.ne, and MUL.
;
; MUL is performed once per array element, requiring
; the microcode controller to execute eight times.

    ;==========================
    ; INPUT ARRAY
    ;=======================
    ; Eight 32-bit values:
    ; 9, 2, 7, 4, 1, 8, 3, 6

    ORG #0xD600;

    FCB #0x9;
    FCB #0x2;
    FCB #0x7;
    FCB #0x4;
    FCB #0x1;
    FCB #0x8;
    FCB #0x3;
    FCB #0x6;

    ;===============
    ; RESULT MEMORY
    ;===============
    ; 0xD640 = Sum
    ; 0xD644 = Minimum
    ; 0xD648 = Maximum
    ; 0xD64C = Even count
    ; 0xD650 = Weighted checksum

    ORG #0xD640;

    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;
    FCB #0x0;

    ;===========
    ; PROGRAM START
    ;===============

    ORG #0x0;

start:
    ; R0 = Input array base address
    ; R1 = Number of elements
    ; R2 = Running sum
    ; R3 = Running minimum
    ; R4 = Running maximum
    ; R5 = Even-number count
    ; R6 = Current array index
    ; R7 = Current element address
    ; R8 = Current array element
    ; R9 = Weighted checksum
    ; R10 = Temporary / multiplication result
    ; R11 = Output base address
    ; R12 = Upper 32 bits of multiplication result

    MOV R0, #0xD600;
    MOV R1, #0x8;

    CLR R2;
    MOV R3, #0x7FFF;
    CLR R4;
    CLR R5;
    CLR R6;

    MOV R7, R0;
    CLR R9;

    ;========================
    ; ARRAY PROCESSING LOOP
    ;======================

loop:
    ; Exit after all eight elements are processed.

    CMP R6, R1;
    B.eq finished;

    ; Load current array element into R8.

    LOAD R8, R7;

    ; Sum += current element.

    ADD R2, R2, R8;

    ;=================
    ; UPDATE MINIMUM
    ;===================
    ; If current < minimum, replace minimum.

    CMP R8, R3;
    B.mi update_min;
    B min_done;

update_min:
    MOV R3, R8;

min_done:

    ;==================
    ; UPDATE MAXIMUM
    ;==============
    ; If maximum < current, replace maximum.

    CMP R4, R8;
    B.mi update_max;
    B max_done;

update_max:
    MOV R4, R8;

max_done:

    ;===================
    ; COUNT EVEN NUMBERS
    ;===================
    ; A value is even when its least significant
    ; bit equals zero.

    AND R10, R8, #0x1;
    CMP R10, #0x0;
    B.ne odd_value;

    ADD R5, R5, #0x1;

odd_value:

    ;==================
    ; WEIGHTED CHECKSUM
    ;==================
    ; weight = index + 1
    ; product = current element * weight
    ; checksum += product
    ;
    ; MUL uses the microcode controller.
    ; Rd receives the lower result and R12 the upper.
    ;
    ; R10 is both a source and the destination.
    ; The controller captures both operands before
    ; writing the multiplication result.

    ADD R10, R6, #0x1;
    MUL R10, R8, R10;
    ADD R9, R9, R10;

    ; Move to next 32-bit array element.

    ADD R7, R7, #0x4;
    ADD R6, R6, #0x1;

    B loop;

    ;====================
    ; WRITE FINAL RESULTS
    ;======================
finished:
    MOV R11, #0xD640;

    STOR R2, R11;
    STOR R3, R11, #0x4;
    STOR R4, R11, #0x8;
    STOR R5, R11, #0xC;
    STOR R9, R11, #0x10;

    HALT;
