#!/usr/bin/env python3
"""One-time local credential entry. Never prints or deploys the entered key."""
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / '.local/commerce/stripe-production.env'
LINK = 'plink_1UCjsiJpvh3XLeRlvwQnSfDk'

def main():
    if not sys.stdin.isatty():
        print('Open the Downloads launcher in Terminal so key entry can stay hidden.')
        return 1
    print('PressTalk automatic licence delivery — Stripe access')
    print('Create a restricted LIVE key named PressTalk licence delivery.')
    print('Give it READ access only to Checkout Sessions, Payment Links, Prices,')
    print('Payment Intents and Charges. Leave all write permissions off.')
    print('This allows the service to confirm a purchase; it cannot charge or refund anyone.')
    print('The key is saved locally with owner-only permissions, never printed.')
    opened = subprocess.run(['/usr/bin/open', 'https://dashboard.stripe.com/apikeys'], capture_output=True)
    if opened.returncode:
        print('Open https://dashboard.stripe.com/apikeys in your browser.')
    key = getpass.getpass('Paste the restricted key here (hidden; blank cancels): ').strip()
    if not key:
        print('No key saved.')
        return 1
    if not re.fullmatch(r'rk_live_[A-Za-z0-9]+', key):
        print('Stopped: this must be a restricted live key beginning rk_live_.')
        return 1
    for path in [f'/v1/payment_links/{LINK}', f'/v1/checkout/sessions?payment_link={LINK}&limit=1',
                 '/v1/prices/price_1UCjhFJpvh3XLeRlgcMWwBHf',
                 '/v1/payment_intents?limit=1', '/v1/charges?limit=1']:
        request = urllib.request.Request('https://api.stripe.com' + path,
                                        headers={'Authorization': 'Bearer ' + key})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                data = json.load(response)
        except urllib.error.HTTPError as error:
            print(f'Stopped: required Stripe read returned HTTP {error.code}. No key saved.')
            return 1
        if '/payment_links/' in path and (data.get('id') != LINK or data.get('livemode') is not True):
            print('Stopped: the key did not identify the existing live PressTalk checkout.')
            return 1
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix='.stripe-key-', dir=DESTINATION.parent)
    temporary = Path(temporary_name)
    with os.fdopen(fd, 'w') as file:
        file.write('STRIPE_SECRET_KEY=' + key + '\n')
    temporary.chmod(0o600)
    temporary.replace(DESTINATION)
    print('Saved and verified the restricted key. Return to Codex so setup can continue.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
