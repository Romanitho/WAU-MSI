[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $AppListPath,
    [Parameter(Mandatory = $false)] [string] $InstallPath,
    [Parameter(Mandatory = $false)] [string] $Upgrade,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall = $false
)

#For troubleshooting
Write-Output "AppListPath:  $AppListPath"
Write-Output "InstallPath:  $InstallPath"
Write-Output "Upgrade:      $Upgrade"
Write-Output "Uninstall:    $Uninstall"


<# FUNCTIONS #>
function Install-Prerequisites {

    try {
        Write-Output "Checking prerequisites..."

        #Check if Visual C++ 2019 or 2022 installed
        $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
        $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
        $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022 }
        if (!($path)) {
            try {
                Write-Output "MS Visual C++ 2015-2022 is not installed"

                #Get proc architecture
                if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
                    $OSArch = "arm64"
                }
                elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
                    $OSArch = "x64"
                }
                else {
                    $OSArch = "x86"
                }

                #Download and install
                $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
                $Installer = "$env:TEMP\VC_redist.$OSArch.exe"
                Write-Output "-> Downloading $SourceURL..."
                Invoke-WebRequest $SourceURL -UseBasicParsing -OutFile $Installer
                Write-Output "-> Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/passive /norestart" -Wait
                Write-Output "-> MS Visual C++ 2015-2022 installed successfully."
            }
            catch {
                Write-Output "-> MS Visual C++ 2015-2022 installation failed."
            }
            finally {
                Remove-Item $Installer -ErrorAction Ignore
            }
        }

        #Check if Microsoft.UI.Xaml.2.8 is installed
        if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -AllUsers)) {
            try {
                Write-Output "Microsoft.UI.Xaml.2.8 is not installed"
                #Download
                $UIXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                $UIXamlFile = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx"
                Write-Output "-> Downloading Microsoft.UI.Xaml.2.8..."
                Invoke-RestMethod -Uri $UIXamlUrl -OutFile $UIXamlFile
                #Install
                Write-Output "-> Installing Microsoft.UI.Xaml.2.8..."
                Add-AppxProvisionedPackage -Online -PackagePath $UIXamlFile -SkipLicense | Out-Null
                Write-Output "-> Microsoft.UI.Xaml.2.8 installed successfully."
            }
            catch {
                Write-Output "-> Failed to intall Microsoft.UI.Xaml.2.8..."
            }
            finally {
                Remove-Item -Path $UIXamlFile -Force
            }
        }

        Write-Output "Prerequisites checked. OK"
    }
    catch {
        Write-Output "Prerequisites checked failed"
    }

}

function Install-WingetAutoUpdate {

    Write-Host "### Post install actions ###"

    try {

        # Clean potential old v1 install
        $OldConfRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        $OldWAUConfig = Get-ItemProperty $OldConfRegPath -ErrorAction SilentlyContinue
        if ($OldWAUConfig.UninstallString) {
            Write-Host "-> Cleanning old v1 WAU version ($($OldWAUConfig.DisplayVersion))"
            Start-Process cmd.exe -ArgumentList "/c $($OldWAUConfig.UninstallString)" -Wait
        }

        #Get WAU config
        $WAUconfig = Get-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        Write-Output "-> WAU Config:"
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
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1" -WorkingDirectory $InstallPath
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        # Set up the task for user apps
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-notify.ps1" -WorkingDirectory $InstallPath
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
        if ($AppListPath -and ($AppListPath -notlike "$InstallPath*")) {
            Write-Output "-> Copying $AppListPath to $InstallPath"
            Copy-Item -Path $AppListPath -Destination $InstallPath
        }

        #Add 1 to counter file
        try {
            Invoke-RestMethod -Uri "https://github.com/Romanitho/WAU-MSI/releases/download/v$($WAUconfig.ProductVersion)/WAU_InstallCounter" | Out-Null
            Write-Host "-> Reported installation."
        }
        catch {
            Write-Host "-> Not able to report installation."
        }

        Write-Host "### WAU MSI Post actions succeeded! ###"

    }
    catch {
        Write-Host "### WAU Installation failed! Error $_. ###"
        return $False
    }
}

function Uninstall-WingetAutoUpdate {

    Write-Host "### Uninstalling WAU started! ###"

    Write-Host "-> Removing scheduled tasks."
    Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Policies" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

    #If upgrade, keep app list. Else, remove.
    if ($Upgrade -like "#{*}") {
        Write-Output "-> Upgrade detected. Keeping *.txt app lists"
    }
    else {
        $AppLists = Get-Item (Join-Path "$InstallPath" "*_apps.txt") | Where-Object Name -ne "default_excluded_apps.txt"
        if ($AppLists) {
            Write-Output "-> Removing items: $AppLists"
            Remove-Item $AppLists -Force
        }
    }

    $ConfFolder = Get-Item (Join-Path "$InstallPath" "config") -ErrorAction SilentlyContinue
    if ($ConfFolder) {
        Write-Output "-> Removing item: $ConfFolder"
        Remove-Item $ConfFolder -Force -Recurse
    }

    Write-Host "### Uninstallation done! ###"
    Start-sleep 1
}


<# MAIN #>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'


# Uninstall
if ($Uninstall) {
    Uninstall-WingetAutoUpdate
}
# Install
else {
    Install-Prerequisites
    Install-WingetAutoUpdate
}
