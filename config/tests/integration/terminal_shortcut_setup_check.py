"""Fixture checks for terminal setup; no live terminal configuration is touched."""
import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "config/scripts"
SEQUENCE = "\x1b[114;7u"


def load_settings(path):
    # Windows Terminal accepts trailing commas in its JSONC settings.
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", path.read_text(encoding="utf-8-sig")))


def windows_setup(modern):
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
        path.parent.mkdir(parents=True)
        settings = {
            "actions": [{"command": "copy", "id": "User.Keep"}],
            "profiles": {"defaults": {"opacity": 87}},
        }
        if modern:
            settings["keybindings"] = [
                {"keys": "ctrl+alt+r", "id": "User.Old"},
                {"keys": "ctrl+shift+c", "id": "User.Keep"},
            ]
        else:
            settings["actions"].append({"command": "paste", "keys": "ctrl+alt+r"})
        path.write_text(json.dumps(settings, indent=4), encoding="utf-8")
        environment = dict(os.environ, LOCALAPPDATA=temporary)

        def run(name, *arguments):
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPTS / name), *arguments],
                env=environment, capture_output=True, text=True,
            )
            assert result.returncode == 0, result.stdout + result.stderr

        for _ in range(2):
            run("setup-powershell.ps1", "-ShortcutsOnly")
            current = load_settings(path)
            assert current["profiles"]["defaults"]["opacity"] == 87
            assert any(action.get("id") == "User.Keep" for action in current["actions"])
            if modern:
                bindings = [item for item in current["keybindings"] if item.get("keys") == "ctrl+alt+r"]
                assert bindings == [{"keys": "ctrl+alt+r", "id": "FoxVim.ProjectReplace"}], bindings
                actions = [item for item in current["actions"] if item.get("id") == "FoxVim.ProjectReplace"]
            else:
                actions = [item for item in current["actions"] if item.get("keys") == "ctrl+alt+r"]
            assert len(actions) == 1, actions
            assert actions[0]["command"] == {"action": "sendInput", "input": SEQUENCE}, actions
        assert list(path.parent.glob("settings.json.backup.*"))
        run("unsetup-powershell.ps1")
        current = load_settings(path)
        assert all(item.get("keys") != "ctrl+alt+r" for item in current.get("keybindings", []))
        assert all(item.get("id") != "FoxVim.ProjectReplace" for item in current["actions"])
        assert all(item.get("keys") != "ctrl+alt+r" for item in current["actions"])


def kitty_setup(include):
    with tempfile.TemporaryDirectory() as temporary:
        config = Path(temporary) / "kitty/kitty.conf"
        config.parent.mkdir()
        config.write_text("include user.conf\n" if include else "font_size 12\n")
        target = config.with_name("user.conf") if include else config
        base = "font_size 12\n"
        target.write_text(base)
        original = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = temporary
        try:
            def run(name):
                source = (SCRIPTS / name).read_text().split("python3 - <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
                with contextlib.redirect_stdout(io.StringIO()):
                    exec(compile(source, name, "exec"), {})

            run("setup-kitty.sh")
            configured = target.read_text()
            assert configured.count("map ctrl+alt+r send_text all \\x1b[114;7u\n") == 1
            run("setup-kitty.sh")
            assert target.read_text() == configured
            # Upgrade the last released block, which lacked project replacement.
            target.write_text(configured.replace("map ctrl+alt+r send_text all \\x1b[114;7u\n", ""))
            run("setup-kitty.sh")
            assert target.read_text() == configured
            run("unsetup-kitty.sh")
            assert target.read_text() == base
            if include:
                assert config.read_text() == "include user.conf\n"
        finally:
            if original is None:
                os.environ.pop("XDG_CONFIG_HOME", None)
            else:
                os.environ["XDG_CONFIG_HOME"] = original


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only-failure", action="store_true")
    args = parser.parse_args()
    checks = [("Kitty main config", lambda: kitty_setup(False)), ("Kitty include", lambda: kitty_setup(True))]
    if shutil.which("powershell.exe"):
        checks += [("Windows Terminal legacy", lambda: windows_setup(False)), ("Windows Terminal modern", lambda: windows_setup(True))]
    failed = 0
    for name, check in checks:
        try:
            check()
            if not args.only_failure:
                print(f"PASS: {name}")
        except Exception as error:
            failed += 1
            print(f"FAIL: {name}: {error}")
    print(f"{len(checks) - failed} passed, {failed} failed")
    raise SystemExit(bool(failed))
