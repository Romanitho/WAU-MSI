[Cmdletbinding()]
Param(
    [Parameter(Mandatory = $false, Position = 0)]  [string] $Path = (Get-Location).Path,
    [Parameter(Mandatory = $false)]  [string] $Sources = "$($Path)\Sources\Winget-AutoUpdate\",
    [Parameter(Mandatory = $false)]  [string] $OutputFolder = $Path,
    [Parameter(Mandatory = $false)]  [string] $IconFile = "$($Path)\Sources\Wix\files\icon.ico",
    [Parameter(Mandatory = $false)]  [string] $BannerFile = "$($Path)\Sources\Wix\files\banner.bmp",
    [Parameter(Mandatory = $false)]  [string] $DialogFile = "$($Path)\Sources\Wix\files\dialog.bmp",
    [Parameter(Mandatory = $false)]  [string] $ProductId = "WAU",
    [Parameter(Mandatory = $false)]  [string] $ProductName = "Winget-AutoUpdate",
    [Parameter(Mandatory = $false)]  [string] $ProductVersion = "1.0.0",
    [Parameter(Mandatory = $false)]  [string] $Manufacturer = "Romanitho",
    [Parameter(Mandatory = $false)]  [string] $HelpLink = "https://github.com/Romanitho/Winget-AutoUpdate",
    [Parameter(Mandatory = $false)]  [string] $AboutLink = "https://github.com/Romanitho/Winget-AutoUpdate",
    [Parameter(Mandatory = $false)]  [string] $UpgradeCodeX86 = "B96866C0-EB44-4C0A-9477-2E5BB09CB9EF",
    [Parameter(Mandatory = $false)]  [string] $UpgradeCodeX64 = "BDDEA607-F4AF-4229-8610-16E3B6455FDC",
    [Parameter(Mandatory = $false)]  [switch] $PreRelease,
    [Parameter(Mandatory = $false)]  [switch] $NoX86,
    [Parameter(Mandatory = $false)]  [switch] $NoX64
)

$ProgressPreference = "SilentlyContinue"

