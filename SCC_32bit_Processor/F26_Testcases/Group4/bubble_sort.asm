    ORG     #0xD500;
    FCB     #0x5;
    FCB     #0x3;
    FCB     #0x7;
    FCB     #0x1;
    FCB     #0x4;
    FCB     #0x9;
    FCB     #0x6;
    FCB     #0x8;
    FCB     #0x2;
    FCB     #0xA;
    ORG     #0x0;
setup:
    MOV     R0, #0xD500;
    MOV     R4, #0xD500;   R4 placeholder for array
    MOV     R5, #0x9;    length of array
    MOV     R7, #0x0;    loop count value

mainloop:
    CMP     R5, #0x0;
    B.eq    exit;            exit if length is zero
    LOAD    R1, R4;          initial pointer to array 

iter:
    CMP     R5, R7;
    B.eq    iterexit;        exit pass if count = length
    B       compare;
compreturn:
    ADD     R4, R4, #0x4;    increment array pointer by 4
    ADD     R7, R7, #0x1;    increment count
    LOAD    R1, R4;          set value from pointer
    B       iter;

iterexit:
    SUB     R4, R4, R4;
    MOV     R4, #0xD500;     reset address to current first value
    SUB     R5, R5, #0x1;    subract one from length
    CLR     R7;              reset count to 0
    B       mainloop;


compare:
    LOAD    R2, R4, #0x4;    load second value to compare
    CMP     R2, R1;      compare two values
    B.mi    swap;            swap if b - a < 0
    B       compreturn;

swap:
    STOR    R1, R4, #0x4;   #store value one in address two
    STOR    R2, R4;          #store value two in address one
    B       compreturn;

exit:
    CLR R1
    MOV R0, #0xD500
    LOAD R1, R0
    MOV R0, #0xD504
    LOAD R1, R0
    MOV R0, #0xD508
    LOAD R1, R0
    MOV R0, #0xD50C
    LOAD R1, R0
    MOV R0, #0xD510
    LOAD R1, R0
    MOV R0, #0xD514
    LOAD R1, R0
    MOV R0, #0xD518
    LOAD R1, R0
    MOV R0, #0xD51C
    LOAD R1, R0
    MOV R0, #0xD520
    LOAD R1, R0
    MOV R0, #0xD524
    LOAD R1, R0
    HALT;
