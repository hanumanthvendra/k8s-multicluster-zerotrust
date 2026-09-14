#!/usr/bin/env python3
"""Tiny backend for the GitOps image pipeline (replaces hashicorp/http-echo)."""
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

CLUSTER = os.environ.get("CLUSTER_NAME", "unknown")
PORT = int(os.environ.get("PORT", "8080"))
BODY = f"Hello from BACKEND  |  cluster={CLUSTER}\n".encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
