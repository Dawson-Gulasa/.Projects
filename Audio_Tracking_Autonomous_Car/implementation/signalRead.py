#//CONTAINS ALL COMMANDS INVOLVING ADC READING AND INTERPRETATION (INCLUDING THE CHECKPOINT B FUNCTION)//

from gpiozero import Button
import time
import driveControls
import numpy as np
import matplotlib.pyplot as plt


#getStrength takes three Button objects and maps them to an array.
#The returned value is the 4th value in the array, which is the sum of the first three binary values.
def getStrength(sig1, sig2, sig3):
    #sigArray is the main data input array. [s1 status, s2 status, s3 status, total strength]
    sigArray = [0, 0, 0, 0]
    if sig1.value == 1:
        sigArray[0] = 1
    else:
        sigArray[0] = 0
    if sig2.value == 1:
        sigArray[1] = 1
    else:
        sigArray[1] = 0
    if sig3.value == 1:
        sigArray[2] = 1
    else:
        sigArray[2] = 0

    sigArray[3] += (sigArray[0] + sigArray[1] + sigArray[2]) 
    return sigArray[3]

#"clock" returns the average of the strength values over a given number of readings (cCount)
#s1, s2, and s3 are Button objects connected to the ADC GPIO ports.
def clock(s1, s2, s3, cCount):
    count = 0
    strengthSum = 0

    while count < cCount:
        strengthSum += getStrength(s1, s2, s3)
        count += 1

    avg = strengthSum/count
    return avg


    if value > slopeGoal:
     slopeStatus = "Decreasing"
    elif value < -1 * slopeGoal:
        slopeStatus = "Increasing"
    else:
        slopeStatus = "Plateau"
    
    return slopeStatus

#Runs clock cycles to gather ADC data and prints results instantaneously for 2 minutes
#Mainly used to adjust the physical ADC potentiometers while monitoring output values
def calibrate(checkpoint):
    print("\nDisplaying Calibration for Checkpoint " + checkpoint + ": \n")

    if checkpoint == "A":
        sigPins = [13, 16, 19]
        count = 4000
    else: 
        sigPins = [14, 15, 24]
        count = 15000

    #Initializes ADC Signals as Button objects
    s1 = Button(sigPins[0], pull_up = False, bounce_time = 0.001)
    s2 = Button(sigPins[1], pull_up = False, bounce_time = 0.001)
    s3 = Button(sigPins[2], pull_up = False, bounce_time = 0.001)

    #Initializes variables
    calibrationTime = 120
    startTime = time.time()

    #While the time is under 4 minutes, clock cycles are ran (refer to clock())and printed instantly
    while (time.time() - startTime) < calibrationTime:
 
        currentVal = clock(s1 = s1, s2 = s2, s3 = s3, cCount= count)
        print("Strength for clock: " + str(currentVal))

    #Closes Button Objects
    s1.close()
    s2.close()
    s3.close()

