[CmdletBinding(PositionalBinding=$false)]
Param(
  [string] $configuration = "Debug",
  [string] $solution = "",
  [string] $verbosity = "minimal",
  [string] $dotnetcliversion = "",
  [string] $toolsetversion = "",
  [string] $packagename = "",
  [string] $packageversion = "",
  [string] $packagesource = "",
  [switch] $addpackage,
  [switch] $restore,
  [switch] $build,
  [switch] $rebuild,
  [switch] $test,
  [switch] $sign,
  [switch] $pack,
  [switch] $ci,
  [switch] $prepareMachine,
  [switch] $log,
  [switch] $help,
  [Parameter(ValueFromRemainingArguments=$true)][String[]]$properties
)

set-strictmode -version 2.0
$ErrorActionPreference = "Stop"

function Print-Usage() {
    Write-Host "Common settings:"
    Write-Host "  -configuration <value>  Build configuration Debug, Release"
    Write-Host "  -verbosity <value>      Msbuild verbosity (q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic])"
    Write-Host "  -help                   Print help and exit"
    Write-Host ""

    Write-Host "Actions:"
    Write-Host "  -restore                Restore dependencies"
    Write-Host "  -build                  Build solution"
    Write-Host "  -rebuild                Rebuild solution"
    Write-Host "  -test                   Run all unit tests in the solution"
    Write-Host "  -sign                   Sign build outputs"
    Write-Host "  -pack                   Package build outputs into NuGet packages and Willow components"
    Write-Host "  -addpackage <arguments> <options>   Add a package to the repo toolset project, see below for arguments and options"
    Write-Host ""

    Write-Host "Advanced settings:"
    Write-Host "  -solution <value>       Path to solution to build"
    Write-Host "  -ci                     Set when running on CI server"
    Write-Host "  -log                    Enable logging (by default on CI)"
    Write-Host "  -prepareMachine         Prepare machine for CI run"
    Write-Host "  -dotnetcliversion <value> Specify cli version to restore (defaults to value specified in Directory.Build.props)"
    Write-Host "  -toolsetversion <value> Specify Repo Toolset version to restore (defaults to value specified in Directory.Build.props)"
    Write-Host ""

    Write-Host "AddPackage arguments:"
    Write-Host "  -packagename <value>"
    Write-Host "  -packageversion <value>"
    Write-Host "AddPackage options:"
    Write-Host "  -packagesource <value>"
    Write-Host ""

    Write-Host "Command line arguments not listed above are passed thru to msbuild."
    Write-Host "The above arguments can be shortened as much as to be unambiguous (e.g. -co for configuration, -t for test, etc.)."
}

if ($help -or (($properties -ne $null) -and ($properties.Contains("/help") -or $properties.Contains("/?")))) {
  Print-Usage
  exit 0
}

function Create-Directory([string[]] $path) {
  if (!(Test-Path $path)) {
    New-Item -path $path -force -itemType "Directory" | Out-Null
  }
}

function GetVersion([string] $name) {
  foreach ($propertyGroup in $VersionsXml.Project.PropertyGroup) {
    if (Get-Member -inputObject $propertyGroup -name $name) {
        return $propertyGroup.$name
    }
  }

  throw "Failed to find $name in $VersionsXml"
}

function InstallDotNetCli {
  
  Create-Directory $DotNetRoot

  # Determine DotNetCliVersion from Directory.Build.props or from command-line   
  if ($ToolsetVersionsPropsFile -eq "" -and $dotnetCliVersion -eq "")
  {
    Write-Host "Error: Please define 'DotNetCliVersion' in Directory.Build.props or alternatively explicitly specify '-dotnetcliversion <value>'"
    exit 1
  }
  elseif ( $dotnetCliVersion -eq "") {
    $dotnetCliVersion = GetVersion("DotNetCliVersion")
  }
  else {
    Write-Host "Using explicitly specified dotnet cli version '$dotnetCliVersion'"
  }

  $installScript = "$DotNetRoot\dotnet-install.ps1"
  if (!(Test-Path $installScript)) { 
    Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/cli/release/2.0.0/scripts/obtain/dotnet-install.ps1" -OutFile $installScript
  }
  
  & $installScript -Version $dotnetCliVersion -InstallDir $DotNetRoot
  if ($lastExitCode -ne 0) {
    throw "Failed to install dotnet cli (exit code '$lastExitCode')."
  }
}

