# Takes commands from serial connection and acts on them
# Supports F5-F12 keys for now.

# imports
import sys
import board
import random
import usb_hid
import digitalio

# libraries
from time import sleep
from adafruit_hid.mouse import Mouse
from adafruit_hid.keycode import Keycode
from adafruit_hid.keyboard import Keyboard

# define devices
m = Mouse( usb_hid.devices )
k = Keyboard( usb_hid.devices )

# led function
led = digitalio.DigitalInOut(board.LED)
led.direction = digitalio.Direction.OUTPUT
def ledOn():
    led.value = True
def ledOff():
    led.value = False
def flash():
    ledOn()
    sleep(0.5)
    ledOff()

#key press function
def press(key):
    rand = round(random.uniform(0.1,0.3), 1)
    k.press(getattr(Keycode,key))
    sleep(rand)
    k.release(getattr(Keycode,key))
    flash()

# Bot program
def bot():
    while True:
        # get data from serial COM interface
        # readline expects a newline. If using pwsh use .WriteLine()
        data = sys.stdin.readline().strip()
        try:
            cmd, opt1, opt2 = data.split(",")
        except:
            cmd = data

        # mouse click
        if cmd == "mlb":
            m.click(Mouse.LEFT_BUTTON)
        elif cmd == "mrb":
            m.click(Mouse.RIGHT_BUTTON)

        # mouse move
        elif cmd == "mm":
            m.move(-100, -100, 0)

        # keyboard press
        elif cmd == "F5":
            press('F5')
        elif cmd == "F6":
            press('F6')
        elif cmd == "F7":
            press('F7')
        elif cmd == "F8":
            press('F8')
        elif cmd == "F9":
            press('F9')
        elif cmd == "F10":
            press('F10')
        elif cmd == "F11":
            press('F11')
        elif cmd == "F12":
            press('F12')

# run it
bot()