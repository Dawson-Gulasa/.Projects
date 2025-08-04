from gpiozero import Motor
from gpiozero import LightSensor
import time

#ldr = LightSensor(18)
#ldr.wait_for_light()
#print("Light detected!")
time.sleep(2)

encoderL = 0
encoderR = 0
mPinL1 = 18
mPinL2 = 19
mPinR1 = 12
mPinR2 = 13

Rmotor = Motor(mPinR2,mPinR1, pwm=True)
Lmotor = Motor(mPinL1,mPinL2, pwm=True)

Lmotor.forward(1)
time.sleep(2)
Lmotor.stop()
Rmotor.forward(1)
time.sleep(2)
Rmotor.stop()
time.sleep(1)
Rmotor.forward(1)
Lmotor.forward(1)
time.sleep(2)
Rmotor.stop()
Lmotor.stop()


