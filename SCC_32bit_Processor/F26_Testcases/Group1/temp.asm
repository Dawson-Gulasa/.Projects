; Converts a hypothetical 32-bit Celsius temperature sensor output into Fahrenheit. Input is scaled times 100
; for more precise output (divide output by 100 to get value in Fahrenheit). AND is used to mask hypothetical
; sensor data that do not include temperature bits in the upper 2 bytes. MULS, DIV, and integer and register
; DIVS are used to adjust the scale of the input and confirm functionality of the instructions. OR is used to
; set bit 15 of the output to 1 as verification.

setup:
    MOV     R1, #25;            Input sensor reading
    MOV     R2, #0x00FF;        Mask sensor reading (pretend upper 2 bytes are other information)
    MOV     R3, #18000;
    MOV     R4, #5;             
    MOV     R5, #2;

convert:
    NOP;
    AND     R1, R1, R2;         Apply mask to sensor data
    MULS    R1, R1, R3;         Multiply by 9/5 or 1.8 times 10000 for more precision
    DIV     R1, R1, R4;         Divide by 5
    DIVS    R1, R1, R5;         Divide by 2
    DIVS    R1, R1, #0xA;       Divide by 10. The 18000 is now 180
    ADD     R1, R1, #0xC80;     Add 3200 (32 degree offset from conversion formula)
    OR      R1, R1, #0x8000;    Set bit 15 high
    XORS    R1, R1, #0x0;       Update flags for verification, R1 contains temp in F
    HALT;
