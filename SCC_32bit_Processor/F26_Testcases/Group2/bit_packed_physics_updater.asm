; 32-bit Packed Sprite Physics and Collision Detection

; This program mimics sprite physics and collision detection used in video games for retro video game
; consoles like the Nintendo GBA. It cycles through 5 locations in memory containing bit-packed data On
; a sprite's XY location, XY velocity, if the sprite is active or not and if the sprite is on the ground 
; or on the air to determine if gravity should be simulated. A y position of 224 is assumed to be the floor
; Gemini was used to assist in the idea for this program and its implementation by asking for a meaningful
; assembly program that would perform an operation related to video games using logical shift and operation
; instructions.
; Critique: The AI did a good job of not just determining the idea for a meaningful assembly loop using logical
; shifts and operations, but tying it to an algorithm that was actual used by video games developed in the past

; Packed Word Layout [31:0]:
;   Bits [31:26] : Unused
;   Bit  [25]    : Is Grounded Flag (1 = On Ground, 0 = In Air)
;   Bit  [24]    : Active Flag      (1 = Update Entity, 0 = Skip Entity)
;   Bits [23:20] : Y Velocity       (4-bit signed, biased representation)
;   Bits [19:16] : X Velocity       (4-bit signed, biased representation)
;   Bits [15:8]  : Y Position       (8-bit unsigned integer, range 0–255)
;   Bits [7:0]   : X Position       (8-bit unsigned integer, range 0–255)

    ORG #0x1000                       ;Store 5 entities in memory starting at address @0x0100

_entity_data:
    ; Entity 0: Resting Grounded State (Active=1, Grounded=1, Vy=0 [0x0], Vx=0 [0x0], Y=224 [0xE0], X=50 [0x32])
    FCB #0x0300E032;

    ; Entity 1: Upward Diagonal Motion (Active=1, Air=0, Vy=-2 [0xE], Vx=1 [0x1], Y=100 [0x64], X=80 [0x50])
    FCB #0x01E16450;

    ; Entity 2: Inactive Entity / Skipped (Active=0, Air=0, Vy=-8 [0x0], Vx=-8 [0x0], Y=0 [0x00], X=0 [0x00])
    FCB #0x00000000;

    ; Entity 3: Fast Falling Near Floor (Active=1, Air=0, Vy=6 [0x6], Vx=-1 [0xF], Y=220 [0xDC], X=120 [0x78])
    FCB #0x016FDC78;

    ; Entity 4: Gentle Downward Motion (Active=1, Air=0, Vy=1 [0x1], Vx=2 [0x2], Y=50 [0x32], X=10 [0x0A])
    FCB #0x0112320A;

    ; Entity 5: Upward Jump (Active=1, Grounded=1, Vy=-4 [0xC], Vx=3 [0x3], Y=224 [0xE0], X=64 [0x40])
    FCB #0x03C3E040;

    ; Entity 6: Terminal Velocity Limit (Active=1, Air=0, Vy=7 [0x7], Vx=0 [0x0], Y=120 [0x78], X=150 [0x96])
    FCB #0x01707896;

    ; Entity 7: Screen Wrap / Underflow X (Active=1, Grounded=1, Vy=0 [0x0], Vx=-2 [0xE], Y=224 [0xE0], X=1 [0x01])
    FCB #0x030EE001;

    ; Entity 8: Floor Collision / Overshoot (Active=1, Air=0, Vy=5 [0x5], Vx=1 [0x1], Y=221 [0xDD], X=100 [0x64])
    FCB #0x0151DD64;

    ; Entity 9: Inactive Flag Edge Case (Active=0, Grounded=1, Vy=4 [0x4], Vx=-4 [0xC], Y=80 [0x50], X=20 [0x14])
    FCB #0x024C5014;

    ORG #0x0;

_setup:
    MOV  R0, #0x1000;             R0 = Base memory address where entity data resides
    MOV  R1, #10;                  R1 = Total entities to process
    MOV  R2, #0;                  R2 = Loop index counter

