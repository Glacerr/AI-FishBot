# AI-FishBot 
**A**udio **I**nteract FishBot for World of Warcraft  

> **风险提示：** 本项目会自动发送游戏操作。此类自动化可能违反游戏规则，并可能导致警告、暂停或永久封禁。普通模式、Raspberry Pi Pico 和 WeakAura 都不能保证安全，也不能保证规避检测；请先了解并自行承担使用风险。

## 图形界面版本

推荐直接双击 `启动_AI-FishBot-界面.cmd` 打开控制台。首次启动且还没有配置方案时，界面会读取当前 `AI-FishBot.ps1` 的设置，并导入为名为“时光服”的方案；原脚本不会被改写。

图形界面提供：

- “基础”“按键与设备”“增益”“通知”“日志”五个分页。
- 多方案的新建、复制、重命名、删除、切换和保存。
- 运行中锁定模式、按键、Pico、WeakAura 等不能安全即时切换的设置；声音灵敏度、自动停止、四组等待、增益和停止通知等实时项目仍可编辑，点击保存后在后台的安全时机生效。
- 四组随机等待的默认范围：咬钩响应 `0.3–0.7` 秒、提竿前 `0.5–0.5` 秒、提竿后 `1.1–1.5` 秒、抛竿前 `0.2–0.6` 秒。
- 最小化到系统托盘，以及从托盘恢复、开始或停止。
- 实时状态和日志查看；缺少声音组件时可使用界面中的“安装声音组件”按钮。
- 原版 `AI-FishBot.ps1` 继续保留。如果新界面不适合当前环境，仍可按下方原有说明配置并启动原脚本。

打开界面不会自动开始真实连接或发送操作。真实运行必须由用户在界面中主动点击“开始”；项目的自动测试使用 `Simulation` 模拟模式，不连接游戏，也不发送真实按键。

### 三种用法及前置条件

- **普通模式：** 需要 Windows PowerShell、可用的声音播放/输出设置，以及游戏内“钓鱼”和“与目标互动”等按键。未使用 WeakAura 时，还需按下文手动设置声音和软目标互动。
- **Raspberry Pi Pico：** 除普通模式所需的游戏设置外，需要已刷入 CircuitPython 的 Pico、下文所述 HID 文件和正确的 COM 端口。Pico 只改变按键的发送方式，不保证规避检测或避免封禁。
- **WeakAura：** 先从下方链接导入配套 WeakAura，再在方案中启用它。它可辅助判断软目标范围并设置相关游戏选项，经典版本尤其需要；它可以与普通输入或 Pico 配合使用，但同样不提供安全保证。

## Description & Design:
This is a Fishing Bot writting in Powershell and Python (If using the Raspberry Pi portion of it).  
It was designed to be very minimalistic and simplistic in code and usage. Its use may still be detectable and may violate game rules.
## How it works:  
It detects the bobber from the sound of the splash and uses Blizzard's soft-interact features to fish. The app does not intentionally modify WoW services, files, or memory. That design does not make the automation safe or undetectable, and Pico input does not remove account-enforcement risk.
## Modes:
There are different ways that this bot can be used depending on how you want to install/setup the bot. Below are descriptions and installation steps of each.
1. **Standalone:** Uses the PowerShell script and software-based input. This will work well in retail, but not as well in classic (due to soft-target range differences). You will need to manually set soft-target settings and in-game audio settings if not using the WeakAura as well (see below). Software input may be detected and may lead to account action.
2. **Raspberry Pi:** This installation/setup option uses the Raspberry Pi Pico as hardware input. It does not guarantee that the automation is undetectable or protect the account from penalties.
3. **Weakaura:** This uses the Weakaura to detect proper soft-target range, so works well in both retail and classic. It Also auto-sets sound and soft-target interact settings so you don't have to do it manually.

## Basic Installation (original script fallback):
1. Download this repo.
2. Right click the zip, select properties > unblock (normal to do this for windows downloads)
3. Extract the zip file. Keep all files in the same directory.
4. Edit the AI-Fishbot.ps1 file and change the settings at the top to how you want to use the bot.
5. Optional (But Recommended): Install the Companion Weakaura or set up the Raspberry Pi Pico if using those.
6. Set in-game keybinds for fishing, Interact With Target, and optional buffs/logout macros.
8. Double-click the AI-Fishbot shortcut file to start the app.

