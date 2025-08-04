#//CONTAINS THE MAIN SCRIPT THAT THE PI RUNS ON STARTUP//

#readAndRun monitors the status of the dipswitch and calls other python functions accordingly
from gpiozero import Button
from gpiozero import LED
import time
import driveControls
import signalRead

#Calls other python functions based on string representation of dipswitch status
def commandCaller(commandString):
    if commandString == "Straight":
         driveControls.driveStraight()
    elif commandString == "Square":
         driveControls.square()
    elif commandString == "Figure 8":
        driveControls.figureEight()
    elif commandString == "Switch Test":
         driveControls.kamikaze()
    elif commandString == "Single":
        signalRead.checkpointB(fullSpinTime=1.79)
        driveControls.stop()
        
        #Performs the LED strobe before moving straight into audio source
        time.sleep(0.5)
        for i in range(0,4):
            ledArray[i].off()
            ledArray[i].blink(0.25,0.25)
            time.sleep(0.05)
        time.sleep(2)
        for i in range(0,4):
            ledArray[i].off()
            ledArray[i].blink(0.1,0.1)
            time.sleep(0.025)
        time.sleep(1)
        for i in range(0,4):
            ledArray[i].off()
            ledArray[i].blink(0.05,0.05)
        time.sleep(0.5)
        for i in range(0,4):
            ledArray[i].off()

        #Drives forward until car hits audio source
        driveControls.kamikaze()
    
    elif commandString == "Multiple":
        
        signalRead.checkpointB(fullSpinTime=1.79)
        driveControls.stop()
        time.sleep(3)
        driveControls.backwards(driveControls.kamikaze() * 0.9)
        time.sleep(3)
        signalRead.checkpointA("A", 5, 5.3, 0.93)
        driveControls.stop()
        time.sleep(3)
        driveControls.kamikaze()

    elif commandString == "Debug":
        #signalRead.calibrate("B")
        #time.sleep(3)
        signalRead.calibrate("B")



#Setup button objects to monitor dipswitch status
bit0 = Button(22, pull_up = False, bounce_time = 0.5)
bit1 = Button(27, pull_up = False, bounce_time = 0.5)
bit2 = Button(20, pull_up = False, bounce_time = 0.5)
bit3 = Button(21, pull_up = False, bounce_time = 0.5)

#Setup LED objects to display command status of car
led0 = LED(11)
led1 = LED(25)
led2 = LED(9)
led3 = LED(10)

#Initialize all other required variables
calledCommand = ""
starttime = time.time()
gpioArray = [bit0, bit1, bit2, bit3]
ledArray = [led0, led1, led2, led3]
bitArray = [0,0,0,0]
oldBitString = "0000"
sameCommandTime = starttime
command = ""

#Define dictionary that maps bitmap to its command definition
commandArray = {
    "0000" : "Don't Move",
    "1010" : "Debug",
    "1011" : "Switch Test",
    "1000" : "Single",
    "1001" : "Multiple",
    "1100" : "Straight",
    "1101" : "Figure 8",
    "1110" : "Square",
    "1111" : "Off"
}

#Use LEDs to signify program is turning on @ startup
for i in range (0,2):
    for i in range(0,4):
        ledArray[i].on()
    time.sleep(0.25)
    for i in range(0,4):
        ledArray[i].off()
    time.sleep(0.25)
                     

#Program runs indefinitely until 10-minute time limit is reached or the "Off" command is called
while (time.time() - starttime) < 600:
    bitString = ""

    #Obtain bit values and display LED representation of bitmap
    for i in range(0, 4):
        if gpioArray[i].value == 1:
            bitArray[3 - i] = 1
            ledArray[i].on()
        else:
            bitArray[3 - i] = 0
            ledArray[i].off()

        bitString += str(bitArray[i])

    if bitString == "0000":
         calledCommand = ""

    #Checks if the status of dipswitch has changed. If so, resets 7-second command debounce
    if (bitString != oldBitString):
        oldBitString = bitString
        print("Dipswitch Value Changed!: " + bitString)
        try:
            print("Command: " + commandArray[bitString])
        except KeyError as e:
             pass
        sameCommandTime = time.time()

    #If valid command is held for 7 seconds, Strobe LEDs and run commmand. 
    if ((sameCommandTime - time.time()) < -7) and (bitString != "0000") and commandArray[bitString] != calledCommand:
            print("Command Called! \n" + commandArray[bitString])
            
            #LED's start strobing to indicate program startup.
            for i in range(0,4):
                 ledArray[i].off()
                 ledArray[i].blink(0.25,0.25)
                 time.sleep(0.05)
            time.sleep(2)
            for i in range(0,4):
                 ledArray[i].off()
                 ledArray[i].blink(0.1,0.1)
                 time.sleep(0.025)
            time.sleep(1)
            for i in range(0,4):
                 ledArray[i].off()
                 ledArray[i].blink(0.05,0.05)
            time.sleep(0.5)
            for i in range(0,4):
                 ledArray[i].off()

            #Ends loop if command is "Off" (Currently 1111)
            if(commandArray[bitString] == "Off"):
                 break
            #Calls requested command and updates calledCommand variable
            #calledCommand variable prevents command from being called again instantly after running
            else:
                 commandCaller(commandArray[bitString])
                 calledCommand = commandArray[bitString]


#Close all GPIOs used in this program
bit0.close()
bit1.close()
bit2.close()
bit3.close()
led0.close()
led1.close()
led2.close()
led3.close()









