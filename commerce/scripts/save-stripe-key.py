#!/usr/bin/env python3
"""One-time local credential entry. Never prints or deploys the entered key."""
import getpass
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
import webbrowser

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / '.local/commerce/stripe-production.env'
LINK = 'plink_1UCjsiJpvh3XLeRlvwQnSfDk'

def main():
    print('PressTalk automatic licence delivery — Stripe access')
    print('Create a restricted LIVE key named PressTalk licence delivery.')
    print('Give it READ access only to Checkout Sessions, Payment Links, Prices,')
    print('Payment Intents and Charges. Leave all write permissions off.')
    print('This allows the service to confirm a purchase; it cannot charge or refund anyone.')
    print('The key is saved locally with owner-only permissions, never printed.')
    webbrowser.open('https://dashboard.stripe.com/apikeys')
    key = getpass.getpass('Paste the restricted key here (hidden; blank cancels): ').strip()
    if not key:
        print('No key saved.')
        return 1
    if not key.startswith('rk_live_'):
        print('Stopped: this must be a restricted live key beginning rk_live_.')
        return 1
    for path in [f'/v1/payment_links/{LINK}', f'/v1/checkout/sessions?payment_link={LINK}&limit=1',
                 '/v1/prices/price_1UCjhFJpvh3XLeRlgcMWwBHf']:
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
    temporary = DESTINATION.with_suffix('.tmp')
    fd = os.open(temporary, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write('STRIPE_SECRET_KEY=' + key + '\n')
    temporary.chmod(0o600)
    temporary.replace(DESTINATION)
    print('Saved and verified the restricted key. Return to Codex so setup can continue.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
