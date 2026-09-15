#!/usr/bin/env python3
"""Tiny backend for the GitOps image pipeline (replaces hashicorp/http-echo)."""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

CLUSTER = os.environ.get("CLUSTER_NAME", "unknown")
PORT = int(os.environ.get("PORT", "8080"))
HELLO = f"Hello from BACKEND  |  cluster={CLUSTER}\n".encode()
HEALTH = json.dumps({"status": "ok", "cluster": CLUSTER}).encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?", 1)[0] in ("/health", "/healthz", "/ready"):
            body, ctype = HEALTH, "application/json; charset=utf-8"
        else:
            body, ctype = HELLO, "text/plain; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
