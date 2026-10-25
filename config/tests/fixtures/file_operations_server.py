"""Small protocol fixture for Neovim's real stdio LSP transport."""
import json
import sys


def send(message):
    body = json.dumps(message).encode()
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    sys.stdout.buffer.flush()


while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line == b"\r\n":
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    msg = json.loads(sys.stdin.buffer.read(int(headers["content-length"])))
    method = msg.get("method")
    result = None
    if method == "initialize":
        flags = msg["params"]["capabilities"]["workspace"]["fileOperations"]
        assert all(flags.get(phase + op) for phase in ("will", "did") for op in ("Rename", "Create", "Delete"))
        operations = {
            phase + op: {"filters": [{"scheme": "file", "pattern": {"glob": "**/*.ts"}}]}
            for phase in ("will", "did") for op in ("Rename", "Create", "Delete")
        }
        result = {"capabilities": {"textDocumentSync": 1, "workspace": {"fileOperations": operations}}}
    elif method == "workspace/willRenameFiles":
        uri = msg["params"]["files"][0]["oldUri"]
        result = {"changes": {uri: [{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}}, "newText": "new"}]}}
    elif method == "workspace/didRenameFiles":
        with open(sys.argv[1], "w", encoding="utf-8") as stream:
            json.dump(msg["params"], stream)
    elif method == "exit":
        break
    if "id" in msg:
        send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
