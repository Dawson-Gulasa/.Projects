from gpiozero import Motor
import time

time.sleep(1)

encoderL = 0
encoderR = 0
mPinL1 = 17
mPinL2 = 18
mPinR1 = 6
mPinR2 = 12
duty = 0.65
motorMultiplier = 1.2

Rmotor = Motor(mPinR1,mPinR2, pwm=True)
Lmotor = Motor(mPinL2,mPinL1, pwm=True)

def turnLeft(seconds):
    Rmotor.forward(0.50)
    time.sleep(seconds)
    stop()

def turnRight(seconds):
    Lmotor.forward(0.65)
    time.sleep(seconds)
    stop()

def straight(seconds):
    Lmotor.forward(0.60)
    time.sleep(0.04)
    Lmotor.forward(0.725)
    Rmotor.forward(0.65)
    time.sleep(seconds)
    stop()

def straightAfterTurn(seconds):
    Lmotor.forward(0.60)
    time.sleep(0.1)
    Lmotor.forward(0.725)
    Rmotor.forward(0.65)
    time.sleep(seconds)
    stop()

def drawLeftArc(seconds):
    Lmotor.forward(0.7)
    Rmotor.forward(0.7)
    time.sleep(seconds)
    stop()

def stop():
    Lmotor.stop()
    Rmotor.stop()


#ACTUAL CHECKPOINT TASK FUNCTIONS

def driveStraight():
    straight(2) 

def square():
    straight(2)
    time.sleep(0.75)
    for i in range(0, 3):
        turnLeft(0.86)
        time.sleep(0.75)
        straightAfterTurn(2) 
        time.sleep(0.75)
    turnLeft(0.84)

#calling draw left arc
time.sleep(2)
drawLeftArc(2)