#Main program for Checkpoint A - C6 Frequency
def checkpointA(checkpoint, newMax, numberToBeat, decayRate):
    
    #Determine ADC GPIO Ports to be monitored
    if checkpoint == "A":
        sigPins = [13, 16, 19]
        ceil = 8
    else: 
        sigPins = [14, 15, 24]
        ceil = 300
    #Creates Button objects
    s1 = Button(sigPins[0], pull_up = False, bounce_time = 0.001)
    s2 = Button(sigPins[1], pull_up = False, bounce_time = 0.001)
    s3 = Button(sigPins[2], pull_up = False, bounce_time = 0.001)

    #Start spinning right. Create start time. Initialize data for finding approx maximum this run.
    driveControls.spinRight()
    sTime = time.time()
    maxArrayLen = 3
    maxArray = [0] * maxArrayLen
    max = 0
    
    #For 6 seconds
    while time.time() - sTime < 6:
        
        #Get value and check if its a new max. If so, populate into array and shift other items over.
        currentVal = clock(s1 = s1, s2 = s2, s3 = s3, cCount = 5000)
        print("FINDING MAX... CURRENT VALUE: " + str(currentVal))
        if currentVal > maxArray[0]:
            for i in range(2):
                point = maxArrayLen - i - 1
                maxArray[point] = maxArray[point - 1]
            
            maxArray[0] = currentVal

            print("NEW MAX FOUND!!  MAX ARRAY: " + str(maxArray))

    driveControls.stop()

    #Sort through array to get rid of outliers & zeros before finding average
    if maxArray[0] > 1.5 * maxArray[1] or maxArray[0] > 1.5 * maxArray[2]:
        if maxArray[1] == 0 and maxArray[2] == 0:
            max = maxArray[0]
        elif maxArray[2] == 0:
            max = (maxArray[1] + maxArray[0]) / 2
        else:
            print("Max Binned for being Outlier...")
            max = (maxArray[1] + maxArray[2]) / 2
    else:
        max = (maxArray[0] + maxArray[1] + maxArray[2]) / 3

    #Create a scalar to bring all data up to a given "Goal integer" (5) for each run.
    #All data in the "Finding audio source" stage will be multiplied by this scalar.
    scalar = newMax / max

    print("Scalar = " + str(newMax) + "/" + str(max) + " = " + str(scalar) + "\n \n")

    #Rotate left around the same amount of time in order to untangle cables.
    time.sleep(1)
    driveControls.spinLeft()
    time.sleep(8)
    driveControls.stop()

    maxFound = 0

    time.sleep(1)

    #Start spinning right. Begin "Finding Audio Source" Stage
    driveControls.spinRight()
    decreaseFlag = 0

    sTime = time.time()

    #For 8 seconds, clock values and check if (current value * scalar) exceeds a given threshold integer
    #If so, check again and see if new value exceeds 80% of the original threshold. If so, stop the car because source is found.
    #The number to beat is multiplied by a value less than 1 every 2 seconds in order to increase sensitivity every rotation.
    while time.time() - sTime < 8:
        
        if time.time() - sTime > 2 * (decreaseFlag + 1):
            print("INCREASING SENS")
            decreaseFlag += 1
            numberToBeat = numberToBeat * decayRate

        currentVal = clock(s1 = s1, s2 = s2, s3 = s3, cCount = 5000) * scalar
        print("Clocking Value: " + str(currentVal))

        if currentVal > numberToBeat and currentVal < ceil:
            currentVal = clock(s1 = s1, s2 = s2, s3 = s3, cCount = 4000) * scalar
            print(" - Verifying Max: " + str(currentVal))

            if currentVal > numberToBeat * 0.9 and currentVal < ceil:
                time.sleep(0.1)
                driveControls.stop()
                maxFound = 1
                break
        
    #Print results to SSH for comedic effect
    if maxFound == 1:
        print("\n Papa Lebron James I have found a value that exceeds the max and I have stopped!")
    else:
        print("Sorry Papa James... I found nothing...")
    driveControls.stop()
#Main program for Checkpoint A - C8 Frequency
def checkpointB(fullSpinTime):
    #Determine ADC GPIO Ports to be monitored
    sigPins = [14, 15, 24]

    #Creates Button objects
    s1 = Button(sigPins[0], pull_up = False, bounce_time = 0.001)
    s2 = Button(sigPins[1], pull_up = False, bounce_time = 0.001)
    s3 = Button(sigPins[2], pull_up = False, bounce_time = 0.001)
    
    
    tDiff = 0
    max = 0
    maxTime = 0
    driveControls.spinLeft()
    time.sleep(fullSpinTime/2)
    sTime = time.time()
    while tDiff < fullSpinTime:
        tDiff = time.time() - sTime
        strength = clock(s1 = s1, s2 = s2, s3 = s3, cCount= 3000)
        print("Signal: " + str(strength) + " | Time: " + str(tDiff))
        if strength > max:
            max = strength
            maxTime = tDiff + fullSpinTime/2 - 0.2
  
            print("New Max! | Signal: " + str(strength) + " | Time: " + str(tDiff))
    
    time.sleep(fullSpinTime/2)
    driveControls.stop()

    time.sleep(3)

    driveControls.spinLeft()
    time.sleep(maxTime * 0.96)
    driveControls.stop

    #Closing ADC GPIOs
    s1.close()
    s2.close()
    s3.close()

