import RPi.GPIO as GPIO
from time import sleep

GPIO.setmode(GPIO.BCM) # Use actual GPIO numbers

# GPIO Definitions
rows = [26, 19, 13, 6] # All GPIO pins corresponding to the various rows
cols = [5, 22, 27, 17] # All GPIO pins corresponding to the various columns
SSD_pins = [21, 20, 16, 12, 25, 24, 23, 18] # All GPIO pins correspondng to the SSD
LED_pin = 1
CLOCK_pins = [4, 10, 9, 11] #Clock pins in consecutive order: 4 = leftmost SSD - 11 = Right most SSD

valid_press = [1,2,3,4,5,6,7,8,9,0, "*"] #characters that are a valid press

# list to hold previous state
display_memory = [None, None, None, None]

# Helper Variable Definitions
star_state = 0
output = None
display_on = True
current_clock_index = 0


# Setup for GPIO Pins
for row in rows:
    GPIO.setup(row, GPIO.OUT)
    GPIO.output(row, GPIO.LOW)
for col in cols:
    GPIO.setup(col, GPIO.IN, pull_up_down=GPIO.PUD_DOWN) #turn on internal pulldown resistors or columns 
for pin in SSD_pins:
    GPIO.setup(pin, GPIO.OUT)
    GPIO.output(pin, GPIO.LOW)
for pin in CLOCK_pins:
    GPIO.setup(pin, GPIO.OUT)
    GPIO.output(pin, GPIO.LOW)
GPIO.setup(LED_pin, GPIO.OUT, pull_up_down=GPIO.PUD_OFF) #turn off internal pulldown
GPIO.output(LED_pin, GPIO.LOW)

# Function to turn all SSD gpios low - Besides star, done separate
def reset(clock_pin):
    for pin in SSD_pins:
        if(pin == 18):      # control to star GPIO separate
            pass
        else:
            GPIO.output(pin, GPIO.LOW)

# Function to pulse the DFF clock one cycle, takes input clock pin
def pulse_clock(pin):
    GPIO.output(pin, GPIO.HIGH)
    sleep(0.001)
    GPIO.output(pin, GPIO.LOW)
    sleep(0.001)

#Turn the GPIOs on cooresponding to the '0' character
def show_0(clock):
    reset(clock)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

#Turn the GPIOs on cooresponding to the '1' character
def show_1(clock):
    reset(clock)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '2' character
