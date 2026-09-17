Option Explicit

Dim shell, command
Set shell = CreateObject("WScript.Shell")

' Change Ubuntu if the WSL distribution has a different name.
command = "wsl.exe -d Ubuntu -u root --exec /bin/sh -lc ""set -e; systemctl start ollama docker stable-diffusion-webui stable-diffusion-vram-watchdog stable-diffusion-autoreload-proxy; docker start open-webui >/dev/null 2>&1 || true; exec /bin/sleep infinity"""
shell.Run command, 0, True
