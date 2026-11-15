; CP4 second program: find the maximum of an array (plus its index, the
; minimum and the sum) in one pass.
;
; The array is signed and unsorted, so the running max visibly changes as the
; loop walks through it (23 -> 42 -> 99), and negative values make the signed
; compare (B.le / B.ge) matter.
;
; Adds to the bubble sort's instructions: register MOV, LSL, register-form
; ADD, and the signed conditions B.le and B.ge.
;
; Results at 0x800:
;   +0x0 max = 99   +0x4 index of max = 5   +0x8 min = -31   +0xC sum = 210

    ORG     #0x400;
    FCB     #0x17;            a[0] = 23
    FCB     #0xFFFFFFFB;      a[1] = -5
    FCB     #0x2A;            a[2] = 42
    FCB     #0x8;             a[3] = 8
    FCB     #0xFFFFFFE1;      a[4] = -31
    FCB     #0x63;            a[5] = 99
    FCB     #0x0;             a[6] = 0
    FCB     #0xF;             a[7] = 15
    FCB     #0xFFFFFFFE;      a[8] = -2
    FCB     #0x3D;            a[9] = 61

    ORG     #0x0;
setup:
    MOV     R0, #0x400;       pointer to the array
    MOV     R1, #0xA;         length
    LSL     R2, R1, #0x2;     length * 4 bytes
    ADD     R2, R0, R2;       end address (one past the last element)
    LOAD    R3, R0;           max = a[0]
    MOV     R4, R3;           min = a[0]
    MOV     R5, R3;           sum = a[0]
    CLR     R6;               index of max = 0
    MOV     R7, #0x1;         i = 1
    ADD     R0, R0, #0x4;     point at a[1]

loop:
    CMP     R0, R2;
    B.eq    done;             stop at the end of the array
    LOAD    R8, R0;           R8 = a[i]
    ADD     R5, R5, R8;       sum = sum + a[i]
    CMP     R8, R3;
    B.le    notmax;           signed: a[i] <= max, keep the max
    MOV     R3, R8;           new max
    MOV     R6, R7;           and where it was found
notmax:
    CMP     R8, R4;
    B.ge    notmin;           signed: a[i] >= min, keep the min
    MOV     R4, R8;           new min
notmin:
    ADD     R0, R0, #0x4;     next element
    ADD     R7, R7, #0x1;     i = i + 1
    B       loop;

done:
    MOV     R9, #0x800;       results base
    STOR    R3, R9;           max
    STOR    R6, R9, #0x4;     index of max
    STOR    R4, R9, #0x8;     min
    STOR    R5, R9, #0xC;     sum
    HALT;