## Weakaura Setup:
Install the companion Weakaura from [https://wago.io/ajvyuK3Io](https://wago.io/ajvyuK3Io) or copy/paste the import string below:  
(This Weakaura as mentioned above is primarily needed/used for classic fishing since soft-target interact range is shorter. However it also sets all the in-game options for you, so I would recommend to use it)
```
!WA:2!1QvZUnYXr4ilh4eISo2BswKehd3MoyLycxQLsw7MOGfWKsKY0r)zsURSdwaU9mtpKT1WPh3DpsI(qoSiajNYbL3G9qoLt6rihcqUnyrEc8JGFcsvDpKIsIdPKwBciPzMU6QRUQV6RRAOM7j3U)T9UTYz1sLxPu5B793UNCWU((kMEoPiwhWdzYDFC7TAStn5HmPIlcN)uEOVq2NQHBYfr84QOa6G2SJ1DSpVtuhnVpl9U5IUB2IeW6sDh0XpqiK9(gAOBpHSUK2N1EqeZP16nRvBNtOHC7Q9GQ9P8W6v1WGvdfHSx6flnJ0bFKuXCfHEQNZOkJcsEZ)nEzlTKf2v37nAQ0uPUEYTsEZKFCYBL82WFV9B44Zd5QEx8XNOyb(7j4HANQ72U9UBVCSmi6D6P1rQ1wAPJODfL4ILOFXHdI)JR0qSuz5XPUohfRp4TAwU09lD)xsJ1WUA3i0ovRDyvpMYn69AXcyUAIwq6rpKruI4qpcy((8UXsMxZJ4E6EZV8bSbVKf2d8mSQchhMm5woAr3UbmzSITbOQNvne8xrVBTqQtaJuZkShXkoPfQyL0J5tJd0p7jYqX2mzxwpqr9yupqJV38OU2b0sVQAig9A)ZK377Fc8OTmUTEGAX)(ZsE3O7vludk1yT(Cy5KSaiaaBGiQUhrm(qn24K(WsYrquVeYjMrQdJKCRM8WOyDYh8SKF9lngi6hqisYDDw9bp8dF4VtsDn(Rhufco6764gR0I(h)dv37ENTfntnxokac6WcpS0WbEIiiUpB3DipI4hhAu0IfYrGpWSvO7wi5D5H0aceU08WUkZOJu0WHTkcuJweg3hCNlUjtV(tOYfZBw7oBtvG)Wkw(cfMSwQ03HZa7Ak6Xg8gkyMAAdonq0DM6XkwMAz7yf3DMkXivM6ypMEMAaKXI(Yul16l0Z2TyKAgAQv9pBM6bKjZ5xDZzpD8697Xc3eYuAOAewDZSd5bbZoAheyUDA7jaznf9yfymON5xC)ZuLLqP05yqiAypyKe)0Aka6IK7x6HfYs0lGzbHNHOPWYzlOf6nB5odGnBzhhenBPrOsrs5zj1eqeZEwJI7tt0ZcTJKIfOyJepBQQqEq2sngv0uLBerZuLAirYufYYumvrgsdmvHSz4tvets803)M8YzTo2SUHsXGZyWFYbhEizWXqYjD(rwhcvV(LpfA8m0le)(ZM196KIMHMU6PTzcsUQPZzGEUIj5tgvDnY8NeI7ArgCduGLFysyNBeLXeqYxDsKjbYVs8kza9lCEuFUCN4j6yR)6zj)KCj)0Co2JvUBYsjlN8(pl6dYUa)ijZLBABWbRygQjCubZnDfbc5Nmp855hjKE7lPrpF)0lIEl7kIQ8XrEunRj7qwO(B4ybOik32nY)y5yU3PFAyuTfDg8N(Qh2(f(8JzE7Jvp)x(rVqlCtBB5Np3FvCQTbdBr9RxBN21Ak)cyz4(dQUvT6Tpv1J6joADJDn3CZn)luXonzDXcr)L3j5wVeU1H6Eqxj6lDGcALUmhE)iHu)s7C)CBla)QV3P(yBmqRhunD(thZb9APs(zwjN)fyplCtXU5sE3JF9nA3JRiGd5afHhsCeqD1Ubufs1sHkLLmnfyi6cANKU3uLYzM0(m6bKkquLa3aTzW7gcvjdbeKpHCixftdcgqadMYHEmkrAOjXyb6FftL2bYxgdxcfJdckoYmnOpaj(eFOhj0GGiuGhr4t2NkDLuFnXzarec6fYBd7cOkpUOePsO9kuJO5ObmwxgSQKJa0pHs6keqdpaxgja2wGa9OAdVNDTvPQdnbtmhAiyepkAhhH2NaCnC3dms5yRU5io0UvSgyMz4856s5YvjqjiQyWaaQtpJ5iWngygECFFWSc1J15Yqpg26bqLzTsyg9PhaputGMk5wNc0bLSeMJHweoflQLiSD7bgHXElr2W2)1ylnk9csOdSbU9yUhSGD9lsGDTRzvardeXquY2ZfSadaahrCuOv0gBC((TWoWGqQVPrkZwpCiWPiovyBG(w0ta27511OT8ciov1BjhUMTqjYEbuWyUOS4QLUFdeUu7w1HHigupPl6A5iLk90oP315PMj)0wrSGa1tH8caGEahVUoGSQcRxjOV2PnhuoyFzRITdG9xUt5BWCw(gmNvmZbYYaOcHI)a9QhhfWgZLysxncyGYOugmo6sOWP6GJCbpqVPrAI5XQiXbaKFbm7AbmR3lfFSwUHVPHUaGo2bkLV)sBIHdPCPknUNXPj0lPLm2s4RfzPky622cV4awUVMgdWqiY4AycRwbUn6DMinT9IMiBTxu(SzY7l86aKzSNvnqq9Q7OPbqwZDAA6XpxtJR8ojpnxvfqNyViI5Ixe9BZwREdcP9HiGUhuAvprG3GNNYuOEZ7EsCy6n3jz1JF9VCuzuMJckwQuPXA7brIbNXqehQWAe81TPYUm9It8eXHJ2iLGjZodUOGvKUxzzBsd7AkJ)(fW3)GeV1d4sgaPmeZPvaGaiZv0bxwDQlPoSWHDD(c2vXAHJwUYBT2cbeiJMS8zxD7IfgfbWYfgDJPyz8KQHv8AIzKh9is(hVtJ2DATxTT2A9kTA3z9pUYo7uBRoTAV7E5pFLV2yAmqdxStrFBAzdpOGAi0psiq3lIIy0ncZyY8fmhvU4yt5rKYRu(dF4dkC(vi1ubaQ5TNrq)nrBCiWepNyzJOWpWMnwcCIY4ZAsBOdzsJFrNvkv0L9w7TvLpVwZo1(0h3yVTHAwm(RnRTXfCvxWNbSwGBA)D3VZEn39tQTE7oWXfp68pz7kn2bFZUgFvEB0kpslLpo8GqGVpFwAp1VUNiaBBRHQ2xgZJIyEn0S(4lEDX8PCOeuK8foxSkuOhxbPHk0GHMFgAgtim9Q5)VAbIXhegqMs)8Fo1EUENECpwYQVWJ5e77J7u5hxBR9Q)4TQIiqhl6l5wjRc8v)G)7f4Ra2TIHSJMoVvRm2JaejscfcDMRDI11j526ByMUe8YBOCgWufjCcgtHzaJ2x1ffIlfHPqUztmUY1GyC5RfX4k3eIXwtNyS81HyS81KyS8Sjg3zXcxgDnP86w7whYnXwrQSEw52wicymLXxlb7iWBzUrYG2RuGcv2A3GHwiL8clG0TN1JQfJN)zM5KEnddZpvaOpSBj4qA3ElIsxKKFLvx93xoFHcgl3EZLNCkm1mmcVsli30PIWeyiCOC2TecO1MaUPw6fSMUcLH6kfkfw(VP4(Hn3mP1Wv4XWcL8yAuTPDtKUGJAxWu3o2pqAfxuppM3KuxtwFXHONcmf0C12qousTuxK4jGqguPoMJfYmIr1Lm5FsM)AtsHiLgIhtXoyHpBX81LxBtapb3SO1tomv2wQzgUuOg8bTg(DNS4fF1UJ(wvGOK5fCFP5pjMXl9(eVGW(0lo44CPt4CTZMWRCvavA2o7YagViaKp9B1cbAnLZxMvI(12V8QEG)R(jXJp3l5l(U(WMR1box3dD(o4GNB4Hpx7dGUjhc9Tk(8CdK(ga)AvSJbG2ck7HF8PDmPSMuv7Zvr)9PDEwrY4JctBZANjuJD3Pywy(ItJLO4uAKi5JC(yGXw3Rj(TJRYnSao8)tGKpA0(zpGaNFCtJoEUcB)VHNkx0BJF7ZhYABR(d6PM9V(Ev9HJbIER6s(xr(0yQh(I9iTB)cP59dA(3n43KN7f9(tnLbFVBph1ulOl5FXTp8)9zjRL8h()p
```
## Raspberry Pi Pico Setup:
Using the Raspberry Pi Pico sends keyboard commands through hardware. It may be useful for this setup, but it does not make automation undetectable and does not eliminate account-enforcement risk.
1. Purchase a Raspberry Pi Pico ($4, USD)
2. Install CircuitPython on to the Pico.
   - instructions here: [adafruit.com](https://learn.adafruit.com/getting-started-with-raspberry-pi-pico-circuitpython/circuitpython)
4. Install the CircuitPython HID module on to the Pico:
   - Copy the 'adafruit_hid' folder in this repo into the 'lib' folder on the Raspberry Pi Pico drive
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
$usePi            = $False # If using a Raspberry Pi Pico for hardware input, set to $True. This does not guarantee detection avoidance.
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
