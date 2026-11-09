$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $PSScriptRoot 'bin\x64'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$vsDevCmd = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $vsDevCmd)) {
    throw "VsDevCmd.bat not found: $vsDevCmd"
}

$targetSource = Join-Path $PSScriptRoot 'target.cpp'
$probeSource = Join-Path $PSScriptRoot 'probe.cpp'
$targetOutput = Join-Path $out 'target.exe'
$probeOutput = Join-Path $out 'probe.dll'

$targetCommand = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /EHsc /MD /DWIN32_LEAN_AND_MEAN `"$targetSource`" /Fe:`"$targetOutput`" /link /SUBSYSTEM:CONSOLE user32.lib"
$probeCommand = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /EHsc /MD /LD /DWIN32_LEAN_AND_MEAN `"$probeSource`" /Fe:`"$probeOutput`" /link /SUBSYSTEM:WINDOWS user32.lib"

cmd.exe /d /s /c $targetCommand
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build target.exe"
}

cmd.exe /d /s /c $probeCommand
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build probe.dll"
}

Write-Output $targetOutput
Write-Output $probeOutput
