; CP5 Group 3 testcase: BOX CALCULATOR (self-checking)
;
; For each box (length, width, height) the program computes, with microcoded
; multiplies:
;   volume  = L*W*H                          MUL (register form)
;   area    = 2*(L*W + L*H + W*H)            MUL, ADD, LSL
;   weight  = volume * 3                     MULS (immediate form), V = overflow
;   status  bit 0 cube, bit 1 weight overflowed (signed), bit 2 area > 1000,
;           bit 3 volume >= 2^31, bit 4 the two volume methods disagree
; and a summary: largest and smallest volume (unsigned) and their box numbers,
; total volume with the number of carries out of 32 bits, boxes with area >
; 1000, boxes with volume > 1,000,000, and an XOR checksum of every result.
;
; SELF-CHECK: each volume is also computed by repeated addition and compared
; with the multiply. Every result and summary word is compared with the
; expected tables below. The final status word is 0x600D when everything
; matches and 0x0BAD otherwise, with the mismatch count next to it.
;
; Memory map
;   0x1000  N, then L, W, H for each box (12 bytes per box)
;   0x1100  expected results, 16 bytes per box: volume, area, weight, status
;   0x1200  computed results, same layout
;   0x1300  computed summary (9 words), 0x1324 mismatch count, 0x1328 final status
;   0x1340  expected summary (9 words)
;
; Note on unsigned branches (F2026.3): CMP/SUBS set C as the carry out,
; C = 1 when a >= b (unsigned). So after CMP a, b: HS means a >= b, LO means
; a < b, HI means a > b, LS means a <= b.

    ORG     #0x1000;
    FCB     #0x6;              N: number of boxes
    FCB     #0x2;              box 0: L
    FCB     #0x3;              box 0: W
    FCB     #0x4;              box 0: H
    FCB     #0x5;              box 1: L
    FCB     #0x5;              box 1: W
    FCB     #0x5;              box 1: H
    FCB     #0xA;              box 2: L
    FCB     #0x1;              box 2: W
    FCB     #0x7;              box 2: H
    FCB     #0x3E8;              box 3: L
    FCB     #0x3E8;              box 3: W
    FCB     #0x3;              box 3: H
    FCB     #0x7D0;              box 4: L
    FCB     #0x7D0;              box 4: W
    FCB     #0x258;              box 4: H
    FCB     #0xBB8;              box 5: L
    FCB     #0xBB8;              box 5: W
    FCB     #0xFA;              box 5: H

    ORG     #0x1100;               expected results
    FCB     #0x18;          box 0: volume
    FCB     #0x34;          box 0: area
    FCB     #0x48;          box 0: weight
    FCB     #0x0;          box 0: status
    FCB     #0x7D;          box 1: volume
    FCB     #0x96;          box 1: area
    FCB     #0x177;          box 1: weight
    FCB     #0x1;          box 1: status
    FCB     #0x46;          box 2: volume
    FCB     #0xAE;          box 2: area
    FCB     #0xD2;          box 2: weight
    FCB     #0x0;          box 2: status
    FCB     #0x2DC6C0;          box 3: volume
    FCB     #0x1EB360;          box 3: area
    FCB     #0x895440;          box 3: weight
    FCB     #0x4;          box 3: status
    FCB     #0x8F0D1800;          box 4: volume
    FCB     #0xC35000;          box 4: area
    FCB     #0xAD274800;          box 4: weight
    FCB     #0xE;          box 4: status
    FCB     #0x861C4680;          box 5: volume
    FCB     #0x1406F40;          box 5: area
    FCB     #0x9254D380;          box 5: weight
    FCB     #0xE;          box 5: status

    ORG     #0x1340;               expected summary
    FCB     #0x8F0D1800;          largest volume
    FCB     #0x4;          box with largest volume
    FCB     #0x18;          smallest volume
    FCB     #0x0;          box with smallest volume
    FCB     #0x1557261B;          total volume (low 32 bits)
    FCB     #0x1;          carries out of the total
    FCB     #0x3;          boxes with area > 1000
    FCB     #0x3;          boxes with volume > 1,000,000
    FCB     #0x375BDA67;          checksum

    ORG     #0x0;
setup:
    MOV     R0, #0x1004;          box pointer
    MOV     R1, #0x1300;          summary base
    MOV     R2, #0x1200;          result pointer (expected results are 0x100 below)
    LOAD    R11, R0, #0x-4;       N
    SUB     R11, R11, #0x1;       boxes left after this one (loop ends below 0)
    STOR    R14, R1;              largest volume = 0
    STOR    R14, R1, #0x4;
    SET     R6;                   smallest volume starts at 0xFFFFFFFF
    STOR    R6, R1, #0x8;
    STOR    R14, R1, #0xC;
    STOR    R14, R1, #0x10;       total volume
    STOR    R14, R1, #0x14;       carries
    STOR    R14, R1, #0x18;       area > 1000 count
    STOR    R14, R1, #0x1C;       volume > 1,000,000 count
    STOR    R14, R1, #0x20;       checksum
    STOR    R14, R1, #0x24;       mismatch count
    STOR    R14, R1, #0x28;       final status

box:
    LOAD    R3, R0;               L
    LOAD    R4, R0, #0x4;         W
    LOAD    R5, R0, #0x8;         H
    CLR     R10;                  status

; volume and surface area (MUL register form)
    MUL     R6, R3, R4;           L*W
    MUL     R7, R6, R5;           volume = L*W*H
    MUL     R9, R3, R5;           L*H
    ADD     R8, R6, R9;
    MUL     R9, R4, R5;           W*H
    ADD     R8, R8, R9;
    LSL     R8, R8, #0x1;         area = 2*(L*W + L*H + W*H)

