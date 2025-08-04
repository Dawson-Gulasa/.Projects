from gpiozero import Button
import time


#Sets Limit Swith to GPIO Pin 17
#Sets pull_up so that ground isn't required for the switch. 
#Sets debounce time to 100ms
button = Button(26, pull_up = False, bounce_time = 0.1)
button.wait_for_press()
print("The button was pressed!")
time.sleep(2)

button.close()








