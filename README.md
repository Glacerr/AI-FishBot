# AI-FishBot 
**A**udio **I**nteract FishBot for World of Warcraft  

***NOTE***: I do not condone botting in games. I do believe in free usage and sharing of code though. What the end user does with that is up to their own morality.
## Description & Design:
This is a Fishing Bot writting in Powershell and Python (If using the Raspberry Pi portion of it).  
It was designed to be very minimalistic and simplistic in code and usage. It was also designed to be as virtually undetectable as possible.
## How it works:  
It detects the bobber from the sound of the splash. It then utilizes legal in-game API's to fish using Blizzard's new soft-interact features. The app never touches the wow services, files or memory in any way. If utilizing the Raspberry Pi portion of this app, it is completely undetectable. If not using the Pi, it is as close to undetectable as can be, similar to other software based bots that utilize windows or python to do keyboard/mouse movements.
## Modes:
There are different ways that this bot can be used depending on how you want to install/setup the bot. Below are descriptions and installation steps of each.
1. **Standalone:** Uses the powershell script and nothing else. This will work well in retail, but not as well in classic (due to soft-target range differences). It will also only use software based input, which is not as safe as using raspberry pi hardware input. You will need to manually set soft-target settings if not using the Weakaura as well (see below)
2. **Raspberry Pi:** This installation/setup option uses the Raspberry Pi Pico as hardware input, making it undetectable.
3. **Weakaura:** This uses the Weakaura to detect proper soft-target range, so works well in both retail and classic. It Also auto-sets sound and soft-target interact settings so you don't have to do it manually.

## Basic Installation:
1. Download this repo.
2. Right click the zip, select properties > unblock (normal to do this for windows downloads)
3. Extract the zip file. Keep all files in the same directory.
4. Edit the AI-Fishbot.ps1 file and change the settings at the top to how you want to use the bot.
5. Optional (But Recommended): Install the Companion Weakaura or set up the Raspberry Pi Pico if using those.
6. Set in-game keybinds for fishing, Interact With Target, and optional buffs/logout macros.
8. Double-click the AI-Fishbot shortcut file to start the app.

