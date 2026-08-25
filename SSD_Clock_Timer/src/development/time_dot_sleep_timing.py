import RPi.GPIO as GPIO
from time import sleep
import time

# date time setup
from datetime import datetime

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
blink_on = True
blink_index = 0 # which digit (0 .. 3) is blinking
blink_period = 0.4 # seconds
last_blink_time = time.monotonic()

# manual mode clock state
manual_h24 = 0
manual_m = 0
manual_s = 0
manual_iter_accum = 0
entry_h24 = None

ITERATIONS_PER_SECOND = 2_600_000 #11_695_960


def burn_iterations(n):
    i = 0
    while i < n:
        i += 1
        
def manual_tick_service():
    #advances the manual clock by 1 second using chunked delay
    global manual_s, manual_m, manual_h24, pm
    
    key_seen = None
    scan_every = 3
    chunk_count = 0
    
    for _ in one_second_delay_chunked():
        chunk_count += 1
        
        if chunk_count % scan_every == 0:
            k = keypad_get_key()
            if k is not None:
                key_seen = k
                if handle_BBB_reset(k):
                    return "BBB_RESET"
                
        sleep(0.001)
        
    manual_s += 1
    if manual_s >= 60:
        manual_s = 0
        manual_m += 1
        if manual_m >= 60:
            manual_m = 0
            manual_h24 = (manual_h24 + 1) % 24
            
        h12, pm_flag = convert_24h_to_12h(manual_h24)
        pm = pm_flag
        load_12h_into_memory(h12, manual_m)
        
    return key_seen
        

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

def show_blank(clock):
    reset(clock)
    pulse_clock(clock)
    
# write one digit helper
def write_digit(index, digit, pm=False):
    clock = CLOCK_pins[index]
    
    # Dot only for the 2nd display
    GPIO.output(18, GPIO.HIGH if (pm and index == 1) else GPIO.LOW)
    
    if digit is None:
        show_blank(clock)
    else:
        key_map[int(digit)](clock)
        
    # always drop dot ater the latch so it doesnt leak
    GPIO.output(18, GPIO.LOW)
    
# main render all 4 digits from memory
def render_display(pm=False):
    global display_memory, display_on
    
    if not display_on:
        # blank everything when display is off
        for i in range(4):
            write_digit(i, None, pm=False)
        return
    
    for i in range(4):
        write_digit(i, display_memory[i], pm=pm)
        
def render_display_blink(pm=False):
    global display_memory, blink_on, blink_index
    
    temp = display_memory.copy()
    if not blink_on:
        temp[blink_index] = None
        
    for i in range(4):
        write_digit(i, temp[i], pm=pm)
        
def manual_entry_step(key):
    global display_memory, blink_index, pm, manual_done, entry_h24
    
    if manual_done:
          return
	
    if key is None:
        return
	
	#only accept digits or manual entry
    if not key.isdigit():
        set_error(True)
        return
	
    d = int(key)
	
	# per digit validation rules
	#blink index 0 = H1, 1 = H2, 2 = M1, 3 = M2
	
	#H1: only 0-2 allowed in 24h time
    if blink_index == 0:
        if d>2:
            set_error(True)
            return
        set_error(False)
        display_memory[0] = d
        blink_index = 1
        return
    
	#H2 Depends on H1
    if blink_index ==1:
        h1 = display_memory[0]
        if h1 is None:
            set_error(True)
            return
		#if H1 = 2 then H2 must be 0-2
        if h1 ==2 and d>3:
            set_error(True)
            return
        
        entry_h24 = h1 * 10 + d
        
        h12, pm_flag = convert_24h_to_12h(entry_h24)
        if h12 is None:
            set_error(True)
            return
        
        pm = pm_flag
        hour_str = f"{h12:02d}"
        display_memory[0] = int(hour_str[0])
        display_memory[1] = int(hour_str[1])
        
        set_error(False)
        blink_index = 2
        return        
        
	# M1 must be 0-5
    if blink_index == 2:
        if d>5:
            set_error(True)
            return
        set_error(False)
        display_memory[2] = d
        blink_index = 3
        return
    
    if blink_index == 3:
        set_error(False)
        display_memory[3] = d
        
        h24 = entry_h24
        m = display_memory[2] * 10 + display_memory[3]
        
        if h24 is None or not (0 <= h24 <= 23 and 0 <= m <= 59):
            set_error(True)
            blink_index = 0
            entry_h24 = None
            return
        
        manual_done = True
        blink_index = 0
        start_manual_clock_from_entry()
        return
    
    
