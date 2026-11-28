[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [switch]$Incremental
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = [IO.Path]::GetFullPath((Split-Path -Parent $scriptDir))
$configurationKey = $Configuration.ToLowerInvariant()
$presetName = "windows-x64-$configurationKey"
$buildDir = Join-Path $root "build\$configurationKey"
$distDir = Join-Path $root "dist"
$stageDir = Join-Path $distDir "ReShade Launcher"
$defaultsDir = Join-Path $distDir "ReShade Launcher Defaults"
$releaseDir = Join-Path $distDir "release"
$portableDir = Join-Path $distDir "portable"

function Find-FirstExisting {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $root
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Child,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $resolvedChild = [IO.Path]::GetFullPath($Child).TrimEnd('\', '/')
    $resolvedParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    if (-not $resolvedChild.StartsWith(
        $resolvedParent + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to modify path outside $resolvedParent`: $resolvedChild"
    }
}

function Reset-GeneratedDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-ChildPath -Child $Path -Parent $distDir
    if (Test-Path -LiteralPath $Path) {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force
            }
            try {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
            catch {
                if ((Get-ChildItem -LiteralPath $Path -Force | Measure-Object).Count -gt 0) {
                    throw
                }
                Write-Warning "Reusing empty generated directory with an external handle: $Path"
            }
        } else {
            Remove-Item -LiteralPath $Path -Force
        }
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-FileIfPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $DestinationDirectory -Force
}

function Copy-Tree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }
    Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
        $relative = Get-RelativePath -BasePath $Source -TargetPath $_.FullName
        $target = Join-Path $Destination $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

function Copy-FilteredTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][scriptblock]$Include
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }
    Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
        $relative = Get-RelativePath -BasePath $Source -TargetPath $_.FullName
        if (-not (& $Include $relative)) {
            return
        }
        $target = Join-Path $Destination $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $targetFull = [IO.Path]::GetFullPath($TargetPath)
    $baseUri = [Uri]::new($baseFull)
    $targetUri = [Uri]::new($targetFull)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Expand-ZipEntries {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$Exclude = @()
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name) -or $Exclude -contains $entry.FullName) {
                continue
            }
            $target = Join-Path $Destination $entry.FullName.Replace('/', '\')
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Portable ZIP source directory does not exist: $Source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }
    $archive = [IO.Compression.ZipFile]::Open(
        $Destination,
        [IO.Compression.ZipArchiveMode]::Create
    )
    try {
        Get-ChildItem -LiteralPath $Source -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
            $entryName = (Get-RelativePath `
                -BasePath $Source `
                -TargetPath $_.FullName).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $_.FullName,
                $entryName,
                [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$programFilesX86 = ${env:ProgramFiles(x86)}
$programFiles = $env:ProgramFiles
$localAppData = $env:LOCALAPPDATA

$vswhereCandidates = @(
    (Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"),
    (Join-Path $programFiles "Microsoft Visual Studio\Installer\vswhere.exe")
)
$vswhereCommand = Get-Command vswhere.exe -ErrorAction SilentlyContinue
if ($vswhereCommand) {
    $vswhereCandidates = @($vswhereCommand.Source) + $vswhereCandidates
}
$vswhere = Find-FirstExisting -Candidates $vswhereCandidates
if (-not $vswhere) {
    throw "vswhere.exe was not found. Install Visual Studio with the C++ workload."
}

$vsInstallPath = (& $vswhere `
    -latest `
    -products "*" `
    -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" `
    -property installationPath).Trim()
if (-not $vsInstallPath) {
    throw "No Visual Studio installation with the x64 MSVC toolchain was found."
}

$vsVersion = (& $vswhere `
    -latest `
    -products "*" `
    -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" `
    -property installationVersion).Trim()
if (-not $vsVersion) {
    throw "Unable to determine the Visual Studio installation version."
}

$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
$cmakeCandidates = @(
    $(if ($cmakeCommand) { $cmakeCommand.Source }),
    (Join-Path $vsInstallPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"),
    (Join-Path $programFiles "CMake\bin\cmake.exe")
)
$cmake = Find-FirstExisting -Candidates $cmakeCandidates
if (-not $cmake) {
    throw "CMake was not found in PATH or the Visual Studio installation."
}
$ctest = Join-Path (Split-Path -Parent $cmake) "ctest.exe"
if (-not (Test-Path -LiteralPath $ctest -PathType Leaf)) {
    throw "ctest.exe was not found next to CMake: $cmake"
}

$ninjaCommand = Get-Command ninja.exe -ErrorAction SilentlyContinue
$ninjaCandidates = @(
    $(if ($ninjaCommand) { $ninjaCommand.Source }),
    (Join-Path $vsInstallPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe")
)
$ninja = Find-FirstExisting -Candidates $ninjaCandidates
if (-not $ninja) {
    throw "Ninja was not found in PATH or the Visual Studio installation."
}

$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$isccCandidates = @(
    $(if ($isccCommand) { $isccCommand.Source }),
    (Join-Path $programFilesX86 "Inno Setup 6\ISCC.exe"),
    (Join-Path $programFiles "Inno Setup 6\ISCC.exe"),
    "D:\Program Files\Inno Setup 6\ISCC.exe",
    (Join-Path $localAppData "Programs\Inno Setup 6\ISCC.exe")
)
$iscc = Find-FirstExisting -Candidates $isccCandidates
if (-not $iscc) {
    throw "ISCC.exe was not found. Install Inno Setup 6."
}

$pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
$pythonCandidates = @(
    $(if ($pythonCommand) { $pythonCommand.Source }),
    (Join-Path $programFiles "Python\python.exe")
)
$python = Find-FirstExisting -Candidates $pythonCandidates
if (-not $python) {
    throw "python.exe was not found. Python 3 is required to build shader packs."
}

$devShellModule = Join-Path $vsInstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
if (-not (Test-Path -LiteralPath $devShellModule -PathType Leaf)) {
    throw "Visual Studio DevShell module was not found: $devShellModule"
}
Import-Module $devShellModule -Force
Enter-VsDevShell `
    -VsInstallPath $vsInstallPath `
    -SkipAutomaticLocation `
    -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null

$env:VSLANG = "1033"
$cmakeDir = Split-Path -Parent $cmake
$ninjaDir = Split-Path -Parent $ninja
$env:PATH = "$cmakeDir;$ninjaDir;$env:PATH"

Write-Host "Visual Studio: $vsInstallPath ($vsVersion)"
Write-Host "CMake: $cmake"
Write-Host "Ninja: $ninja"
Write-Host "Inno Setup: $iscc"
Write-Host "Python: $python"

Invoke-Checked $cmake @("--preset", $presetName, "-DBUILD_TESTING=ON") $root
$buildArguments = @("--build", "--preset", $presetName)
if (-not $Incremental) {
    $buildArguments += "--clean-first"
}
Invoke-Checked $cmake $buildArguments $root
Invoke-Checked $ctest @("--preset", $presetName) $root

$versionFile = Join-Path $root "cmake\version.cmake"
$versionText = Get-Content -LiteralPath $versionFile -Raw
$versionMatch = [regex]::Match(
    $versionText,
    'set\s*\(\s*RESHADE_LAUNCHER_VERSION\s+"([^"]+)"\s*\)'
)
if (-not $versionMatch.Success) {
    throw "Unable to read RESHADE_LAUNCHER_VERSION from $versionFile"
}
$appVersion = $versionMatch.Groups[1].Value
$quadVersion = if (($appVersion.Split(".")).Count -ge 4) {
    $appVersion
} else {
    "$appVersion.0"
}

$modLoaderPackBuilder = Join-Path $root "tools\build_mod_loader_packs.py"
$modLoaderOutputDir = Join-Path $root "mod-loaders"
$versionJsonFile = Join-Path $root "version.json"
Invoke-Checked $python @(
    $modLoaderPackBuilder,
    "--mod-loader-root",
    (Join-Path $root "MOD_loader"),
    "--output-dir",
    $modLoaderOutputDir,
    "--version-file",
    $versionJsonFile
) $root

$mainExe = Join-Path $buildDir "bin\ReShade Launcher Build.exe"
$updaterExe = Join-Path $buildDir "bin\ReShadeLauncherUpdater.exe"
foreach ($requiredPath in @($mainExe, $updaterExe)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Expected build output was not produced: $requiredPath"
    }
}

Reset-GeneratedDirectory -Path $stageDir
Reset-GeneratedDirectory -Path $defaultsDir
Reset-GeneratedDirectory -Path $releaseDir

Copy-FileIfPresent -Source $mainExe -DestinationDirectory $stageDir
Copy-FileIfPresent -Source $updaterExe -DestinationDirectory $stageDir

foreach ($fileName in @(
    "translations.json",
    "version.json",
    "b.jpg",
    "icon.ico",
    "3dmloader.dll",
    "README.md",
    "LICENSE"
)) {
    Copy-FileIfPresent `
        -Source (Join-Path $root $fileName) `
        -DestinationDirectory $stageDir
}

$nativeLicenseFiles = @(
    "COPYING.txt",
    "LICENSE.GPL.txt"
)
foreach ($licenseName in $nativeLicenseFiles) {
    Copy-FileIfPresent `
        -Source (Join-Path $root "native\3dmloader\$licenseName") `
        -DestinationDirectory (Join-Path $stageDir "licenses\3dmloader")
}

Copy-FileIfPresent `
    -Source (Join-Path $root "native\3dmloader\BUILD.md") `
    -DestinationDirectory (Join-Path $stageDir "licenses\3dmloader")

$preservedReShadeDirectories = @(
    "Presets",
    "reshade_config",
    "reshade_shaders",
    "Shaders",
    "Textures",
    "full.zip"
)
Copy-FilteredTree `
    -Source (Join-Path $root "ReShade") `
    -Destination (Join-Path $stageDir "ReShade") `
    -Include {
        param($relativePath)
        $firstPart = ($relativePath -split '[\\/]', 2)[0]
        return $preservedReShadeDirectories -notcontains $firstPart
    }

Copy-Tree `
    -Source (Join-Path $root "README") `
    -Destination (Join-Path $stageDir "README")

Copy-Tree `
    -Source (Join-Path $root "ReShade\Presets") `
    -Destination (Join-Path $defaultsDir "ReShade\Presets")

$protectedStagePaths = @(
    "launch_config",
    "custom_data",
    "ReShade\reshade_config",
    "ReShade\Presets",
    "ReShade\reshade_shaders"
)
foreach ($relativePath in $protectedStagePaths) {
    $protectedPath = Join-Path $stageDir $relativePath
    if (Test-Path -LiteralPath $protectedPath) {
        throw "Program payload unexpectedly contains preserved user data: $protectedPath"
    }
}
foreach ($relativePath in @("ReShade\Shaders", "ReShade\Textures", "ReShade\full.zip")) {
    $unwantedPath = Join-Path $stageDir $relativePath
    if (Test-Path -LiteralPath $unwantedPath) {
        throw "Program payload unexpectedly contains non-lite shader content: $unwantedPath"
    }
}
if (Test-Path -LiteralPath (Join-Path $stageDir "MOD_loader")) {
    throw "Program payload unexpectedly contains MOD_loader."
}

$stagedMods = @(
    Get-ChildItem `
        -LiteralPath (Join-Path $stageDir "MOD_loader") `
        -Recurse `
        -Directory `
        -Filter "Mods" `
        -ErrorAction SilentlyContinue
)
if ($stagedMods.Count -gt 0) {
    throw "Program payload unexpectedly contains MOD_loader Mods directories."
}
$stagedUserIni = @(
    Get-ChildItem `
        -LiteralPath (Join-Path $stageDir "MOD_loader") `
        -Recurse `
        -File `
        -Filter "d3dx_user.ini" `
        -ErrorAction SilentlyContinue
)
if ($stagedUserIni.Count -gt 0) {
    throw "Program payload unexpectedly contains d3dx_user.ini."
}

$shaderBuildDir = Join-Path $buildDir "shader-packs"
$shaderPackDir = Join-Path $stageDir "shader-packs"
New-Item -ItemType Directory -Path $shaderBuildDir -Force | Out-Null
New-Item -ItemType Directory -Path $shaderPackDir -Force | Out-Null
$shaderPackBuilder = Join-Path $root "tools\build_shader_packs.py"
Invoke-Checked $python @(
    $shaderPackBuilder,
    "--source",
    (Join-Path $root "ReShade"),
    "--out-dir",
    $shaderBuildDir
) $root

foreach ($shaderPackName in @("lite.zip", "full.zip")) {
    $shaderPackPath = Join-Path $shaderBuildDir $shaderPackName
    if (-not (Test-Path -LiteralPath $shaderPackPath -PathType Leaf)) {
        throw "Shader pack builder did not produce $shaderPackPath"
    }
    if ((Get-Item -LiteralPath $shaderPackPath).Length -eq 0) {
        throw "Shader pack is empty: $shaderPackPath"
    }
}

Copy-Item `
    -LiteralPath (Join-Path $shaderBuildDir "lite.zip") `
    -Destination (Join-Path $shaderPackDir "lite.zip") `
    -Force

$fullShaderSource = Join-Path $shaderBuildDir "full.zip"
$fullShaderHash = (Get-FileHash -LiteralPath $fullShaderSource -Algorithm SHA256).Hash.ToLowerInvariant()
$fullShaderAssetName =
    "ReShade-Launcher-shaders-full-$($fullShaderHash.Substring(0, 16)).zip"
$fullShaderAsset = Join-Path $releaseDir $fullShaderAssetName
Copy-Item `
    -LiteralPath $fullShaderSource `
    -Destination $fullShaderAsset `
    -Force

$fullShaderItem = Get-Item -LiteralPath $fullShaderAsset
$fullShaderDescriptor = [ordered]@{
    url = "https://github.com/v4806/ReShade-Launcher/releases/download/v$appVersion/$fullShaderAssetName"
    size = $fullShaderItem.Length
    sha256 = $fullShaderHash
}
$fullShaderJson = $fullShaderDescriptor | ConvertTo-Json
[IO.File]::WriteAllText(
    (Join-Path $shaderPackDir "full.json"),
    $fullShaderJson,
    [Text.UTF8Encoding]::new($false)
)

$liteShaderDir = Join-Path $defaultsDir "ReShade\reshade_shaders"
Expand-ZipEntries `
    -ZipPath (Join-Path $shaderBuildDir "lite.zip") `
    -Destination $liteShaderDir `
    -Exclude @("pack.json")

$issPath = Join-Path $root "packaging\ReShade-Launcher.iss"
Invoke-Checked $iscc @("/DMyAppVersion=$appVersion", $issPath) $root

$installerPath = Join-Path $releaseDir "ReShade-Launcher-installer-v$appVersion.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Inno Setup did not produce the expected installer: $installerPath"
}

Reset-GeneratedDirectory -Path $portableDir
Copy-FilteredTree `
    -Source $stageDir `
    -Destination $portableDir `
    -Include {
        param($relativePath)
        return $relativePath.Replace('\', '/') -ine "shader-packs/full.zip"
    }
Copy-Tree `
    -Source (Join-Path $defaultsDir "ReShade\Presets") `
    -Destination (Join-Path $portableDir "ReShade\Presets")
Copy-Tree `
    -Source $liteShaderDir `
    -Destination (Join-Path $portableDir "ReShade\reshade_shaders")
Copy-FileIfPresent `
    -Source (Join-Path $root "3dmloader.dll") `
    -DestinationDirectory (Join-Path $portableDir "_internal")

$portableZip = Join-Path $releaseDir "ReShade-Launcher-portable-v$appVersion.zip"
New-ZipFromDirectory -Destination $portableZip -Source $portableDir

$portableArchive = [IO.Compression.ZipFile]::OpenRead($portableZip)
try {
    $portableEntries = @(
        $portableArchive.Entries |
            Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
            ForEach-Object { $_.FullName }
    )
    $entrySet = [Collections.Generic.HashSet[string]]::new(
        [string[]]$portableEntries,
        [StringComparer]::OrdinalIgnoreCase
    )

    $legacyLoader = $portableArchive.GetEntry("_internal/3dmloader.dll")
    if (-not $legacyLoader -or $legacyLoader.Length -le 0) {
        throw "Portable ZIP does not contain a non-empty _internal/3dmloader.dll"
    }
    foreach ($requiredEntry in @(
        "ReShade Launcher Build.exe",
        "3dmloader.dll",
        "ReShade/ReShade64.dll"
    )) {
        if (-not $entrySet.Contains($requiredEntry)) {
            throw "Portable ZIP is missing required entry: $requiredEntry"
        }
    }

    Get-ChildItem -LiteralPath $stageDir -Recurse -File | ForEach-Object {
        $relative = (Get-RelativePath -BasePath $stageDir -TargetPath $_.FullName).Replace('\', '/')
        if ($relative -ieq "shader-packs/full.zip") {
            return
        }
        if (-not $entrySet.Contains($relative)) {
            throw "Portable ZIP is missing staged program file: $relative"
        }
    }

    foreach ($assetRoot in @(
        @{
            Source = (Join-Path $root "ReShade\Addons")
            Prefix = "ReShade/Addons"
        },
        @{
            Source = (Join-Path $root "ReShade\sound")
            Prefix = "ReShade/sound"
        },
        @{
            Source = (Join-Path $root "ReShade\Presets")
            Prefix = "ReShade/Presets"
        }
    )) {
        Get-ChildItem -LiteralPath $assetRoot.Source -Recurse -File | ForEach-Object {
            $relative = (Get-RelativePath `
                -BasePath $assetRoot.Source `
                -TargetPath $_.FullName).Replace('\', '/')
            $entryName = "$($assetRoot.Prefix)/$relative"
            if (-not $entrySet.Contains($entryName)) {
                throw "Portable ZIP is missing ReShade asset: $entryName"
            }
        }
    }

    $liteArchive = [IO.Compression.ZipFile]::OpenRead((Join-Path $shaderBuildDir "lite.zip"))
    try {
        $expectedLiteEntries = @(
            $liteArchive.Entries |
                Where-Object {
                    -not [string]::IsNullOrEmpty($_.Name) -and
                    $_.FullName -ine "pack.json"
                } |
                ForEach-Object { "ReShade/reshade_shaders/$($_.FullName)" }
        )
    }
    finally {
        $liteArchive.Dispose()
    }

    $actualLiteEntries = @(
        $portableEntries |
            Where-Object {
                $_ -like "ReShade/reshade_shaders/Shaders/*" -or
                $_ -like "ReShade/reshade_shaders/Textures/*"
            }
    )
    $missingLiteEntries = @($expectedLiteEntries | Where-Object { -not $entrySet.Contains($_) })
    if ($missingLiteEntries.Count -gt 0) {
        throw "Portable ZIP is missing lite shader files, first: $($missingLiteEntries[0])"
    }
    $expectedLiteSet = [Collections.Generic.HashSet[string]]::new(
        [string[]]$expectedLiteEntries,
        [StringComparer]::OrdinalIgnoreCase
    )
    $extraLiteEntries = @($actualLiteEntries | Where-Object { -not $expectedLiteSet.Contains($_) })
    if ($extraLiteEntries.Count -gt 0) {
        throw "Portable ZIP contains shader files outside lite.zip, first: $($extraLiteEntries[0])"
    }
    if (-not ($actualLiteEntries | Where-Object { $_ -like "ReShade/reshade_shaders/Shaders/*" })) {
        throw "Portable ZIP has no active lite Shaders directory content."
    }
    if (-not ($actualLiteEntries | Where-Object { $_ -like "ReShade/reshade_shaders/Textures/*" })) {
        throw "Portable ZIP has no active lite Textures directory content."
    }
    foreach ($forbiddenEntry in @(
        "shader-packs/full.zip",
        "ReShade/reshade_shaders/full.zip"
    )) {
        if ($entrySet.Contains($forbiddenEntry)) {
            throw "Portable ZIP contains forbidden full shader pack: $forbiddenEntry"
        }
    }
}
finally {
    $portableArchive.Dispose()
}

Write-Host ""
Write-Host "Build complete."
Write-Host "Application payload: $stageDir"
Write-Host "Installer: $installerPath"
Write-Host "Portable ZIP: $portableZip"
