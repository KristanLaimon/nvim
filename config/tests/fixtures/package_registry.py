"""Small offline npm registry used by real npm/Bun integration tests."""
import io
import json
import tarfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = "fox-package-fixture"
VERSIONS = ["1.0.0", "2.0.0", "3.0.0-beta.1"]


def archive(version):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w:gz") as tar:
        for name, content in {
            "package/package.json": json.dumps({"name": NAME, "version": version}),
            "package/index.js": "module.exports = 42;\n",
        }.items():
            encoded = content.encode()
            entry = tarfile.TarInfo(name)
            entry.size = len(encoded)
            tar.addfile(entry, io.BytesIO(encoded))
    return data.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.startswith(f"/{NAME}/-/"):
            version = self.path.rsplit("/", 1)[1].removesuffix(".tgz")
            if version not in VERSIONS:
                self.send_error(404)
                return
            body = archive(version)
            content_type = "application/octet-stream"
        elif self.path.split("?", 1)[0] == f"/{NAME}":
            base = f"http://127.0.0.1:{self.server.server_port}"
            body = json.dumps({
                "name": NAME,
                "dist-tags": {"latest": "2.0.0", "next": "3.0.0-beta.1"},
                "versions": {
                    v: {"name": NAME, "version": v,
                        "dist": {"tarball": f"{base}/{NAME}/-/{v}.tgz"}}
                    for v in VERSIONS
                },
            }).encode()
            content_type = "application/json"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
