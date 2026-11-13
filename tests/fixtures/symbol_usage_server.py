"""Reference-count fixture over Neovim's actual stdio LSP transport."""
import json
import sys
import time

text = ""
uri = ""


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
    method = msg.get("method", "")
    if method in ("textDocument/documentSymbol", "textDocument/references"):
        with open(sys.argv[1], "a", encoding="utf-8") as log:
            log.write(method + "\n")
    result = None
    if method == "initialize":
        result = {"capabilities": {"textDocumentSync": 1, "documentSymbolProvider": True, "referencesProvider": True}}
    elif method == "textDocument/didOpen":
        doc = msg["params"]["textDocument"]
        text, uri = doc["text"], doc["uri"]
    elif method == "textDocument/didChange":
        text = msg["params"]["contentChanges"][-1]["text"]
    elif method == "textDocument/documentSymbol":
        result = []
        for row, line in enumerate(text.splitlines()):
            if "function " in line or "method " in line:
                span = {"start": {"line": row, "character": 0}, "end": {"line": row, "character": len(line)}}
                result.append({"name": "fixture", "kind": 6 if "method " in line else 12, "range": span, "selectionRange": span})
    elif method == "textDocument/references":
        time.sleep(0.06)
        result = [{"uri": uri, "range": {"start": {"line": i + 2, "character": 0}, "end": {"line": i + 2, "character": 3}}} for i in range(3 if "extra" in text else 2)]
    elif method == "exit":
        break
    if "id" in msg:
        send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
