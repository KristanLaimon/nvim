"""Install the official WakaTime CLI using only Python 3's standard library."""

import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen
from zipfile import ZipFile


def download(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "FoxVim-WakaTime-Installer"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def install(destination: Path) -> str:
    operating_system = platform.system().lower()
    if operating_system == "linux" and (os.environ.get("TERMUX_VERSION") or hasattr(sys, "getandroidapilevel")):
        operating_system = "android"
    machine = platform.machine().lower()
    architecture = {
        "amd64": "amd64", "x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64",
        "i386": "386", "i686": "386", "x86": "386", "armv7l": "arm", "armv6l": "arm",
    }.get(machine)
    if not architecture:
        raise ValueError("Unsupported processor: " + machine)
    binary = "wakatime-cli-" + operating_system + "-" + architecture
    archive_name = binary + ".zip"
    if operating_system == "windows":
        binary += ".exe"
    release = json.loads(download("https://api.github.com/repos/wakatime/wakatime-cli/releases/latest"))
    assets = {asset["name"]: asset["browser_download_url"] for asset in release["assets"]}
    if archive_name not in assets:
        raise ValueError("No official release for " + operating_system + "/" + architecture)
    checksums = download(assets["checksums_sha256.txt"]).decode("utf-8")
    expected = next((line.split()[0] for line in checksums.splitlines()
                     if len(line.split()) == 2 and line.split()[1].lstrip("*") == archive_name), None)
    archive = download(assets[archive_name])
    if expected is None or hashlib.sha256(archive).hexdigest() != expected.lower():
        raise ValueError("WakaTime release checksum verification failed")
    with ZipFile(io.BytesIO(archive)) as package:
        executable = package.read(binary)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".wakatime-", suffix=destination.suffix,
                                     delete=False) as temporary:
        candidate = Path(temporary.name)
        temporary.write(executable)
    try:
        candidate.chmod(0o755)
        result = subprocess.run([str(candidate), "--version"], check=True, capture_output=True,
                                text=True, timeout=10, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        os.replace(candidate, destination)
        return result.stdout.strip() + " installed at " + str(destination)
    finally:
        candidate.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: install_wakatime.py <destination>")
        print(install(Path(sys.argv[1])))
    except Exception as error:
        print("WakaTime installation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
