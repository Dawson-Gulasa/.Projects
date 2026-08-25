#!/usr/bin/env python3
"""
Seven Segment Display Clock (Clock only, no timer)

Implements:
- START mode: on boot shows 00:00, LED off, dot off
- AUTO mode (key 'A'): uses datetime.now() to show current time HH:MM (12-hour),
  dot ON on the right-most hour digit when PM, dot OFF when AM
- MANUAL mode (key 'B'): user sets time in 24-hour entry (HHMM) with flashing digit prompt.
  Invalid entry turns LED on and keeps same digit flashing.
  After entry is complete, clock runs by incrementing internal time each second.
- '#' toggles all SSDs on/off (when turned back on, restores the correct value)
- "B B B" at any time returns to START mode (00:00, LED off, dot off)
- Simple debouncing: press detection + wait-for-release + small delay

Checksheet behaviors covered:
- Debouncing, # toggle, BBB reset
- Manual entry constraints and LED behavior
- Rollover from 08:59->09:00 and 11:59 PM -> 12:00 AM
"""

import RPi.GPIO as GPIO
from time import sleep
from datetime import datetime
from collections import deque

# -----------------------------
# GPIO Pin Definitions (BCM)
# -----------------------------
GPIO.setmode(GPIO.BCM)

rows = [26, 19, 13, 6]
cols = [5, 22, 27, 17]

# Segment lines shared by all displays via DFF "D" inputs
# Your ordering is assumed consistent with your show_0..show_9 functions.
SSD_pins = [21, 20, 16, 12, 25, 24, 23, 18]  # NOTE: 18 used as "dot" in your code

# DFF clock pins (one per digit): [H_tens, H_ones, M_tens, M_ones]
CLOCK_pins = [4, 10, 9, 11]

LED_pin = 1  # Consider changing if needed

DOT_PIN = 18  # dot segment line (same physical line as in SSD_pins)

# -----------------------------
# Timing + Flash Parameters
# -----------------------------
DEBOUNCE_PRESS_S = 0.03
DEBOUNCE_RELEASE_S = 0.10
FLASH_PERIOD_S = 0.25  # digit blink rate during manual entry

# Manual clock tick behavior
USE_SLEEP_DELAY = True  # set False to use crude busy-loop delay
BUSYWAIT_CAL = 2200000  # tune this constant on your Pi (bigger = longer delay)

# -----------------------------
# Setup GPIO
# -----------------------------
for r in rows:
    GPIO.setup(r, GPIO.OUT)
    GPIO.output(r, GPIO.LOW)

