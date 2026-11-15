; Signed Temperature Log Analyzer with Unit Conversion, Statistics and Time Formatting

; This program mimics the post-processing step of an embedded data logger (a weather station or a
; freezer monitor). The logger stores 8 signed temperature readings in tenths of a degree Celsius
; (215 = 21.5 C) and the total time the log ran in seconds. The program then:
;   1. Converts every reading to tenths of a degree Fahrenheit (F = C * 9 / 5 + 32) using a signed divide.
;   2. Computes the signed mean (quotient + remainder) of the readings using a signed register divide,
;      then verifies it by multiplying back (mean * count + remainder must equal the sum).
;   3. Computes the population variance (mean of squared deviations) with a signed register multiply
;      and an unsigned register divide.
;   4. Builds an alarm bitmask (bit i = 1 if reading i > 20.0 C), derives the "OK" mask with an XOR,
;      and cross checks the two masks with an AND to produce a status word.
;   5. Splits the log duration into HH:MM:SS with unsigned immediate divides, and computes the average
;      sampling interval with an unsigned register divide.
;   6. Converts the variance into ASCII decimal digits. Digits come out of repeated division
;      least-significant-first, so each one is PUSHed on the stack and then POPped back off in reverse
;      order to be written into memory most-significant-first.

; The creation of this file was assisted by claude by asking it for an idea for a meaningful assembly program that
; uses all four types of divide in the ISA, push, pop, and if possible some of the other unused instructions in
; the ISA coverage. 
; Critique: The AI did a good job of determining how a sensor log analyzer can utilize all four divider operators
; in different ways to properly test them.

