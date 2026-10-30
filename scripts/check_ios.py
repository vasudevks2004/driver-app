"""Fail early when native iOS permissions or Keychain signing drift."""
from pathlib import Path
import json
import plistlib

root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
entitlements = plistlib.loads((root / 'ios/Runner/Runner.entitlements').read_bytes())
project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
assert entitlements['keychain-access-groups'] == [
    '$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'
], 'Keep driver credentials in the app Keychain group'
assert project.count('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;') == 3, \
    'Debug, Profile and Release must all enable Keychain access'
for permission in ('NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription'):
    assert info.get(permission, '').strip(), f'Missing {permission}'
assert not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads', False), \
    'Do not disable HTTPS enforcement'
icons = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for icon in json.loads((icons / 'Contents.json').read_text())['images']:
    assert (icons / icon['filename']).is_file(), 'Missing iOS app icon'
print('iOS permissions, Keychain build settings, HTTPS policy and icons: PASS')
