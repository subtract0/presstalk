#!/usr/bin/env python3
"""Compile actual app wiring into a bounded UI test process.

The fixture replaces only the app's top-level run loop and opens private access
for assertions. Functional method bodies and all other app sources are unchanged.
It runs the actual UI installation and AppKit event loop so keyboard commands
reach the focused text responder. It does not run capture startup, request
permissions, load models or use a real Keychain. Requires a macOS GUI session.
"""
import os
import json
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
build = root / '.build/arm64-apple-macosx/debug'
source_path = Path(os.environ.get('PRESSTALK_TEST_APP_SOURCE', root / 'Sources/JarvisTap/main.swift'))
source = source_path.read_text()
marker = '// Runs before any AppKit setup: the self-test must not race the dictation'
assert source.count(marker) == 1, 'Cannot identify the production entry point'
body = source.split(marker)[0]
body = re.sub(r'(?m)^(\s*(?:@objc\s+)?)private\s+', r'\1', body)
with tempfile.TemporaryDirectory(prefix='presstalk-app-wiring-') as directory:
    temp = Path(directory)
    transformed = temp / 'AppUnderTest.swift'
    transformed.write_text(body)
    objects = [line for line in (build / 'jarvistap.product/Objects.LinkFileList').read_text().splitlines()
               if '/JarvisTap.build/' not in line]
    response = temp / 'dependencies.txt'
    response.write_text('\n'.join(objects) + '\n')
    command = ['swiftc', '-module-name', 'PressTalkAppWiringTest', '-I', str(build / 'Modules'),
               '-I', str(build), '-module-cache-path', str(build / 'ModuleCache')]
    description = json.loads((build / 'description.json').read_text())
    compilation = next(v for v in description['swiftCommands'].values() if v['moduleName'] == 'JarvisTap')
    flags = compilation['otherArguments']
    for index, flag in enumerate(flags[:-1]):
        if flag == '-Xcc': command += [flag, flags[index + 1]]
    command += ['-target', 'arm64-apple-macosx14.0', '-swift-version', '5', '-lc++']
    command += [str(root / 'Tests/Fixtures/AppWiring/main.swift'), str(transformed)]
    command += [str(p) for p in sorted((root / 'Sources/JarvisTap').glob('*.swift')) if p.name != 'main.swift']
    command += ['@' + str(response), '-o', str(temp / 'app-wiring')]
    subprocess.run(command, check=True, cwd=root)
    env = dict(os.environ, PRESSTALK_OPEN_PERMISSION_PANES='0', PRESSTALK_AUTO_SHOW_SETUP_WINDOW='0',
               PRESSTALK_TRACE_LOG=str(temp / 'trace.log'), PRESSTALK_WIRING_STATUS_FILE=str(temp / 'runtime.json'))
    result = subprocess.run([str(temp / 'app-wiring')], env=env, capture_output=True, text=True, cwd=root, timeout=30)
    print(result.stdout, end=''); print(result.stderr, end='')
    assert result.returncode == 0 and 'PASS: actual app settings/menu wiring' in result.stdout, \
        'App wiring fixture did not finish all behavioral assertions'
