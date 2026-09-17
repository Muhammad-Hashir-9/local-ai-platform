param(
    [string]$Distribution = "Ubuntu"
)

$ErrorActionPreference = "Stop"

$logDirectory = Join-Path $env:ProgramData "WSL-AI"
$logPath = Join-Path $logDirectory "startup.log"
$wslPath = Join-Path $env:WINDIR "System32\wsl.exe"

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function Write-StartupLog {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $logPath -Value "[$timestamp] $Message"
}

Write-StartupLog "Startup task invoked as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)."

$linuxLauncher = "/usr/local/sbin/start-ai-services"

try {
    Write-StartupLog "Launching distribution '$Distribution' and AI services."
    & $wslPath -d $Distribution -u root --exec $linuxLauncher 2>&1 |
        ForEach-Object { Write-StartupLog $_.ToString() }

    $exitCode = $LASTEXITCODE
    Write-StartupLog "wsl.exe exited with code $exitCode."
    exit $exitCode
}
catch {
    Write-StartupLog "Startup failed: $($_.Exception.Message)"
    exit 1
}