for c in cols:
    GPIO.setup(c, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

for p in SSD_pins:
    GPIO.setup(p, GPIO.OUT)
    GPIO.output(p, GPIO.LOW)

for cp in CLOCK_pins:
    GPIO.setup(cp, GPIO.OUT)
    GPIO.output(cp, GPIO.LOW)

GPIO.setup(LED_pin, GPIO.OUT)
GPIO.output(LED_pin, GPIO.LOW)

# -----------------------------
# Low-level DFF / Segment Helpers
# -----------------------------
def _reset_segments():
    """Drive all segment lines LOW (including dot)."""
    for p in SSD_pins:
        GPIO.output(p, GPIO.LOW)

def _pulse_clock(clock_pin):
    """Pulse a DFF clock to latch whatever is currently on the shared segment lines."""
    GPIO.output(clock_pin, GPIO.HIGH)
    sleep(0.001)
    GPIO.output(clock_pin, GPIO.LOW)
    sleep(0.001)

def _latch_blank(digit_index):
    """Blank (all segments off) a specific digit by latching all-low."""
    _reset_segments()
    _pulse_clock(CLOCK_pins[digit_index])

# -----------------------------
# Segment Patterns
# -----------------------------
# Instead of many show_X functions, use a pattern map.
# These are derived from your existing show_0..show_9 wiring choices.
# Each entry is a list of GPIO pins to set HIGH for that digit (excluding clock pulse).
DIGIT_TO_PINS = {
    0: [20, 16, 12, 25, 24, 23],
    1: [12, 23],
    2: [16, 12, 21, 25, 24],
    3: [16, 12, 21, 23, 24],
    4: [20, 21, 12, 23],
    5: [16, 20, 21, 23, 24],
    6: [16, 20, 21, 23, 24, 25],
    7: [16, 12, 23],
    8: [16, 20, 21, 23, 24, 25, 12],
    9: [16, 20, 21, 23, 12],
}

def latch_digit(digit_index, value, dot=False):
    """
    Latch one digit:
    - digit_index: 0..3
    - value: int 0..9 or None for blank
    - dot: True to light dot on this digit
    """
    _reset_segments()

    # dot segment line
    if dot:
        GPIO.output(DOT_PIN, GPIO.HIGH)

    if value is not None:
        pins = DIGIT_TO_PINS.get(int(value), [])
        for p in pins:
            GPIO.output(p, GPIO.HIGH)

    _pulse_clock(CLOCK_pins[digit_index])

    # Always return lines low after latch (DFF holds it)
    _reset_segments()

def latch_all_blank():
    """Turn all digits off (latch blank into each DFF)."""
    for i in range(4):
        _latch_blank(i)

def latch_display(digits, pm_dot=False):
    """
    Latch all 4 digits.
    digits: list of 4 ints (0..9) or None
    pm_dot: dot ON on the right-most hour digit (digit_index=1) when PM
    """
    for i in range(4):
        dot_here = (pm_dot and i == 1)
        latch_digit(i, digits[i], dot=dot_here)

# -----------------------------
# Keypad Scan + Decode
# -----------------------------
KEYMAP = {
    (26, 5): "1", (26, 22): "2", (26, 27): "3", (26, 17): "A",
    (19, 5): "4", (19, 22): "5", (19, 27): "6", (19, 17): "B",
    (13, 5): "7", (13, 22): "8", (13, 27): "9", (13, 17): "C",
    (6, 5):  "*", (6, 22): "0", (6, 27): "#", (6, 17): "D",
}

def get_key_nonblocking():
    """
    Scan keypad once and return a key string if a press is detected; else None.
    Debounce approach:
    - detect press
    - wait a short press-stability time
    - confirm still pressed
    - wait for release
    """
    # Drive rows one at a time
    for r in rows:
        # set all rows low, then current row high
        for rr in rows:
            GPIO.output(rr, GPIO.LOW)
        GPIO.output(r, GPIO.HIGH)

        for c in cols:
            if GPIO.input(c) == 1:
                # candidate press
                sleep(DEBOUNCE_PRESS_S)
                if GPIO.input(c) != 1:
                    continue  # bounce

                key = KEYMAP.get((r, c), None)

                # wait for release
                while GPIO.input(c) == 1:
                    sleep(0.01)
                sleep(DEBOUNCE_RELEASE_S)

                GPIO.output(r, GPIO.LOW)
                return key

        GPIO.output(r, GPIO.LOW)

    return None

# -----------------------------
# Delay methods (for later report)
# -----------------------------
def delay_seconds(seconds):
    """
    Two timing methods:
    - sleep-based (accurate/easy)
    - crude busywait (no library timing calls inside it)
    """
    if USE_SLEEP_DELAY:
        sleep(seconds)
    else:
        # crude, needs tuning using BUSYWAIT_CAL
        loops = int(BUSYWAIT_CAL * seconds)
        for _ in range(loops):
            pass

# -----------------------------
# Time Helpers
# -----------------------------
def to_12h_and_pm(hour24):
    """
    Convert 0..23 to (hour12 1..12) and pm flag.
    0 -> 12 AM, 12 -> 12 PM, 13 -> 1 PM, etc.
    """
    pm = (hour24 >= 12)
    h = hour24 % 12
    if h == 0:
        h = 12
    return h, pm

def digits_from_time_12h(hour24, minute):
    """Return [H_tens, H_ones, M_tens, M_ones] for 12-hour display plus pm flag."""
    h12, pm = to_12h_and_pm(hour24)
    hh = f"{h12:02d}"
    mm = f"{minute:02d}"
    return [int(hh[0]), int(hh[1]), int(mm[0]), int(mm[1])], pm

def validate_manual_digit(pos, entered_digits, candidate_char):
    """
    Validate digit-by-digit time entry in 24-hour format.
    pos: 0..3
    entered_digits: list of already accepted digits (ints)
    candidate_char: keypad key string
    Returns (ok_bool, digit_or_none)
    """
    if candidate_char is None:
        return (False, None)

    # Only numeric allowed during time-entry
    if candidate_char not in "0123456789":
        return (False, None)

    d = int(candidate_char)

    if pos == 0:
        # tens of hour: 0..2
        return (d <= 2, d)

    if pos == 1:
        # ones of hour depends on tens
        tens = entered_digits[0]
        if tens == 2:
            return (d <= 3, d)  # 20..23
        else:
            return (True, d)    # 00..19

    if pos == 2:
        # tens of minute: 0..5
        return (d <= 5, d)

    if pos == 3:
        # ones of minute: 0..9
        return (True, d)

    return (False, None)

# -----------------------------
# FSM States
# -----------------------------
STATE_START = "START"
STATE_AUTO = "AUTO"
STATE_MANUAL_ENTRY = "MANUAL_ENTRY"
STATE_MANUAL_RUN = "MANUAL_RUN"

# FSM Variables
state = STATE_START
display_enabled = True

# Display "registers" (what we restore after '#')
disp_digits = [0, 0, 0, 0]  # 4 digits on SSD
disp_pm_dot = False         # dot on digit 1 indicates PM

# Manual time registers (24-hour internal)
manual_hour24 = 0
manual_minute = 0

# For detecting BBB reset anywhere
last_keys = deque(maxlen=3)

def go_start():
    """Return to START mode: 00:00, LED off, dot off."""
    global state, disp_digits, disp_pm_dot, manual_hour24, manual_minute
    GPIO.output(LED_pin, GPIO.LOW)
    disp_digits = [0, 0, 0, 0]
    disp_pm_dot = False
    manual_hour24, manual_minute = 0, 0
    state = STATE_START
    if display_enabled:
        latch_display(disp_digits, pm_dot=disp_pm_dot)

def toggle_display():
    """'#' behavior: turn off all SSDs; if turned back on, restore current disp_*."""
    global display_enabled
    display_enabled = not display_enabled
    if not display_enabled:
        latch_all_blank()
    else:
        latch_display(disp_digits, pm_dot=disp_pm_dot)

def handle_global_keys(k):
    """
    Handle keys that should work in any state:
    - '#': display toggle
    - BBB: reset to START
    Returns True if the key was consumed here.
    """
    if k is None:
        return False

    # Track last 3 keys for BBB reset detection
    last_keys.append(k)
    if list(last_keys) == ["B", "B", "B"]:
        go_start()
        return True

    if k == "#":
        toggle_display()
        return True

    return False

# -----------------------------
# State Behaviors
# -----------------------------
def state_start_step(k):
    """
    START behavior:
    - show 00:00
    - wait for 'A' (AUTO) or 'B' (manual entry)
    """
    global state
    if not display_enabled:
        return

    if k == "A":
        GPIO.output(LED_pin, GPIO.LOW)
        state = STATE_AUTO
    elif k == "B":
        GPIO.output(LED_pin, GPIO.LOW)
        state = STATE_MANUAL_ENTRY

def state_auto_step():
    """
    AUTO mode:
    - read datetime.now()
    - convert to 12-hour, dot indicates PM on digit 1
    - update display (fast is ok; but you can optimize to only update when changed)
    """
    global disp_digits, disp_pm_dot

    now = datetime.now()
    hour24 = now.hour
    minute = now.minute

    digits, pm = digits_from_time_12h(hour24, minute)

    # update "registers"
    disp_digits = digits
    disp_pm_dot = pm

    if display_enabled:
        latch_display(disp_digits, pm_dot=disp_pm_dot)

def state_manual_entry():
    """
    Manual entry:
    - prompt digits left->right (HHMM in 24-hour format)
    - currently active digit flashes until valid numeric entry
    - invalid entry -> LED ON; stay on same digit
    """
    global state, disp_digits, disp_pm_dot, manual_hour24, manual_minute

    GPIO.output(LED_pin, GPIO.LOW)

    entered = [None, None, None, None]
    pos = 0
    flash_on = True

    # Start from whatever is currently latched in disp_digits (or 00:00)
    # but checksheet expects you to start flashing leftmost H after pressing B.
    entered = [None, None, None, None]
    disp_pm_dot = False  # dot off during entry until time is complete

    while True:
        # If display is disabled, we still accept input but we don't flash visibly.
        # When re-enabled, we restore whatever current "entered" state is.
        if display_enabled:
            # Build a "preview" list:
            preview = []
            for i in range(4):
                if entered[i] is None:
                    preview.append(0)  # show 0 for unset positions (optional)
                else:
                    preview.append(entered[i])

            # Flash the active position by latching blank or the preview value
            # while keeping the other digits steady.
            for i in range(4):
                if i == pos and flash_on:
                    latch_digit(i, None, dot=False)  # blank the active digit
                else:
                    v = preview[i] if entered[i] is not None else 0
                    latch_digit(i, v, dot=False)

        # Wait a bit, then flip flash state
        delay_seconds(FLASH_PERIOD_S)
        flash_on = not flash_on

        # Read key (nonblocking)
        k = get_key_nonblocking()
        if handle_global_keys(k):
            # BBB or # handled; if BBB happened, exit to START
            if state == STATE_START:
                return
            # if display was toggled back on, restore the current preview
            continue

        if k is None:
            continue

        # During entry, ignore A/C/D/* keys, treat as invalid (LED on)
        ok, digit = validate_manual_digit(pos, [d for d in entered if d is not None], k)
        if not ok:
            GPIO.output(LED_pin, GPIO.HIGH)
            continue

        # Accept digit
        GPIO.output(LED_pin, GPIO.LOW)
        entered[pos] = digit
        pos += 1

        # If complete, finalize manual time registers and switch to MANUAL_RUN
        if pos >= 4:
            hh = entered[0] * 10 + entered[1]
            mm = entered[2] * 10 + entered[3]
            manual_hour24 = hh
            manual_minute = mm

            # Compute display in 12-hour format + PM dot
            disp_digits, disp_pm_dot = digits_from_time_12h(manual_hour24, manual_minute)

            if display_enabled:
                latch_display(disp_digits, pm_dot=disp_pm_dot)

            state = STATE_MANUAL_RUN
            return

def state_manual_run_step():
    """
    Manual-run mode:
    - increments internal (hour24, minute) every 60 seconds
    - updates display each second (safe) or each minute (optimized)
    """
    global manual_hour24, manual_minute, disp_digits, disp_pm_dot

    # We update once per second. Use a simple 60-count loop for minutes.
    # If your loop timing drifts, you’ll tune delay_seconds() / BUSYWAIT_CAL later.
    for _ in range(60):
        # allow keypad actions during the second ticks
        k = get_key_nonblocking()
        if handle_global_keys(k):
            if state == STATE_START:
                return
            # '#' toggle has already happened; just keep going
        else:
            # In MANUAL_RUN, 'A' could switch to AUTO (optional but helpful)
            if k == "A":
                GPIO.output(LED_pin, GPIO.LOW)
                # Switch modes immediately
                globals()["state"] = STATE_AUTO
                return

        # Keep display stable (restore after #)
        if display_enabled:
            latch_display(disp_digits, pm_dot=disp_pm_dot)

        delay_seconds(1.0)

    # One minute elapsed -> increment time
    manual_minute += 1
    if manual_minute >= 60:
        manual_minute = 0
        manual_hour24 += 1
        if manual_hour24 >= 24:
            manual_hour24 = 0

    disp_digits, disp_pm_dot = digits_from_time_12h(manual_hour24, manual_minute)

    if display_enabled:
        latch_display(disp_digits, pm_dot=disp_pm_dot)

# -----------------------------
# Main
# -----------------------------
def main():
    global state

    # On power-up: 00:00, LED off, dot off
    go_start()

    try:
        while True:
            k = get_key_nonblocking()
            if handle_global_keys(k):
                # BBB or # already handled
                continue

            if state == STATE_START:
                state_start_step(k)

            elif state == STATE_AUTO:
                # allow switching to MANUAL via B
                if k == "B":
                    state = STATE_MANUAL_ENTRY
                else:
                    state_auto_step()
                delay_seconds(0.2)  # don't hammer CPU; update often enough

            elif state == STATE_MANUAL_ENTRY:
                state_manual_entry()

            elif state == STATE_MANUAL_RUN:
                state_manual_run_step()

            else:
                # safety fallback
                go_start()

    except KeyboardInterrupt:
        pass
    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    main()
