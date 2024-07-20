#Function to update WAU

function Update-WAU {

    $OnClickAction = "https://github.com/Romanitho/WAU-MSI/releases"
    $Button1Text = $NotifLocale.local.outputs.output[10].message

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

    #Run WAU update
    try {
        #Download the msi
        Write-ToLog "Downloading the GitHub Repository version $WAUAvailableVersion" "Cyan"
        $MsiFile = "$env:temp\WAU.msi"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/WAU-MSI/releases/download/v$($WAUAvailableVersion)/WAU.msi" -OutFile $MsiFile

        #Update WAU
        Write-ToLog "Updating WAU..." "Yellow"
        Start-Process msiexec.exe -ArgumentList "$MsiFile /qn"

        #Remove update zip file and update temp folder
        Write-ToLog "Done. Cleaning msi file..." "Cyan"
        Remove-Item -Path $MsiFile -Force -ErrorAction SilentlyContinue

        #Send success Notif
        Write-ToLog "WAU Update completed." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

        #Rerun with newer version
        Write-ToLog "Re-run WAU"
        Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop

        exit

    }

    catch {

        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
        Write-ToLog "WAU Update failed" "Red"

    }

}