# Used to turn first hour display off if 24 hour time is <= 10 or >= 22
def reset_first_display():
    for pin in SSD_pins:
        if(pin == 18):      # control to star GPIO separate
            pass
        else:
            GPIO.output(pin, GPIO.LOW)

# continuously grabs the current time and assigns time variables correctly
def get_time():
	global cur_hour, cur_minute, cur_minute_1, cur_minute_2, cur_hour_raw, cur_hour_1, cur_hour_2
	now = datetime.now()
	cur_hour_raw = now.hour
	cur_minute = now.minute
	
	minute_str = f"{cur_minute:02d}"
	cur_minute_1 = int(minute_str[0])
	cur_minute_2 = int(minute_str[1])
	
	if(cur_hour_raw > 12):
		cur_hour = cur_hour_raw - 12
	else:
		cur_hour = cur_hour_raw
		
	hour_str = f"{cur_hour:02d}"
	cur_hour_1 = int(hour_str[0])
	cur_hour_2 = int(hour_str[1])

def display_hour(hour, clock):
	get_time()
	global cur_hour, cur_minute, cur_hour_raw
	if(cur_hour < 10):
		show_0(CLOCK_pins[0])
		
	if(cur_hour_raw >= 12):
		GPIO.output(18, GPIO.HIGH)
	else:
		GPIO.output(18, GPIO.LOW)
		
	match hour:
		case 1:
			show_1(clock)
		case 2:
			show_2(clock)
		case 3:
			show_3(clock)
		case 4:
			show_4(clock)
		case 5:
			show_5(clock)
		case 6:
			show_6(clock)
		case 7:
			show_7(clock)
		case 8:
			show_8(clock)
		case 9:
			show_9(clock)
		case 10:
			show_1(clock)
			show_0(clock)
		case 11:
			show_1(clock)
			show_1(clock)
		case 12:
			show_1(clock)
			show_2(clock)
		
	GPIO.output(18, GPIO.LOW)
			
def display_minute(minute, clock):
	get_time()
	global cur_hour, cur_minute, cur_minute_1, cur_minute_2, cur_hour_raw, cur_hour_1, cur_hour_2
		
	match minute:
		case 0:
			show_0(clock)
		case 1:
			show_1(clock)
		case 2:
			show_2(clock)
		case 3:
			show_3(clock)
		case 4:
			show_4(clock)
		case 5:
			show_5(clock)
		case 6:
			show_6(clock)
		case 7:
			show_7(clock)
		case 8:
			show_8(clock)
		case 9:
			show_9(clock)
	
	
def display_real_time():
	get_time()
	global cur_hour, cur_minute, cur_minute_1, cur_minute_2, cur_hour_raw, cur_hour_1, cur_hour_2
	display_minute(cur_minute_1, CLOCK_pins[2])
	display_minute(cur_minute_2, CLOCK_pins[3])
	display_hour(cur_hour_1, CLOCK_pins[0])
	display_hour(cur_hour_2, CLOCK_pins[1])

	
def keypad_to_display():
    global output, display_on, star_state, current_clock_index, display_memory
    
    while True:
        
        for row in rows:
            # keep only ONE row active
            for r in rows:
                GPIO.output(r, GPIO.LOW)
            GPIO.output(row, GPIO.HIGH)

            for col in cols:
                if GPIO.input(col) == 1:
                    on_row = row
                    on_col = col
                    
                    output = None
                    
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
                        output = "star"

                    #Logic for pound toggle 
                    elif on_row == 6 and on_col == 27:
                        print("#")
                        output = "hash"
                        display_on = not display_on # toggle display status
                        if display_on:
                            print("Display on")

                    elif on_row == 26 and on_col == 17:
                         print('A'); output = "A"
                    elif on_row == 19 and on_col == 17:
                         print('B'); output = "B"
                    elif on_row == 13 and on_col == 17:
                         print('C'); output = "C"
                    elif on_row == 6 and on_col == 17:
                         print('D'); output = "D"
                                
                    # debounce: wait for release
                    while GPIO.input(col) == 1:
                        sleep(0.2)
                    sleep(0.2)
                    
                    GPIO.output(row, GPIO.LOW)
                    return output

        GPIO.output(row, GPIO.LOW)
        
    sleep(0.005)