; weight = volume * 3 (MULS immediate form). Keep its flags with MOVF.
    MULS    R9, R7, #0x3;
    MOVF    R6;                   R6 bit 0 = V from the MULS

; cube when L = W = H. These compares change the flags.
    CMP     R3, R4;
    B.ne    notcube;
    CMP     R4, R5;
    B.ne    notcube;
    ORS     R10, R10, #0x1;       bit 0: cube
notcube:
    SAVF    R6;                   put the MULS flags back
    B.vc    noovf;
    ORS     R10, R10, #0x2;       bit 1: the weight overflowed (signed)
noovf:

; area > 1000 (signed compare)
    CMP     R8, #0x3E8;
    B.le    smallarea;
    ORS     R10, R10, #0x4;       bit 2: large area
    LOAD    R6, R1, #0x18;
    ADD     R6, R6, #0x1;
    STOR    R6, R1, #0x18;
smallarea:

; volume bit 31 (ANDS register form against 0x80000000)
    MOV     R6, #0x0;
    MOVT    R6, #0x8000;          R6 = 0x80000000
    ANDS    R6, R7, R6;
    B.eq    lowvol;
    ORS     R10, R10, #0x8;       bit 3: volume >= 2^31
lowvol:

; volume > 1,000,000 (unsigned). After CMP R7, R6: HI = (volume > 1000000).
    MOV32   R6, #0xF4240;
    CMP     R7, R6;
    B.hi    bigbox;
    B       notbig;
bigbox:
    LOAD    R6, R1, #0x1C;
    ADD     R6, R6, #0x1;
    STOR    R6, R1, #0x1C;
notbig:

; largest volume (unsigned). After CMP R7, R6: LS = (volume <= max), keep max.
    LOAD    R6, R1;
    CMP     R7, R6;
    B.ls    notmax;
    STOR    R7, R1;
    SUB     R6, R2, #0x1200;      box number = (result pointer - 0x1200) / 16
    LSR     R6, R6, #0x4;
    STOR    R6, R1, #0x4;
notmax:

; smallest volume (unsigned). After CMP R7, R6: HS = (volume >= min), keep min.
    LOAD    R6, R1, #0x8;
    CMP     R7, R6;
    B.hs    notmin;
    STOR    R7, R1, #0x8;
    SUB     R6, R2, #0x1200;      box number
    LSR     R6, R6, #0x4;
    STOR    R6, R1, #0xC;
notmin:

; total volume (ADDS register form). LO = no carry out.
    LOAD    R6, R1, #0x10;
    ADDS    R6, R6, R7;
    STOR    R6, R1, #0x10;
    B.lo    nocarry;
    LOAD    R6, R1, #0x14;
    ADD     R6, R6, #0x1;
    STOR    R6, R1, #0x14;
nocarry:

; self-check 1: the volume again, by adding L*W to itself H times
    MUL     R6, R3, R4;           L*W
    CLR     R3;                   running sum
addlw:
    ADD     R3, R3, R6;
    SUBS    R5, R5, #0x1;
    B.gt    addlw;                signed: more layers left
    CMP     R3, R7;
    B.eq    volok;
    ORS     R10, R10, #0x10;      bit 4: the two volume methods disagree
volok:

; store this box's results and fold them into the checksum (XORS register form)
    STOR    R7, R2;
    STOR    R8, R2, #0x4;
    STOR    R9, R2, #0x8;
    STOR    R10, R2, #0xC;
    LOAD    R6, R1, #0x20;
    XORS    R6, R6, R7;
    XORS    R6, R6, R8;
    XORS    R6, R6, R9;
    XORS    R6, R6, R10;
    STOR    R6, R1, #0x20;

; self-check 2: compare with the expected results. ORS keeps Z = 1 only when
; every word matches.
    LOAD    R3, R2, #0x-100;      expected volume
    XOR     R3, R3, R7;
    LOAD    R4, R2, #0x-FC;       expected area
    XOR     R4, R4, R8;
    ORS     R3, R3, R4;
    LOAD    R4, R2, #0x-F8;       expected weight
    XOR     R4, R4, R9;
    ORS     R3, R3, R4;
    LOAD    R4, R2, #0x-F4;       expected status
    XOR     R4, R4, R10;
    ORS     R3, R3, R4;
    B.eq    boxok;
    LOAD    R4, R1, #0x24;
    ADD     R4, R4, #0x1;
    STOR    R4, R1, #0x24;
boxok:

; next box. PL: boxes left >= 0.
    ADD     R0, R0, #0xC;
    ADD     R2, R2, #0x10;
    SUBS    R11, R11, #0x1;
    B.pl    box;

; self-check 3: compare the 9 summary words with the expected summary
    MOV     R0, #0x1300;
    MOV     R2, #0x1340;
    MOV     R5, #0x9;
sumchk:
    LOAD    R3, R0;
    LOAD    R4, R2;
    CMP     R3, R4;
    B.eq    sumok;
    LOAD    R4, R1, #0x24;
    ADD     R4, R4, #0x1;
    STOR    R4, R1, #0x24;
sumok:
    ADD     R0, R0, #0x4;
    ADD     R2, R2, #0x4;
    SUBS    R5, R5, #0x1;
    B.ne    sumchk;

; final status: 0x600D when nothing mismatched, 0x0BAD otherwise
    LOAD    R3, R1, #0x24;
    CMP     R3, #0x0;
    B.ne    fail;
    MOV     R3, #0x600D;
    STOR    R3, R1, #0x28;
    HALT;
fail:
    MOV     R3, #0xBAD;
    STOR    R3, R1, #0x28;
    HALT;