function AddPackageToToolset {
  if ($packagename -eq "" -Or $packageversion -eq "") {
    Write-Host "Missing required option 'packagename' or 'packageversion'"
    exit 1
  }
  $restoreArgs = @()
  if ($packagesource -ne "") {
    $restoreArgs += "--source"
    $restoreArgs += $packageSource
    Say "Add a reference to '$packageSource' in your feed sources (NuGet.Config, RestoreSources, etc...) to prevent future Restore issues with the Toolset project"
  }

  & $DotNetExe add $ToolsetRestoreProj package $packagename --version $packageversion --package-directory $NuGetPackageRoot $restoreArgs

}
function InstallToolset {
    & $DotNetExe msbuild $ToolsetRestoreProj /t:restore /m /nologo /clp:Summary /warnaserror /v:$verbosity /p:RestorePackagesPath=$NuGetPackageRoot /p:NuGetPackageRoot=$NuGetPackageRoot /p:ExcludeRestorePackageImports=false /p:RoslynToolsRepoToolsetVersion=$ToolsetVersion
}

function Build {
  if ($ci -or $log) {
    Create-Directory($logDir)
    $logCmd = "/bl:" + (Join-Path $LogDir "Build.binlog")
  } else {
    $logCmd = ""
  }
 
  & $DotNetExe msbuild $ToolsetBuildProj /m /nologo /clp:Summary /warnaserror /v:$verbosity $logCmd /p:Configuration=$configuration /p:SolutionPath=$solution /p:Restore=$restore /p:Build=$build /p:Rebuild=$rebuild /p:Test=$test /p:Sign=$sign /p:Pack=$pack /p:CIBuild=$ci /p:NuGetPackageRoot=$NuGetPackageRoot $properties
}

function Stop-Processes() {
  Write-Host "Killing running build processes..."
  Get-Process -Name "dotnet" -ErrorAction SilentlyContinue | Stop-Process
  Get-Process -Name "vbcscompiler" -ErrorAction SilentlyContinue | Stop-Process
}

function Find-File([string] $directory, [string] $filename) {
  if ($directory -eq "") {
    return ""
  }

  $file = Join-Path $directory $filename
  Write-Host "Looking for file, '$filename' in '$directory'"
  if (Test-Path $file) {
    return $file
  }
  $directory = Split-Path -Path $directory -Parent
  return Find-File $directory $filename
}


try {

  $RepoRoot = Join-Path $PSScriptRoot "..\..\"
  $DotNetRoot = Join-Path $RepoRoot ".dotnet"
  $DotNetExe = Join-Path $DotNetRoot "dotnet.exe"
  $BuildProj = Join-Path $PSScriptRoot "build.proj"
  $ToolsetRestoreProj = Join-Path $PSScriptRoot "Toolset.proj"
  $ArtifactsDir = Join-Path $RepoRoot "artifacts"
  $ToolsetDir = Join-Path $ArtifactsDir "toolset"
  $LogDir = Join-Path (Join-Path $ArtifactsDir $configuration) "log"
  $TempDir = Join-Path (Join-Path $ArtifactsDir $configuration) "tmp"
  $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "true"

  # Search for the ToolsetVersions.props file in the current or any parent directory
  $toolsetVersionsPropsFile = Find-File $PSScriptRoot "Directory.Build.props"
  if($toolsetVersionsPropsFile -eq "")
  {
    Write-Host "Cannot find file 'Directory.Build.props' in any parent directories."
  }
  else {
    [xml]$VersionsXml = Get-Content($toolsetVersionsPropsFile)
  }

  if ($solution -eq "") {
    $solution = @(gci(Join-Path $RepoRoot "*.sln"))[0]
  }

  if ($env:NUGET_PACKAGES -ne $null) {
    $NuGetPackageRoot = $env:NUGET_PACKAGES.TrimEnd("\") + "\"
  } else {
    $NuGetPackageRoot = (Join-Path $RepoRoot "packages") + "\"
  }

  if ($ci) {
    Create-Directory $TempDir
    $env:TEMP = $TempDir
    $env:TMP = $TempDir
  }

  # Determine toolsetversion either from ToolsetVersion.props or from command-line
  if ($toolsetVersionsPropsFile -eq "" -and $toolsetversion -eq "")
  {
    Write-Host "Error: Please define 'RoslynToolsRepoToolsetVersion' in Directory.Build.props or alternatively explicitly specify '-toolsetversion <value>'"
    exit 1
  }
  elseif ( $ToolsetVersion -eq "" ) {
    $ToolsetVersion = GetVersion("RoslynToolsRepoToolsetVersion")
  }
  else {
    Write-Host "Using explicitly specified toolset version '$ToolsetVersion'"
  }

  if ($restore) {
    InstallDotNetCli
    InstallToolset
  }

  if ($addpackage) {
    AddPackageToToolset
  }

  if ($build) {
    $ToolsetBuildProj = Join-Path $NuGetPackageRoot "roslyntools.repotoolset\$ToolsetVersion\tools\Build.proj"
    Build
  }
  exit $lastExitCode
}
catch {
  Write-Host $_
  Write-Host $_.Exception
  Write-Host $_.ScriptStackTrace
  exit 1
}
finally {
  Pop-Location
  if ($ci -and $prepareMachine) {
    Stop-Processes
  }
}
