#!/usr/bin/env python3
"""Exercise the real gate over a site fixture, including absent live call sites."""
import contextlib
import http.server
import importlib.util
import io
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('presstalk_download_link_gate.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LinkGateTests(unittest.TestCase):
    def test_real_gate_rejects_broken_customer_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            site = root / 'site'
            site.mkdir()
            policy = root / 'Sources/PressTalkCore/EntitlementPolicy.swift'
            policy.parent.mkdir(parents=True)
            policy.write_text('public static let checkoutURLString = "https://presstalk.app/buy.html"')
            download = '<a href="https://github.com/example/app/releases/download/v1/app.zip">Download</a>'
            buy = f'<a href="{gate.CHECKOUT_SERVICE}">Continue</a>'
            (site / 'index.html').write_text(download + '<a href="buy.html">Buy</a>')
            (site / 'buy.html').write_text(buy)
            with patch.object(gate, 'ROOT', root), patch.object(gate, 'SITE', site), \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                with patch.object(gate, 'status', return_value=(200, '')) as probe:
                    self.assertEqual(gate.main(), 0)
                    self.assertIn(gate.CHECKOUT_SERVICE, [call.args[0] for call in probe.call_args_list])
                with patch.object(gate, 'status', side_effect=lambda url: (503 if url == gate.CHECKOUT_SERVICE else 200, '')):
                    self.assertEqual(gate.main(), 1)
                (site / 'index.html').write_text(download.replace('app.zip', 'app.dmg') + '<a href="buy.html">Buy</a>')
                with patch.object(gate, 'status', return_value=(200, '')) as probe:
                    self.assertEqual(gate.main(), 0)
                    self.assertTrue(any(call.args[0].endswith('.dmg') for call in probe.call_args_list))
                with patch.object(gate, 'status', side_effect=lambda url: (404 if url.endswith('.dmg') else 200, '')):
                    self.assertEqual(gate.main(), 1)
                (site / 'index.html').write_text(download + '<a href="buy.html">Buy</a>')
                with patch.object(gate, 'status', return_value=(200, '')):
                    (site / 'buy.html').unlink()
                    self.assertEqual(gate.main(), 1)
                    (site / 'buy.html').write_text('<!--' + buy + '-->')
                    self.assertEqual(gate.main(), 1)
                    (site / 'buy.html').write_text(buy)
                    (site / 'index.html').write_text('<!--' + download + '--><a href="buy.html">Buy</a>')
                    self.assertEqual(gate.main(), 1)

    def test_http_probe_follows_redirect_to_its_real_result(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                if self.path.startswith('/redirect-'):
                    self.send_response(303)
                    self.send_header('Location', '/' + self.path.removeprefix('/redirect-'))
                else:
                    self.send_response(200 if self.path == '/ok' else 404)
                self.end_headers()

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            origin = f'http://127.0.0.1:{server.server_port}'
            self.assertEqual(gate.status(origin + '/redirect-ok')[0], 200)
            self.assertEqual(gate.status(origin + '/redirect-missing')[0], 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
