#!/usr/bin/env python3
import json
import os
import time
import urllib.request

BASE_URL = "http://127.0.0.1:7860"
IDLE_SECONDS = 300
POLL_SECONDS = 2
STATE_DIRECTORY = "/run/sd-vram-watchdog"
UNLOADED_MARKER = os.path.join(STATE_DIRECTORY, "checkpoint-unloaded")


def api(path, method="GET"):
    request = urllib.request.Request(BASE_URL + path, method=method)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response) if response.length != 0 else None


def mark_unloaded():
    os.makedirs(STATE_DIRECTORY, exist_ok=True)
    temporary = UNLOADED_MARKER + ".tmp"
    with open(temporary, "w", encoding="utf-8") as marker:
        marker.write(f"{time.time()}\n")
    os.replace(temporary, UNLOADED_MARKER)


last_activity = time.monotonic()
last_job_timestamp = None
checkpoint_unloaded = os.path.exists(UNLOADED_MARKER)

while True:
    try:
        status = api("/sdapi/v1/progress")
        state = status.get("state", {})
        job_timestamp = state.get("job_timestamp")
        active = bool(state.get("job_count", 0) or status.get("progress", 0))

        if active or (
            last_job_timestamp is not None
            and job_timestamp != last_job_timestamp
        ):
            last_activity = time.monotonic()
            checkpoint_unloaded = False

        if job_timestamp:
            last_job_timestamp = job_timestamp

        if (
            not active
            and not checkpoint_unloaded
            and time.monotonic() - last_activity >= IDLE_SECONDS
        ):
            api("/sdapi/v1/unload-checkpoint", method="POST")
            mark_unloaded()
            checkpoint_unloaded = True
            print("Checkpoint unloaded after 5 minutes idle", flush=True)
    except Exception as error:
        print(f"Waiting for Stable Diffusion API: {error}", flush=True)

    time.sleep(POLL_SECONDS)
