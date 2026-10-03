#!/usr/bin/env python3
"""Exercise the UI launcher's failure handling without launching an app."""
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[2]
shots = root / "build/shots"
shots.mkdir(parents=True, exist_ok=True)
name = "runner-check-" + uuid.uuid4().hex
snapshot = shots / (name + ".png")
marker = snapshot.with_suffix(".complete")

with tempfile.TemporaryDirectory(prefix="runner-tests-", dir=root / "build") as folder:
    temporary = Path(folder)
    commands = temporary / "bin"
    commands.mkdir()
    scripts = {
        "open": """#!/usr/bin/env python3
import os, pathlib, sys
if os.environ['MOCK_LAUNCH'] == 'fail':
    sys.exit(7)
if os.environ['MOCK_LAUNCH'] == 'complete':
    path = next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('ORICMD_SNAPSHOT='))
    pathlib.Path(path).write_bytes(b'fresh snapshot')
    pathlib.Path(path).with_suffix('.complete').touch()
""",
        "defaults": """#!/bin/zsh
print -- "$*" >> "$MOCK_DEFAULTS_LOG"
""",
        "sips": "#!/bin/zsh\nexit 0\n",
    }
    for command, contents in scripts.items():
        path = commands / command
        path.write_text(contents)
        path.chmod(0o755)
    log = temporary / "defaults.log"
    environment = dict(os.environ, PATH=str(commands) + ":" + os.environ["PATH"],
                       TMPDIR=str(temporary), MOCK_DEFAULTS_LOG=str(log))
    lock = temporary / "oricmd-ui-tests.lock"

    def run(mode, keys="wait"):
        result = subprocess.run(["/bin/zsh", str(root / "scripts/test/run.sh"), name, keys],
                                env=dict(environment, MOCK_LAUNCH=mode), text=True, capture_output=True)
        return result

    try:
        snapshot.write_bytes(b'stale snapshot')
        marker.touch()
        result = run("fail")
        assert result.returncode == 7, result.stderr
        assert not snapshot.exists() and not marker.exists(), "stale results survived"
        assert not lock.exists(), "failed launch left a lock"
        assert log.read_text().strip() == 'delete ru.themmag.OriCmd.tests'
        print("ok   failed launches cannot reuse old snapshots and clean up test settings")

        result = run("unfinished")
        assert result.returncode != 0 and 'did not finish' in result.stderr, result.stderr
        assert not lock.exists()
        print("ok   a successful launch without a completion marker fails")

        result = run("complete")
        assert result.returncode == 0, result.stderr
        assert snapshot.read_bytes() == b'fresh snapshot' and marker.exists()
        assert not lock.exists()
        print("ok   completed runs save fresh results and release the lock")

        result = run("complete", keys="")
        assert result.returncode == 0, result.stderr
        print("ok   snapshot-only runs accept an empty key sequence")

        previous = log.read_text()
        lock.mkdir()
        result = run("complete")
        assert result.returncode != 0 and 'Another UI test' in result.stderr, result.stderr
        assert lock.exists() and log.read_text() == previous
        print("ok   overlapping runs leave the active run and its settings untouched")
        lock.rmdir()
    finally:
        snapshot.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