def keypad_get_key():
    #scan once
    for row in rows:
    #keep only one row active
        for r in rows:
            GPIO.output(r, GPIO.LOW)
        GPIO.output(row, GPIO.HIGH)
        
        for col in cols:
            if GPIO.input(col) == 1:
                #decode key
                if row == 26 and col == 5: key = '1'
                elif row == 26 and col == 22: key = '2'
                elif row == 26 and col == 27: key = '3'
                elif row == 19 and col == 5: key = '4'
                elif row == 19 and col == 22: key = '5'
                elif row == 19 and col == 27: key = '6'
                elif row == 13 and col == 5: key = '7'
                elif row == 13 and col == 22: key = '8'
                elif row == 13 and col == 27: key = '9'
                elif row == 6 and col == 22: key = '0'
                
                elif row == 6 and col == 5: key = '*'
                elif row == 6 and col == 27: key = '#'
                 
                elif row == 26 and col == 17: key = 'A'
                elif row == 19 and col == 17: key = 'B'
                elif row == 13 and col == 17: key = 'C'
                elif row == 6 and col == 17: key = 'D'
                else:
                    key = None
                #debounce: wait for release
                while GPIO.input(col) == 1:
                    sleep(0.01)
                sleep(0.05)
                
                GPIO.output(row, GPIO.LOW)
                return key
            
        GPIO.output(row, GPIO.LOW)
    return None
    
def display_zeros():
	GPIO.output(18, GPIO.LOW)
	i = 0
	while(i <= 3):
		show_0(CLOCK_pins[i])
		i = i + 1
	return
	
def set_error(on):
	GPIO.output(LED_pin, GPIO.HIGH if on else GPIO.LOW)
	
def get_24h_from_memory():
	#display memory = [H1, H2, M1, M2]
	h = display_memory[0] * 10 + display_memory[1]
	m = display_memory[2] * 10 +display_memory[3]
	return h,m 

# returns  (h12, pm_flag)	
def convert_24h_to_12h(h24):
	if h24 < 0 or h24 > 23:
		return None, None
		
	pm_flag = (h24 >= 12)
	
	h12 = h24 %12
	if h12 == 0:
		h12 = 12
	
	return h12, pm_flag

#overwrite display_memory with 12h digits
def load_12h_into_memory(h12,m):
	hour_str = f"{h12:02d}"
	min_str = f"{m:02d}"
	display_memory[0] = int(hour_str[0])
	display_memory[1] = int(hour_str[1])
	display_memory[2] = int(min_str[0])
	display_memory[3] = int(min_str[1])

def start_manual_clock_from_entry():
    global manual_h24, manual_m, manual_s, pm, manual_iter_accum, entry_h24
    
    
    h24 = entry_h24 if entry_h24 is not None else (display_memory[0] * 10 + display_memory[1])
    
    m = display_memory[2] * 10 + display_memory[3]
    
    
    manual_h24 = h24
    manual_m = m
    manual_s = 0
    manual_iter_accum = 0
    
    h12, pm_flag = convert_24h_to_12h(manual_h24)
    pm = pm_flag
    load_12h_into_memory(h12, manual_m)
    
def manual_tick_nonblocking():
    #wait 1 second, then advance manual clock by 1 second
    global manual_s, manual_m, manual_h24, pm

    sleep(1)

    manual_s += 1
    if manual_s >= 60:
        manual_s = 0
        manual_m += 1
        if manual_m >= 60:
            manual_m = 0
            manual_h24 = (manual_h24 + 1) % 24

        # update display once per minute
        h12, pm_flag = convert_24h_to_12h(manual_h24)
        pm = pm_flag
        load_12h_into_memory(h12, manual_m)
    
