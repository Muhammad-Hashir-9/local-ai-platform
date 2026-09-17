#!/usr/bin/env bash
set -euo pipefail

systemctl start \
  ollama \
  docker \
  stable-diffusion-webui \
  stable-diffusion-vram-watchdog \
  stable-diffusion-autoreload-proxy

docker start open-webui >/dev/null 2>&1 || true

echo "systemd service states:"
systemctl is-active \
  ollama \
  docker \
  stable-diffusion-webui \
  stable-diffusion-vram-watchdog \
  stable-diffusion-autoreload-proxy

printf "open-webui="
docker inspect open-webui --format '{{.State.Status}}'
echo "startup checks complete"

exec /bin/sleep infinity