_entity_loop:
    ; Loop Termination Check
    CMP  R2, R1;                  Compare loop index (R2) against total count (R1)
    B.GE _update_done;            If index >= total count, terminate the update loop

    ; Calculate Entity Memory Address
    LSL  R9, R2, #2;              R9 = R2 * 4 (4 byte offset based current index)
    ADD  R9, R0, R9;              R9 = R0 + R9 (Absolute address of current entity word)
    LOAD R3, R9, #0;              R3 = Load 32-bit packed entity word from memory address in R9

    ; Active Bit Validation
    LSR  R4, R3, #24;             Shift bit 24 down to position 0 (bits 24-31 now at 0-7)
    ANDS R4, R4, #1;              Isolate bit 0 (Active Flag) and set condition flags
    B.EQ _next_entity;            Skip inactive bits

    ; Unpack Positions
    AND  R4, R3, #0xFF;           R4 = Extract lower 8 bits (X Position, range 0-255)
    LSR  R5, R3, #8;              Shift Y position down from bits 8-15 to position 0-7
    AND  R5, R5, #0xFF;           R5 = Extract 8 bits (Y Position, range 0-255)

    ; Unpack & Sign-Extend Y Velocity
    LSR  R6, R3, #20;             Shift Y Velocity from bits 20-23 down to position 0-3
    AND  R6, R6, #0xF;            Isolate lower 4 bits (raw unsigned 4-bit representation)
    XOR  R6, R6, #8;              Toggle sign bit (bit 3) to adjust bias
    SUB  R6, R6, #8;              Subtract 8 to complete sign-extension (-8 to +7)

    ; Unpack & Sign-Extend X Velocity
    LSR  R7, R3, #16;             Shift X Velocity from bits 16-19 down to position 0-3
    AND  R7, R7, #0xF;            Isolate lower 4 bits
    XOR  R7, R7, #8;              Toggle sign bit (bit 3) to adjust bias
    SUB  R7, R7, #8;              Subtract 8 to complete sign-extension (-8 to +7)

    ; Apply Gravity & Terminal Velocity Clamping
    ADD  R6, R6, #1;              Increase downward Y Velocity by 1 (Gravity step)
    CMP  R6, #7;                  Check if Y Velocity exceeds max terminal velocity (7)
    B.LE _apply_movement;         If Y Velocity <= 7, proceed to apply movement
    MOV  R6, #7;                  Clamp downward Y Velocity to maximum cap of 7

_apply_movement:
    ; Update Spatial Coordinates
    ADD  R4, R4, R7;              New X = Current X + X Velocity
    ADD  R5, R5, R6;              New Y = Current Y + Y Velocity

    ; Collision Detection & Grounded Flag Logic
    MOV  R8, #1;                  Prepare bitmask value
    LSL  R8, R8, #25;             R8 = (1 << 25), bitmask for Grounded flag (bit 25)
    NOT  R10, R8;                 Invert mask (all 1s except 0 at bit 25)
    AND  R3, R3, R10;             Clear bit 25 in R3 (Reset "Is Grounded" to 0)

    CMP  R5, #224;              Compare new Y position against floor boundary (Y = 224)
    B.LT _repack_data;            If Y < 224 (above floor), proceed to repacking

    MOV  R5, #224;              Clamp Y position to floor boundary (224)
    MOV  R6, #0;                  Reset Y Velocity to 0 (stop falling)
    OR   R3, R3, R8;              Set Grounded flag (bit 25 = 1) using pre-calculated mask

_repack_data:
    ; Clear Stale Position/Velocity Data
    LSR  R3, R3, #24;             Shift upper byte (Flags) down to bits 0-7, clearing lower 24 bits
    LSL  R3, R3, #24;             Shift Flags back to bits 24-31 (leaving bits 0-23 as zeros)

    ; Repack Updated Fields into 32-Bit Word
    AND  R4, R4, #0xFF;           Ensure X coordinate wraps within 8 bits (0-255)
    OR   R3, R3, R4;              Pack X Position into bits 0-7

    AND  R5, R5, #0xFF;           Ensure Y coordinate wraps within 8 bits
    LSL  R5, R5, #8;              Move Y Position to bits 8-15
    OR   R3, R3, R5;              Pack Y Position into bits 8-15

    AND  R7, R7, #0xF;            Mask X Velocity to 4 bits
    LSL  R7, R7, #16;             Move X Velocity to bits 16-19
    OR   R3, R3, R7;              Pack X Velocity into bits 16-19

    AND  R6, R6, #0xF;            Mask Y Velocity to 4 bits
    LSL  R6, R6, #20;             Move Y Velocity to bits 20-23
    OR   R3, R3, R6;              Pack Y Velocity into bits 20-23

    ; Write Back Updated Word to Memory
    STOR R3, R9, #0;                Store updated 32-bit entity word back into RAM address R9

_next_entity:
    ADD  R2, R2, #1;              Increment loop counter (R2++)
    B    _entity_loop;            Unconditional branch to process next entity in array

_update_done:
    HALT;                             Terminate execution