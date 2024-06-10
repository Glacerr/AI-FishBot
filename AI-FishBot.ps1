#########################################
#               AI-FishBot              #
#########################################
# Author: Glacerr                       #
# Desc: Audio Interact Fishing Bot      #
# Last Modified: 09JUN2024              #
# Changelog:                            #
# v1.0                                  #
#  Initial Release                      #
#########################################
# Requirements:                         #
#   - World of Warcraft                 #
#   - Windows 10/11                     #
#   - Companion WeakAura Recommended    #
#     https://wago.io/ajvyuK3Io         #
#########################################
# Instructions:                         #
# https://github.com/glacerr/ai-fishbot #
#########################################


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
$picoComPort      = "COM6" # Set to Pi pico com port if using a Pi. You can see in-use COM ports with this Powershell command: [System.IO.Ports.SerialPort]::getportnames()
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

###################################
### DON'T EDIT BELOW THIS LINE ####
###################################

# import winform
Add-Type -AssemblyName System.Windows.Forms

# make console window smaller
if (-not $psISE) {
    $buffer = $host.ui.RawUI.BufferSize
    $buffer.width  = "70"
    $buffer.height = "15"
    $host.UI.RawUI.Set_WindowSize($buffer)
    $host.UI.RawUI.Set_BufferSize($buffer)
}

function Start-Cast {
    if ($usePi) {
        $port.WriteLine("$cast")
    } else {
        [System.Windows.Forms.SendKeys]::SendWait("{$cast}") # press keybind to cast
    }
}

function Start-Bobber {
    write-host "Bite Detected" -ForegroundColor Green
    if ($UseWindowFocus) {$wshell.AppActivate("World of Warcraft") | Out-Null}
    Start-Sleep -Milliseconds 500
    if ($usePi) {
        $port.WriteLine("$bobber")
    } else {
        [System.Windows.Forms.SendKeys]::SendWait("{$bobber}") # press keybind to loot
    }
}

function Apply-Buff {
    param(
        [string]$buffKeybind,
        [int]$buffCastTime
    )

    if ($UseWindowFocus) {$wshell.AppActivate("World of Warcraft") | Out-Null}
    if ($usePi) {
        $port.WriteLine("$buffKeybind")
    } else {
        [System.Windows.Forms.SendKeys]::SendWait("{$buffKeybind}")
    }
    Start-Sleep -Seconds $($buffCastTime + 2)
}

function Send-Notification {
    param(
        [string]$msg
    )

    $discordHeaders = @{
        "Content-Type" = "application/json"
    }

    $discordBody = @{
        content = $msg
    } | convertto-json

    Invoke-RestMethod -Uri $discordWebHook -Method POST -Headers $discordHeaders -Body $discordBody
}

function Start-Fish {
    if ($useWeakAura) {
        write-host "Casting.." -ForegroundColor Yellow
        $rangeCount = 0
        $script:restartCount = -1
        $jobFish = start-job -ScriptBlock {Write-AudioDevice -PlaybackStream}

        DO {
            $rangeCount++
            $script:restartCount++
            if ($UseWindowFocus) {$wshell.AppActivate("World of Warcraft") | Out-Null}
            Start-Sleep -Milliseconds 200
            Start-Cast
            $randomRecast = Get-Random -Minimum 1000 -Maximum 1500
            Start-Sleep -Milliseconds $randomRecast # delay to detect good cast before trying to re-cast
            $SoundCheck = ($jobFish | receive-job)

            if ($rangeCount -ge $fishingRetries) {
                Write-Host "$fishingRetries unsuccessful casts in a row .. stopping AI-Fishbot" -ForegroundColor Yellow
                # send stop notification
                if ($enableNotifications -and $onStop) {
                    Send-Notification -msg "**AI-Fishbot Stopped**`nHooked: $count`nCasting Retries: $script:restartCountTotal`nReason: $fishingRetries unsuccessful casts in a row"
                }
                Write-Host "Close this window and try again" -ForegroundColor Yellow
                Exit
            }
        } Until (($soundCheck -match "[$audioSensitivity-9][0-9]") -or ($soundCheck -match "100"))
        $script:restartCountTotal = $script:restartCountTotal + $script:restartCount
        if ($rangeCount -eq 1) {
            Write-Host "Casting Succeeded: $rangeCount try" -ForegroundColor Green
        } else {
            Write-Host "Casting Succeeded: $rangeCount tries" -ForegroundColor Green
        }
        $jobFish | Stop-Job | Remove-Job
    } else {
        write-host "Fishing.." -ForegroundColor Yellow
        if ($UseWindowFocus) {$wshell.AppActivate("World of Warcraft") | Out-Null}
        Start-Sleep -Milliseconds 200
        Start-Cast 
    }
    $waitAfterCast = 4
    Start-Sleep -Seconds $waitAfterCast # Wait a couple before listening for bobber to let other custom sounds finish. No fishbites occur in the first few seconds anyways.
}

