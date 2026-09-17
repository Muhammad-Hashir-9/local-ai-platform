# Windows Startup Methods for the WSL AI Stack

This deployment supports two independent Windows Task Scheduler methods. They start the same services inside WSL but make different availability and security tradeoffs.

## Choose a method

| Method | Trigger and identity | Availability | Security and compatibility profile |
|---|---|---|---|
| Pre-login startup | At system startup, delayed 60 seconds, Windows user through S4U, highest privileges | Services can become available at the Windows sign-in screen | Starts network-facing applications before interactive authentication; depends on the installed WSL version supporting noninteractive startup |
| Post-login startup | At logon, interactive Windows user, limited privileges | Services start only after that user signs in locally or through RDP | Narrower availability window, simpler user context, and generally the more conservative compatibility option |

Both tasks can remain enabled. The pre-login task provides service-like availability, while the post-login task acts as a fallback if noninteractive WSL startup fails after an update. Starting already-active systemd services and the Docker container is idempotent; the second launcher mainly adds another harmless WSL keep-alive process.

These are Task Scheduler patterns, not native Windows services. WSL distributions are normally registered per Windows user, so run either task as the Windows account that owns the distribution. Do not switch the pre-login task to `SYSTEM` unless the distribution was deliberately provisioned for that context.

## Shared Linux startup launcher

The pre-login method calls a single executable path inside WSL, avoiding fragile quoting across Task Scheduler, Windows PowerShell, `wsl.exe`, and the Linux shell. Install the included [`start-ai-services.sh`](../start-ai-services.sh):

```bash
sudo install -m 0755 start-ai-services.sh /usr/local/sbin/start-ai-services
```

The launcher contains:

```bash
set -e
systemctl start \
  ollama docker stable-diffusion-webui \
  stable-diffusion-vram-watchdog \
  stable-diffusion-autoreload-proxy
docker start open-webui >/dev/null 2>&1 || true
exec /bin/sleep infinity
```

The final sleep is intentional: it keeps the WSL instance and scheduled task alive. systemd and Docker remain responsible for supervising their individual processes.

## Method A: pre-login startup

Use this when LAN clients must reach the applications after Windows boots, even while the host remains at the sign-in screen.

Included files:

- [`start-ai-services.sh`](../start-ai-services.sh): the Linux-side startup and keep-alive sequence installed at `/usr/local/sbin/start-ai-services`.
- [`Start-WSLAIServices.ps1`](../windows/Start-WSLAIServices.ps1): launches WSL, starts the services, records diagnostics, and keeps WSL alive.
- [`Register-PreLoginTask.ps1`](../windows/Register-PreLoginTask.ps1): creates the boot-triggered scheduled task.

Install the Linux launcher first. Then copy both Windows PowerShell files to a permanent local directory. Do not leave the task pointing to a temporary checkout or removable drive. From an elevated PowerShell session in that directory, run:

```powershell
.\Register-PreLoginTask.ps1 `
  -WindowsUser "$env:USERDOMAIN\$env:USERNAME" `
  -Distribution "Ubuntu"
```

The registered task uses:

- Name: `WSL AI Services Pre-Login Startup`
- Trigger: at system startup
- Delay: 60 seconds
- Logon type: S4U, so the task does not embed a Windows password
- Run level: highest
- Runtime limit: disabled
- Retry policy: three attempts at one-minute intervals
- Battery restrictions: disabled
- Diagnostic log: `%ProgramData%\WSL-AI\startup.log`

S4U tasks have no interactive desktop and limited access to remote network resources. This stack uses local files and services, so that restriction is appropriate. WSL behavior in noninteractive sessions can vary across releases; keep the post-login method available until the cold-boot acceptance test passes on the target machine.

### Pre-login acceptance test

1. Restart Windows.
2. Remain at the Windows sign-in screen; do not use RDP because an RDP connection creates a login session.
3. Wait long enough for the 60-second delay plus Docker and GPU initialization.
4. From another trusted LAN device, open `http://<host-ip>:3000` and `http://<host-ip>:7860`.
5. Sign in afterward and inspect `%ProgramData%\WSL-AI\startup.log` and Task Scheduler history.
6. Confirm all Linux services are active and Open WebUI is healthy.

## Method B: post-login startup

Use this when starting network-facing applications only after interactive authentication is preferred, or when the installed WSL release does not start reliably through S4U.

Copy [`WSL-AI-Startup.vbs`](../windows/WSL-AI-Startup.vbs) to a permanent local directory and update the distribution name if needed. Register a task with these settings:

| Setting | Value |
|---|---|
| Name | `WSL AI Services Startup` |
| Trigger | At logon for the Windows account that owns the WSL distribution |
| Delay | 30 seconds |
| Security option | Run only when the user is logged on |
| Run level | Limited privileges |
| Program | `wscript.exe` |
| Arguments | `//B //Nologo "C:\path\to\WSL-AI-Startup.vbs"` |
| Execution time limit | Disabled |

`wscript.exe` launches the command without leaving a terminal window open. A local console login or RDP login triggers this task.

## Running both methods

Keeping both tasks enabled provides a straightforward fallback:

```text
Windows boot
  -> pre-login task attempts to start WSL and the AI stack

Windows user login
  -> post-login task repeats the idempotent start commands
  -> recovers availability if pre-login WSL startup failed
```

The fallback does not reserve additional model VRAM by itself. It may create a second keep-alive shell after login, but the named systemd services and Docker container are not duplicated.

## Verification and rollback

Inspect both tasks:

```powershell
Get-ScheduledTask -TaskName "WSL AI Services Pre-Login Startup"
Get-ScheduledTask -TaskName "WSL AI Services Startup"
Get-ScheduledTaskInfo -TaskName "WSL AI Services Pre-Login Startup"
```

Check the stack:

```powershell
wsl -d Ubuntu -u root -- systemctl is-active `
  ollama docker stable-diffusion-webui `
  stable-diffusion-vram-watchdog `
  stable-diffusion-autoreload-proxy

wsl -d Ubuntu -u root -- docker inspect open-webui `
  --format "status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{end}}"
```

To roll back to post-login startup only, run PowerShell as Administrator:

```powershell
Stop-ScheduledTask -TaskName "WSL AI Services Pre-Login Startup" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "WSL AI Services Pre-Login Startup" -Confirm:$false
```

This leaves `WSL AI Services Startup` unchanged and enabled.
