import RPi.GPIO as GPIO
from time import sleep
GPIO.setmode(GPIO.BCM)

rows = [26, 19, 13, 6]  # X1 = GPIO 25, X2 = GPIO 19, X3, = GPIO 6
cols = [5, 22, 27, 17] # Y1 = GPIO 5, Y2 = GPIO 22, Y3 = GPIO 27

keys = [[1,2,3, 'A'],[4,5,6, "B"],[7, 8, 9, 'D'],['*',0,'#', 'D']] # matrix of the keypad symbols for refernce 

for row in rows:                     #set up the rows as inputs
    GPIO.setup(row,GPIO.OUT)

for col in cols:
    GPIO.setup(col, GPIO.IN, pull_up_down=GPIO.PUD_DOWN ) #set up the columns as inputs, and set to internal pulldown

def keypad_to_terminal():
    for row in rows:
        GPIO.output(row, GPIO.HIGH)   #turn each one of the rows on individually
        on_row = row                  #set a variable to hold the current row
        for col in cols:              #loop through the columns reading one at a time
            if GPIO.input(col) == 1:
                on_col = col          #if a olumn reads high, set a variable to hold the column value
                
                #match the column value and row value to the cooresponding keypad character
                if on_row == 26 and on_col == 5:
                    print(1)
                if on_row == 26 and on_col == 22:
                    print(2)
                if on_row == 26 and on_col == 27:
                    print(3)
                if on_row == 19 and on_col == 5:
                    print(4)
                if on_row == 19 and on_col ==22:
                    print(5)
                if on_row == 19 and on_col == 27:
                    print(6)
                if on_row == 13 and on_col == 5:
                    print(7)
                if on_row == 13 and on_col == 22:
                    print(8)
                if on_row == 13 and on_col == 27:
                    print(9)                                                           
                if on_row == 6 and on_col == 22:
                    print(0)
                elif on_row == 26 and on_col == 17:
                    print('A')
                elif on_row == 19 and on_col == 17:
                    print('B')
                elif on_row == 13 and on_col == 17:
                    print('C')
                elif on_row == 6 and on_col == 17:
                    print('D')
                elif on_row == 6 and on_col == 5:
                    print('*') 
                   
                while GPIO.input(col) ==1: #debouncing, wont print another number until the button state goes low
                    sleep(0.01)
                sleep(0.05)

        GPIO.output(row, GPIO.LOW)  

try: 
    while True:
        keypad_to_terminal()
        # for row in rows:
        #     GPIO.output(row, GPIO.HIGH)   #turn each one of the rows on individually
        #     on_row = row                  #set a variable to hold the current row
        #     for col in cols:              #loop through the columns reading one at a time
        #         if GPIO.input(col) == 1:
        #             on_col = col          #if a olumn reads high, set a variable to hold the column value
                    
        #             #match the column value and row value to the cooresponding keypad character
        #             if on_row == 26 and on_col == 5:
        #                 print(1)
        #             if on_row == 26 and on_col == 22:
        #                 print(2)
        #             if on_row == 26 and on_col == 27:
        #                 print(3)
        #             if on_row == 19 and on_col == 5:
        #                 print(4)
        #             if on_row == 19 and on_col ==22:
        #                 print(5)
        #             if on_row == 19 and on_col == 27:
        #                 print(6)
        #             if on_row == 13 and on_col == 5:
        #                 print(7)
        #             if on_row == 13 and on_col == 22:
        #                 print(8)
        #             if on_row == 13 and on_col == 27:
        #                 print(9)                                                           
        #             if on_row == 6 and on_col == 22:
        #                 print(0)
        #             elif on_row == 26 and on_col = 17
        #                 print('A')
        #             elif on_row == 19 and on_col = 17
        #                 print('B')
        #             elif on_row == 13 and on_col = 17
        #                 print('C')
        #             elif on_row == 6 and on_col = 17
        #                 print('D')
                        
                    
        #             while GPIO.input(col) ==1: #debouncing, wont print another number until the button state goes low
        #                 sleep(0.01)
        #             sleep(0.05)    
                    
                    
        #     GPIO.output(row, GPIO.LOW)                            

except KeyboardInterrupt:
    sleep(0.1)
    GPIO.cleanup()
