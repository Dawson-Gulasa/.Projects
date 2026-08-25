# 7-Segment Display Clock + Keypad

# What this program does:
# - Drives four 7-segment displays through DFF-latched segment lines (SSD_pins) and per-digit clocks (CLOCK_pins).
# - Reads a 4x4 matrix keypad (rows/cols) to control modes and set time.
# - Supports three states:
#   IDLE: shows 00:00, waiting for mode select
#   AUTO: shows real (system) time in 12-hour format, dot indicates PM
#   MANUAL: user enters a time; then the clock runs forward from that entry

# Key controls:
# - A: enter AUTO mode
# - B: enter MANUAL entry mode
# - #: toggle display ON/OFF
# - BBB (three B presses within BBB_Window seconds): force reset to IDLE (00:00)
# - In MANUAL entry: digits only, if invalid -> LED error appears

import time
from time import sleep
from datetime import datetime

import RPi.GPIO as GPIO

# GPIO / HARDWARE CONFIG

GPIO.setmode(GPIO.BCM)  # Use BCM numbering

# Keypad matrix wiring
rows = [26, 19, 13, 6] # GPIO outputs (drive rows)
cols = [5, 22, 27, 17] # GPIO inputs (read columns)

# 7-segment segment GPIOs (wired to segment inputs of DFF latch)
SSD_pins = [21, 20, 16, 12, 25, 24, 23, 18]

# Error LED pin
LED_pin = 1

# Per-digit latch clocks left to right
CLOCK_pins = [4, 10, 9, 11] # [HH tens, HH ones (dot here), MM tens, MM ones]



# GLOBAL STATE

valid_press = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, "*"]

# Holds current digits to render: [H1, H2, M1, M2]
display_memory = [None, None, None, None]

# Dot (PM indicator) state used by show_star
star_state = 0

# Most recent keypad output
output = None

# Display enable (toggled by '#')
display_on = True

# Blink controls (used in MANUAL entry)
blink_on = True
blink_index = 0 # which digit index (0-3) is blinking during MANUAL entry
blink_period = 0.4 # seconds
last_blink_time = time.monotonic()

# Manual mode clock state
manual_h24 = 0
manual_m = 0
manual_s = 0
manual_iter_accum = 0
entry_h24 = None # temporary 24h hour built during entry (blink_index 0/1)

# Busy-loop calibration constant used by manual_tick_nonblocking()
ITERATIONS_PER_SECOND = 2_600_000  # calibrated value

# State machine / mode
state = "IDLE"
pm = False # PM flag for dot indicator on 2nd display
manual_done = False # MANUAL entry done -> clock runs

# BBB reset detector
b_count = 0
b_first_time = 0.0
BBB_Window = 2.0 # seconds



# GPIO SETUP

# Initialize all GPIO directions and default output levels.
# Inputs: None
# Outputs: None (configures hardware)
def gpio_init():
    # Keypad rows as outputs (default LOW)
    for row in rows:
        GPIO.setup(row, GPIO.OUT)
        GPIO.output(row, GPIO.LOW)

    # Keypad columns as inputs with pull-downs
    for col in cols:
        GPIO.setup(col, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

    # Segment pins as outputs (default LOW)
    for pin in SSD_pins:
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, GPIO.LOW)

    # Digit clock pins as outputs (default LOW)
    for pin in CLOCK_pins:
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, GPIO.LOW)

    # Error LED output
    GPIO.setup(LED_pin, GPIO.OUT, pull_up_down=GPIO.PUD_OFF)
    GPIO.output(LED_pin, GPIO.LOW)



# LOW-LEVEL DISPLAY HELPERS

# Clear (LOW) all segment GPIOs except the dot (GPIO 18).
# Inputs: clock_pin
# Outputs: None
def reset(clock_pin):
    for pin in SSD_pins:
        if pin == 18:
            # dot handled separately so it doesn't get unintentionally latched
            continue
        GPIO.output(pin, GPIO.LOW)

