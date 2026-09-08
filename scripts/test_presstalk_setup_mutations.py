#!/usr/bin/env python3
"""Require the UI/wiring tests to reject removed production callback calls."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app_command = ['python3', 'scripts/test_presstalk_app_wiring.py']
baseline = subprocess.run(app_command, cwd=root, capture_output=True, text=True)
assert baseline.returncode == 0 and 'PASS: actual app settings/menu wiring' in baseline.stdout, baseline.stdout + baseline.stderr
main = (root / 'Sources/JarvisTap/main.swift').read_text()
ui = (root / 'Sources/JarvisTap/FirstRunSetupWindow.swift').read_text()
cases = [
    ('settings_action', main, 'self?.runVisibleSetupCheck()', 'PRESSTALK_TEST_APP_SOURCE',
     'Settings setup action never constructed the guide', app_command),
    ('delivery_observer', main, 'self?.firstRunSetupWindowController?.observeDictation(transcript)', 'PRESSTALK_TEST_APP_SOURCE',
     'production delivery observer never reached the guide', app_command),
    ('delivery_confirmation', main, 'self.withStateLock { self.setupNeedsFreshDictation = false }', 'PRESSTALK_TEST_APP_SOURCE',
     'real delivery observer or confirmation callback is disconnected', app_command),
    ('model_action', ui, 'onDownloadSpeechModel?()', 'PRESSTALK_TEST_SETUP_UI_SOURCE',
     'Model button does not start or show preparation', ['bash', 'scripts/test_presstalk_setup_controls.sh']),
]
with tempfile.TemporaryDirectory(prefix='presstalk-setup-mutations-') as directory:
    def run(case):
        name, source, call, variable, expected, command = case
        assert call in source, f'Mutation no longer applies: {name}'
        path = Path(directory) / (name + '.swift')
        path.write_text(source.replace(call, '/* deliberately disconnected */', 1))
        env = dict(os.environ); env[variable] = str(path)
        result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
        output = result.stdout + result.stderr
        rejected = result.returncode != 0 and any(
            expected in line and (line.startswith('FAIL: ') or 'Fatal error: ' in line)
            for line in output.splitlines())
        if not rejected: print(output)
        return {'mutation': name, 'rejectedByBehavior': rejected}
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(run, cases))
    print(json.dumps(results, indent=2))
    assert all(r['rejectedByBehavior'] for r in results), 'A removed call site escaped the behavioral assertions'
print('PASS: all four removed production callbacks fail behavioral tests')