def manual_tick_one_second():
    # Busy - waits ~1 second using calibrated loop, then increments manual time by 1 second.
    global manual_h24, manual_m, manual_s, pm
    
    one_second_delay()
    
    manual_s += 1
    if manual_s >= 60:
        manual_s = 0
        manual_m += 1
        if manual_m >= 60:
            manual_m = 0
            manual_h24 = (manual_h24 + 1) % 24
        
        # update display ONCE per minute
        h12, pm_flag = convert_24h_to_12h(manual_h24)
        pm = pm_flag
        load_12h_into_memory(h12, manual_m)
        
        
def enter_idle():
	global state, display_memory, blink_index, pm, manual_done, blink_on, entry_h24
	state = "IDLE"
	display_memory = [0, 0, 0, 0]
	blink_index = 0
	pm = False
	manual_done = False
	blink_on = True
	entry_h24 = None
	set_error(False)
	
def enter_manual():
	global state, display_memory, blink_index, pm, manual_done, blink_on, manual_iter_accum, entry_h24
	state = "MANUAL"
	display_memory = [0, 0, 0, 0]
	blink_index = 0
	pm = False
	manual_done = False
	blink_on = True
	manual_iter_accum = 0
	entry_h24 = None
	set_error(False)
	
def enter_auto():
	global state, manual_done
	state = "AUTO"
	manual_done = True
	set_error(False)

def handle_hash_toggle(key):
    global display_on
    if key != '#':
        return False
    
    display_on = not display_on
    print("Display ON" if display_on else "Display OFF")
    return True

def handle_BBB_reset(key):
	global b_count, b_first_time
	
	if key != 'B':
		return False
		
	now = time.monotonic()
	
	if b_count == 0 or (now - b_first_time) > BBB_Window:
		b_count = 1
		b_first_time = now
		return False
		
	b_count += 1
	if b_count >= 3:
		b_count = 0
		b_first_time = 0.0
		print("BBB -> IDLE (00:00)")
		enter_idle()
		return True
	
	return False
	
def expire_BBB_if_needed():
	global b_count, b_first_time
	if b_count > 0 and (time.monotonic() - b_first_time) > BBB_Window:
		b_count = 0
		b_first_time = 0.0
		

try:
    display_memory = [0, 0, 0, 0]
    blink_index = 0
    pm = False 
    manual_done = False
    state = "IDLE"
    b_count = 0
    b_first_time = 0.0
    BBB_Window = 2.0
    enter_idle() #00:00 at selection mode

    
    while True:
        #keypad_to_terminal()
        now = time.monotonic()
       
        if state == "MANUAL" and (not manual_done):
            if(now - last_blink_time) >= blink_period:
                blink_on = not blink_on
                last_blink_time = now
        else:
            blink_on = True
			
        k = keypad_get_key()
        if k is not None:
            print("Key:", k)
            
        if handle_hash_toggle(k):
            if not display_on:
                render_display(pm=False)
            sleep(0.02)
            continue
			
        if handle_BBB_reset(k): # Always return to IDLE
            render_display(pm=False)
            sleep(0.02)
            continue
        
        if state == "IDLE":
            display_memory = [0, 0, 0, 0]
            if display_on:
                render_display(pm=False)
            else:
                render_display(pm=False)
                
            if k == 'A':
                enter_auto()
            elif k == 'B':
                enter_manual()
        
        elif state == "AUTO": # Pull real time
            if display_on:
                display_real_time()
            else:
                get_time()
			
        elif state == "MANUAL": # User enters time
            if not manual_done:
                manual_entry_step(k)
                if display_on:
                    render_display_blink(pm=pm)
                else:
                    render_display(pm=False)
            else:
                manual_tick_nonblocking()
                if display_on:
                    render_display(pm=pm)
                else:
                    render_display(pm=False)
				
        sleep(0.02)
        
except KeyboardInterrupt:
    GPIO.cleanup()
    
