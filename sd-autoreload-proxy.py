#!/usr/bin/env python3
import json
import os
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "http://127.0.0.1:7860"
# Bind only to Docker's private bridge gateway. Open WebUI reaches this through
# host.docker.internal; Windows and LAN clients continue using port 7860.
LISTEN_ADDRESS = "172.17.0.1"
LISTEN_PORT = 7861
UNLOADED_MARKER = "/run/sd-vram-watchdog/checkpoint-unloaded"
GENERATION_PATHS = {"/sdapi/v1/txt2img", "/sdapi/v1/img2img"}
reload_lock = threading.Lock()


def reload_if_needed():
    if not os.path.exists(UNLOADED_MARKER):
        return

    with reload_lock:
        if not os.path.exists(UNLOADED_MARKER):
            return

        request = urllib.request.Request(
            UPSTREAM + "/sdapi/v1/reload-checkpoint", method="POST"
        )
        with urllib.request.urlopen(request, timeout=300) as response:
            response.read()
        os.unlink(UNLOADED_MARKER)
        print("Checkpoint reloaded for an incoming generation request", flush=True)


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def proxy(self):
        path = self.path.split("?", 1)[0]
        try:
            if self.command == "POST" and path in GENERATION_PATHS:
                reload_if_needed()

            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length else None
            headers = {
                key: value
                for key, value in self.headers.items()
                if key.lower()
                not in {"host", "connection", "content-length", "accept-encoding"}
            }
            request = urllib.request.Request(
                UPSTREAM + self.path,
                data=body,
                headers=headers,
                method=self.command,
            )
            try:
                response = urllib.request.urlopen(request, timeout=900)
            except urllib.error.HTTPError as error:
                response = error

            response_body = response.read()
            self.send_response(response.status)
            content_type = response.headers.get("Content-Type")
            if content_type:
                self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(response_body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(response_body)
        except Exception as error:
            response_body = json.dumps(
                {"error": "Stable Diffusion reload/proxy failure", "detail": str(error)}
            ).encode()
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response_body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(response_body)
            print(f"Proxy error: {error}", flush=True)

    do_GET = proxy
    do_POST = proxy
    do_PUT = proxy
    do_DELETE = proxy

    def log_message(self, format_string, *args):
        print(f"{self.address_string()} - {format_string % args}", flush=True)


server = ThreadingHTTPServer((LISTEN_ADDRESS, LISTEN_PORT), ProxyHandler)
print(f"Stable Diffusion auto-reload proxy listening on {LISTEN_PORT}", flush=True)
server.serve_forever()
