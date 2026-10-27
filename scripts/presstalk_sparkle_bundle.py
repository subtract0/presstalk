#!/usr/bin/env python3
"""Configure and verify the Sparkle framework embedded in a staged app."""
import argparse
import base64
from pathlib import Path
import plistlib
import subprocess
import sys

FEED_URL = 'https://presstalk.app/appcast.xml'
SPARKLE_VERSION = '2.10.1'
REQUIRED_BINARIES = (
    'Sparkle', 'Autoupdate', 'Updater.app/Contents/MacOS/Updater',
    'XPCServices/Installer.xpc/Contents/MacOS/Installer',
    'XPCServices/Downloader.xpc/Contents/MacOS/Downloader',
)


def public_key(path):
    encoded = Path(path).read_text().strip()
    if len(base64.b64decode(encoded, validate=True)) != 32:
        raise ValueError('Sparkle public key must encode exactly 32 bytes')
    return encoded


def configure(app, production, key_path=None):
    path = Path(app) / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    expected_id = 'com.am.presstalk' if production else None
    if production and info.get('CFBundleIdentifier') != expected_id:
        raise ValueError('Production updates require the official bundle identifier')
    if not production and not info.get('CFBundleIdentifier', '').endswith('.dev'):
        raise ValueError('Non-distribution app must use a .dev identity')
    info.update({
        'SUEnableAutomaticChecks': production,
        'SUAutomaticallyUpdate': production,
        'SUAllowsAutomaticUpdates': production,
        'SUEnableSystemProfiling': False,
        'SUVerifyUpdateBeforeExtraction': True,
        'SURequireSignedFeed': True,
        'SUSignedFeedFailureExpirationInterval': 0,
        'LSMinimumSystemVersion': '14.0.0',
    })
    if production:
        info['SUFeedURL'] = FEED_URL
        info['SUPublicEDKey'] = public_key(key_path)
    else:
        info.pop('SUFeedURL', None)
        info.pop('SUPublicEDKey', None)
    path.write_bytes(plistlib.dumps(info, sort_keys=False))


def verify(app):
    app = Path(app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    production = info.get('CFBundleIdentifier') == 'com.am.presstalk'
    if not production and not info.get('CFBundleIdentifier', '').endswith('.dev'):
        raise ValueError('Unknown app identity for updater configuration')
    for name in ('SUEnableAutomaticChecks', 'SUAutomaticallyUpdate', 'SUAllowsAutomaticUpdates'):
        if info.get(name) is not production:
            raise ValueError(f'Unexpected {name} default')
    for name, expected in (('SUEnableSystemProfiling', False),
                           ('SUVerifyUpdateBeforeExtraction', True), ('SURequireSignedFeed', True)):
        if info.get(name) is not expected:
            raise ValueError(f'Unexpected {name}')
    if info.get('SUSignedFeedFailureExpirationInterval') != 0:
        raise ValueError('Feed signature verification must not expire')
    if info.get('LSMinimumSystemVersion') != '14.0.0':
        raise ValueError('Unexpected minimum macOS version')
    if production:
        if info.get('SUFeedURL') != FEED_URL:
            raise ValueError('Production update feed does not match the fixed HTTPS feed')
        if len(base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)) != 32:
            raise ValueError('Missing or invalid Sparkle public key')
    elif 'SUFeedURL' in info or 'SUPublicEDKey' in info:
        raise ValueError('Development app must not use a production feed or key')

    notice = app / 'Contents/Resources/Sparkle-LICENSE'
    if not notice.is_file() or not notice.read_bytes().strip():
        raise ValueError('Missing Sparkle redistribution licence and notices')

    framework = app / 'Contents/Frameworks/Sparkle.framework'
    if framework.is_symlink():
        raise ValueError('Sparkle must be embedded in the app, not linked externally')
    current = framework / 'Versions/Current'
    if not current.is_symlink() or current.readlink() != Path('B'):
        raise ValueError('Versioned Sparkle framework links were not preserved')
    version = framework / 'Versions/B'
    framework_info = plistlib.loads((version / 'Resources/Info.plist').read_bytes())
    if framework_info.get('CFBundleShortVersionString') != SPARKLE_VERSION:
        raise ValueError('Embedded Sparkle does not match the pinned version')
    for relative in REQUIRED_BINARIES:
        if not (version / relative).is_file():
            raise ValueError(f'Missing Sparkle helper: {relative}')
    for path in framework.rglob('*'):
        if path.is_symlink():
            if path.readlink().is_absolute():
                raise ValueError(f'Absolute framework link: {path.name}')
            try:
                path.resolve(strict=True).relative_to(framework.resolve(strict=True))
            except (OSError, ValueError, RuntimeError) as error:
                raise ValueError(f'Escaping or broken framework link: {path.name}') from error

    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    if '@rpath/Sparkle.framework/Versions/B/Sparkle' not in linked:
        raise ValueError('App executable is not linked to the embedded Sparkle framework')
    commands = subprocess.check_output(['otool', '-l', str(binary)], text=True)
    if 'path @executable_path/../Frameworks (offset ' not in commands:
        raise ValueError('App executable is missing its packaged Frameworks runpath')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('configure', 'verify', 'validate-key'))
    parser.add_argument('--app', type=Path)
    parser.add_argument('--production', action='store_true')
    parser.add_argument('--public-key', type=Path)
    args = parser.parse_args()
    if args.action == 'validate-key':
        public_key(args.public_key)
    elif args.action == 'configure':
        configure(args.app, args.production, args.public_key)
    else:
        verify(args.app)
        print('Sparkle bundle: pinned framework, helpers, runpath and signed-feed policy verified')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Sparkle bundle rejected: {error}', file=sys.stderr)
        sys.exit(1)
