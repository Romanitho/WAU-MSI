[Cmdletbinding()]
Param(
  [Parameter(Mandatory = $false, Position = 0)]  [string] $Path = (Get-Location).Path,
  [Parameter(Mandatory = $false)]  [string] $Sources = (Get-Location).Path,
  [Parameter(Mandatory = $false)]  [string] $OutputFolder = (Get-Location).Path,
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
  [Parameter(Mandatory = $false)]  [switch] $NoX86,
  [Parameter(Mandatory = $false)]  [switch] $NoX64
)

$ProgressPreference = "SilentlyContinue"

# WiX paths
If (!(Get-ChildItem -Path "$env:HOMEDRIVE\Program Files*\WiX*\" -Filter heat.exe -Recurse)) {
  $ToolSetURL = "https://github.com/wixtoolset/wix3/releases/download/wix314rtm/wix314.exe"
  Invoke-WebRequest -Uri $ToolSetURL -OutFile (Join-Path $Path \wix.exe) -UseBasicParsing
  Start-Process .\wix.exe -ArgumentList "/S" -Wait
}
$wixDir = Split-Path ((((Get-ChildItem -Path "$env:HOMEDRIVE\Program Files*\WiX*\" -Filter heat.exe -Recurse) | Select-Object FullName)[0]).FullName)
$heatExe = Join-Path $wixDir "heat.exe"
$candleExe = Join-Path $wixDir "candle.exe"
$lightExe = Join-Path $wixDir "light.exe"

# Platform settings
$platforms = @()

$x86Settings = @{ 'arch' = 'x86';
  'sysFolder'            = 'SystemFolder';
  'progfolder'           = 'ProgramFilesFolder';
  'upgradeCode'          = $UpgradeCodeX86;
  'productName'          = "${ProductName} (x86)";
  'outputMsi'            = (Join-Path $OutputFolder ($productID + "_" + $ProductVersion + "_x86.msi"))
}
$x64Settings = @{ 'arch' = 'x64';
  'sysFolder'            = 'System64Folder';
  'progfolder'           = 'ProgramFiles64Folder';
  'upgradeCode'          = $UpgradeCodeX64;
  'productName'          = "${ProductName} (x64)";
  'outputMsi'            = (Join-Path $OutputFolder ($productID + "_" + $ProductVersion + "_x64.msi"))
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
  $platformUpgradeCode = $platform.upgradeCode
  $platformProgFolder = $platform.progFolder
  $platformProductName = $platform.productName

  $modulesWxs = Join-Path $Path "_modules${platformArch}.wxs"
  $productWxs = Join-Path $Path ".wxs${platformArch}"
  $modulesWixobj = Join-Path $Path "_modules${platformArch}.wixobj"
  $productWixobj = Join-Path $Path ".wixobj${platformArch}"

  # Build XML
  $wixXml = [xml] @"
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns='http://schemas.microsoft.com/wix/2006/wi'>
  <Product Id="*" Language="1033" Name="$platformProductName" Version="$ProductVersion" Manufacturer="$Manufacturer" UpgradeCode="$platformUpgradeCode" >

    <Package Id="*" Description="$platformProductName Installer" InstallPrivileges="elevated" Comments="$ProductName Installer" InstallerVersion="200" Compressed="yes" Platform="$platformArch"/>
    <Icon Id="icon.ico" SourceFile="$IconFile"/>
    
    <Property Id="ARPPRODUCTICON" Value="icon.ico" />
    <Property Id="LISTPATH" Value="null" />
    <Property Id="MODSPATH" Value="null" />
    <Property Id="AZUREBLOBURL" Value="null" />
    <Property Id="DESKTOPSHORTCUT" Value="0" />
    <Property Id="NOTIFICATIONLEVEL" Value="Full" />
    <Property Id="UPDATESATLOGON" Value="1" />
    <Property Id="UPDATESINTERVAL" Value="Weekly" />
    <Property Id="UPDATESATTIME" Value="06am" />
    <Property Id="RUNONMETERED" Value="0" />
    <Property Id="INSTALLUSERCONTEXT" Value="1" />
    <Property Id="BYPASSLISTFORUSERS" Value="null" />
    <Property Id="RUNWAU" Value="0" />
    <Property Id="DISABLEWAUAUTOUPDATE" Value="0" />
    <Property Id="USEWHITELIST" Value="0" />
    <Property Id="MAXLOGFILES" Value="3" />
    <Property Id="MAXLOGSIZE" Value="1048576" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Run WAU after closing this wizard." />
    <Property Id="WixShellExecTarget" Value="schtasks /run /tn WAU\Winget-AutoUpdate" />
    <Property Id="ARPHELPLINK" Value="$HelpLink"/>
    <Property Id="ARPURLINFOABOUT" Value="$AboutLink"/>
    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLDIR"/>

    <Upgrade Id="$platformUpgradeCode">
      <!-- Detect any newer version of this product -->
      <UpgradeVersion Minimum="$ProductVersion" IncludeMinimum="no" OnlyDetect="yes" Language="1033" Property="NEWPRODUCTFOUND" />

      <!-- Detect and remove any older version of this product -->
      <UpgradeVersion Maximum="$ProductVersion" IncludeMaximum="yes" OnlyDetect="no" Language="1033" Property="OLDPRODUCTFOUND" />
    </Upgrade>

    <!-- Define a custom action -->
    <CustomAction Id="PreventDowngrading" Error="Newer version already installed." />

    <InstallExecuteSequence>
      <!-- Prevent downgrading -->
      <Custom Action="PreventDowngrading" After="FindRelatedProducts">NEWPRODUCTFOUND</Custom>
      <RemoveExistingProducts After="InstallFinalize" />
    </InstallExecuteSequence>

    <InstallUISequence>
      <!-- Prevent downgrading -->
      <Custom Action="PreventDowngrading" After="FindRelatedProducts">NEWPRODUCTFOUND</Custom>
    </InstallUISequence>

    <MediaTemplate EmbedCab="yes"/>
    <WixVariable Id="WixUIBannerBmp" Value="$BannerFile"></WixVariable>
    <WixVariable Id="WixUIDialogBmp" Value="$DialogFile"></WixVariable>

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="$platformProgFolder" Name="$platformProgFolder">
        <Directory Id="INSTALLDIR" Name="$ProductName"/>
      </Directory>
    </Directory>
    
    <Feature Id="$ProductId" Title="$ProductName" Level="1">
        <ComponentGroupRef Id="INSTALLDIR">
        </ComponentGroupRef>
    </Feature>
    <UIRef Id="WixUI_InstallDir"/>
    <UI>
    	<Publish Control="Next" Dialog="WelcomeDlg" Value="InstallDirDlg" Event="NewDialog">1</Publish>
		  <Publish Control="Back" Dialog="InstallDirDlg" Value="WelcomeDlg" Event="NewDialog" Order="2">2</Publish>
    </UI>
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
  & $lightexe -sval -sw1076 -spdb -ext WixUIExtension -out $platformOutputMsi $modulesWixobj $productWixobj -b $Sources -sice:ICE91 -sice:ICE69 -sice:ICE38 -sice:ICE57 -sice:ICE64 -sice:ICE204 -sice:ICE80
}
