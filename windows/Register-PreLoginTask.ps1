param(
    [string]$TaskName = "WSL AI Services Pre-Login Startup",
    [string]$WindowsUser = "$env:USERDOMAIN\$env:USERNAME",
    [string]$Distribution = "Ubuntu",
    [string]$LauncherPath = (Join-Path $PSScriptRoot "Start-WSLAIServices.ps1")
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run this script from an elevated PowerShell session."
}

$resolvedLauncher = (Resolve-Path -LiteralPath $LauncherPath).Path
$actionArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$resolvedLauncher`" -Distribution `"$Distribution`""

$action = New-ScheduledTaskAction `
    -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument $actionArguments

$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT1M"

$principal = New-ScheduledTaskPrincipal `
    -UserId $WindowsUser `
    -LogonType S4U `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Starts the WSL AI stack at Windows boot before interactive login." `
    -Force
