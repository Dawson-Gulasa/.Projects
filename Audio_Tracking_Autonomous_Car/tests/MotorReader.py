from gpiozero import Motor
from gpiozero import DigitalInputDevice
import time
import csv

def readRPM(Duty : float, Motor : str):
    start = time.time()

    if Motor == "Left":
        encoder = LLightSensor
        motor = Lmotor
    else:   
        encoder = RLightSensor
        motor = Rmotor

    motor.forward(speed=Duty)
    count = 0
    #Status is 0 when dark and 1 when light is detected
    status = 0
    time.sleep(1)
    while (time.time() - start) < 10:
        
        if (status == 0 and encoder.value == 1):
            count += 1
        
        status = encoder.value

    Rotations = (count/20)
    RPM = Rotations*6 
    motor.stop()
    print("Motor: " + Motor + " | Duty Cycle: " + str(Duty) + " | RPM: " + str(RPM) )


    with open('RPMs.csv', 'w', newline='') as csvfile:
        spamwriter = csv.writer(csvfile, delimiter=' ',
                                quotechar='|', quoting=csv.QUOTE_MINIMAL)
        spamwriter.writerow(['Motor: ' + Motor, 'Duty Cycle: ' + str(Duty), 'RPM: ' + str(RPM)])


time.sleep(2)

ePinR = 21
ePinL = 25

mPinL1 = 18
mPinL2 = 19
mPinR1 = 12
mPinR2 = 13

Rmotor = Motor(mPinR2,mPinR1, pwm=True)
Lmotor = Motor(mPinL1,mPinL2, pwm=True)
#LLightSensor = DigitalInputDevice(25, pull_up=False)
RLightSensor = DigitalInputDevice(25, pull_up=False)

for i in range(65, 100, 2):
    readRPM(i/100, "Right")
    time.sleep(1)


