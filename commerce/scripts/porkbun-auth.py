#!/usr/bin/env python3
"""Authorize Porkbun through PKCE; persist credentials without displaying them."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2] / '.local/commerce'
STATE = ROOT / 'porkbun-auth-state.json'
KEYS = ROOT / 'porkbun.env'
BASE = 'https://api.porkbun.com/api/json/v3'


def save_private(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def request(path, data):
    req = urllib.request.Request(BASE + path, data=json.dumps(data).encode(),
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            return json.load(error)
        except ValueError:
            return {'status': 'ERROR', 'code': 'HTTP_' + str(error.code)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'check'])
    parser.add_argument('--open', action='store_true', help='Open approval in your normal browser')
    args = parser.parse_args()
    if KEYS.exists():
        print('Porkbun credentials already saved. No new key requested.')
        return 0
    if args.action == 'start':
        state = json.loads(STATE.read_text()) if STATE.exists() else None
        if not state or time.time() - state['created'] > 1800:
            verifier = secrets.token_urlsafe(60)
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
            result = request('/apikey/request', {
                'name': 'PressTalk — presstalk.app email DNS setup',
                'codeChallenge': challenge,
                'codeChallengeMethod': 'S256',
            })
            url = urllib.parse.urlparse(result.get('authUrl', ''))
            if not result.get('requestToken') or url.scheme != 'https' or url.hostname != 'porkbun.com':
                print('Authorization request failed:', result.get('code', result.get('status', 'INVALID_RESPONSE')))
                return 1
            state = {'created': time.time(), 'verifier': verifier,
                     'requestToken': result['requestToken'], 'authUrl': result['authUrl']}
            save_private(STATE, json.dumps(state))
        print('Approve PressTalk access here (expires after 30 minutes):')
        print(state['authUrl'])
        if args.open:
            opened = subprocess.run(['/usr/bin/open', state['authUrl']], capture_output=True)
            if opened.returncode:
                print('Automatic browser opening is unavailable here. Open the link above manually.')
        return 0
    if not STATE.exists():
        print('Start authorization first.')
        return 1
    state = json.loads(STATE.read_text())
    result = request('/apikey/retrieve', {
        'requestToken': state['requestToken'], 'codeVerifier': state['verifier'],
    })
    if result.get('status') == 'SUCCESS' and result.get('apikey') and result.get('secretapikey'):
        # Save the one-time secret immediately, before any additional network call.
        save_private(KEYS, 'PORKBUN_API_KEY=' + json.dumps(result['apikey']) + '\n'
                     + 'PORKBUN_SECRET_API_KEY=' + json.dumps(result['secretapikey']) + '\n')
        STATE.unlink()
        print('Porkbun credentials saved with owner-only permissions. No secrets displayed.')
        return 0
    print('Porkbun authorization:', result.get('status', 'UNKNOWN'), result.get('code', ''))
    return 2 if result.get('status') == 'PENDING' else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print('Stopped:', type(error).__name__, '— no credentials displayed. Retry after checking the connection.')
        raise SystemExit(1)