# WiX paths
If (!(Get-ChildItem -Path "$env:HOMEDRIVE\Program Files*\WiX*\" -Filter heat.exe -Recurse)) {
    $ToolSetURL = "https://github.com/wixtoolset/wix3/releases/download/wix314rtm/wix314.exe"
    Invoke-WebRequest -Uri $ToolSetURL -OutFile (Join-Path $Path "\wix.exe") -UseBasicParsing
    Start-Process (Join-Path $Path "\wix.exe") -ArgumentList "/S" -Wait
}
$wixDir = Split-Path ((((Get-ChildItem -Path "$env:HOMEDRIVE\Program Files*\WiX*\" -Filter heat.exe -Recurse) | Select-Object FullName)[0]).FullName)
$heatExe = Join-Path $wixDir "heat.exe"
$candleExe = Join-Path $wixDir "candle.exe"
$lightExe = Join-Path $wixDir "light.exe"

if ($PreRelease) {
    $Comment = "NIGHTLY"
    $UpdatePreRelease = "#1"
}
else {
    $Comment = "STABLE"
    $UpdatePreRelease = "#0"
}

# Platform settings
$platforms = @()

$x86Settings = @{
    'arch'        = 'x86';
    'sysFolder'   = 'System32';
    'progfolder'  = 'ProgramFilesFolder';
    'upgradeCode' = $UpgradeCodeX86;
    'productName' = "${ProductName} (x86)";
    'win64'       = 'no';
    'outputMsi'   = (Join-Path $OutputFolder ($productID + "_x86.msi"))
}
$x64Settings = @{
    'arch'        = 'x64';
    'sysFolder'   = 'Sysnative';
    'progfolder'  = 'ProgramFiles64Folder';
    'upgradeCode' = $UpgradeCodeX64;
    'productName' = "${ProductName}";
    'win64'       = 'yes';
    'outputMsi'   = (Join-Path $OutputFolder ($productID + ".msi"))
}

If (!$Nox86) {
    $platforms += $x86Settings
}
If (!$Nox64) {
    $platforms += $x64Settings
}

# Do the build
foreach ($platform in $platforms) {
    $platformArch = $platform.arch
    $platformSysFolder = $platform.sysFolder
    $platformProgFolder = $platform.progFolder
    $platformUpgradeCode = $platform.upgradeCode
    $platformProductName = $platform.productName
    $platformWin64 = $platform.win64

    $modulesWxs = Join-Path $Path "_modules${platformArch}.wxs"
    $productWxs = Join-Path $Path ".wxs${platformArch}"
    $modulesWixobj = Join-Path $Path "_modules${platformArch}.wixobj"
    $productWixobj = Join-Path $Path ".wixobj${platformArch}"


    # Build XML
    $wixXml = [xml] @"
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns='http://schemas.microsoft.com/wix/2006/wi'>

    <!-- Product Config -->
    <Product Id="*" Language="1033" Name="$platformProductName" Version="$ProductVersion" Manufacturer="$Manufacturer" UpgradeCode="$platformUpgradeCode" >

        <!-- Package Config -->
        <Package Id="*" Description="$ProductId ($platformArch) [$ProductVersion]" InstallPrivileges="elevated" Comments="$ProductName Installer" InstallerVersion="200" Compressed="yes" Platform="$platformArch" InstallScope="perMachine"/>
        <Icon Id="icon.ico" SourceFile="$IconFile"/>
        <WixVariable Id="WixUIBannerBmp" Value="$BannerFile"></WixVariable>
        <WixVariable Id="WixUIDialogBmp" Value="$DialogFile"></WixVariable>
        <MediaTemplate EmbedCab="yes"/>

        <!-- Upgrade handling -->
        <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />

        <!-- MSI Properties Config -->
        <Property Id="ARPCOMMENTS" Value="$Comment" />
        <Property Id="ARPPRODUCTICON" Value="icon.ico" />
        <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Run WAU after closing this wizard." />
        <Property Id="ARPHELPLINK" Value="$HelpLink"/>
        <Property Id="ARPURLINFOABOUT" Value="$AboutLink"/>
        <Property Id="WIXUI_INSTALLDIR" Value="INSTALLDIR"/>

        <!-- Check for Powershell -->
        <Property Id="POWERSHELLEXE">
            <RegistrySearch Id="POWERSHELLEXE" Type="raw" Root="HKLM" Key="SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" Name="Path" />
        </Property>
        <Condition Message="You must have PowerShell 5.0 or higher."><![CDATA[Installed OR POWERSHELLEXE]]></Condition>

        <!-- WAU Properties Config -->
        <Property Id="RUN_WAU" Value="NO" />
        <Property Id="NOTIFICATIONLEVEL" Secure="yes" />
        <Property Id="NOTIFICATIONLEVEL_VALUE" Value="Full">
            <RegistrySearch Id="SearchNotificationLevel" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_NotificationLevel" Win64="$platformWin64" />
        </Property>
        <Property Id="USERCONTEXT" Secure="yes" />
        <Property Id="USERCONTEXT_REG" Value="#0">
            <RegistrySearch Id="SearchUserContext" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UserContext" Win64="$platformWin64" />
        </Property>
        <Property Id="DISABLEWAUAUTOUPDATE" Secure="yes" />
        <Property Id="DISABLEWAUAUTOUPDATE_REG" Value="#0">
            <RegistrySearch Id="SearchWAUSelfUpdate" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_DisableAutoUpdate" Win64="$platformWin64" />
        </Property>
        <Property Id="UPDATESINTERVAL" Secure="yes" />
        <Property Id="UPDATESINTERVAL_VALUE" Value="Never">
            <RegistrySearch Id="SearchUpdateInterval" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UpdatesInterval" Win64="$platformWin64" />
        </Property>
        <Property Id="UPDATESATLOGON" Secure="yes" />
        <Property Id="UPDATESATLOGON_REG" Value="#1">
            <RegistrySearch Id="SearchWAUUpdatesAtLogon" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UpdatesAtLogon" Win64="$platformWin64" />
        </Property>
        <Property Id="USEWHITELIST" Value="0">
            <RegistrySearch Id="SearchUseWhiteList" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UseWhiteList" Win64="$platformWin64" />
        </Property>
        <Property Id="BLACKLIST_PATH">
            <DirectorySearch Id="CheckBlacklistDir" Path="[CURRENTDIRECTORY]">
                <FileSearch Id="CheckBlacklistFile" Name="excluded_apps.txt" />
            </DirectorySearch>
        </Property>
        <Property Id="WHITELIST_PATH">
            <DirectorySearch Id="CheckWhitelistDir" Path="[CURRENTDIRECTORY]">
                <FileSearch Id="CheckWhitelistFile" Name="included_apps.txt" />
            </DirectorySearch>
        </Property>
        <Property Id="B_W_LIST_PATH" Secure="yes" />
        <Property Id="LISTPATH" Secure="yes" />
        <Property Id="LISTPATH_VALUE">
            <RegistrySearch Id="SearchListPath" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_ListPath" Win64="$platformWin64" />
        </Property>
        <Property Id="MODPATH" Secure="yes" />
        <Property Id="MODPATH_VALUE">
            <RegistrySearch Id="SearchModsPath" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_ModsPath " Win64="$platformWin64" />
        </Property>
        <Property Id="AZUREBLOBURL" Secure="yes" />
        <Property Id="AZUREBLOBURL_VALUE">
            <RegistrySearch Id="SearchAzureBlobSASURL" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_AzureBlobSASURL" Win64="$platformWin64" />
        </Property>
        <Property Id="DONOTRUNONMETERED" Secure="yes" />
        <Property Id="DONOTRUNONMETERED_VALUE" Value="#1">
            <RegistrySearch Id="SearchDoNotRunOnMetered" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_DoNotRunOnMetered" Win64="$platformWin64" />
        </Property>
        <Property Id="UPDATESATTIME" Secure="yes" />
        <Property Id="UPDATESATTIME_VALUE" Value="06am">
            <RegistrySearch Id="SearchUpdatesAtTime" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UpdatesAtTime" Win64="$platformWin64" />
        </Property>
        <Property Id="BYPASSLISTFORUSERS" Secure="yes" />
        <Property Id="BYPASSLISTFORUSERS_VALUE" Value="#0">
            <RegistrySearch Id="SearchBypassListForUsers" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_BypassListForUsers" Win64="$platformWin64" />
        </Property>
        <Property Id="MAXLOGFILES" Secure="yes" />
        <Property Id="MAXLOGFILES_VALUE" Value="#3">
            <RegistrySearch Id="SearchMaxLogFiles" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_MaxLogFiles" Win64="$platformWin64" />
        </Property>
        <Property Id="MAXLOGSIZE" Secure="yes" />
        <Property Id="MAXLOGSIZE_VALUE" Value="#1048576">
            <RegistrySearch Id="SearchMaxLogSize" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_MaxLogSize" Win64="$platformWin64" />
        </Property>
        <Property Id="UPDATEPRERELEASE" Secure="yes" />
        <Property Id="UPDATEPRERELEASE_REG" Value="$UpdatePreRelease">
            <RegistrySearch Id="SearchUpdatePrerelease" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_UpdatePrerelease" Win64="$platformWin64" />
        </Property>
        <Property Id="DESKTOPSHORTCUT" Secure="yes" />
        <Property Id="DESKTOPSHORTCUT_VALUE" Value="#0">
            <RegistrySearch Id="SearchDesktopShortcut" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_DesktopShortcut" Win64="yes" />
        </Property>
        <Property Id="STARTMENUSHORTCUT" Secure="yes" />
        <Property Id="STARTMENUSHORTCUT_VALUE" Value="#0">
            <RegistrySearch Id="SearchStartMenuShortcut" Type="raw" Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]" Name="WAU_StartMenuShortcut" Win64="yes" />
        </Property>

        <!-- Define a custom action -->
        <Directory Id="TARGETDIR" Name="SourceDir">
            <Directory Id="$platformProgFolder" Name="$platformProgFolder">
                <Directory Id="INSTALLDIR" Name="$ProductName">
                    <Component Id="CompReg" Guid="*" Win64="$platformWin64">
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="ProductVersion" Type="string" Value="[ProductVersion]" KeyPath="yes" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="InstallLocation" Type="string" Value="[INSTALLDIR]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_NotificationLevel" Type="string" Value="[NOTIFICATIONLEVEL_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UserContext" Type="integer" Value="[USERCONTEXT]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_DisableAutoUpdate" Type="integer" Value="[DISABLEWAUAUTOUPDATE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UpdatesInterval" Type="string" Value="[UPDATESINTERVAL_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UpdatesAtLogon" Type="integer" Value="[UPDATESATLOGON]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UseWhiteList" Type="integer" Value="[USEWHITELIST]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_ListPath" Type="string" Value="[LISTPATH_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_ModsPath" Type="string" Value="[MODPATH_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_AzureBlobSASURL" Type="string" Value="[AZUREBLOBURL_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_DoNotRunOnMetered" Type="string" Value="[DONOTRUNONMETERED_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UpdatesAtTime" Type="string" Value="[UPDATESATTIME_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_BypassListForUsers" Type="string" Value="[BYPASSLISTFORUSERS_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_MaxLogFiles" Type="string" Value="[MAXLOGFILES_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_MaxLogSize" Type="string" Value="[MAXLOGSIZE_VALUE]" />
                        </RegistryKey>
                        <RegistryKey Key="SOFTWARE\[Manufacturer]\[ProductName]" Root="HKLM">
                            <RegistryValue Name="WAU_UpdatePrerelease" Type="integer" Value="[UPDATEPRERELEASE]" />
                        </RegistryKey>
                        <RegistryKey Key="AppUserModelId\Windows.SystemToast.Winget.Notification" Root="HKCR">
                            <RegistryValue Name="DisplayName" Type="string" Value="Application Update" />
                        </RegistryKey>
                        <RegistryKey Key="AppUserModelId\Windows.SystemToast.Winget.Notification" Root="HKCR">
                            <RegistryValue Name="IconUri" Type="string" Value="%SystemRoot%\system32\@WindowsUpdateToastIcon.png" />
                        </RegistryKey>
                        <RegistryKey Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]">
                            <RegistryValue Name="WAU_DesktopShortcut" Type="integer" Value="[DESKTOPSHORTCUT]" />
                        </RegistryKey>
                        <RegistryKey Root="HKLM" Key="SOFTWARE\[Manufacturer]\[ProductName]">
                            <RegistryValue Name="WAU_StartMenuShortcut" Type="integer" Value="[STARTMENUSHORTCUT]" />
                        </RegistryKey>
                    </Component>
                </Directory>
            </Directory>
            <Directory Id="DesktopFolder" Name="DesktopFolder">
                <Component Id="DesktopShortcut" Guid="*">
                    <Condition>DESKTOPSHORTCUT = 1</Condition>
                    <RegistryKey Root="HKCU" Key="SOFTWARE\[Manufacturer]\[ProductName]">
                        <RegistryValue Name="WAU_DesktopShortcut" Type="integer" Value="[DESKTOPSHORTCUT]" KeyPath="yes" />
                    </RegistryKey>
                    <Shortcut Id="DesktopShortcut" Name="Run WAU" Target="[System64Folder]conhost.exe" Arguments="--headless [System64Folder]schtasks.exe -run -tn WAU\Winget-AutoUpdate" Icon="icon.ico" />
                </Component>
            </Directory>
            <Directory Id="ProgramMenuFolder" Name="ProgramMenuFolder">
                <Directory Id="Wau" Name="$ProductName">
                    <Component Id="StartMenuShortcut" Guid="*">
                        <Condition>STARTMENUSHORTCUT = 1</Condition>
                        <RegistryKey Root="HKCU" Key="SOFTWARE\[Manufacturer]\[ProductName]">
                            <RegistryValue Name="WAU_StartMenuShortcut" Type="integer" Value="[STARTMENUSHORTCUT]" KeyPath="yes" />
                        </RegistryKey>
                        <Shortcut Id="StartMenuShortcut1" Name="Run WAU" Target="[System64Folder]schtasks.exe" Arguments="-run -tn WAU\Winget-AutoUpdate" Icon="icon.ico" />
                        <Shortcut Id="StartMenuShortcut2" Name="Open log" Target="[INSTALLDIR]logs\updates.log" />
                        <RemoveFolder Id="WAU" On="uninstall" />
                    </Component>
                </Directory>
            </Directory>
        </Directory>

        <!-- WAU Features -->
        <Feature Id="$ProductId" Title="$ProductName" Level="1">
            <ComponentGroupRef Id="INSTALLDIR" />
            <ComponentRef Id="CompReg" />
            <ComponentRef Id="DesktopShortcut" />
            <ComponentRef Id="StartMenuShortcut" />
        </Feature>

        <!-- UI Config -->
        <UI Id="WixUI_InstallDir">
            <TextStyle Id="WixUI_Font_Normal" FaceName="Tahoma" Size="8" />
            <TextStyle Id="WixUI_Font_Bigger" FaceName="Tahoma" Size="12" />
            <TextStyle Id="WixUI_Font_Title" FaceName="Tahoma" Size="9" Bold="yes" />
            <Property Id="DefaultUIFont" Value="WixUI_Font_Normal" />
            <Property Id="WixUI_Mode" Value="InstallDir" />
            <DialogRef Id="BrowseDlg" />
            <DialogRef Id="DiskCostDlg" />
            <DialogRef Id="ErrorDlg" />
            <DialogRef Id="FatalError" />
            <DialogRef Id="FilesInUse" />
            <DialogRef Id="MsiRMFilesInUse" />
            <DialogRef Id="PrepareDlg" />
            <DialogRef Id="ProgressDlg" />
            <DialogRef Id="ResumeDlg" />
            <DialogRef Id="UserExit" />
            <Publish Dialog="BrowseDlg" Control="OK" Event="DoAction" Value="WixUIValidatePath" Order="3">1</Publish>
            <Publish Dialog="BrowseDlg" Control="OK" Event="SpawnDialog" Value="InvalidDirDlg" Order="4"><![CDATA[NOT WIXUI_DONTVALIDATEPATH AND WIXUI_INSTALLDIR_VALID<>"1"]]></Publish>
            <Publish Dialog="ExitDialog" Control="Finish" Event="DoAction" Value="StartWAU" Order="1">WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 and NOT Installed</Publish>
            <Publish Dialog="ExitDialog" Control="Finish" Event="EndDialog" Value="Return" Order="999">1</Publish>
            <Publish Dialog="WelcomeDlg" Control="Next" Event="NewDialog" Value="WAUInstallDirDlg">1</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="Back" Event="NewDialog" Value="WelcomeDlg">1</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="Next" Event="SetTargetPath" Value="[WIXUI_INSTALLDIR]" Order="1">1</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="Next" Event="DoAction" Value="WixUIValidatePath" Order="2">NOT WIXUI_DONTVALIDATEPATH</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="Next" Event="SpawnDialog" Value="InvalidDirDlg" Order="3"><![CDATA[NOT WIXUI_DONTVALIDATEPATH AND WIXUI_INSTALLDIR_VALID<>"1"]]></Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="Next" Event="NewDialog" Value="WAUConfig" Order="4">WIXUI_DONTVALIDATEPATH OR WIXUI_INSTALLDIR_VALID="1"</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="ChangeFolder" Property="_BrowseProperty" Value="[WIXUI_INSTALLDIR]" Order="1">1</Publish>
            <Publish Dialog="WAUInstallDirDlg" Control="ChangeFolder" Event="SpawnDialog" Value="BrowseDlg" Order="2">1</Publish>
            <Publish Dialog="VerifyReadyDlg" Control="Back" Event="NewDialog" Value="WAUConfig" Order="1">NOT Installed</Publish>
            <Publish Dialog="VerifyReadyDlg" Control="Back" Event="NewDialog" Value="WelcomeDlg" Order="2">Installed</Publish>
            <Publish Dialog="MaintenanceWelcomeDlg" Control="Next" Event="NewDialog" Value="MaintenanceTypeDlg">1</Publish>
            <Publish Dialog="MaintenanceTypeDlg" Control="RepairButton" Event="NewDialog" Value="WAUConfig">1</Publish>
            <Publish Dialog="MaintenanceTypeDlg" Control="RemoveButton" Event="NewDialog" Value="VerifyReadyDlg">1</Publish>
            <Publish Dialog="MaintenanceTypeDlg" Control="Back" Event="NewDialog" Value="MaintenanceWelcomeDlg">1</Publish>
            <Publish Dialog="WAUConfig" Control="Back" Event="NewDialog" Value="WAUInstallDirDlg" Order="1">NOT Installed</Publish>
            <Publish Dialog="WAUConfig" Control="Back" Event="NewDialog" Value="MaintenanceTypeDlg" Order="2">Installed</Publish>
            <Publish Dialog="WAUConfig" Control="Next" Event="NewDialog" Value="VerifyReadyDlg">1</Publish>
            <Property Id="ARPNOMODIFY" Value="1" />

            <!-- WAU Custome UI Config -->
            <Dialog Id="WAUInstallDirDlg" Width="370" Height="270" Title="!(loc.InstallDirDlg_Title)">
                <Control Id="Next" Type="PushButton" X="236" Y="243" Width="56" Height="17" Default="yes" Text="!(loc.WixUINext)" />
                <Control Id="Back" Type="PushButton" X="180" Y="243" Width="56" Height="17" Text="!(loc.WixUIBack)" />
                <Control Id="Cancel" Type="PushButton" X="304" Y="243" Width="56" Height="17" Cancel="yes" Text="!(loc.WixUICancel)">
                    <Publish Event="SpawnDialog" Value="CancelDlg">1</Publish>
                </Control>
                <Control Id="Description" Type="Text" X="25" Y="23" Width="280" Height="15" Transparent="yes" NoPrefix="yes" Text="!(loc.InstallDirDlgDescription)" />
                <Control Id="Title" Type="Text" X="15" Y="6" Width="200" Height="15" Transparent="yes" NoPrefix="yes" Text="!(loc.InstallDirDlgTitle)" />
                <Control Id="BannerBitmap" Type="Bitmap" X="0" Y="0" Width="370" Height="44" TabSkip="no" Text="!(loc.InstallDirDlgBannerBitmap)" />
                <Control Id="BannerLine" Type="Line" X="0" Y="44" Width="370" Height="0" />
                <Control Id="BottomLine" Type="Line" X="0" Y="234" Width="370" Height="0" />
                <Control Id="FolderLabel" Type="Text" X="20" Y="60" Width="290" Height="30" NoPrefix="yes" Text="!(loc.InstallDirDlgFolderLabel)" />
                <Control Id="Folder" Type="PathEdit" X="20" Y="100" Width="320" Height="18" Property="WIXUI_INSTALLDIR" Indirect="yes" />
                <Control Id="ChangeFolder" Type="PushButton" X="20" Y="120" Width="56" Height="17" Text="!(loc.InstallDirDlgChange)" />
                <Control Id="WAUDesktopShortcut" Type="CheckBox" Width="155" Height="17" X="20" Y="180" Text="Install Desktop shortcut" Property="DESKTOPSHORTCUT_CHECKED" CheckBoxValue="1">
                    <Publish Property="DESKTOPSHORTCUT" Value="1" Order="1">DESKTOPSHORTCUT_CHECKED</Publish>
                    <Publish Property="DESKTOPSHORTCUT" Value="0" Order="2">NOT DESKTOPSHORTCUT_CHECKED</Publish>
                </Control>
                <Control Id="WAUStartMenuShortcut" Type="CheckBox" Width="155" Height="17" X="20" Y="200" Text="Install Start Menu shortcut" Property="STARTMENUSHORTCUT_CHECKED" CheckBoxValue="1">
                    <Publish Property="STARTMENUSHORTCUT" Value="1" Order="1">STARTMENUSHORTCUT_CHECKED</Publish>
                    <Publish Property="STARTMENUSHORTCUT" Value="0" Order="2">NOT STARTMENUSHORTCUT_CHECKED</Publish>
                </Control>
            </Dialog>
            <Dialog Id="WAUConfig" Width="370" Height="270" Title="!(loc.InstallDirDlg_Title)">
                <Control Id="Next" Type="PushButton" X="236" Y="243" Width="56" Height="17" Default="yes" Text="!(loc.WixUINext)" />
                <Control Id="Back" Type="PushButton" X="180" Y="243" Width="56" Height="17" Text="!(loc.WixUIBack)" />
                <Control Id="Cancel" Type="PushButton" X="304" Y="243" Width="56" Height="17" Cancel="yes" Text="!(loc.WixUICancel)">
                    <Publish Event="SpawnDialog" Value="CancelDlg">1</Publish>
                </Control>
                <Control Id="Title" Type="Text" X="15" Y="6" Width="200" Height="15" Transparent="yes" NoPrefix="yes" Text="{\WixUI_Font_Title}WAU Configuration" />
                <Control Id="Description" Type="Text" X="25" Y="23" Width="280" Height="15" Transparent="yes" NoPrefix="yes" Text="Select the configuration and click on Next" />
                <Control Id="BannerBitmap" Type="Bitmap" X="0" Y="0" Width="370" Height="44" TabSkip="no" Text="WixUI_Bmp_Banner" />
                <Control Id="BannerLine" Type="Line" X="0" Y="44" Width="370" Height="0" />
                <Control Id="BottomLine" Type="Line" X="0" Y="234" Width="370" Height="0" />
                <Control Id="NotifLevelLabel" Type="Text" X="20" Y="60" Width="76" Height="14" NoPrefix="yes" Text="Notification level:" />
                <Control Id="NotifLevelComboBox" Type="ComboBox" X="98" Y="58" Width="70" Height="16" Property="NOTIFICATIONLEVEL_VALUE" ComboList="yes" Sorted="yes">
                    <ComboBox Property="NOTIFICATIONLEVEL_VALUE">
                        <ListItem Value="Full" Text="Full" />
                        <ListItem Value="SuccessOnly" Text="Succes only" />
                        <ListItem Value="None" Text="None" />
                    </ComboBox>
                </Control>
                <Control Type="CheckBox" Id="UserContextCheckBox" Width="190" Height="14" X="20" Y="80" Text="Install WAU with User context execution too" Property="USERCONTEXT_CHECKED" CheckBoxValue="1">
                    <Publish Property="USERCONTEXT" Value="1" Order="1">USERCONTEXT_CHECKED</Publish>
                    <Publish Property="USERCONTEXT" Value="0" Order="2">NOT USERCONTEXT_CHECKED</Publish>
                </Control>
                <Control Type="CheckBox" Id="WAUAutoUpdateCheckBox" Width="190" Height="14" X="20" Y="100" Text="Disable WAU Auto Update" Property="DISABLEWAUAUTOUPDATE_CHECKED" CheckBoxValue="1">
                    <Publish Property="DISABLEWAUAUTOUPDATE" Value="1" Order="1">DISABLEWAUAUTOUPDATE_CHECKED</Publish>
                    <Publish Property="DISABLEWAUAUTOUPDATE" Value="0" Order="2">NOT DISABLEWAUAUTOUPDATE_CHECKED</Publish>
                </Control>
                <Control Type="GroupBox" Id="RadioGroupText" Width="320" Height="58" X="20" Y="122" Text="Update interval" />
                <Control Type="RadioButtonGroup" Id="UpdateIntervalRad" Property="UPDATESINTERVAL_VALUE" Width="300" Height="18" X="30" Y="136">
                    <RadioButtonGroup Property="UPDATESINTERVAL_VALUE">
                        <RadioButton Text="Daily" Height="17" Value="Daily" Width="58" X="0" Y="0" />
                        <RadioButton Text="Weekly" Height="17" Value="Weekly" Width="58" X="60" Y="0" />
                        <RadioButton Text="Biweekly" Height="17" Value="Biweekly" Width="58" X="120" Y="0" />
                        <RadioButton Text="Monthly" Height="17" Value="Monthly" Width="58" X="180" Y="0" />
                        <RadioButton Text="Never" Height="17" Value="Never" Width="58" X="240" Y="0" />
                    </RadioButtonGroup>
                </Control>
                <Control Type="CheckBox" Id="WAUUpdatesAtLogonCheckBox" Width="140" Height="14" X="30" Y="158" Text="Run WAU at user logon" Property="UPDATESATLOGON_CHECKED" CheckBoxValue="1">
                    <Publish Property="UPDATESATLOGON" Value="1" Order="1">UPDATESATLOGON_CHECKED</Publish>
                    <Publish Property="UPDATESATLOGON" Value="0" Order="2">NOT UPDATESATLOGON_CHECKED</Publish>
                </Control>
                <Control Type="Text" Id="ListTextBox" Width="313" Height="12" X="20" Y="190" Text="Provided list: (The list must be in the same directory as this installer)" />
                <Control Type="Edit" Id="ListEdit" Width="320" Height="17" X="20" Y="202" Property="B_W_LIST_PATH" Disabled="yes" />
            </Dialog>
        </UI>
        <UIRef Id="WixUI_Common" />

        <!-- Set properties -->
        <SetProperty Id="DESKTOPSHORTCUT_CHECKED" After="AppSearch" Value="1">DESKTOPSHORTCUT_VALUE = "#1"</SetProperty>
        <SetProperty Action="SetDESKTOPSHORTCUT_0" Id="DESKTOPSHORTCUT" After="AppSearch" Value="0"><![CDATA[(NOT DESKTOPSHORTCUT) AND (DESKTOPSHORTCUT_VALUE <> "#1")]]></SetProperty>
        <SetProperty Action="SetDESKTOPSHORTCUT_1" Id="DESKTOPSHORTCUT" After="AppSearch" Value="1"><![CDATA[(NOT DESKTOPSHORTCUT) AND (DESKTOPSHORTCUT_VALUE = "#1")]]></SetProperty>
        <SetProperty Id="STARTMENUSHORTCUT_CHECKED" After="AppSearch" Value="1">STARTMENUSHORTCUT_VALUE = "#1"</SetProperty>
        <SetProperty Action="SetSTARTMENUSHORTCUT_0" Id="STARTMENUSHORTCUT" After="AppSearch" Value="0"><![CDATA[(NOT STARTMENUSHORTCUT) AND (STARTMENUSHORTCUT_VALUE <> "#1")]]></SetProperty>
        <SetProperty Action="SetSTARTMENUSHORTCUT_1" Id="STARTMENUSHORTCUT" After="AppSearch" Value="1"><![CDATA[(NOT STARTMENUSHORTCUT) AND (STARTMENUSHORTCUT_VALUE = "#1")]]></SetProperty>
        <SetProperty Id="NOTIFICATIONLEVEL_VALUE" After="AppSearch" Value="[NOTIFICATIONLEVEL]">NOTIFICATIONLEVEL</SetProperty>
        <SetProperty Action="SetUSERCONTEXT_0" Id="USERCONTEXT" After="AppSearch" Value="0"><![CDATA[(NOT USERCONTEXT) AND (USERCONTEXT_REG <> "#1")]]></SetProperty>
        <SetProperty Action="SetUSERCONTEXT_1" Id="USERCONTEXT" After="AppSearch" Value="1"><![CDATA[(NOT USERCONTEXT) AND (USERCONTEXT_REG = "#1")]]></SetProperty>
        <SetProperty Id="USERCONTEXT_CHECKED" After="AppSearch" Value="1">USERCONTEXT_REG = "#1"</SetProperty>
        <SetProperty Action="SetDISABLEWAUAUTOUPDATE_0" Id="DISABLEWAUAUTOUPDATE" After="AppSearch" Value="0"><![CDATA[(NOT DISABLEWAUAUTOUPDATE) AND (DISABLEWAUAUTOUPDATE_REG <> "#1")]]></SetProperty>
        <SetProperty Action="SetDISABLEWAUAUTOUPDATE_1" Id="DISABLEWAUAUTOUPDATE" After="AppSearch" Value="1"><![CDATA[(NOT DISABLEWAUAUTOUPDATE) AND (DISABLEWAUAUTOUPDATE_REG = "#1")]]></SetProperty>
        <SetProperty Id="DISABLEWAUAUTOUPDATE_CHECKED" After="AppSearch" Value="1">DISABLEWAUAUTOUPDATE_REG = "#1"</SetProperty>
        <SetProperty Id="UPDATESINTERVAL_VALUE" After="AppSearch" Value="[UPDATESINTERVAL]">UPDATESINTERVAL</SetProperty>
        <SetProperty Action="SetUPDATESATLOGON_0" Id="UPDATESATLOGON" After="AppSearch" Value="0"><![CDATA[(NOT UPDATESATLOGON) AND (UPDATESATLOGON_REG <> "#1")]]></SetProperty>
        <SetProperty Action="SetUPDATESATLOGON_1" Id="UPDATESATLOGON" After="AppSearch" Value="1"><![CDATA[(NOT UPDATESATLOGON) AND (UPDATESATLOGON_REG = "#1")]]></SetProperty>
        <SetProperty Id="UPDATESATLOGON_CHECKED" After="AppSearch" Value="1">UPDATESATLOGON_REG = "#1"</SetProperty>
        <SetProperty Action="SetLIST_PATHBlackList" Id="B_W_LIST_PATH" After="AppSearch" Value="[BLACKLIST_PATH]">BLACKLIST_PATH</SetProperty>
        <SetProperty Action="SetLIST_PATHWhiteList" Id="B_W_LIST_PATH" After="SetLIST_PATHBlackList" Value="[WHITELIST_PATH]">WHITELIST_PATH</SetProperty>
        <SetProperty Action="SetUSEWHITELIST_0" Id="USEWHITELIST" After="SetLIST_PATHWhiteList" Value="0">BLACKLIST_PATH OR USEWHITELIST = "#0"</SetProperty>
        <SetProperty Action="SetUSEWHITELIST_1" Id="USEWHITELIST" After="SetUSEWHITELIST_0" Value="1">WHITELIST_PATH OR USEWHITELIST = "#1"</SetProperty>
        <SetProperty Id="LISTPATH_VALUE" After="AppSearch" Value="[LISTPATH]">LISTPATH</SetProperty>
        <SetProperty Id="MODPATH_VALUE" After="AppSearch" Value="[MODPATH]">MODPATH</SetProperty>
        <SetProperty Id="AZUREBLOBURL_VALUE" After="AppSearch" Value="[AZUREBLOBURL]">AZUREBLOBURL</SetProperty>
        <SetProperty Id="DONOTRUNONMETERED_VALUE" After="AppSearch" Value="#[DONOTRUNONMETERED]">DONOTRUNONMETERED</SetProperty>
        <SetProperty Id="UPDATESATTIME_VALUE" After="AppSearch" Value="[UPDATESATTIME]">UPDATESATTIME</SetProperty>
        <SetProperty Id="BYPASSLISTFORUSERS_VALUE" After="AppSearch" Value="#[BYPASSLISTFORUSERS]">BYPASSLISTFORUSERS</SetProperty>
        <SetProperty Id="MAXLOGFILES_VALUE" After="AppSearch" Value="#[MAXLOGFILES]">MAXLOGFILES</SetProperty>
        <SetProperty Id="MAXLOGSIZE_VALUE" After="AppSearch" Value="#[MAXLOGSIZE]">MAXLOGSIZE</SetProperty>
        <SetProperty Action="SetUPDATEPRERELEASE_0" Id="UPDATEPRERELEASE" After="AppSearch" Value="0"><![CDATA[(NOT UPDATEPRERELEASE) AND (UPDATEPRERELEASE_REG <> "#1")]]></SetProperty>
        <SetProperty Action="SetUPDATEPRERELEASE_1" Id="UPDATEPRERELEASE" After="AppSearch" Value="1"><![CDATA[(NOT UPDATEPRERELEASE) AND (UPDATEPRERELEASE_REG = "#1")]]></SetProperty>
        <SetProperty Id="CA_PowerShell_Install" Before="CA_PowerShell_Install" Sequence="execute" Value="&quot;[%SystemDrive]\Windows\$platformSysFolder\WindowsPowerShell\v1.0\powershell.exe&quot; -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -File &quot;[INSTALLDIR]WAU-MSI_Actions.ps1&quot; &quot;[B_W_LIST_PATH]&quot; -InstallPath &quot;[INSTALLDIR]" />
        <SetProperty Id="CA_PowerShell_Uninstall" Before="CA_PowerShell_Uninstall" Sequence="execute" Value="&quot;[%SystemDrive]\Windows\$platformSysFolder\WindowsPowerShell\v1.0\powershell.exe&quot; -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -File &quot;[INSTALLDIR]WAU-MSI_Actions.ps1&quot; -Uninstall -InstallPath &quot;[INSTALLDIR]" />

        <!-- Custom Actions -->
        <CustomAction Id="StartWAU" Impersonate="yes" ExeCommand="schtasks /run /tn WAU\Winget-AutoUpdate" Directory="INSTALLDIR" Return="ignore" />
        <CustomAction Id="CA_PowerShell_Install" BinaryKey="WixCA" DllEntry="WixQuietExec" Execute="deferred" Return="check" Impersonate="no" />
        <CustomAction Id="CA_PowerShell_Uninstall" BinaryKey="WixCA" DllEntry="WixQuietExec" Execute="deferred" Return="ignore" Impersonate="no" />
        <InstallExecuteSequence>
            <Custom Action="StartWAU" After="InstallFinalize">RUN_WAU="YES"</Custom>
            <Custom Action="CA_PowerShell_Install" Before="InstallFinalize">NOT (REMOVE="ALL")</Custom>
            <Custom Action="CA_PowerShell_Uninstall" Before="RemoveFiles">REMOVE="ALL"</Custom>
        </InstallExecuteSequence>
    </Product>
</Wix>
"@


    # Save XML and create productWxs
    $wixXml.Save($modulesWxs)
    & $heatExe dir $Sources -nologo -sfrag -sw5150 -ag -srd -gg -dir $ProductName -out $productWxs -cg INSTALLDIR -dr INSTALLDIR

    # Produce wixobj files
    & $candleexe $modulesWxs -out $modulesWixobj
    & $candleexe $productWxs -out $productWixobj
}
foreach ($platform in $platforms) {
    $platformArch = $platform.arch
    $modulesWixobj = Join-Path $Path "_modules${platformArch}.wixobj"
    $productWixobj = Join-Path $Path ".wixobj${platformArch}"
    $platformOutputMsi = $platform.outputMsi

    # Produce the MSI file
    & $lightexe -sval -sw1076 -spdb -ext WixUIExtension -ext WixUtilExtension -out $platformOutputMsi $modulesWixobj $productWixobj -b $Sources -sice:ICE91 -sice:ICE69 -sice:ICE38 -sice:ICE57 -sice:ICE64 -sice:ICE204 -sice:ICE80
}
