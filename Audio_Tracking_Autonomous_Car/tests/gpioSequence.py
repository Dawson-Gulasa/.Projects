from gpiozero import LED
import time
time.sleep(2)
gpioList = [14,18,23,9,8,12,16,21,15,27,24,25,7,5,13,26,4,17,22,10,11,6,19,20]

for i in range(0, len(gpioList)):
    #Set LED to current GPIO Pin in list
    led = LED(gpioList[i])
    print("LED: " + str(gpioList[i]))
    led.on()
    time.sleep(0.5)
    led.off()
    led.close()

