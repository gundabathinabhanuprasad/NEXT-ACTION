"""Local Production Web Server for NextAction.

Simulates production Nginx behavior:
1. Serves production static Flutter Web build from apps/mobile_web/build/web.
2. Provides SPA routing fallback (try_files $uri /index.html).
3. Reverse proxies /api, /health, /ready requests to the FastAPI backend at http://127.0.0.1:8000.
4. Serves download portal at /download.html and Android APK at /downloads/app-release.apk.
"""

import http.server
import os
from pathlib import Path
import socketserver
import urllib.error
import urllib.request

PORT = 8080
BACKEND_URL = "http://127.0.0.1:8000"
WEB_DIR = Path(__file__).resolve().parent.parent / "apps" / "mobile_web" / "build" / "web"


class SPAProxyHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler supporting SPA routing and backend proxying."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def do_GET(self):
        # Proxy backend endpoints directly to FastAPI backend
        if (
            self.path.startswith("/api/")
            or self.path.startswith("/health")
            or self.path.startswith("/ready")
            or self.path.startswith("/docs")
            or self.path.startswith("/openapi.json")
        ):
            self._proxy_request("GET")
            return

        # Check if requested static file exists
        req_path = self.path.split("?")[0]
        file_path = WEB_DIR / req_path.lstrip("/")

        # If not found and not an asset/file with extension, fallback to index.html (SPA routing)
        if not file_path.exists() and "." not in os.path.basename(req_path):
            self.path = "/index.html"

        super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/"):
            self._proxy_request("POST")
        else:
            self.send_error(405, "Method Not Allowed")

    def do_PUT(self):
        if self.path.startswith("/api/"):
            self._proxy_request("PUT")
        else:
            self.send_error(405, "Method Not Allowed")

    def do_PATCH(self):
        if self.path.startswith("/api/"):
            self._proxy_request("PATCH")
        else:
            self.send_error(405, "Method Not Allowed")

    def do_DELETE(self):
        if self.path.startswith("/api/"):
            self._proxy_request("DELETE")
        else:
            self.send_error(405, "Method Not Allowed")

    def _proxy_request(self, method: str):
        target_url = f"{BACKEND_URL}{self.path}"
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        req_headers = {}
        for header, val in self.headers.items():
            if header.lower() not in ("host", "content-length"):
                req_headers[header] = val

        req = urllib.request.Request(
            target_url, data=body, headers=req_headers, method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                self.send_response(resp.status)
                for h, val in resp.getheaders():
                    if h.lower() not in (
                        "transfer-encoding",
                        "content-encoding",
                        "content-length",
                    ):
                        self.send_header(h, val)
                resp_data = resp.read()
                self.send_header("Content-Length", str(len(resp_data)))
                self.end_headers()
                self.wfile.write(resp_data)
        except urllib.error.HTTPError as err:
            self.send_response(err.code)
            for h, val in err.headers.items():
                if h.lower() not in (
                    "transfer-encoding",
                    "content-encoding",
                    "content-length",
                ):
                    self.send_header(h, val)
            err_data = err.read()
            self.send_header("Content-Length", str(len(err_data)))
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as exc:
            self.send_error(502, f"Bad Gateway: {exc}")


def run_server():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), SPAProxyHandler) as httpd:
        print(f"[NextAction Web Server] Serving {WEB_DIR} on http://127.0.0.1:{PORT}")
        print(f"[NextAction Web Server] Proxying API traffic to {BACKEND_URL}")
        httpd.serve_forever()


if __name__ == "__main__":
    run_server()