def show_2(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '3' character
def show_3(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '4' character
def show_4(clock):
    reset(clock)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '5' character
def show_5(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '6' character
def show_6(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    pulse_clock(clock)
    
#Turn the GPIOs on cooresponding to the '7' character
def show_7(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

    
#Turn the GPIOs on cooresponding to the '8' character
def show_8(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock(clock)

    
#Turn the GPIOs on cooresponding to the '9' character
def show_9(clock):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock(clock)

    
#Turn the GPIOs on cooresponding to the '*' character
def show_star():
    global star_state, display_memory

    # Change star status & Print Status
    star_state = 0 if star_state == 1 else 1
    print("***Dot On***" if star_state else "**Dot Off**")

    # Saves digit on 2nd display
    digit = display_memory[1]

    # Change star output depending on status
    GPIO.output(18, GPIO.HIGH if star_state == 1 else GPIO.LOW)
    
    if digit is not None:
        key_map[digit](CLOCK_pins[1])
    else:
        reset(CLOCK_pins[1])
        pulse_clock(CLOCK_pins[1])

    # bring star GPIO back low after clock pulse
    GPIO.output(18, GPIO.LOW)


# Shows the digits previously on (used for "#" function)
def show_last(clock):
    if output == 0: show_0(clock)
    elif output == 1: show_1(clock)
    elif output == 2: show_2(clock)
    elif output == 3: show_3(clock)
    elif output == 4: show_4(clock)
    elif output == 5: show_5(clock)
    elif output == 6: show_6(clock)
    elif output == 7: show_7(clock)
    elif output == 8: show_8(clock)
    elif output == 9: show_9(clock)
    # elif output == "A": show_A(clock)
    # elif output == "B": show_B(clock)
    # elif output == "C": show_C(clock)
    # elif output == "D": show_D(clock)
    elif output == "*": show_star(CLOCK_pins[1])

#map of key presses and show character functions 
key_map = {0: show_0, 1: show_1, 2: show_2, 3: show_3, 4: show_4, 5: show_5, 6: show_6, 7: show_7, 8: show_8, 9: show_9, '*': show_star}
    
def keypad_to_terminal():
    global output, display_on, star_state, current_clock_index, display_memory
    for row in rows:
        # keep only ONE row active
        for r in rows:
            GPIO.output(r, GPIO.LOW)
        GPIO.output(row, GPIO.HIGH)

        for col in cols:
            if GPIO.input(col) == 1:
                on_row = row
                on_col = col
                
                # flag to check if number logic needs to be updated
                is_number_press = False 
                
                if on_row == 26 and on_col == 5:
                    print(1); is_number_press = True ; output = 1
                elif on_row == 26 and on_col == 22:
                    print(2); is_number_press = True; output = 2
                elif on_row == 26 and on_col == 27:
                    print(3); is_number_press = True; output = 3
                elif on_row == 19 and on_col == 5:
                    print(4); is_number_press = True; output = 4
                elif on_row == 19 and on_col == 22:
                    print(5); is_number_press = True; output = 5
                elif on_row == 19 and on_col == 27:
                    print(6); is_number_press = True; output = 6
                elif on_row == 13 and on_col == 5:
                    print(7); is_number_press = True; output = 7
                elif on_row == 13 and on_col == 22:
                    print(8); is_number_press = True; output = 8
                elif on_row == 13 and on_col == 27:
                    print(9); is_number_press = True; output = 9
                elif on_row == 6 and on_col == 22:
                    print(0);  is_number_press = True; output = 0

                # logic for star press
                elif on_row == 6 and on_col == 5:
                    print("*");
                    if display_on: #if the star is pressed update only SSD clock
                        show_star() #hard code SSD-2 clock pin
                        GPIO.output(LED_pin, GPIO.LOW) # Bring star GPIO back low

                #Logic for pound toggle 
                elif on_row == 6 and on_col == 27:
                    print("#")
                    display_on = not display_on # toggle display status
                    if display_on:
                        print("Display on")
                        GPIO.output(LED_pin, GPIO.LOW)
                        #restore dot

                        # prepare for displays to come back on
                        # setting star GPIO to its status
                        if(star_state == 1):
                            GPIO.output(18, GPIO.HIGH)
                        else: GPIO.output(18, GPIO.LOW)
                        
                        #restore numbers in the memory list
                        for i in range(4):
                            if i == 1 and star_state == 1:
                                GPIO.output(18, GPIO.HIGH)
                            else:
                                GPIO.output(18, GPIO.LOW)
                                
                            val = display_memory[i]
                            if val is not None:
                                key_map[val](CLOCK_pins[i])
                            else:
                                reset(CLOCK_pins[i])
                                pulse_clock(CLOCK_pins[i])
                                
                        # Bring star GPIO back low after updates
                        GPIO.output(18, GPIO.LOW)
                    else:
                        print("Display off")
                        #Wipe SSDs
                        GPIO.output(18, GPIO.LOW)
                        for pin in CLOCK_pins:
                            reset(pin)
                            pulse_clock(pin)

                elif on_row == 26 and on_col == 17:
                     print('A'); GPIO.output(LED_pin, GPIO.HIGH)
                elif on_row == 19 and on_col == 17:
                     print('B'); GPIO.output(LED_pin, GPIO.HIGH)
                elif on_row == 13 and on_col == 17:
                     print('C'); GPIO.output(LED_pin, GPIO.HIGH)
                elif on_row == 6 and on_col == 17:
                     print('D'); GPIO.output(LED_pin, GPIO.HIGH)

                #logic to update number
                if is_number_press: #if number flag is true turn the LED LOW and display
                    GPIO.output(LED_pin, GPIO.LOW)
                    if display_on:
                        if current_clock_index == 1 and star_state == 1:
                            GPIO.output(18, GPIO.HIGH)
                        else:
                            GPIO.output(18, GPIO.LOW)
                        
                        show_last(CLOCK_pins[current_clock_index])
                        GPIO.output(18, GPIO.LOW)
                        
                        display_memory[current_clock_index] = output
                        
                        #increment index
                        current_clock_index+= 1
                        if current_clock_index > 3:
                            current_clock_index = 0
                            
                # debounce: wait for release
                while GPIO.input(col) == 1:
                    sleep(0.2)
                sleep(0.2)

                # (optional) break so you don’t keep scanning after a press
                break

        GPIO.output(row, GPIO.LOW)
        
    

try:
    while True:
        keypad_to_terminal()
            
except KeyboardInterrupt:
    GPIO.cleanup()
    



