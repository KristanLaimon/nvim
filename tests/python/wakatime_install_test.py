import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

source = Path(__file__).resolve().parents[2] / "scripts/dependencies/install_wakatime.py"
spec = importlib.util.spec_from_file_location("wakatime_installer", source)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class WakaTimeInstallTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.destination = Path(self.directory.name) / "user folder/.wakatime/wakatime-cli.exe"
        self.archive_name = "wakatime-cli-windows-amd64.zip"
        archive = io.BytesIO()
        with ZipFile(archive, "w") as package:
            package.writestr("wakatime-cli-windows-amd64.exe", b"verified executable")
        self.archive = archive.getvalue()
        self.checksum = hashlib.sha256(self.archive).hexdigest()

    def download(self, url):
        if url.endswith("/latest"):
            return json.dumps({"assets": [
                {"name": self.archive_name, "browser_download_url": "https://github.com/archive"},
                {"name": "checksums_sha256.txt", "browser_download_url": "https://github.com/checksums"},
            ]}).encode()
        if url.endswith("/checksums"):
            return (self.checksum + "  " + self.archive_name + "\n").encode()
        return self.archive

    def install(self):
        with patch.object(installer.platform, "system", return_value="Windows"), \
                patch.object(installer.platform, "machine", return_value="AMD64"), \
                patch.object(installer, "download", side_effect=self.download), \
                patch.object(installer.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 0, "v1.2.3\n", "")) as run:
            result = installer.install(self.destination)
            candidate = Path(run.call_args.args[0][0])
            self.assertFalse(candidate.exists())
            return result

    def test_installs_verified_executable_in_user_directory(self):
        self.assertIn("v1.2.3 installed", self.install())
        self.assertEqual(self.destination.read_bytes(), b"verified executable")

    def test_rejects_checksum_mismatch_without_replacing_existing_cli(self):
        self.destination.parent.mkdir(parents=True)
        self.destination.write_bytes(b"existing CLI")
        self.checksum = "0" * 64
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.install()
        self.assertEqual(self.destination.read_bytes(), b"existing CLI")

    def test_failed_version_check_preserves_existing_cli_and_cleans_candidate(self):
        self.destination.parent.mkdir(parents=True)
        self.destination.write_bytes(b"existing CLI")
        with patch.object(installer.platform, "system", return_value="Windows"), \
                patch.object(installer.platform, "machine", return_value="AMD64"), \
                patch.object(installer, "download", side_effect=self.download), \
                patch.object(installer.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "CLI")):
            with self.assertRaises(subprocess.CalledProcessError):
                installer.install(self.destination)
        self.assertEqual(self.destination.read_bytes(), b"existing CLI")
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])


if __name__ == "__main__":
    unittest.main()
