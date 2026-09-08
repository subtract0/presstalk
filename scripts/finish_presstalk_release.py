#!/usr/bin/env python3
"""Finish a hash-bound, locally reviewed Mac artifact in the owner's Terminal."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inventory(app):
    result = {}
    for path in sorted(Path(app).rglob('*')):
        if path.is_symlink():
            raise RuntimeError(f'Unexpected symbolic link: {path}')
        if path.is_file():
            result[str(path.relative_to(app))] = {'sha256': sha(path), 'mode': path.stat().st_mode & 0o777}
    return result


def verify_prepared(manifest):
    app = Path(manifest['app'])
    if inventory(app) != manifest['files']:
        raise RuntimeError('The prepared app differs from the reviewed artifact.')
    for name in ('entitlements', 'readinessScript'):
        if sha(manifest[name]['path']) != manifest[name]['sha256']:
            raise RuntimeError(f'The reviewed {name} changed.')
    check_metadata(app, manifest)
    return app


def check_metadata(app, manifest):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    for key, value in manifest['metadata'].items():
        if info.get(key) != value:
            raise RuntimeError(f'App metadata does not match: {key}')


def run(args, log=None):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    if log:
        Path(log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed ({result.returncode}):\n{result.stderr.strip() or result.stdout.strip()}')
    return result.stdout


def verify_signed(app, manifest, notarized=False):
    check_metadata(app, manifest)
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    run(['/usr/bin/codesign', '--verify', '-R', manifest['requirement'], app])
    for relative in manifest['machOFiles']:
        path = app / relative
        report = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(path)], capture_output=True, text=True)
        if report.returncode or not all(part in report.stderr for part in (
            'Timestamp=', 'runtime', 'TeamIdentifier=' + manifest['team'], 'Authority=Developer ID Application:')):
            raise RuntimeError(f'Missing Developer ID, hardened runtime, or secure timestamp: {relative}')
    raw = run(['/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', app / 'Contents/MacOS/jarvistap'])
    if plistlib.loads(raw.encode()) != {'com.apple.security.device.audio-input': True}:
        raise RuntimeError('Unexpected microphone entitlements.')
    if notarized:
        run(['/usr/bin/xcrun', 'stapler', 'validate', app])
        run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app])


def require_stopped():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'jarvistap'], capture_output=True, text=True)
    if result.returncode == 0:
        raise RuntimeError('PressTalk is still running. Quit it from its menu, then run this launcher again.')
    if result.returncode != 1:
        raise RuntimeError('Could not check whether PressTalk is running. Installation was not attempted.')


def install(app, manifest, receipt):
    print('\nThe notarized release candidate is ready. Your previous app will be preserved.', flush=True)
    input('Quit PressTalk from its menu bar menu, then press Return to install: ')
    require_stopped()
    target = Path.home() / 'Applications/PressTalk.app'
    if Path('/Applications/PressTalk.app').exists():
        raise RuntimeError('A second PressTalk is present in /Applications. Resolve the duplicate before installing this user copy.')
    target.parent.mkdir(exist_ok=True)
    if target.exists():
        if target.is_symlink() or plistlib.loads((target / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != 'com.am.presstalk':
            raise RuntimeError('The existing app has an unexpected identity or is a symbolic link.')
    stage_root = Path(tempfile.mkdtemp(prefix='.presstalk-install-', dir=target.parent))
    staged = stage_root / 'PressTalk.app'
    run(['/usr/bin/ditto', app, staged])
    if inventory(staged) != inventory(app):
        raise RuntimeError('The installation copy differs from the verified app.')
    verify_signed(staged, manifest, notarized=True)
    require_stopped()
    backup = None
    if target.exists():
        backup_root = Path.home() / 'Library/Application Support/PressTalk Install Backups'
        backup_root.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='before-23.2-', dir=backup_root)) / 'PressTalk.app'
        target.rename(backup)
    try:
        staged.rename(target)
    except OSError:
        if backup:
            backup.rename(target)
        raise
    stage_root.rmdir()
    receipt['installedApp'] = str(target)
    receipt['previousApp'] = str(backup) if backup else None
    print('Installed verified PressTalk 0.1.23 / 23.2.', flush=True)
    if backup:
        print(f'Previous app preserved at: {backup}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--verify-prepared', action='store_true')
    parser.add_argument('--offline-test', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    manifest = json.loads(args.manifest.read_text())
    prepared = verify_prepared(manifest)
    print('Verified the complete reviewed PressTalk 0.1.23 / 23.2 artifact.', flush=True)
    if args.verify_prepared:
        return
    output = Path(manifest['outputDirectory'])
    output.mkdir(parents=True, exist_ok=True)
    receipt_path = output / 'release-receipt.json'
    if args.offline_test:
        if not receipt_path.exists():
            raise RuntimeError('Finish installing the reviewed release candidate first.')
        receipt = json.loads(receipt_path.read_text())
        installed = Path.home() / 'Applications/PressTalk.app'
        if receipt.get('manifestSHA256') != sha(args.manifest) or inventory(installed) != receipt.get('signedFiles'):
            raise RuntimeError('The installed app does not match the notarized release receipt.')
        verify_signed(installed, manifest, notarized=True)
        print('This test denies network access to PressTalk only. Other apps stay connected.', flush=True)
        input('Quit PressTalk, then press Return to start the offline test: ')
        require_stopped()
        print('Keep this Terminal open. Dictate a sentence in another app, then quit PressTalk.', flush=True)
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)', str(installed / 'Contents/MacOS/jarvistap')])
        if result.returncode:
            raise RuntimeError(f'The offline app process exited with status {result.returncode}; success has not been recorded.')
        print('The offline process exited. Its exit code alone does not prove successful dictation.', flush=True)
        return
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text())
        app = Path(receipt['app'])
        if receipt.get('manifestSHA256') != sha(args.manifest) or receipt.get('signedFiles') != inventory(app):
            raise RuntimeError('The prior notarized artifact does not match its release receipt.')
        verify_signed(app, manifest, notarized=True)
        print('Reusing the verified notarized candidate.', flush=True)
    else:
        job = Path(tempfile.mkdtemp(prefix='notary-', dir=output))
        app = job / 'PressTalk.app'
        run(['/usr/bin/ditto', prepared, app])
        if inventory(app) != manifest['files']:
            raise RuntimeError('The signing copy differs from the reviewed artifact.')
        keychain = Path.home() / 'Library/Keychains/login.keychain-db'
        sign = ['/usr/bin/codesign', '--force', '--sign', manifest['identity'], '--keychain', str(keychain), '--timestamp', '--options', 'runtime']
        print('Signing with your existing Developer ID and an Apple secure timestamp.', flush=True)
        # The unchanged nested input-method app already carries its own verified
        # Developer ID signature. Sign only the changed main executable and seal.
        run(sign + ['--entitlements', manifest['entitlements']['path'], '--identifier', 'com.am.presstalk', app / 'Contents/MacOS/jarvistap'], job / 'sign-main.log')
        run(sign + ['--entitlements', manifest['entitlements']['path'], app], job / 'sign-app.log')
        verify_signed(app, manifest)
        submission = job / 'submission.zip'
        run(['/usr/bin/ditto', '-c', '-k', '--keepParent', app, submission])
        print('Submitting this exact build to Apple. Notarization can take several minutes.', flush=True)
        raw = run(['/usr/bin/xcrun', 'notarytool', 'submit', submission, '--keychain-profile', 'presstalk-notary', '--keychain', keychain, '--wait', '--output-format', 'json'], job / 'notary-output.log')
        result = json.loads(raw)
        (job / 'notary-result.json').write_text(json.dumps(result, indent=2))
        if result.get('status') != 'Accepted':
            raise RuntimeError('Apple did not accept this build. Its report has been preserved; nothing was installed.')
        run(['/usr/bin/xcrun', 'stapler', 'staple', app], job / 'staple.log')
        verify_signed(app, manifest, notarized=True)
        run(['/bin/bash', manifest['readinessScript']['path'], '--app', app, '--require-developer-id', '--json-output', job / 'readiness.json'], job / 'readiness.log')
        archive = output / 'PressTalk-0.1.23-23.2.zip'
        run(['/usr/bin/ditto', '-c', '-k', '--keepParent', app, archive])
        receipt = {'manifestSHA256': sha(args.manifest), 'app': str(app), 'signedFiles': inventory(app),
                   'binarySHA256': sha(app / 'Contents/MacOS/jarvistap'), 'archive': str(archive),
                   'archiveSHA256': sha(archive), 'notarizationID': result['id'], 'notarizationStatus': result['status']}
        receipt_path.write_text(json.dumps(receipt, indent=2))
        print('Apple accepted this build. Stapled ticket, signature and Gatekeeper all pass.', flush=True)
    install(app, manifest, receipt)
    receipt_path.write_text(json.dumps(receipt, indent=2))
    try:
        run(['/usr/bin/open', Path(receipt['installedApp'])])
        guide = Path.home() / 'Downloads/PressTalk Release Test.html'
        if guide.exists():
            run(['/usr/bin/open', guide])
    except RuntimeError:
        print('Installation is complete. Open PressTalk from your Applications folder to start it.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, EOFError, KeyboardInterrupt) as error:
        print(f'\nStopped: {error}', file=sys.stderr, flush=True)
        sys.exit(1)
