#!/bin/bash
set -euo pipefail
APP=${1:?Usage: verify-dev.sh APP}
codesign --verify --deep --strict "$APP"
python3 - "$APP" <<'PY'
import plistlib
import os
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1])
def require(value, message):
    if not value:
        raise SystemExit('Invalid development bundle: ' + message)

for bundle, identifier in [(app, 'solimanali.openlist.dev'),
                           (app / 'Contents/PlugIns/OpenlistWidget.appex', 'solimanali.openlist.dev.OpenlistWidget')]:
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == identifier, f'{bundle.name} identifier')
    require(info.get('CFBundleDisplayName') == 'Openlist Dev', f'{bundle.name} display name')
    entitlements = plistlib.loads(subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(bundle)], check=True, capture_output=True).stdout)
    require(not any('icloud' in key or 'aps-environment' in key for key in entitlements), 'Dev must not request iCloud or push access')
    groups = entitlements.get('com.apple.security.application-groups', [])
    require(not groups or groups == ['Y5UE64R7TQ.solimanali.openlist.dev'], 'Dev must never request the production App Group')
    require(entitlements.get('com.apple.security.app-sandbox') is True, 'Dev remains sandboxed')
    if bundle == app:
        require(info.get('CFBundleExecutable') == 'openlist-dev', 'distinct development executable')
        require(info.get('CFBundleIconName') == 'OpenlistDev' or info.get('CFBundleIconFile') == 'OpenlistDev', 'DEV-badged app icon')
        require(info.get('OpenlistDevelopment') in (True, 'YES'), 'development Info.plist marker')
        require('OpenlistReviewSession' not in info, 'normal Dev must not use a disposable review fixture')
helper = app / 'Contents/MacOS/openlist-mcp'
signature = subprocess.run(['codesign', '-d', '--verbose=2', str(helper)], check=True, capture_output=True).stderr.decode()
require('Identifier=solimanali.openlist.dev.mcp' in signature, 'distinct MCP helper signing identity')
environment = {key: value for key, value in os.environ.items() if key not in ('OPENLIST_MCP_TOKEN', 'OPENLIST_MCP_URL')}
help_text = subprocess.run([str(helper), '--help'], check=True, capture_output=True, env=environment).stdout.decode()
require('default http://127.0.0.1:45874/mcp.' in help_text, 'compiled Dev helper must default to the distinct Dev port')
print('Verified development app, widget, helper, DEV icon and isolated entitlements')
PY