; Input Layout (0x1000):
;   0x1000 - 0x101C : 8 signed 32-bit temperature readings (tenths of a degree C, two's complement)
;   0x1020          : Log duration in seconds (unsigned 32-bit)

; Output Layout (base 0x1100) and EXPECTED VALUES for the data below:
;   0x1100 : Mean (signed quotient)                  = 100   (0x64)
;   0x1104 : Mean remainder (from R12 after DIVS)    = 5     (0x05)
;   0x1108 : Variance (tenths C squared)             = 17734 (0x4546)
;   0x110C : Alarm mask (bit i set if reading i>200) = 0x91  (readings 0, 4, 7)
;   0x1110 : OK mask (alarm mask XOR 0xFF)           = 0x6E
;   0x1114 : Hours                                   = 12    (0x0C)
;   0x1118 : Minutes                                 = 34    (0x22)
;   0x111C : Seconds                                 = 56    (0x38)
;   0x1120 : Average sampling interval (seconds)     = 5662  (0x161E)
;   0x1124 : Status (bit0=any alarm, bit1=all alarm, bit2=mask error, bit3=mean check error) = 1
;   0x1128 : Number of ASCII digits written          = 5
;   0x1140 - 0x115C : Fahrenheit readings (tenths F) = 707, 257, 536, 302, 860, 401, 176, 770
;                     (0x2C3, 0x101, 0x218, 0x12E, 0x35C, 0x191, 0x0B0, 0x302)
;   0x1180 - 0x1194 : ASCII digits of variance       = 0x31, 0x37, 0x37, 0x33, 0x34, 0x00 ("17734")

    ORG #0x1000                       ;Input data begins at address @0x1000

_sensor_data:
    ; Reading 0: Warm room, 21.5 C (215 = 0xD7), above alarm threshold
    FCB #0x000000D7;

    ; Reading 1: Cold outdoors, -3.5 C (-35 = 0xFFFFFFDD), negative input for signed divide
    FCB #0xFFFFFFDD;

    ; Reading 2: Mild, 12.0 C (120 = 0x78)
    FCB #0x00000078;

    ; Reading 3: Near freezing, -1.0 C (-10 = 0xFFFFFFF6), negative input
    FCB #0xFFFFFFF6;

    ; Reading 4: Hot spot, 30.0 C (300 = 0x12C), above alarm threshold
    FCB #0x0000012C;

    ; Reading 5: Cool, 4.5 C (45 = 0x2D)
    FCB #0x0000002D;

    ; Reading 6: Freezer, -8.0 C (-80 = 0xFFFFFFB0), negative input
    FCB #0xFFFFFFB0;

    ; Reading 7: Warm, 25.0 C (250 = 0xFA), above alarm threshold
    FCB #0x000000FA;

    ; Log duration: 45296 seconds = 12 h 34 min 56 s (0xB0F0)
    FCB #0x0000B0F0;

    ORG #0x0;

_setup:
    MOV  R0, #0x1000;             R0 = Base memory address of the sensor readings
    MOV  R1, #8;                  R1 = Total number of readings
    MOV  R2, #0;                  R2 = Loop index counter
    MOV  R3, #0;                  R3 = Running sum of readings (signed)
    MOV  R10, #0x1100;            R10 = Base memory address of the output area
    MOV  R11, #0;                 R11 = Alarm bitmask accumulator
    MOV  R7, #1;                  R7 = Walking bit (1 << index) used to build the alarm mask

_pass1_loop:
    ; Loop Termination Check
    CMP  R2, R1;                  Compare loop index (R2) against total count (R1)
    B.GE _pass1_done;             If index >= count, first pass is finished

    ; Load Current Reading
    LSL  R9, R2, #2;              R9 = R2 * 4 (byte offset of current reading)
    ADD  R9, R0, R9;              R9 = Absolute address of current reading
    LOAD R4, R9, #0;              R4 = Signed reading in tenths of a degree C

    ; Accumulate Sum
    ADD  R3, R3, R4;              Sum += reading

    ; Celsius to Fahrenheit: F = (C * 9) / 5 + 320 (tenths of a degree). Signed divide truncates toward zero.
    MUL  R5, R4, #9;              R5 = C * 9
    DIVS R5, R5, #5;              R5 = (C * 9) / 5 (signed immediate divide)
    ADD  R5, R5, #320;            R5 = Fahrenheit in tenths (adds the 32.0 degree offset)

    ; Store Fahrenheit Value at 0x1140 + 4 * index
    LSL  R9, R2, #2;              R9 = R2 * 4
    ADD  R9, R10, R9;             R9 = output base + offset
    ADD  R9, R9, #0x40;           R9 = address inside the Fahrenheit array
    STOR R5, R9, #0;              Store converted reading

    ; Alarm Check: reading > 20.0 C (200 tenths) using a signed compare
    CMP  R4, #200;                Compare reading against alarm threshold
    B.LE _no_alarm;               If reading <= 200 (signed), no alarm for this sensor
    OR   R11, R11, R7;            Set this sensor's bit in the alarm mask (register OR)

_no_alarm:
    LSL  R7, R7, #1;              Move walking bit to the next sensor
    ADD  R2, R2, #1;              Increment loop counter
    B    _pass1_loop;             Process next reading

_pass1_done:
    ; Signed Mean = Sum / Count. The remainder is automatically placed in R12 by the divide.
    DIVS R6, R3, R1;              R6 = Mean (signed register divide), R12 = remainder
    MOV  R7, R12;                 R7 = Remainder, copied out of R12 before another MUL/DIV overwrites it

    STOR R6, R10, #0;             Output +0x00 = Mean
    ADD  R9, R10, #4;             R9 = address of output +0x04
    STOR R7, R9, #0;              Output +0x04 = Mean remainder

    ; Verify Mean: (Mean * Count) + Remainder must equal the original sum
    MULS R8, R6, R1;              R8 = Mean * Count (signed register multiply, upper bits go to R12)
    ADD  R8, R8, R7;              R8 = Reconstructed sum
    MOV  R2, #0;                  R2 = Status word (index register is free until pass 2)
    CMP  R8, R3;                  Compare reconstructed sum against the true sum
    B.EQ _mean_verified;          If equal, the divide was correct
    OR   R2, R2, #8;              Status bit 3 = mean verification error

_mean_verified:
    ; Alarm Mask, OK Mask and Status Word
    ADD  R9, R10, #0x0C;          R9 = address of output +0x0C
    STOR R11, R9, #0;             Output +0x0C = Alarm mask

    CMP  R11, #0;                 Were any alarms raised?
    B.EQ _no_any_alarm;           If mask is zero skip
    OR   R2, R2, #1;              Status bit 0 = at least one sensor in alarm (immediate OR)

_no_any_alarm:
    XORS R8, R11, #0xFF;          R8 = OK mask (invert the 8 sensor bits); Z=1 only if all sensors in alarm
    B.NE _not_all_alarm;          If any sensor is OK, skip
    OR   R2, R2, #2;              Status bit 1 = all sensors in alarm

_not_all_alarm:
    ADD  R9, R10, #0x10;          R9 = address of output +0x10
    STOR R8, R9, #0;              Output +0x10 = OK mask

    AND  R9, R11, R8;             Alarm mask AND OK mask must always be zero (register AND)
    CMP  R9, #0;                  Check for overlap
    B.EQ _masks_consistent;       No overlap, the masks are consistent
    OR   R2, R2, #4;              Status bit 2 = mask consistency error

_masks_consistent:
    ADD  R9, R10, #0x24;          R9 = address of output +0x24
    STOR R2, R9, #0;              Output +0x24 = Status word

    ; Pass 2: Variance = (sum of (reading - mean)^2) / count
    MOV  R2, #0;                  Reset loop index
    MOV  R3, #0;                  R3 = Sum of squared deviations (reuse sum register)

_pass2_loop:
    CMP  R2, R1;                  Compare loop index against total count
    B.GE _pass2_done;             If index >= count, second pass is finished

    LSL  R9, R2, #2;              R9 = R2 * 4
    ADD  R9, R0, R9;              R9 = Absolute address of current reading
    LOAD R4, R9, #0;              R4 = Signed reading

    SUB  R5, R4, R6;              R5 = Deviation from mean (may be negative)
    MULS R5, R5, R5;              R5 = Deviation squared (signed register multiply, always positive)
    ADD  R3, R3, R5;              Accumulate squared deviation

    ADD  R2, R2, #1;              Increment loop counter
    B    _pass2_loop;             Process next reading

_pass2_done:
    DIV  R3, R3, R1;              R3 = Variance (unsigned register divide, sum of squares is non-negative)
    ADD  R9, R10, #8;             R9 = address of output +0x08
    STOR R3, R9, #0;              Output +0x08 = Variance

    ; Time Formatting: Duration in seconds -> HH:MM:SS, and average sampling interval
    LSL  R9, R1, #2;              R9 = Count * 4
    ADD  R9, R0, R9;              R9 = Address just past the readings (holds the log duration)
    LOAD R4, R9, #0;              R4 = Log duration in seconds

    DIV  R8, R4, R1;              R8 = Average sampling interval = duration / count (unsigned register divide)
    ADD  R9, R10, #0x20;          R9 = address of output +0x20
    STOR R8, R9, #0;              Output +0x20 = Average interval in seconds

    DIV  R5, R4, #3600;           R5 = Hours (unsigned immediate divide), R12 = seconds left over
    MOV  R4, R12;                 R4 = Seconds left after removing whole hours (read from remainder register)

    DIV  R7, R4, #60;             R7 = Minutes (unsigned immediate divide), R12 = seconds left over
    MOV  R4, R12;                 R4 = Remaining seconds (0-59)

    ADD  R9, R10, #0x14;          R9 = address of output +0x14
    STOR R5, R9, #0;              Output +0x14 = Hours
    ADD  R9, R10, #0x18;          R9 = address of output +0x18
    STOR R7, R9, #0;              Output +0x18 = Minutes
    ADD  R9, R10, #0x1C;          R9 = address of output +0x1C
    STOR R4, R9, #0;              Output +0x1C = Seconds

    ; Variance to ASCII: divide by 10 repeatedly, PUSH each remainder (least significant digit first)
    MOV  R7, #10;                 R7 = Divisor held in a register for the register divide
    MOV  R2, #0;                  R2 = Number of digits produced

_push_digits:
    DIV  R5, R3, R7;              R5 = Quotient = value / 10 (unsigned register divide), R12 = remainder
    MOV  R8, R12;                 R8 = Remainder = current decimal digit (0-9)
    PUSH R8;                      Push digit onto the stack
    ADD  R2, R2, #1;              Count the digit
    MOV  R3, R5;                  Value = Quotient
    CMP  R3, #0;                  Any digits left?
    B.NE _push_digits;            Keep going until the quotient reaches zero

    ADD  R9, R10, #0x28;          R9 = address of output +0x28
    STOR R2, R9, #0;              Output +0x28 = Number of digits
    ADD  R9, R10, #0x80;          R9 = Address of the ASCII output buffer

_pop_digits:
    CMP  R2, #0;                  Any digits left on the stack?
    B.EQ _digits_done;            If none remain, finish

    POP  R8;                      Pop digit (now most significant digit first)
    ADD  R8, R8, #0x30;           Convert 0-9 to ASCII '0'-'9'
    STOR R8, R9, #0;              Store ASCII character
    ADD  R9, R9, #4;              Advance buffer pointer by one word
    SUB  R2, R2, #1;              One fewer digit on the stack
    B    _pop_digits;             Pop next digit

_digits_done:
    MOV  R8, #0;                  Null terminator value
    STOR R8, R9, #0;              Terminate ASCII string

    HALT;                         Terminate execution