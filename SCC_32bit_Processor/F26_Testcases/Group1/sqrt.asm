; Integer square root: for each of the 10 inputs at 0x400, finds the largest whole number whose square is
; less than or equal to the input, and stores it in the results table at 0x440 (input at 0x400 + 4n ->
; root at 0x440 + 4n). The inputs include 0, 1, perfect squares, numbers just below a perfect square, and
; the largest 32 bit value, so every result is easy to check by hand.
; The root is built one bit at a time from bit 15 down: a bit is kept if (root + bit)^2 is still <= the
; input (unsigned compare with B.LS). This uses MUL, LSL, LSR, MOVT, register MOV, LOAD/STOR in a loop,
; and B.LS/B.NE, beyond what bubble sort uses.
; The class emulator sets the carry flag backwards after CMP, so it takes the wrong B.LS branches. The
; results table is checked against the right answers instead (EMU_ALLOW in the makefile's sqrt target).
    ORG     #0x400;
    FCB     #0x0;               [0x400] 0          -> root 0
    FCB     #0x1;               [0x404] 1          -> root 1
    FCB     #0x2;               [0x408] 2          -> root 1
    FCB     #0x4;               [0x40C] 4          -> root 2
    FCB     #0xF;               [0x410] 15         -> root 3
    FCB     #0x10;              [0x414] 16         -> root 4
    FCB     #0x63;              [0x418] 99         -> root 9
    FCB     #0x64;              [0x41C] 100        -> root 10
    FCB     #0xF4240;           [0x420] 1000000    -> root 1000 (0x3E8)
    FCB     #0xFFFFFFFF;        [0x424] 4294967295 -> root 65535 (0xFFFF)
    ORG     #0x0;
setup:
    MOV     R4, #0x400;         R4 points at the next input
    MOV     R5, #0x440;         R5 points at the next result
    MOV     R6, #0xA;           R6 counts the inputs left

next_input:
    LOAD    R0, R4;             R0 contains the value to be square rooted

sqrt_bit:
    MOV     R1, #1;
    LSL     R1, R1, #15;        Start by testing bit 2^15
    MOV     R2, #0;             R2 stores current accumulated root value

sqrt_loop:
    ADD     R3, R2, R1;         Add current root and test bit
    MUL     R3, R3, R3;         Square result to check against input
    CMP     R3, R0;             Comparing to the input value...
    B.LS    update_root;        ...if less than or same, add test bit to our square root value

sqrt_loop_after_update:
    LSR     R1, R1, #0x1;       Shift R1 right to check next bit
    CMP     R1, #0x0;           If this isn't the final shift (making R1 0)...
    B.NE    sqrt_loop;          ...continue loop...
    MOV     R0, R2;             Otherwise move final result into R0
    STOR    R0, R5;             Store the root in the results table

    ADD     R4, R4, #0x4;       Move to the next input and result
    ADD     R5, R5, #0x4;
    SUBS    R6, R6, #0x1;       Stop after all 10 inputs
    B.NE    next_input;
    HALT;

update_root:
    ADD     R2, R2, R1;
    B       sqrt_loop_after_update;
