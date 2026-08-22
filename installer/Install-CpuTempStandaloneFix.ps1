param([string]$CpuTempDirectory)

$ErrorActionPreference = 'Stop'
$taskName = 'CpuTemp Standalone Sensor Bridge'
$expectedOriginal = '89FA5F06715620AD5F8208ECA18229A3242A0FF3165D3067AF40FA7B73EFCD57'
$expectedStandalone = '894E06AE74CE9991C77EB190D01E54BD3BFB341E7FD8B8909DF2766BC02A5AB1'
$expectedBridge = '108B8130A144E3681771FD1E3FC2AF2FEB14697EDB37E515A4D7EAC0CE3F7449'
$expectedBinding = '66806D525DE41C1CBCD9F56E14BE3962F773D65124230426FD13E3763BEC366A'
$bundle = Split-Path -Parent $MyInvocation.MyCommand.Path

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($CpuTempDirectory) { $arguments += @('-CpuTempDirectory',"`"$CpuTempDirectory`"") }
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

if (-not $CpuTempDirectory) {
    $default = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\CpuTemp'
    $answer = Read-Host "CpuTemp folder containing CpuTemp.exe [$default]"
    $CpuTempDirectory = if ([string]::IsNullOrWhiteSpace($answer)) { $default } else { $answer }
}

$target = (Resolve-Path -LiteralPath $CpuTempDirectory).Path
$exe = Join-Path $target 'CpuTemp.exe'
$asar = Join-Path $target 'resources\app.asar'
$backup = Join-Path $target 'resources\app.asar.cputemp-fanfix-backup'
$temporary = Join-Path $target 'resources\app.asar.cputemp-standalone-new'
$lib = Join-Path $target 'lib'
$bridgeInstallDirectory = Join-Path $env:ProgramFiles 'CpuTempSensorBridge'
$bridge = Join-Path $bridgeInstallDirectory 'CpuTempFanBridge.exe'
$bridgePayload = Join-Path $bundle 'payload\CpuTempFanBridge.exe'
$bindingPayload = Join-Path $bundle 'payload\binding.js'

if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $asar)) {
    throw "CpuTemp.exe/resources/app.asar not found under: $target"
}
if (Get-Process CpuTemp -ErrorAction SilentlyContinue) {
    throw 'CpuTemp is running. Exit it from the tray and run the installer again.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bridgePayload).Hash -ne $expectedBridge) {
    throw 'CpuTempFanBridge.exe failed SHA-256 verification.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bindingPayload).Hash -ne $expectedBinding) {
    throw 'binding.js failed SHA-256 verification.'
}

$pawnPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO'
)
$pawn = $pawnPaths | ForEach-Object {
    Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue
} | Select-Object -First 1
$pawnVersion = $null
if ($pawn) { [version]::TryParse([string]$pawn.DisplayVersion, [ref]$pawnVersion) | Out-Null }
if (-not $pawnVersion -or $pawnVersion -lt [version]'2.2.0') {
    throw 'PawnIO 2.2.0 or newer was not found. Install and run Fan Control v273 or newer first, confirm its motherboard sensors work, then rerun this installer.'
}

$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $asar).Hash
if ($currentHash -ne $expectedStandalone) {
    if (-not (Test-Path -LiteralPath $backup)) {
        if ($currentHash -ne $expectedOriginal) {
            throw "Unsupported app.asar build ($currentHash); no original backup is available."
        }
        Copy-Item -LiteralPath $asar -Destination $backup
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne $expectedOriginal) {
        throw 'Rollback backup does not match the supported CpuTemp 1.0.15 build.'
    }

    try {
        & (Join-Path $bundle 'Patch-AsarEntry.ps1') `
            -Archive $backup `
            -InternalPath 'node_modules/hwinfo/dist/binding.js' `
            -Replacement $bindingPayload `
            -OutputArchive $temporary
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash -ne $expectedStandalone) {
            throw 'Standalone app.asar failed final SHA-256 verification.'
        }
        Move-Item -LiteralPath $temporary -Destination $asar -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

Get-Process CpuTempFanBridge -ErrorAction SilentlyContinue | Stop-Process -Force
[IO.Directory]::CreateDirectory($bridgeInstallDirectory) | Out-Null
Copy-Item -LiteralPath $bridgePayload -Destination $bridge -Force
$legacyBridge = Join-Path $lib 'CpuTempFanBridge.exe'
if (Test-Path -LiteralPath $legacyBridge) { Remove-Item -LiteralPath $legacyBridge -Force }

$action = New-ScheduledTaskAction -Execute $bridge -Argument ('--watch-lhm "{0}"' -f $lib)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

$statusPath = Join-Path $lib 'CpuTempFanBridge.status'
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $statusPath) {
        $status = Get-Content -Raw -LiteralPath $statusPath
        if ($status -match '^OK:') { break }
    }
}
if (-not $status -or $status -notmatch '^OK:') {
    throw "The bridge task was installed, but its health check failed: $status"
}

Write-Output 'CpuTemp Standalone Fix installed successfully.'
Write-Output $status.Trim()
Write-Output "Rollback backup: $backup"
Write-Output 'Open CpuTemp.exe normally after closing this installer window.'
