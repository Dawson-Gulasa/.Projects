from gpiozero import Button
import time

#Sets Limit Swith to GPIO Pin 17
#Sets pull_up so that ground isn't required for the switch. 
#Sets debounce time to 2s
bit0 = Button(27, pull_up = False, bounce_time = 0.5)
bit1 = Button(22, pull_up = False, bounce_time = 0.5)
bit2 = Button(20, pull_up = False, bounce_time = 0.5)
bit3 = Button(21, pull_up = False, bounce_time = 0.5)

starttime = time.time()
bitArray = [0,0,0,0]
oldBitString = "0000"
commandArray = {
    "0000" : "Don't Move",
    "1000" : "Single",
    "1001" : "Multiple",
    "1100" : "Straight",
    "1101" : "Figure 8",
    "1110" : "Square",
    "1111" : "Debug"
}
while (time.time() - starttime) < 120:

    if bit0.is_pressed:
        bitArray[3] = 1
    else:
        bitArray[3] = 0

    if bit1.is_pressed:
        bitArray[2] = 1
    else:
        bitArray[2] = 0
    
    if bit2.is_pressed:
        bitArray[1] = 1
    else:
        bitArray[1] = 0
    
    if bit3.is_pressed:
        bitArray[0] = 1
    else:
        bitArray[0] = 0
    
    bitString = str(bitArray[0]) + str(bitArray[1]) + str(bitArray[2]) + str(bitArray[3])

    if (bitString != oldBitString):
        oldBitString = bitString
        print("Dipswitch Value Changed!: " + bitString)
        print("Command: " + commandArray[bitString])

bit0.release()
bit1.release()
bit2.release()
bit3.release()









