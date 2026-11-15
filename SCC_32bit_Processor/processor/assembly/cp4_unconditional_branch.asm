; cp4_unconditional_branch.asm
; SCC CP4 unconditional-branch timing regression.
;
; At PC=0x00, B #8 must redirect directly to PC=0x08.
; The NOP at PC=0x04 must never be fetched as the
; next architectural instruction.

    ORG #0x0;

    B #0x8;
    NOP;
    HALT;