import RPi.GPIO as GPIO
from time import sleep
GPIO.setmode(GPIO.BCM)

rows = [26, 19, 13, 6]  # X1 = GPIO 25, X2 = GPIO 19, X3, = GPIO 6
cols = [5, 22, 27] # Y1 = GPIO 5, Y2 = GPIO 22, Y3 = GPIO 27

SSD_pins = [21, 20, 16, 12, 25, 24, 23, 18]

clock = 4
GPIO.setup(clock, GPIO.OUT)

keys = [[1,2,3],[4,5,6],['*',0,'#']] # matrix of the keypad symbols

for row in rows:                     #set up the rows as inputs
    GPIO.setup(row,GPIO.OUT)
    
for pin in SSD_pins:                     #set up the SSD pins as outputs
    GPIO.setup(pin,GPIO.OUT)

for col in cols:
    GPIO.setup(col, GPIO.IN, pull_up_down=GPIO.PUD_DOWN ) #set up the columns as inputs, and set to internal pulldown


try:
    while True:
        for pin in SSD_pins:
            GPIO.output(pin, GPIO.HIGH)
            GPIO.output(clock, GPIO.HIGH)
            GPIO.output(pin, GPIO.LOW)
            GPIO.output(clock, GPIO.LOW)
            sleep(2)

except KeyboardInterrupt:
    sleep(0.1)
    GPIO.cleanup()