# Start fish bot
Write-Host "##########################" -ForegroundColor Magenta
write-host "  Audio Interact Fishbot "  -ForegroundColor Magenta
Write-Host "##########################" -ForegroundColor Magenta

# check for AudioDeviceCmdlets module and install
Try {
    Get-Command -name Write-AudioDevice -ErrorAction Stop | Out-Null
} Catch {
    # no audiocmdlets detected
    $noAudioModule = $True
}

if ($noAudioModule) {
    Write-Host "Installing Audio Cmdlets"
    Try {
        Get-ChildItem -Recurse | Unblock-File
        $modulepath = "$($profile | split-path)\Modules\AudioDeviceCmdlets"
        if (!(Test-Path "$modulepath\AudioDeviceCmdlets.dll")) {
            New-Item $modulepath -Type Directory -Force | Out-Null
            Copy-Item -Path '.\AudioModule\AudioDeviceCmdlets.dll' -Destination $modulepath -Force
            Copy-Item -Path '.\AudioModule\AudioDeviceCmdlets.psd1' -Destination $modulepath -Force
        }
        Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Confirm:$True
        $noAudioModule = $False
    } Catch {
        Write-Host "Audio Cmdlets Failed to load." -ForegroundColor Red
        Write-Host "Check AudioModule directory is unblocked/permissions allowed" -ForegroundColor Red
        $noAudioModule = $False
        Write-Host 'Close this window and try again'
        Exit
    }
}

if ($UseWindowFocus) {$wshell = New-Object -ComObject wscript.shell}
Get-Job | Stop-Job | Remove-Job
if ($port.IsOpen) { $port.close() }
$count = 0
$script:restartCount = 0
$script:restartCountTotal = 0

if ($usePi) {
    Write-Host "Using Pi for hardware input" -ForegroundColor Yellow
    $port = new-Object System.IO.Ports.SerialPort $picoComPort,115200,None,8,one
    try {
        $port.Open()
        Write-Host "Pi Connection Established" -ForegroundColor Green
    } Catch {
        Write-Host "Pi Connection Failed!" -ForegroundColor Red
        Write-Host "Check settings or COM port of Pi. Or set 'usePi' to $false in settings to not use Pi" -ForegroundColor Yellow
        Write-Host "Close this window and try again" -ForegroundColor Yellow
        Exit
    }
} else {
    Write-Host "NOT using Pi - input will be software based" -ForegroundColor Yellow # injected
}

if (-not $UseWindowFocus) {
    Write-Host "Not Auto-Focusing WoW. Make sure you have the window up and focused." -ForegroundColor Yellow
}
if (-not $useWeakAura) {
    Write-Host "Not Using Weakaura companion. Casting is 'fire and forget'" -ForegroundColor Yellow
}

if ($retail) {
    Write-Host "Retail Mode: Fishing starts in 5 seconds.."
} else {
    Write-Host "Classic Mode: Fishing starts in 5 seconds.."
}
if ($autoStop) {
    $autoEndTime = (Get-Date).AddMinutes($autoStopTime)
}
Sleep -Seconds 5

# send start notification
if ($enableNotifications -and $onStart) {
    Send-Notification -msg "**AI-Fishbot started fishing**"
}

