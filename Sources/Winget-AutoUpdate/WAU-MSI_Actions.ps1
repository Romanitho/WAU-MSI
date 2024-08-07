[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)] [string] $AppListPath,
    [Parameter(Mandatory = $false)] [string] $InstallPath,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall = $false
)


#For troubleshooting
Write-Output "AppListPath: $AppListPath"
Write-Output "InstallPath: $InstallPath"
Write-Output "Uninstall:   $Uninstall"


<# FUNCTIONS #>

function Install-WingetAutoUpdate {

    Write-Host "Post install actions:"

    try {

        # Clean potential old install
        $OldConfRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        $OldWAUConfig = Get-ItemProperty $OldConfRegPath -ErrorAction SilentlyContinue
        if ($OldWAUConfig.UninstallString) {
            Write-Host "-> Cleanning old WAU version ($($OldWAUConfig.DisplayVersion))"
            Start-Process cmd.exe -ArgumentList "/c $($OldWAUConfig.UninstallString)" -Wait
        }

        #Get WAU config
        $WAUconfig = Get-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        Write-Output $WAUconfig

        # Settings for the scheduled task for Updates (System)
        Write-Host "-> Installing WAU scheduled tasks"
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($InstallPath)winget-upgrade.ps1`""
        $taskTriggers = @()
        if ($WAUconfig.WAU_UpdatesAtLogon -eq 1) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
        if ($WAUconfig.WAU_UpdatesInterval -eq "Daily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUconfig.WAU_UpdatesAtTime
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "BiDaily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUconfig.WAU_UpdatesAtTime -DaysInterval 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "Weekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "BiWeekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "Monthly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
        }
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        # Set up the task, and register it
        if ($taskTriggers) {
            $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTriggers
        }
        else {
            $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        }
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task in User context
        $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "Invisible.vbs `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1`"" -WorkingDirectory $InstallPath
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        # Set up the task for user apps
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "Invisible.vbs `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-notify.ps1`"" -WorkingDirectory $InstallPath
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the GPO scheduled task
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($InstallPath)WAU-Policies.ps1`""
        $tasktrigger = New-ScheduledTaskTrigger -Daily -At 6am
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Policies' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        #Set task readable/runnable for all users
        $scheduler = New-Object -ComObject "Schedule.Service"
        $scheduler.Connect()
        $task = $scheduler.GetFolder("WAU").GetTask("Winget-AutoUpdate")
        $sec = $task.GetSecurityDescriptor(0xF)
        $sec = $sec + '(A;;GRGX;;;AU)'
        $task.SetSecurityDescriptor($sec, 0)

        #Copy App list to install folder (exept on self update)
        if ($AppListPath -notlike "$InstallPath*") {
            Copy-Item -Path $AppListPath -Destination $InstallPath
        }

        #Add 1 to counter file
        try {
            Invoke-RestMethod -Uri "https://github.com/Romanitho/WAU-MSI/releases/download/v$($WAUconfig.ProductVersion)/WAU_InstallCounter" | Out-Null
        }
        catch {
            Write-Host "-> Not able to report installation."
        }

        Write-Host "-> WAU MSI Post actions succeeded!`n"

    }
    catch {
        Write-Host "-> WAU Installation failed! Error $_.`n"
        return $False
    }
}

function Uninstall-WingetAutoUpdate {

    Write-Host "Uninstalling WAU started!"

    Write-Host "-> Removing scheduled tasks."
    Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Policies" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

    $AppLists = Get-Item (Join-Path "$InstallPath" "*_apps.txt") -ErrorAction SilentlyContinue
    if ($AppLists) {
        Write-Output "Remove item: $AppLists"
        Remove-Item $AppLists -Force
    }

    $ConfFolder = Get-Item (Join-Path "$InstallPath" "config") -ErrorAction SilentlyContinue
    if ($ConfFolder) {
        Write-Output "Remove item: $ConfFolder"
        Remove-Item $ConfFolder -Force -Recurse
    }

    Write-Host "Uninstallation done!`n"
    Start-sleep 1
}


<# MAIN #>

$Script:ProgressPreference = 'SilentlyContinue'

if (-not $Uninstall) {
    Install-WingetAutoUpdate
}
else {
    Uninstall-WingetAutoUpdate
}
