import RPi.GPIO as GPIO
from time import sleep

GPIO.setmode(GPIO.BCM) # Use actual GPIO numbers

# GPIO Definitions
rows = [26, 19, 13, 6] # All GPIO pins correspondng to the various rows
cols = [5, 22, 27, 17] # All GPIO pins correspondng to the various columns
SSD_pins = [21, 20, 16, 12, 25, 24, 23, 18] # All GPIO pins correspondng to the SSD
CLK = 4  # DFF CLK GPIO pin


star_state = 0
output = None
display_on = True

# Setup for GPIO Pins
for row in rows:
    GPIO.setup(row, GPIO.OUT)
    GPIO.output(row, GPIO.LOW)
for col in cols:
    GPIO.setup(col, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
for pin in SSD_pins:
    GPIO.setup(pin, GPIO.OUT)
    GPIO.output(pin, GPIO.LOW)
GPIO.setup(CLK, GPIO.OUT)
GPIO.output(CLK, GPIO.LOW)


# Function to turn all SSD gpios low
def reset():
    for pin in SSD_pins:
        if(pin == 18):      # control to star GPIO separate
            pass
        else:
            GPIO.output(pin, GPIO.LOW)
            pulse_clock()

# Function to pulse the DFF clock one cycle
def pulse_clock():
    GPIO.output(CLK, GPIO.HIGH)
    sleep(0.001)
    GPIO.output(CLK, GPIO.LOW)
    sleep(0.001)

#Turn the GPIOs on cooresponding to the '0' character
def show_0():
    reset()
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()

#Turn the GPIOs on cooresponding to the '1' character
def show_1():
    reset()
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '2' character
def show_2():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '3' character
def show_3():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '4' character
def show_4():
    reset()
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '5' character
def show_5():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '6' character
def show_6():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '7' character
def show_7():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '8' character
def show_8():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '9' character
def show_9():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the '*' character
def show_star():
    global star_state
    if star_state == 1:
        star_state = 0
        GPIO.output(18, GPIO.LOW)
        print("**Dot Off**")
        pulse_clock()
    elif star_state == 0:
        star_state = 1
        GPIO.output(18, GPIO.HIGH)
        print("**Dot On**")
        pulse_clock()
    
#Turn the GPIOs on cooresponding to the 'A' character
def show_A():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH) 
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the 'B' character
def show_B():
    reset()
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the 'C' character
def show_C():
    reset()
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock()
    
#Turn the GPIOs on cooresponding to the 'D' character
def show_D():
    reset()
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock()
    
def show_last():
    if output == 0: show_0()
    elif output == 1: show_1()
    elif output == 2: show_2()
    elif output == 3: show_3()
    elif output == 4: show_4()
    elif output == 5: show_5()
    elif output == 6: show_6()
    elif output == 7: show_7()
    elif output == 8: show_8()
    elif output == 9: show_9()
    elif output == "A": show_A()
    elif output == "B": show_B()
    elif output == "C": show_C()
    elif output == "D": show_D()
    #elif output == "*": show_star()
    
    
    
def keypad_to_terminal():
    global output, display_on, star_state
    for row in rows:
        # keep only ONE row active
        for r in rows:
            GPIO.output(r, GPIO.LOW)
        GPIO.output(row, GPIO.HIGH)

        for col in cols:
            if GPIO.input(col) == 1:
                on_row = row
                on_col = col

                if on_row == 26 and on_col == 5:
                    print(1); show_1(); output = 1
                elif on_row == 26 and on_col == 22:
                    print(2); show_2(); output = 2
                elif on_row == 26 and on_col == 27:
                    print(3); show_3(); output = 3
                elif on_row == 19 and on_col == 5:
                    print(4); show_4(); output = 4
                elif on_row == 19 and on_col == 22:
                    print(5); show_5(); output = 5
                elif on_row == 19 and on_col == 27:
                    print(6); show_6(); output = 6
                elif on_row == 13 and on_col == 5:
                    print(7); show_7(); output = 7
                elif on_row == 13 and on_col == 22:
                    print(8); show_8(); output = 8
                elif on_row == 13 and on_col == 27:
                    print(9); show_9(); output = 9
                elif on_row == 6 and on_col == 5:
                    print("*"); show_star();
                elif on_row == 6 and on_col == 22:
                    print(0);  show_0(); output = 0
                elif on_row == 6 and on_col == 27:
                    print("#")
                    display_on = not display_on
                    if display_on:
                        if(star_state == 1):
                            GPIO.output(18, GPIO.HIGH)
                            
                        show_last()
                        print("**Display on**")
                    else:
                        GPIO.output(18, GPIO.LOW)
                        reset()
                        print("**Display off**")
                elif on_row == 26 and on_col == 17:
                    print('A'); show_A(); output = "A"
                elif on_row == 19 and on_col == 17:
                    print('B'); show_B(); output = "B"
                elif on_row == 13 and on_col == 17:
                    print('C'); show_C(); output = "C"
                elif on_row == 6 and on_col == 17:
                    print('D'); show_D(); output = "D"
                else:
                    output = 100

                # debounce: wait for release
                while GPIO.input(col) == 1:
                    sleep(0.2)
                sleep(0.2)
                
                # return output

                # (optional) break so you don’t keep scanning after a press
                break

        GPIO.output(row, GPIO.LOW)
        
    

try:
    while True:
        keypad_to_terminal()
            
except KeyboardInterrupt:
    GPIO.cleanup()



