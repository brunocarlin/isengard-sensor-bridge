param([string]$CpuTempDirectory)

$ErrorActionPreference = 'Stop'
$taskName = 'CpuTemp Standalone Sensor Bridge'
$expectedOriginal = '89FA5F06715620AD5F8208ECA18229A3242A0FF3165D3067AF40FA7B73EFCD57'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($CpuTempDirectory) { $arguments += @('-CpuTempDirectory',"`"$CpuTempDirectory`"") }
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}
if (-not $CpuTempDirectory) { $CpuTempDirectory = Read-Host 'CpuTemp folder containing CpuTemp.exe' }
$target = (Resolve-Path -LiteralPath $CpuTempDirectory).Path
$asar = Join-Path $target 'resources\app.asar'
$backup = Join-Path $target 'resources\app.asar.cputemp-fanfix-backup'
$lib = Join-Path $target 'lib'
$bridgeInstallDirectory = Join-Path $env:ProgramFiles 'CpuTempSensorBridge'
$bridge = Join-Path $bridgeInstallDirectory 'CpuTempFanBridge.exe'

if (Get-Process CpuTemp -ErrorAction SilentlyContinue) { throw 'Exit CpuTemp from the tray before restoring.' }
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Get-Process CpuTempFanBridge -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not (Test-Path -LiteralPath $backup)) { throw "Rollback backup not found: $backup" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne $expectedOriginal) {
    throw 'Rollback backup failed SHA-256 verification.'
}
Copy-Item -LiteralPath $backup -Destination $asar -Force
if (Test-Path -LiteralPath $bridge) { Remove-Item -LiteralPath $bridge -Force }
if (Test-Path -LiteralPath $bridgeInstallDirectory) { Remove-Item -LiteralPath $bridgeInstallDirectory -Force }
foreach ($name in 'CpuTempFanBridge.exe','CpuTempFanBridge.json','CpuTempFanBridge.rpm','CpuTempFanBridge.status') {
    $file = Join-Path $lib $name
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
}
Write-Output 'Original CpuTemp 1.0.15 restored. PawnIO was left installed because it may be shared by other monitoring tools.'
