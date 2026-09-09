#!/usr/bin/env python3
"""Package an already-signed app in a Finder drag-to-Applications disk image.

Install the pinned build dependencies with scripts/dmg-requirements.txt.
Signing and notarizing the resulting DMG are separate release steps.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
app = args.app.resolve()
output = args.output.resolve()
if output.exists():
    parser.error('Output already exists; use a fresh artifact path')
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
if app.name != 'PressTalk.app' or info.get('CFBundleIdentifier') != 'com.am.presstalk':
    parser.error('Expected the production PressTalk.app bundle')
icon_name = info.get('CFBundleIconFile', '')
if icon_name != 'PressTalk.icns' or not (app / 'Contents/Resources' / icon_name).is_file():
    parser.error('The app must contain its registered PressTalk icon')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
try:
    import dmgbuild
except ImportError:
    sys.exit('Install scripts/dmg-requirements.txt into the Python environment used for packaging.')
root = Path(__file__).resolve().parents[1]
subprocess.run(['swift', str(root / 'scripts/presstalk_bundle_icon_gate.swift'), str(app)], check=True)
output.parent.mkdir(parents=True, exist_ok=True)
dmgbuild.build_dmg(str(output), 'PressTalk', settings={
    'format': 'UDZO',
    'files': [str(app)],
    'symlinks': {'Applications': '/Applications'},
    'icon': str(app / 'Contents/Resources' / icon_name),
    'background': str(root / 'resources/installer-background.png'),
    'icon_locations': {'PressTalk.app': (170, 180), 'Applications': (470, 180)},
    # Reserve room for Finder chrome even when the user's preferences show
    # its status/path bars despite the image's preferred window settings.
    'window_rect': ((180, 140), (640, 500)),
    'default_view': 'icon-view',
    'show_status_bar': False, 'show_tab_view': False, 'show_toolbar': False,
    'show_pathbar': False, 'show_sidebar': False,
    'show_icon_preview': False, 'include_icon_view_settings': True,
    'include_list_view_settings': False, 'arrange_by': None,
    'icon_size': 112, 'text_size': 15, 'label_pos': 'bottom',
    'hide_extension': ['PressTalk.app'],
})
print(f'Created {output}')
