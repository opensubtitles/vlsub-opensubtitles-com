#!/usr/bin/env python3
"""Local plain-HTTP door to an https-only API server, for developing VLSub.

VLC's Lua can send headers (Api-Key, Authorization) only over plain HTTP;
the development API is reachable over https only. This proxy listens on
127.0.0.1 - nothing outside this computer can reach it - and forwards every
request to the https server:

    VLSub --http--> 127.0.0.1:<port> --https--> https://rb-dev.ngrok.dev

Normally started by `tools/dev.sh run --dev-api`. By hand:

    python3 tools/devproxy.py https://rb-dev.ngrok.dev --port-file /tmp/p
    VLSUB_API_URL=http://127.0.0.1:<port>/api/v1 VLSUB_API_KEY=... vlc

- The port is chosen by the system (no fixed port to collide with) unless
  --port is given; it is printed and written to --port-file.
- Redirects are passed back, never followed: VLSub follows the AI
  translation's redirect chain itself. A redirect to the upstream host is
  rewritten to a relative one so that VLSub stays on the proxy.
- One line per request is printed: method, path, status, time. Headers and
  bodies (tokens, passwords, subtitles) are never printed.

Python 3 standard library only.
"""
import argparse
import http.client
import http.server
import socketserver
import sys
import time
import urllib.parse

HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
              "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
              "accept-encoding"}


def make_handler(upstream):
    target = urllib.parse.urlsplit(upstream)
    if target.scheme != "https" or not target.hostname:
        sys.exit("upstream must be https://host[:port], got " + upstream)
    host = target.hostname
    port = target.port or 443
    absolute = "https://" + target.netloc

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):  # the default logs to stderr with client IP
            pass

        def forward(self):
            started = time.time()
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else None
            headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
            headers["Host"] = target.netloc
            headers["Accept-Encoding"] = "identity"
            headers["ngrok-skip-browser-warning"] = "1"
            status, reason, answer_headers, payload = 502, "Bad Gateway", [], b""
            try:
                conn = http.client.HTTPSConnection(host, port, timeout=170)
                conn.request(self.command, self.path, body=body, headers=headers)
                res = conn.getresponse()
                status, reason = res.status, res.reason
                payload = res.read()
                answer_headers = [(k, v) for k, v in res.getheaders() if k.lower() not in HOP_BY_HOP]
                conn.close()
            except Exception as error:  # report, do not crash the proxy
                payload = ('{"message":"devproxy: %s"}' % type(error).__name__).encode()
                answer_headers = [("Content-Type", "application/json")]
            self.send_response_only(status, reason)
            for key, value in answer_headers:
                if key.lower() == "location" and value.startswith(absolute):
                    value = value[len(absolute):] or "/"
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            print("%-6s %-70s %3d %6.2fs" % (self.command, self.path.split("?")[0][:70], status,
                                            time.time() - started), flush=True)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = forward

    return Handler


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("upstream", nargs="?", default="https://rb-dev.ngrok.dev")
    parser.add_argument("--port", type=int, default=0, help="0 = any free port (default)")
    parser.add_argument("--port-file", help="write the port here once listening")
    args = parser.parse_args()
    server = Server(("127.0.0.1", args.port), make_handler(args.upstream))
    port = server.server_address[1]
    if args.port_file:
        with open(args.port_file, "w") as f:
            f.write(str(port))
    print("devproxy: http://127.0.0.1:%d -> %s" % (port, args.upstream), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
