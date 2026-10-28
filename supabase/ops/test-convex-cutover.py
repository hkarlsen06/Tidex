#!/usr/bin/env python3
"""Exercise both cutover stages through an isolated Caddy on localhost."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import socket
import subprocess
import tempfile
from threading import Thread
import time
from urllib.error import URLError
from urllib.request import Request, urlopen


class Upstream(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"path": self.path, "method": self.command}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    do_POST = do_GET

    def log_message(self, *args):
        pass


helper = Path(__file__).with_name("convex-cutover.py")
upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
Thread(target=upstream.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / "before.Caddyfile"
        other_host = "\nkeep.example.com {\n    respond 204\n}\n"
        source.write_text("identity.tidex.no, api.tidex.no {\n    respond 200\n}\n" + other_host)
        for stage in ("supabase", "convex"):
            candidate = root / "candidate.Caddyfile"
            subprocess.run([
                "python3", str(helper), "--source", str(source), "--output",
                str(candidate), "--calendar", stage,
            ], check=True, stdout=subprocess.DEVNULL)
            generated = candidate.read_text()
            assert generated.endswith(other_host), "Another site's configuration changed"
            site = re.search(r"(?ms)^identity\.tidex\.no, api\.tidex\.no \{\n.*?^\}", generated)[0]
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            site = site.replace("identity.tidex.no, api.tidex.no", f"http://127.0.0.1:{port}")
            site = re.sub(r"(?m)^    (import|bind) .*\n", "", site)
            site = re.sub(r"(?ms)^    tls \{\n.*?^    \}\n", "", site)
            for address in ("100.109.207.90:8000", "127.0.0.1:3221"):
                site = site.replace(address, f"127.0.0.1:{upstream.server_port}")
            candidate.write_text("{\n    admin off\n    auto_https off\n}\n" + site)
            with (root / "caddy.log").open("w") as log:
                process = subprocess.Popen([
                    "caddy", "run", "--config", str(candidate), "--adapter", "caddyfile",
                ], stdout=log, stderr=log)
                try:
                    deadline = time.monotonic() + 10
                    while True:
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                                break
                        except OSError:
                            if process.poll() is not None or time.monotonic() > deadline:
                                raise AssertionError((root / "caddy.log").read_text())
                            time.sleep(0.05)
                    base = f"http://127.0.0.1:{port}"
                    refresh = "/auth/v1/token?grant_type=refresh_token"
                    with urlopen(Request(base + refresh, method="POST"), timeout=2) as response:
                        assert json.load(response) == {"path": refresh, "method": "POST"}
                    feed = "/functions/v1/calendar-feed/tidex-routing-probe.ics"
                    with urlopen(base + feed, timeout=2) as response:
                        expected = feed if stage == "supabase" else feed.removeprefix("/functions/v1")
                        assert json.load(response)["path"] == expected
                    for path, method in [
                        (refresh, "GET"), ("/auth/v1/token?grant_type=password", "POST"),
                        ("/auth/v1/user", "PUT"), ("/rest/v1/profiles", "POST"),
                        ("/functions/v1/send_message", "POST"), ("/storage/v1/object/test", "POST"),
                        ("/graphql/v1", "POST"), ("/realtime/v1/websocket", "GET"),
                        (refresh + "&grant_type=password", "POST"),
                        ("/auth/v1/token?grant_type=password&grant_type=refresh_token", "POST"),
                        (feed, "POST"),
                    ]:
                        try:
                            urlopen(Request(base + path, method=method), timeout=2)
                        except (URLError, ConnectionError):
                            pass
                        else:
                            raise AssertionError(f"Write freeze allowed {method} {path}")
                finally:
                    process.terminate()
                    process.wait(timeout=10)
            print(f"PASS {stage}: refresh and calendar work; all eleven other routes abort")
finally:
    upstream.shutdown()
    upstream.server_close()
