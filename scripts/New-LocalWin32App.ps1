#Requires -PSEdition Desktop
#Requires -Modules Evergreen, VcRedist
<#
    Import application packages into Intune locally
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
param (
    [Parameter()]
    [System.String] $Path = "E:\projects\packagefactory",

    [Parameter()]
    [System.String] $PackageFolder = "packages",

    [Parameter()]
    [System.String] $PackageManifest = "App.json",

    [Parameter()]
    [System.String[]] $Applications = @("Microsoft.NET",
        "MicrosoftVcRedist2022x86",
        "MicrosoftVcRedist2022x64",
        "AdobeAcrobatReaderDCMUI",
        "ImageCustomise"),

    [Parameter()]
    [ValidateSet("Apps", "Updates")]
    [System.String] $Type = "Apps"
)

foreach ($Application in $Applications) {
    try {
        # Get the application details
        Write-Host "Application: $Application"
        $AppPath = [System.IO.Path]::Combine($Path, $PackageFolder, $Type, $Application)
        Write-Host -ForegroundColor "Cyan" "Read: $([System.IO.Path]::Combine($AppPath, $PackageManifest))"
        $Manifest = Get-Content -Path $([System.IO.Path]::Combine($AppPath, $PackageManifest)) | ConvertFrom-Json
    }
    catch {
        throw $_
    }

    # Download the application installer
    if ($Null -eq $Manifest.Application.Filter) {
        Write-Host -ForegroundColor "Cyan" "$Application not supported for automatic download."
    }
    else {
        if ($Manifest.Application.Filter -match "Get-VcList") {

            Write-Host -ForegroundColor "Cyan" "Filter: $($Manifest.Application.Filter)"
            $App = Invoke-Expression -Command $Manifest.Application.Filter
            $Filename = $(Split-Path -Path $App.Download -Leaf)
            Write-Host -ForegroundColor "Cyan" "Package: $($App.Name); $Filename."
            New-Item -Path [System.IO.Path]::Combine($AppPath, $Manifest.PackageInformation.SourceFolder) -ItemType "Directory" -Force | Out-Null
            Invoke-WebRequest -Uri $App.Download -OutFile $([System.IO.Path]::Combine($AppPath, $Manifest.PackageInformation.SourceFolder, $Filename)) -UseBasicParsing
        }
        else {

            if (Test-Path -Path $Manifest.PackageInformation.SetupFile) {
                Write-Information -MessageData "File exists: $($Manifest.PackageInformation.SetupFile)" -InformationAction "Continue"
            }
            else {

                # Get the application installer via Evergreen and download
                $result = Invoke-Expression -Command $Manifest.Application.Filter | Save-EvergreenApp -CustomPath $([System.IO.Path]::Combine($Path, $PackageFolder, $Type, $AppItem, $Manifest.PackageInformation.SourceFolder))

                # Unpack the installer file if its a zip file
                Write-Host "Downloaded: $($result.FullName)"
                if ($result.FullName -match "\.zip$") {
                    $params = @{
                        Path            = $result.FullName
                        DestinationPath = $([System.IO.Path]::Combine($Path, $PackageFolder, $Type, $AppItem, $Manifest.PackageInformation.SourceFolder))
                    }
                    Write-Host "Expand: $($result.FullName)"
                    Expand-Archive @params
                    Remove-Item -Path $result.FullName -Force
                }

                # Run the command defined in PrePackageCmd
                if ($Manifest.Application.PrePackageCmd.Length -gt 0) {
                    $params = @{
                        FilePath     = $result.FullName
                        ArgumentList = $($Manifest.Application.PrePackageCmd -replace "#Path", $([System.IO.Path]::Combine($Path, $PackageFolder, $Type, $AppItem, $Manifest.PackageInformation.SourceFolder)))
                        NoNewWindow  = $True
                        Wait         = $True
                    }
                    Write-Host "Start: $($result.FullName) $($Manifest.Application.PrePackageCmd -replace "#Path", $([System.IO.Path]::Combine($Path, $PackageFolder, $Type, $AppItem, $Manifest.PackageInformation.SourceFolder)))"
                    Start-Process @params
                    Remove-Item -Path $result.FullName -Force
                }
            }
        }
    }

    # Package the application
    if (Test-Path -Path $([System.IO.Path]::Combine($AppPath, $Manifest.PackageInformation.SourceFolder))) {
        $params = @{
            Application       = $Application
            Path              = $([System.IO.Path]::Combine($Path, $PackageFolder))
            Type              = $Type
            DisplayNameSuffix = ""
        }
        .\Create-Win32App.ps1 @params
    }
    else {
        Write-Error -Message "Cannot find path $([System.IO.Path]::Combine($AppPath, $Manifest.PackageInformation.SourceFolder))"
    }
}
