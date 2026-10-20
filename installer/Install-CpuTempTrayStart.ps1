param([string]$CpuTempDirectory = "$env:ProgramFiles\CpuTemp", [switch]$Restore)
$ErrorActionPreference = 'Stop'
$expectedStandalone = '894E06AE74CE9991C77EB190D01E54BD3BFB341E7FD8B8909DF2766BC02A5AB1'
$expectedTray = '19FD46CEC8E51CE7EF4D4DD5C6B15DD13EF8C263E999D474651B486C6FDE9850'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-CpuTempDirectory', "`"$CpuTempDirectory`"")
    if ($Restore) { $arguments += '-Restore' }
    $process = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}
$log = Join-Path $PSScriptRoot 'tray-start-install.log'
try {
    $target = (Resolve-Path -LiteralPath $CpuTempDirectory).Path
    $asar = Join-Path $target 'resources\app.asar'
    $backup = "$asar.tray-start-backup"
    $temporary = "$asar.tray-start-new"
    $exe = Join-Path $target 'CpuTemp.exe'
    $replacement = Join-Path $PSScriptRoot '..\compat\start-in-tray.js'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'CpuTemp.exe not found.' }
    # Reuse the existing task and preserve its privilege level.
    $task = Get-ScheduledTask -TaskName 'StartCpuTemp' -ErrorAction Stop
    if ($task.Actions.Count -ne 1 -or $task.Actions.Execute.Trim('"') -ne $exe -or $task.Actions.Arguments -ne '--startupWithMinimize') {
        throw 'StartCpuTemp is not the expected startup task; no changes made.'
    }
    if ($Restore) {
        if ((Get-FileHash -LiteralPath $backup).Hash -ne $expectedStandalone) { throw 'Tray rollback backup failed verification.' }
        if ((Get-FileHash -LiteralPath $asar).Hash -notin @($expectedStandalone, $expectedTray)) { throw 'Current archive is an unknown build; refusing to overwrite it.' }
    } else {
        $currentHash = (Get-FileHash -LiteralPath $asar).Hash
        if ($currentHash -ne $expectedStandalone) { throw 'Requires the unmodified Isengard standalone sensor fix for CpuTemp 1.0.15. Restore the tray patch before reinstalling.' }
        & (Join-Path $PSScriptRoot 'Set-CpuTempTrayEntry.ps1') -Archive $asar -Replacement $replacement -OutputArchive $temporary
        if ((Get-FileHash -LiteralPath $temporary).Hash -ne $expectedTray) { throw 'Tray archive failed final SHA-256 verification.' }
        if (Test-Path -LiteralPath $backup) {
            if ((Get-FileHash -LiteralPath $backup).Hash -ne $expectedStandalone) { throw 'Existing tray rollback backup failed verification.' }
        } else { Copy-Item -LiteralPath $asar -Destination $backup }
    }
    # Only stop CpuTemp from this installation. The sensor bridge keeps running.
    Get-CimInstance Win32_Process -Filter "Name = 'CpuTemp.exe'" | Where-Object {
        $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -eq $exe
    } | ForEach-Object {
        $cpuTempProcessId = $_.ProcessId
        Stop-Process -Id $cpuTempProcessId -Force
        Wait-Process -Id $cpuTempProcessId -Timeout 15 -ErrorAction SilentlyContinue
    }
    if ($Restore) { Copy-Item -LiteralPath $backup -Destination $asar -Force }
    else {
        Copy-Item -LiteralPath $temporary -Destination $asar -Force
        if ((Get-FileHash -LiteralPath $asar).Hash -ne $expectedTray) { throw 'Installed archive failed verification.' }
        Remove-Item -LiteralPath $temporary -Force
    }
    Stop-ScheduledTask -TaskName 'StartCpuTemp'
    Start-ScheduledTask -TaskName 'StartCpuTemp'
    "Success. Restore=$Restore. Backup=$backup" | Set-Content -LiteralPath $log
} catch {
    $_ | Out-String | Set-Content -LiteralPath $log
    exit 1
}
