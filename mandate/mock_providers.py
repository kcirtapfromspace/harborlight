#!/usr/bin/env python3
# Demo-only mock providers for Act 5. Serves a throwaway GitHub Actions API and
# a throwaway Vault KV v2 on one loopback port, returning dummy values. This is
# NOT a real GitHub or Vault endpoint and must never be pointed at one: it
# exists so the bounded-task ledger can be exercised locally with no accounts.
#
# The act proves the broker's ledger mechanics — manifest pinning, the one-shot
# slot charge, replay denial, revoke — not a real provider effect. Every value
# below is synthetic.
import base64
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# Dummy secret the mock Vault hands back for the manifest's value_ref.
VAULT_SECRET = "bt-demo-secret-plaintext"  # dummy

# The GitHub secrets API seals the value against this key with a libsodium
# sealed box, which only scalar-multiplies against it, so any 32 random bytes
# are a usable public key for the demo. Regenerated each start.
PUBKEY = base64.b64encode(os.urandom(32)).decode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep the transcript clean
        pass

    def _send(self, code, body=None):
        self.send_response(code)
        if body is not None:
            payload = json.dumps(body).encode()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_header("Content-Length", "0")
            self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        # Vault KV v2: a pinned ?version= read requires the data+metadata envelope.
        if path == "/v1/secret/data/task-app":
            return self._send(200, {
                "data": {
                    "data": {"TOKEN": VAULT_SECRET},
                    "metadata": {"version": 1, "destroyed": False, "deletion_time": ""},
                }
            })
        # GitHub: resolve the repository to a stable numeric id at plan time.
        if path == "/repos/acme/task-widgets":
            return self._send(200, {"id": 424242, "full_name": "acme/task-widgets"})
        # GitHub: the public key the secret is sealed against.
        if path == "/repos/acme/task-widgets/actions/secrets/public-key":
            return self._send(200, {"key_id": "568250167", "key": PUBKEY})
        return self._send(404, {"message": "not found"})

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)
        # GitHub: accept the sealed secret write.
        if self.path.startswith("/repos/acme/task-widgets/actions/secrets/"):
            return self._send(201)
        return self._send(404, {"message": "not found"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = HTTPServer(("127.0.0.1", port), Handler)
    # Print the bound port on the first line so the caller can read it.
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