# enable buff timers and put on initial buffs.
if ($enableBuffs) {
    Write-Host "Buffs Enabled.." -ForegroundColor Green
    foreach ($buff in $enableBuffs) {
        $buffKey  = Get-Variable -Name "buffKeybind$buff" -ValueOnly
        $buffCast = Get-Variable -Name "buffCastTime$buff" -ValueOnly
        $buffTime = Get-Variable -Name "buffDuration$buff" -ValueOnly
        Write-Host "Applying Buff #$buff" -ForegroundColor Green
        Apply-Buff $buffKey $buffCast
        Set-Variable -Name "buffTimeLeft$buff" -Value $((Get-Date).AddMinutes($buffTime))
    }
    Start-Sleep -Seconds 2
}

#set casting time
if ($retail) {
    $castingTime = 22 - $waitAfterCast
} else {
    $castingTime = 30 - $waitAfterCast
}

while ($True) {

    Start-Fish
    $jobCatch = start-job -ScriptBlock {Write-AudioDevice -PlaybackStream}
    $endTime = (Get-Date).AddSeconds($castingTime)

    while ((Get-Date) -le $endTime) {
        
        $db = ($jobCatch | receive-job)

        if (($db -match "[$audioSensitivity-9][0-9]") -or ($db -match "100")) {
            $count++
            $jobCatch | Stop-Job | Remove-Job
            $random1 = Get-Random -Minimum 300 -Maximum 700
            $random2 = Get-Random -Minimum 1100 -Maximum 1500 # loot
            start-sleep -Milliseconds $random1
            Start-Bobber
            Clear-Host
            Write-Host "Hooked: $count"
            if ($useWeakAura) {
                Write-Host "Casting Retries: $script:restartCountTotal"
            }
            start-sleep -Milliseconds $random2
            # start loop again
            Start-Fish
            $jobCatch = start-job -ScriptBlock {Write-AudioDevice -PlaybackStream}
            $endTime = (Get-Date).AddSeconds($castingTime)
        }

        # stop if time reached
        if ($autoStop -and ((Get-Date) -gt $autoEndTime)) {
            # end loop
            Break
        }

        # check if buffs need re-appling
        if ($enableBuffs) {
            foreach ($buff in $enableBuffs) {
                $buffExpired = Get-Variable -Name "buffTimeLeft$buff" -ValueOnly
                $timeCheck = (Get-Date).AddSeconds(-10)
                if ($timeCheck -gt $buffExpired) {
                    $buffKey  = Get-Variable -Name "buffKeybind$buff" -ValueOnly
                    $buffCast = Get-Variable -Name "buffCastTime$buff" -ValueOnly
                    $buffTime = Get-Variable -Name "buffDuration$buff" -ValueOnly
                    Write-Host "Re-applying Buff #$buff" -ForegroundColor Green
                    Apply-Buff $buffKey $buffCast
                    Set-Variable -Name "buffTimeLeft$buff" -Value $((Get-Date).AddMinutes($buffTime))
                }
            }
        }

    }
    $jobCatch | Stop-Job | Remove-Job
    # loop again unless autostop is used
    if ($autoStop -and ((Get-Date) -gt $autoEndTime)) {
        # end script
        Write-Host "Time Limit Reached - Fishing Stopped" -ForegroundColor Yellow
        if ($autoLogout) {
            write-host "Logging Out.." -ForegroundColor Yellow
            if ($UseWindowFocus) {$wshell.AppActivate("World of Warcraft") | Out-Null}
            Start-Sleep -Milliseconds 500
            if ($usePi) {
                $port.WriteLine("$logout")
            } else {
                [System.Windows.Forms.SendKeys]::SendWait("{$logout}") # press keybind to logout
            }
        }

        if ($port.IsOpen) { $port.close() }

        # send stop notification
        if ($enableNotifications -and $onStop) {
            Send-Notification -msg "**AI-Fishbot Stopped**`nHooked: $count`n$(if ($useWeakAura) {"Casting Retries: $script:restartCountTotal`n"})Reason: AutoStop time reached after $($autoStopTime)m"
        }
        Write-Host -NoNewLine 'You may close this window'
        Exit

    } else {
        write-host "Casting finished with no bite" -ForegroundColor Yellow
    }
}
