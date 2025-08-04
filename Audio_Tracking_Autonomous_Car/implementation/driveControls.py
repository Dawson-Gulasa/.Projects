#//CONTAINS ALL COMMANDS INVOLVING MOTOR CONTROL (INCLUDING CHECKPOINT C FUNCTIONS)//
from gpiozero import Motor
from gpiozero import Button
import time

time.sleep(1)

#Defining variables and constants
encoderL = 0
encoderR = 0
limSwitchPin = 26
mPinL1 = 17
mPinL2 = 18
mPinR1 = 6
mPinR2 = 12
duty = 0.65
motorMultiplier = 1.2

#Instantiating Motor objects
Rmotor = Motor(mPinR1,mPinR2, pwm=True)
Lmotor = Motor(mPinL2,mPinL1, pwm=True)

#Spin commands for checkpoint B. Spin motors with no time limit.
def spinLeft():
    Lmotor.backward(0.51)
    Rmotor.forward(0.51)

def spinSlowLeft():
    Rmotor.forward(0.55)

def spinRight():
    Lmotor.forward(0.50)
    Rmotor.backward(0.50)

#UntangleLeft:
def untangleLeft():
    spinLeft()
    time.sleep(8)
    stop()

def untangleRight():
    spinRight()
    time.sleep(9)
    stop()


#Turning commands for Checkpoint C. Includes both degree and time options.
def turnLeft(seconds):
    Rmotor.forward(0.50)
    time.sleep(seconds)
    stop()

def turnLeftDegrees(degrees):
    Rmotor.forward(0.50)
    #Uses a constant ratio that converts the desired degree turn to seconds
    time.sleep(0.00955555555555555555555555555556*degrees)
    stop()

def turnRightDegrees(degrees):
    Lmotor.forward(0.50)
    #Uses a constant ratio that converts the desired degree turn to seconds
    time.sleep(0.00955555555555555555555555555556*degrees)
    stop()

def turnRight(seconds):
    Lmotor.forward(0.65)
    time.sleep(seconds)
    stop()

#Makes car move straight for x seconds. Hard-Coded transfer function is used.
def straight(seconds):
    #Lmotor.forward(0.60)
    #time.sleep(0.04)
    Lmotor.forward(0.725)
    Rmotor.forward(0.65)
    time.sleep(seconds)
    stop()

def backwards(seconds):
    #Lmotor.forward(0.60)
    #time.sleep(0.04)
    time.sleep(0.5)
    Lmotor.backward(0.725)
    Rmotor.backward(0.65)
    time.sleep(seconds)
    stop()

#Arc commands for figure 8 movement in checkpoint C
def arcLeft(seconds):
    Lmotor.forward(0.4)
    Rmotor.forward(0.60)
    time.sleep(seconds)
    stop()

def arcRight(seconds):
    Lmotor.forward(0.5)
    Rmotor.forward(0.4)
    time.sleep(seconds)
    stop()

#Straight commands that adjust the robots' rear wheel to go straight after turning
def straightAfterTurnL(seconds):
    Lmotor.forward(0.60)
    time.sleep(0.10)
    stop()
    time.sleep(0.5)
    straight(seconds - 0.05)
    stop()

def straightAfterTurnR(seconds):
    Rmotor.forward(0.40)
    time.sleep(0.20)
    stop()
    time.sleep(0.22)
    straight(seconds)
    stop()    

#Stops all motors
def stop():
    Lmotor.stop()
    Rmotor.stop()

#Command for checkpoint B. Moves straight for up to 8 seconds
def kamikaze():
    limSwitch = Button(limSwitchPin, pull_up = False, bounce_time = 0.1)

    Lmotor.forward(0.60)
    time.sleep(0.04)
    Lmotor.forward(0.725)
    Rmotor.forward(0.65)
    startTime = time.time()
    while True:
        if limSwitch.value == 1:
            stop()
            break
    
    print("GOTCHA!")
    
    limSwitch.close()
    return time.time() - startTime 

#ACTUAL CHECKPOINT C TASK FUNCTIONS

#Full straight command for checkpoint C.
def driveStraight():
    straight(2.65) 
    stop()

#Full square command for checkpoint C.
def square():
    straight(2.65)
    time.sleep(0.75)
    #0 to 7
    for i in range(0, 7):
        turnLeft(1.1)
        time.sleep(0.75)
        straightAfterTurnL(2.65) 
        #straight(2.75)
        time.sleep(0.75)
    turnLeft(0.85)
    stop()

#Does a single figure 8 for checkpoint C. Figure starts in center.
def figureEightSingle():
    time.sleep(0.5)
    turnLeftDegrees(105)
    time.sleep(0.5)
    arcLeft(1.5)
    time.sleep(0.5)
    turnLeftDegrees(89)

    time.sleep(0.5)
    straightAfterTurnL(2)
    time.sleep(0.5)
    
    
    turnRightDegrees(100)
    time.sleep(0.5)
    arcRight(2.19)
    time.sleep(0.5)
    turnRightDegrees(82)
    time.sleep(0.5)
    straightAfterTurnR(1.8)
    time.sleep(0.5)

#Total figure 8 motion. Includes 2 single figure 8 statements.
def figureEight():
    time.sleep(2)
    straight(1)
    figureEightSingle()
    figureEightSingle()
    stop()
