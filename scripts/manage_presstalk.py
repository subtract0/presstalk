#!/usr/bin/env python3
"""Open the private PressTalk access manager using this Mac's operator credential."""
import json
import os
from pathlib import Path
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request
import subprocess

CONFIG = Path.home() / 'Library/Application Support/PressTalk Operator/config.json'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    info = CONFIG.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError('Operator credentials must be private to your Mac account.')
    config = json.loads(CONFIG.read_text())
    origin = config['origin']
    if origin != 'https://presstalk-licenses.presstalk.workers.dev':
        raise RuntimeError('Unexpected PressTalk service address.')
    request = urllib.request.Request(origin + '/admin/link', data=b'', method='POST', headers={
        'Authorization': 'Bearer ' + config['token'], 'User-Agent': 'PressTalk-Operator/1.0',
    })
    with urllib.request.build_opener(NoRedirect).open(request, timeout=20) as response:
        result = json.loads(response.read(4096))
    url = urllib.parse.urlsplit(result['url'])
    if urllib.parse.urlunsplit((url.scheme, url.netloc, '', '', '')) != origin or url.path != '/admin/enter':
        raise RuntimeError('The service returned an unexpected sign-in address.')
    if '--check' in sys.argv:
        print('PressTalk manager authorization verified. No browser was opened.')
    else:
        subprocess.run(['/usr/bin/open', result['url']], check=True)
        print('Your PressTalk manager is opening in your browser.')
        print('Choose a person, give extra days or Free forever, then copy their link.')

if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        print('Could not open the manager (service status %s). Try again shortly.' % error.code)
        sys.exit(1)
    except Exception as error:
        # Never print request objects, credentials, or authenticated URLs.
        print('Could not open the manager. Check your connection and try again. (%s)' % type(error).__name__)
        sys.exit(1)
