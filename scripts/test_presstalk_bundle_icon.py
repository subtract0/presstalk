#!/usr/bin/env python3
"""A copied file alone is not enough: Finder must find and decode the icon."""
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='presstalk-icon-test-') as folder:
    app = Path(folder) / 'PressTalk.app'
    resources = app / 'Contents/Resources'; resources.mkdir(parents=True)
    info = app / 'Contents/Info.plist'; icon = resources / 'PressTalk.icns'
    def check(expected):
        p = subprocess.run(['swift', str(root / 'scripts/presstalk_bundle_icon_gate.swift'), str(app)], capture_output=True, text=True)
        assert (p.returncode == 0) == expected, p.stdout + p.stderr
    info.write_bytes(plistlib.dumps({'CFBundleIconFile': 'PressTalk.icns'}))
    shutil.copyfile(root / 'resources/PressTalk.icns', icon)
    check(True)
    info.write_bytes(plistlib.dumps({'CFBundleIconFile': 'Wrong.icns'})); check(False)
    info.write_bytes(plistlib.dumps({'CFBundleIconFile': 'PressTalk.icns'}))
    icon.unlink(); check(False)
    icon.write_bytes(b'not an icon'); check(False)
print('PASS: icon gate rejects missing registration, missing file and corrupt image')