# Pulse a digit's DFF latch clock to capture the currently-driven segment lines.

# Inputs: pin (one of CLOCK_pins)
# Outputs: None
def pulse_clock(pin: int):
    GPIO.output(pin, GPIO.HIGH)
    sleep(0.001)
    GPIO.output(pin, GPIO.LOW)
    sleep(0.001)

# Latch a blank (all segments off) into a digit.
# Inputs: clock (the digit clock pin (CLOCK_pins[index]))
# Outputs: None
def show_blank(clock: int):
    reset(clock)
    pulse_clock(clock)



# PER-DIGIT "SHOW" FUNCTIONS
# NOTE: These functions drive *segment pins* then pulse the digit clock.

# Display digit 0 on the given digit clock.
def show_0(clock: int):
    reset(clock)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 1 on the given digit clock.
def show_1(clock: int):
    reset(clock)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 2 on the given digit clock.
def show_2(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 3 on the given digit clock.
def show_3(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 4 on the given digit clock.
def show_4(clock: int):
    reset(clock)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 5 on the given digit clock.
def show_5(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 6 on the given digit clock.
def show_6(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 7 on the given digit clock
def show_7(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 8 on the given digit clock.
def show_8(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(24, GPIO.HIGH)
    GPIO.output(25, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock(clock)

# Display digit 9 on the given digit clock.
def show_9(clock: int):
    reset(clock)
    GPIO.output(16, GPIO.HIGH)
    GPIO.output(20, GPIO.HIGH)
    GPIO.output(21, GPIO.HIGH)
    GPIO.output(23, GPIO.HIGH)
    GPIO.output(12, GPIO.HIGH)
    pulse_clock(clock)

# Toggle the dot (GPIO 18) on/off, and re-latch the second digit so the dot state is captured.
# Inputs: _unused_clock_pin
# Outputs: None
def show_star(_unused_clock_pin=None):
    global star_state, display_memory

    # Toggle dot state
    star_state = 0 if star_state == 1 else 1
    print("***Dot On***" if star_state else "**Dot Off**")

    # Dot only belongs to the 2nd display (index 1)
    digit = display_memory[1]

    # Drive dot pin while latching the digit so it gets stored with that digit
    GPIO.output(18, GPIO.HIGH if star_state == 1 else GPIO.LOW)

    if digit is not None:
        key_map[int(digit)](CLOCK_pins[1])
    else:
        reset(CLOCK_pins[1])
        pulse_clock(CLOCK_pins[1])

    # Always drop dot after the latch to prevent leaking into other digits
    GPIO.output(18, GPIO.LOW)


# Map of numeric digits to their segment-writer functions
key_map = {
    0: show_0, 1: show_1, 2: show_2, 3: show_3, 4: show_4,
    5: show_5, 6: show_6, 7: show_7, 8: show_8, 9: show_9,
    '*': show_star, 
}


# DISPLAY RENDERING (from display_memory)

# Latch a single digit (or blank) into the selected display.
# Inputs: index (0-3: digit position), digit (None for blank, or 0-9 for a numeral), 
#         pm (if True, drive the dot ONLY for index==1 (second display))
# Outputs: None
def write_digit(index: int, digit, pm: bool = False):
    clock = CLOCK_pins[index]

    # Dot is only used on the second display (index 1)
    GPIO.output(18, GPIO.HIGH if (pm and index == 1) else GPIO.LOW)

    if digit is None:
        show_blank(clock)
    else:
        key_map[int(digit)](clock)

    # Always drop dot after latching
    GPIO.output(18, GPIO.LOW)

# Render all 4 digits using display_memory.
# Inputs: pm (If True, dot indicates PM on the second display)
# Outputs: None
def render_display(pm: bool = False):
    global display_on, display_memory

    if not display_on:
        # When display is off, blank all digits
        for i in range(4):
            write_digit(i, None, pm=False)
        return

    for i in range(4):
        write_digit(i, display_memory[i], pm=pm)

# Render display_memory but blink the digit at blink_index when blink_on == False.
# Inputs: pm
# Outputs: None
def render_display_blink(pm: bool = False):
    global display_memory, blink_on, blink_index

    temp = display_memory.copy()
    if not blink_on:
        temp[blink_index] = None

    for i in range(4):
        write_digit(i, temp[i], pm=pm)



# KEYPAD SCANNING

# Scan the keypad ONE time and return a decoded key (debounced on release).
# Inputs: None
# Outputs: key (str) in {'0'-'9','*','#','A','B','C','D'} or None if no key pressed
def keypad_get_key():
    for row in rows:
        # Keep only one row active at a time
        for r in rows:
            GPIO.output(r, GPIO.LOW)
        GPIO.output(row, GPIO.HIGH)

        for col in cols:
            if GPIO.input(col) == 1:
                # Decode based on row/col
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

                # Debounce: wait for release
                while GPIO.input(col) == 1:
                    sleep(0.01)
                sleep(0.05)

                GPIO.output(row, GPIO.LOW)
                return key

        GPIO.output(row, GPIO.LOW)

    return None

# Used in earlier deliverable, kept for reference
def keypad_to_display():
    global output, display_on

    while True:
        for row in rows:
            # Keep only ONE row active
            for r in rows:
                GPIO.output(r, GPIO.LOW)
            GPIO.output(row, GPIO.HIGH)

            for col in cols:
                if GPIO.input(col) == 1:
                    on_row = row
                    on_col = col

                    output = None
                    is_number_press = False

                    if on_row == 26 and on_col == 5:
                        print(1); is_number_press = True; output = 1
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
                        print(0); is_number_press = True; output = 0

                    elif on_row == 6 and on_col == 5:
                        print("*")
                        output = "star"

                    elif on_row == 6 and on_col == 27:
                        print("#")
                        output = "hash"
                        display_on = not display_on
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

                    # Debounce: wait for release
                    while GPIO.input(col) == 1:
                        sleep(0.2)
                    sleep(0.2)

                    GPIO.output(row, GPIO.LOW)
                    return output

        GPIO.output(row, GPIO.LOW)

    sleep(0.005)


# ERROR / STATUS HELPERS

# Turn the error LED on/off.
# Inputs: on (True -> LED on, False -> LED off)
# Outputs: None
def set_error(on: bool):
    GPIO.output(LED_pin, GPIO.HIGH if on else GPIO.LOW)

# Latch 0 into all 4 digits.
# Inputs: None
# Outputs: None
def display_zeros():
    GPIO.output(18, GPIO.LOW)
    for i in range(4):
        show_0(CLOCK_pins[i])


# TIME / CONVERSION HELPERS

# Read system time and populate globals used by AUTO mode display functions.
# Inputs: None
# Outputs: None (updates globals: cur_hour_raw, cur_hour, cur_minute, and digit splits)
def get_time():
    global cur_hour, cur_minute, cur_minute_1, cur_minute_2
    global cur_hour_raw, cur_hour_1, cur_hour_2

    now = datetime.now()
    cur_hour_raw = now.hour
    cur_minute = now.minute

    minute_str = f"{cur_minute:02d}"
    cur_minute_1 = int(minute_str[0])
    cur_minute_2 = int(minute_str[1])

    # 12-hour conversion for display (AUTO mode)
    if cur_hour_raw > 12:
        cur_hour = cur_hour_raw - 12
    else:
        cur_hour = cur_hour_raw

    hour_str = f"{cur_hour:02d}"
    cur_hour_1 = int(hour_str[0])
    cur_hour_2 = int(hour_str[1])

# Display a single minute digit (0..9) on the given digit clock.
# Inputs: minute (integer 0-9), clock (digit clock pin)
# Outputs: None
def display_minute(minute: int, clock: int):
    match minute:
        case 0: show_0(clock)
        case 1: show_1(clock)
        case 2: show_2(clock)
        case 3: show_3(clock)
        case 4: show_4(clock)
        case 5: show_5(clock)
        case 6: show_6(clock)
        case 7: show_7(clock)
        case 8: show_8(clock)
        case 9: show_9(clock)


# Display a single hour digit or multi-digit hour on a digit clock (legacy logic).
# Also controls PM dot based on cur_hour_raw.
# Inputs: hour (hour digit (often cur_hour_1 or cur_hour_2)), clock (digit clock pin)
# Outputs:None
def display_hour(hour: int, clock: int):
    get_time()
    global cur_hour, cur_hour_raw

    # If hour < 10, force leading zero on first display
    if cur_hour < 10:
        show_0(CLOCK_pins[0])

    # Dot indicates PM
    GPIO.output(18, GPIO.HIGH if (cur_hour_raw >= 12) else GPIO.LOW)

    match hour:
        case 1: show_1(clock)
        case 2: show_2(clock)
        case 3: show_3(clock)
        case 4: show_4(clock)
        case 5: show_5(clock)
        case 6: show_6(clock)
        case 7: show_7(clock)
        case 8: show_8(clock)
        case 9: show_9(clock)
        case 10:
            show_1(clock); show_0(clock)
        case 11:
            show_1(clock); show_1(clock)
        case 12:
            show_1(clock); show_2(clock)

    GPIO.output(18, GPIO.LOW)

# AUTO mode: show system time across all 4 digits (HH:MM),
# with PM indicated by dot on second display.
# Inputs: None
# Outputs: None
def display_real_time():
    get_time()
    global cur_minute_1, cur_minute_2, cur_hour_1, cur_hour_2

    display_minute(cur_minute_1, CLOCK_pins[2])
    display_minute(cur_minute_2, CLOCK_pins[3])
    display_hour(cur_hour_1, CLOCK_pins[0])
    display_hour(cur_hour_2, CLOCK_pins[1])

# Convert a 24-hour hour value into 12-hour display value + PM flag.
# Inputs: h24 (integer hour in [0-23])
# Outputs: h12 (integer hour in [1-12]), pm_flag (True if PM, False if AM)
# Returns (None, None) if input is invalid.
def convert_24h_to_12h(h24: int):
    if h24 < 0 or h24 > 23:
        return None, None

    pm_flag = (h24 >= 12)

    h12 = h24 % 12
    if h12 == 0:
        h12 = 12

    return h12, pm_flag

# Overwrite display_memory with 12-hour digits for hour and minute.
# Inputs: h12(integer [1-12]), m (integer [0-59])
# Outputs: None (updates display_memory)
def load_12h_into_memory(h12: int, m: int):
    hour_str = f"{h12:02d}"
    min_str = f"{m:02d}"
    display_memory[0] = int(hour_str[0])
    display_memory[1] = int(hour_str[1])
    display_memory[2] = int(min_str[0])
    display_memory[3] = int(min_str[1])

# Get 24h-style HH and MM as integers from display_memory digits.
# Inputs: None
# Outputs: h = display_memory[0]*10 + display_memory[1], m = display_memory[2]*10 + display_memory[3]
def get_24h_from_memory():
    h = display_memory[0] * 10 + display_memory[1]
    m = display_memory[2] * 10 + display_memory[3]
    return h, m


# MANUAL CLOCK (NON-BLOCKING TICK USING CALIBRATED BURN LOOP)

# Busy loop used for timing calibration.
# Inputs: n (number of loop iterations)
# Outputs: None
def burn_iterations(n: int):
    i = 0
    while i < n:
        i += 1

# Initialize manual clock state from user-entered time.
# Inputs: None (uses entry_h24 and display_memory)
# Outputs: None (updates manual_h24/manual_m/manual_s/pm/display_memory)
def start_manual_clock_from_entry():
    global manual_h24, manual_m, manual_s, pm, manual_iter_accum, entry_h24

    # Prefer the explicitly built 24h hour if available
    h24 = entry_h24 if entry_h24 is not None else (display_memory[0] * 10 + display_memory[1])
    m = display_memory[2] * 10 + display_memory[3]

    manual_h24 = h24
    manual_m = m
    manual_s = 0
    manual_iter_accum = 0

    h12, pm_flag = convert_24h_to_12h(manual_h24)
    pm = pm_flag
    load_12h_into_memory(h12, manual_m)

# Advance the manual clock using small time slices (busy loop),
# updating the display once per minute (matches your existing behavior).
# Inputs: step_iters (iterations to burn per call (controls how often this is invoked))
# Outputs: None (updates manual time and display_memory)
def manual_tick_nonblocking(step_iters: int = 120_000):
    global manual_iter_accum, manual_s, manual_m, manual_h24, pm

    burn_iterations(step_iters)
    manual_iter_accum += step_iters

    while manual_iter_accum >= ITERATIONS_PER_SECOND:
        manual_iter_accum -= ITERATIONS_PER_SECOND

        manual_s += 1
        if manual_s >= 60:
            manual_s = 0
            manual_m += 1
            if manual_m >= 60:
                manual_m = 0
                manual_h24 = (manual_h24 + 1) % 24

            # Update display once per minute
            h12, pm_flag = convert_24h_to_12h(manual_h24)
            pm = pm_flag
            load_12h_into_memory(h12, manual_m)



# MANUAL ENTRY (BLINKING DIGIT ENTRY + VALIDATION)

# Handle one keypad keypress for manual time entry.
# Entry format (conceptually): HH:MM in 24-hour time.
# But display_memory is rewritten to 12-hour digits as soon as hour is complete
# , while entry_h24 preserves the actual 24h hour.
# Inputs: key (keypad key as string or None)
# Outputs: None (updates display_memory, blink_index, pm, manual_done, entry_h24)
def manual_entry_step(key):
    global display_memory, blink_index, pm, manual_done, entry_h24

    if manual_done:
        return

    if key is None:
        return

    # Only accept numeric digits during manual entry
    if not key.isdigit():
        set_error(True)
        return

    d = int(key)

    # blink_index mapping: 0=H1, 1=H2, 2=M1, 3=M2

    # H1: only 0-2 allowed for 24h time
    if blink_index == 0:
        if d > 2:
            set_error(True)
            return
        set_error(False)
        display_memory[0] = d
        blink_index = 1
        return

    # H2: depends on H1 (if H1==2 then H2 must be 0-3)
    if blink_index == 1:
        h1 = display_memory[0]
        if h1 is None:
            set_error(True)
            return
        if h1 == 2 and d > 3:
            set_error(True)
            return

        entry_h24 = h1 * 10 + d

        h12, pm_flag = convert_24h_to_12h(entry_h24)
        if h12 is None:
            set_error(True)
            return

        # Convert display to 12h now, but keep entry_h24 for actual manual time
        pm = pm_flag
        hour_str = f"{h12:02d}"
        display_memory[0] = int(hour_str[0])
        display_memory[1] = int(hour_str[1])

        set_error(False)
        blink_index = 2
        return

    # M1: 0-5
    if blink_index == 2:
        if d > 5:
            set_error(True)
            return
        set_error(False)
        display_memory[2] = d
        blink_index = 3
        return

    # M2: 0-9, then finalize entry
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


# STATE MACHINE HELPERS (IDLE / MANUAL / AUTO)

# Enter IDLE state: display 00:00, no blinking, no PM dot.
# Inputs: None
# Outputs: None (updates state + globals)
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

# Enter MANUAL state: reset entry to 00:00 and start blinking digit 0.
# Inputs: None
# Outputs: None (updates state + globals)
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

# Enter AUTO state: show real time from system clock.
# Inputs: None
# Outputs: None (updates state + globals)
def enter_auto():
    global state, manual_done
    state = "AUTO"
    manual_done = True
    set_error(False)



# SPECIAL KEY HANDLERS (# toggle, BBB reset)

# Toggle display ON/OFF when '#' is pressed.
# Inputs: key (keypad key or None)
# Outputs: True if handled, False otherwise
def handle_hash_toggle(key):
    global display_on
    if key != '#':
        return False

    display_on = not display_on
    print("Display ON" if display_on else "Display OFF")
    return True

# Detect 'BBB' sequence (3 presses of 'B' within BBB_Window seconds) and reset to IDLE.
# Inputs: key (keypad key or None)
# Outputs: True if a BBB reset occurred, False otherwise
def handle_BBB_reset(key):
    global b_count, b_first_time, BBB_Window

    if key != 'B':
        return False

    now = time.monotonic()

    # Start or restart the window
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

# clears BBB tracking if window expires.
# Inputs: None
# Outputs: None
def expire_BBB_if_needed():
    global b_count, b_first_time
    if b_count > 0 and (time.monotonic() - b_first_time) > BBB_Window:
        b_count = 0
        b_first_time = 0.0



# FUNCTIONS USED FOR TESTING, PREVIOUS DESIGNS, OR PREVIOUS DELIVERABLES

# def manual_tick_service():
#     global manual_s, manual_m, manual_h24, pm

#     key_seen = None
#     scan_every = 3
#     chunk_count = 0

    # for _ in one_second_delay_chunked():
    #     chunk_count += 1

        # if chunk_count % scan_every == 0:
        #     k = keypad_get_key()
        #     if k is not None:
        #         key_seen = k
        #         if handle_BBB_reset(k):
        #             return "BBB_RESET"

        # sleep(0.001)

    # manual_s += 1
    # if manual_s >= 60:
    #     manual_s = 0
    #     manual_m += 1
    #     if manual_m >= 60:
    #         manual_m = 0
    #         manual_h24 = (manual_h24 + 1) % 24

    #     h12, pm_flag = convert_24h_to_12h(manual_h24)
    #     pm = pm_flag
    #     load_12h_into_memory(h12, manual_m)

    # return key_seen


def manual_tick_one_second():
    global manual_h24, manual_m, manual_s, pm

    # one_second_delay()

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


def reset_first_display():
    for pin in SSD_pins:
        if pin == 18:
            continue
        GPIO.output(pin, GPIO.LOW)


def show_last(clock):
    global output
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
    elif output == "*": show_star(CLOCK_pins[1])



# MAIN

try:
    gpio_init()

    # Initialize into IDLE state (00:00)
    enter_idle()

    while True:
        now = time.monotonic()

        # Blink timing only during MANUAL entry (before manual_done)
        if state == "MANUAL" and (not manual_done):
            if (now - last_blink_time) >= blink_period:
                blink_on = not blink_on
                last_blink_time = now
        else:
            blink_on = True

        # Read keypad
        k = keypad_get_key()
        if k is not None:
            print("Key:", k)

        # Handle display toggle
        if handle_hash_toggle(k):
            # Immediately refresh after toggle
            render_display(pm=False)
            sleep(0.02)
            continue

        # Handle BBB reset (always takes priority)
        if handle_BBB_reset(k):
            render_display(pm=False)
            sleep(0.02)
            continue

        # STATE MACHINE
        if state == "IDLE":
            display_memory = [0, 0, 0, 0]
            render_display(pm=False)

            if k == 'A':
                enter_auto()
            elif k == 'B':
                enter_manual()

        elif state == "AUTO":
            # When display is off, we still call get_time() to keep globals updated
            if display_on:
                display_real_time()
            else:
                get_time()

        elif state == "MANUAL":
            if not manual_done:
                # User is entering time
                manual_entry_step(k)
                if display_on:
                    render_display_blink(pm=pm)
                else:
                    render_display(pm=False)
            else:
                # Time is running from the entered value
                manual_tick_nonblocking(step_iters=120_000)
                if display_on:
                    render_display(pm=pm)
                else:
                    render_display(pm=False)

        sleep(0.02)

except KeyboardInterrupt:
    pass
finally:
    GPIO.cleanup()