## Weakaura Setup:
Install the companion Weakaura from [https://wago.io/ajvyuK3Io](https://wago.io/ajvyuK3Io) or copy/paste the import string below:  
(This Weakaura as mentioned above is primarily needed/used for classic fishing since soft-target interact range is shorter. However it also sets all the in-game options for you, so I would recommended to use it)
```
!WA:2!1QvZUnYXr4ilh4eISo2BswKehd3MoyLycxQLsw7MOGfWKsKY0r)zsURSdwaU9mtpKT1WPh3DpsI(qoSiajNYbL3G9qoLt6rihcqUnyrEc8JGFcsvDpKIsIdPKwBciPzMU6QRUQV6RRAOM7j3U)T9UTYz1sLxPu5B793UNCWU((kMEoPiwhWdzYDFC7TAStn5HmPIlcN)uEOVq2NQHBYfr84QOa6G2SJ1DSpVtuhnVpl9U5IUB2IeW6sDh0XpqiK9(gAOBpHSUK2N1EqeZP16nRvBNtOHC7Q9GQ9P8W6v1WGvdfHSx6flnJ0bFKuXCfHEQNZOkJcsEZ)nEzlTKf2v37nAQ0uPUEYTsEZKFCYBL82WFV9B44Zd5QEx8XNOyb(7j4HANQ72U9UBVCSmi6D6P1rQ1wAPJODfL4ILOFXHdI)JR0qSuz5XPUohfRp4TAwU09lD)xsJ1WUA3i0ovRDyvpMYn69AXcyUAIwq6rpKruI4qpcy((8UXsMxZJ4E6EZV8bSbVKf2d8mSQchhMm5woAr3UbmzSITbOQNvne8xrVBTqQtaJuZkShXkoPfQyL0J5tJd0p7jYqX2mzxwpqr9yupqJV38OU2b0sVQAig9A)ZK377Fc8OTmUTEGAX)(ZsE3O7vludk1yT(Cy5KSaiaaBGiQUhrm(qn24K(WsYrquVeYjMrQdJKCRM8WOyDYh8SKF9lngi6hqisYDDw9bp8dF4VtsDn(Rhufco6764gR0I(h)dv37ENTfntnxokac6WcpS0WbEIiiUpB3DipI4hhAu0IfYrGpWSvO7wi5D5H0aceU08WUkZOJu0WHTkcuJweg3hCNlUjtV(tOYfZBw7oBtvG)Wkw(cfMSwQ03HZa7Ak6Xg8gkyMAAdonq0DM6XkwMAz7yf3DMkXivM6ypMEMAaKXI(Yul16l0Z2TyKAgAQv9pBM6bKjZ5xDZzpD8697Xc3eYuAOAewDZSd5bbZoAheyUDA7jaznf9yfymON5xC)ZuLLqP05yqiAypyKe)0Aka6IK7x6HfYs0lGzbHNHOPWYzlOf6nB5odGnBzhhenBPrOsrs5zj1eqeZEwJI7tt0ZcTJKIfOyJepBQQqEq2sngv0uLBerZuLAirYufYYumvrgsdmvHSz4tvets803)M8YzTo2SUHsXGZyWFYbhEizWXqYjD(rwhcvV(LpfA8m0le)(ZM196KIMHMU6PTzcsUQPZzGEUIj5tgvDnY8NeI7ArgCduGLFysyNBeLXeqYxDsKjbYVs8kza9lCEuFUCN4j6yR)6zj)KCj)0Co2JvUBYsjlN8(pl6dYUa)ijZLBABWbRygQjCubZnDfbc5Nmp855hjKE7lPrpF)0lIEl7kIQ8XrEunRj7qwO(B4ybOik32nY)y5yU3PFAyuTfDg8N(Qh2(f(8JzE7Jvp)x(rVqlCtBB5Np3FvCQTbdBr9RxBN21Ak)cyz4(dQUvT6Tpv1J6joADJDn3CZn)luXonzDXcr)L3j5wVeU1H6Eqxj6lDGcALUmhE)iHu)s7C)CBla)QV3P(yBmqRhunD(thZb9APs(zwjN)fyplCtXU5sE3JF9nA3JRiGd5afHhsCeqD1Ubufs1sHkLLmnfyi6cANKU3uLYzM0(m6bKkquLa3aTzW7gcvjdbeKpHCixftdcgqadMYHEmkrAOjXyb6FftL2bYxgdxcfJdckoYmnOpaj(eFOhj0GGiuGhr4t2NkDLuFnXzarec6fYBd7cOkpUOePsO9kuJO5ObmwxgSQKJa0pHs6keqdpaxgja2wGa9OAdVNDTvPQdnbtmhAiyepkAhhH2NaCnC3dms5yRU5io0UvSgyMz4856s5YvjqjiQyWaaQtpJ5iWngygECFFWSc1J15Yqpg26bqLzTsyg9PhaputGMk5wNc0bLSeMJHweoflQLiSD7bgHXElr2W2)1ylnk9csOdSbU9yUhSGD9lsGDTRzvardeXquY2ZfSadaahrCuOv0gBC((TWoWGqQVPrkZwpCiWPiovyBG(w0ta27511OT8ciov1BjhUMTqjYEbuWyUOS4QLUFdeUu7w1HHigupPl6A5iLk90oP315PMj)0wrSGa1tH8caGEahVUoGSQcRxjOV2PnhuoyFzRITdG9xUt5BWCw(gmNvmZbYYaOcHI)a9QhhfWgZLysxncyGYOugmo6sOWP6GJCbpqVPrAI5XQiXbaKFbm7AbmR3lfFSwUHVPHUaGo2bkLV)sBIHdPCPknUNXPj0lPLm2s4RfzPky622cV4awUVMgdWqiY4AycRwbUn6DMinT9IMiBTxu(SzY7l86aKzSNvnqq9Q7OPbqwZDAA6XpxtJR8ojpnxvfqNyViI5Ixe9BZwREdcP9HiGUhuAvprG3GNNYuOEZ7EsCy6n3jz1JF9VCuzuMJckwQuPXA7brIbNXqehQWAe81TPYUm9It8eXHJ2iLGjZodUOGvKUxzzBsd7AkJ)(fW3)GeV1d4sgaPmeZPvaGaiZv0bxwDQlPoSWHDD(c2vXAHJwUYBT2cbeiJMS8zxD7IfgfbWYfgDJPyz8KQHv8AIzKh9is(hVtJ2DATxTT2A9kTA3z9pUYo7uBRoTAV7E5pFLV2yAmqdxStrFBAzdpOGAi0psiq3lIIy0ncZyY8fmhvU4yt5rKYRu(dF4dkC(vi1ubaQ5TNrq)nrBCiWepNyzJOWpWMnwcCIY4ZAsBOdzsJFrNvkv0L9w7TvLpVwZo1(0h3yVTHAwm(RnRTXfCvxWNbSwGBA)D3VZEn39tQTE7oWXfp68pz7kn2bFZUgFvEB0kpslLpo8GqGVpFwAp1VUNiaBBRHQ2xgZJIyEn0S(4lEDX8PCOeuK8foxSkuOhxbPHk0GHMFgAgtim9Q5)VAbIXhegqMs)8Fo1EUENECpwYQVWJ5e77J7u5hxBR9Q)4TQIiqhl6l5wjRc8v)G)7f4Ra2TIHSJMoVvRm2JaejscfcDMRDI11j526ByMUe8YBOCgWufjCcgtHzaJ2x1ffIlfHPqUztmUY1GyC5RfX4k3eIXwtNyS81HyS81KyS8Sjg3zXcxgDnP86w7whYnXwrQSEw52wicymLXxlb7iWBzUrYG2RuGcv2A3GHwiL8clG0TN1JQfJN)zM5KEnddZpvaOpSBj4qA3ElIsxKKFLvx93xoFHcgl3EZLNCkm1mmcVsli30PIWeyiCOC2TecO1MaUPw6fSMUcLH6kfkfw(VP4(Hn3mP1Wv4XWcL8yAuTPDtKUGJAxWu3o2pqAfxuppM3KuxtwFXHONcmf0C12qousTuxK4jGqguPoMJfYmIr1Lm5FsM)AtsHiLgIhtXoyHpBX81LxBtapb3SO1tomv2wQzgUuOg8bTg(DNS4fF1UJ(wvGOK5fCFP5pjMXl9(eVGW(0lo44CPt4CTZMWRCvavA2o7YagViaKp9B1cbAnLZxMvI(12V8QEG)R(jXJp3l5l(U(WMR1box3dD(o4GNB4Hpx7dGUjhc9Tk(8CdK(ga)AvSJbG2ck7HF8PDmPSMuv7Zvr)9PDEwrY4JctBZANjuJD3Pywy(ItJLO4uAKi5JC(yGXw3Rj(TJRYnSao8)tGKpA0(zpGaNFCtJoEUcB)VHNkx0BJF7ZhYABR(d6PM9V(Ev9HJbIER6s(xr(0yQh(I9iTB)cP59dA(3n43KN7f9(tnLbFVBph1ulOl5FXTp8)9zjRL8h()p
```
## Raspberry Pi Pico Setup:
Utilizing the Raspberry Pi Pico to send the actual keyboard commands makes this truly undetectable. This is the preferred way to utilize this bot.
1. Purchase a Raspberry Pi Pico ($4, USD)
2. Install CircuitPython on to the Pico.
   - instructions here: [adafruit.com](https://learn.adafruit.com/getting-started-with-raspberry-pi-pico-circuitpython/circuitpython)
4. Install the CircuitPython HID module on to the Pico:
   - Copy the 'adadruit_hid' folder in this repo into the 'lib' folder on the Raspberry Pi Pico drive
5. Copy the 'code.py' file on to the Raspberry Pi Pico drive.
6. Unplug/replug the Raspberry Pi Pico.

# App Settings
(Edit these to your own settings at the top of the AI-FishBot.ps1 file) 
```
### General Settings ###
$retail           = $True  # Set $True for Retail and $False for Classic. Fishing cast times are different among game versions.
$autoStop         = $True  # $False to disable. Will autostop the bot after tge time set below.
$autoStopTime     = 60     # Amount of minutes to stop the bot. Used when $autoStop is set to $True above.
$autoLogout       = $False # If $True, your char will logout after the $autoStopTime is reached and $autoStop is set to $True
$audioSensitivity = 3      # Valid values are 1-9. Set lower if cast/bite not being detected. Higher is better if possible as you can cast even if other noises are around but probably needs a custom sound for that (see my recommendation).
$UseWindowFocus   = $True  # If set to $False, you need to make sure wow is focused yourself. Set to $True to have it be focused each time a command needs to be sent to it.
$enableBuffs      = (0)    # Array of buffs to use. Set to (0) for no buffs, or set (1) or (1..X) for multiple. ie: for 3 buffs enter: (1..3) See additional buff settings below.
$fishingRetries   = 15     # Used when $useWeakAura is set to $True. How many times to keep trying to land a cast that is within softtarget interact range before stopping the bot. Retail has a larger softtarget distance than classic/sod, so more tries are needed in those game versions.
$usePi            = $False # If using a raspberry pi pico, set to $True. Pi is safer for hardware input. Costs 4$ USD, pretty worth.
$picoComPort      = "COM6" # set to Pi pico com port if using a pi. You can see in-use COM ports with this Powershell command: [System.IO.Ports.SerialPort]::getportnames()
$useWeakAura      = $False # Set this to $True to use the weak aura companion. If no weak aura companion is used, the app will not know if a cast has a good softtarget in range. Retail has a larger range, so the weak aura is not really needed, but classic is smaller and pretty much needs the weakaura, and needs this set to $True in classic. Get from here: https://wago.io/ajvyuK3Io

### Main Keybinds ###
# valid options are the Function keys. F5-F12
# Code is easily modifiable for different or more if you want to do that yourself.
$cast   = "F6"  # start fishing keybind. (make a macro '/cast fishing' and keybind it)
$bobber = "F7"  # click bobber action keybind (set in wow options 'Interact With Target')
$logout = "F8"  # make a macro '/logout' or '/camp' to use for this keybind

### Notification Settings ###
# Only Discord Supported currently
# Sends a notification when fishing starts and/or stops. Sends caught stats when stopped as well.
$enableNotifications = $False # $True to enable, $False to disable
$discordWebhook = "https://discord.com/api/webhooks/your webhook here"
$onStart = $True
$onStop  = $True

### Buff Settings ###
# Note that this app is not "buff-aware". Meaning, when the app first runs, and you have buffs enabled, it will try and apply all of them, and then again after each duration set below expires.
# If you re-start this app, and still have buff's on, it won't know and will start again with applying them and starting a fresh duration countdown. Keep that in mind.
# replicate these variables for each of your buffs, changing the number to the next higher one. ie: buffKeybind1..buffKeybind2..
#
# buff1
$buffKeybind1  = "F9"
$buffCastTime1 = 5  # If there is a cast/time it takes to apply the buff. In seconds. Minimum of 1, for global cooldown.
$buffDuration1 = 10 # How long does the buff last. Used to know when to re-apply. In Minutes.
# buff2
$buffKeybind2  = "F10"
$buffCastTime2 = 5
$buffDuration2 = 30
# buff3
# ...
```
# Tips & Tricks:
- Enable Autoloot
- Set your keybinds in game options for 'Interact With Target', your fishing cast key, and optional buffs or logout keybinds.
- Be in a quiet area if possible, since this is based off of sound detection. Play with the sound levels in wow and the $audioSensitivity if needed.
- Classic allows overwriting spell sounds. Can replace fishing 'splash/bite' sound with the ones recommended in [this Weakaura](https://wago.io/ajvyuK3Io) for a louder 'ding' sound detection for the bot if needed.
### Manual soft-target settings if not using the WeakAura:
```
/console SoftTargetInteract 3
/console SoftTargetInteractArc 2
/console SoftTargetInteractRange 30
/console SoftTargetInteractGameObject 1
/console SoftTargetIconInteract 1
/console SoftTargetTooltipInteract 1
```
### Manual In-game audio settings if not using the WeakAura:
- Enable Sound
- Set Output Device to System Default
- Set Master Volume to like 70% or higher
- Set Effects to 100%
- Sound Effects: Checked
- Sound in Background: Checked
- Turn off all the other sound options
### Sample Macros:
Fishing Macro:
```
#showtooltip fishing
/equip [noworn:fishing pole] Mastercraft Kalu'ak Fishing Pole
/cast fishing
```
Buff Macro:
```
/use [worn:Fishing Pole] Nightcrawlers
/use 16
```
Logout Macro:
```
/logout
```
