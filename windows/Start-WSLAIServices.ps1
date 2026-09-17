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

$linuxCommand = 'set -e; systemctl start ollama docker stable-diffusion-webui stable-diffusion-vram-watchdog stable-diffusion-autoreload-proxy; docker start open-webui >/dev/null 2>&1 || true; echo "systemd service states:"; systemctl is-active ollama docker stable-diffusion-webui stable-diffusion-vram-watchdog stable-diffusion-autoreload-proxy; printf "open-webui="; docker inspect open-webui --format "{{.State.Status}}"; echo "startup checks complete"; exec /bin/sleep infinity'

try {
    Write-StartupLog "Launching distribution '$Distribution' and AI services."
    & $wslPath -d $Distribution -u root --exec /bin/sh -lc $linuxCommand 2>&1 |
        ForEach-Object { Write-StartupLog $_.ToString() }

    $exitCode = $LASTEXITCODE
    Write-StartupLog "wsl.exe exited with code $exitCode."
    exit $exitCode
}
catch {
    Write-StartupLog "Startup failed: $($_.Exception.Message)"
    exit 1
}
