#!/bin/bash
set -euo pipefail
distribution=false
if [[ ${1:-} == --distribution ]]; then
    distribution=true
    shift
fi
if [[ $# -ne 1 ]]; then
    echo 'Usage: Scripts/verify-bundle.sh [--distribution] <Buckle.app>' >&2
    exit 64
fi
app_path="$1"
extension_path="$app_path/Contents/PlugIns/BuckleFinder.appex"
test -x "$app_path/Contents/MacOS/Buckle"
test -x "$extension_path/Contents/MacOS/BuckleFinder"
codesign --verify --deep --strict "$app_path"
codesign --verify --strict "$extension_path"
python3 - "$app_path" "$distribution" <<'PY'
import plistlib
import re
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1])
extension = app / 'Contents/PlugIns/BuckleFinder.appex'
with (app / 'Contents/Info.plist').open('rb') as source:
    host_info = plistlib.load(source)
with (extension / 'Contents/Info.plist').open('rb') as source:
    extension_info = plistlib.load(source)
assert host_info['CFBundleIconName'] == 'Buckle', 'The app must use the Buckle Icon Composer document'
assert host_info['CFBundleIconFile'] == 'Buckle', 'The compatibility icon must match the main icon'
for resource in ('Buckle.icns', 'Assets.car', 'MenuBarIconTemplate.tiff'):
    assert (app / 'Contents/Resources' / resource).is_file(), f'Missing branding resource: {resource}'
# COMBINE_HIDPI_IMAGES preserves both PNG scales in one named TIFF resource.
template = subprocess.run(
    ['tiffutil', '-info', str(app / 'Contents/Resources/MenuBarIconTemplate.tiff')],
    check=True, capture_output=True, text=True)
assert re.findall(r'Image Width: (\d+) Image Length: (\d+)', template.stdout + template.stderr) == [
    ('20', '20'), ('40', '40')], 'The menu-bar template must contain both 1x and 2x images'
assert not (app / 'Contents/Resources/AppIcon.icns').exists(), 'The previous app icon must not be bundled'
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    assert host_info[key] == extension_info[key], f'Mismatched {key}'
assert host_info['CFBundleIdentifier'] == 'studio.slippindylan.Buckle', 'Unexpected application bundle identifier'
assert extension_info['CFBundleIdentifier'] == 'studio.slippindylan.Buckle.Finder', 'Unexpected Finder bundle identifier'
assert extension_info['NSExtension']['NSExtensionPrincipalClass'] == 'BuckleFinder.BuckleFinderSync'
assert extension_info['CFBundlePackageType'] == 'XPC!'
architectures = []
for bundle, executable in ((app, 'Buckle'), (extension, 'BuckleFinder')):
    binary = bundle / 'Contents/MacOS' / executable
    architectures.append(set(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()))
    signature = subprocess.run(['codesign', '-d', '--verbose=4', str(bundle)], check=True, capture_output=True, text=True)
    assert 'Signature=adhoc' in signature.stderr, f'Expected account-free ad-hoc signature: {bundle}'
    if bundle == app and 'runtime' in signature.stderr:
        signed_entitlements = subprocess.run(
            ['codesign', '-d', '--entitlements', ':-', str(bundle)], check=True, capture_output=True)
        assert plistlib.loads(signed_entitlements.stdout).get('com.apple.security.cs.disable-library-validation') is True, (
            'Ad-hoc hardened application cannot load Sparkle without a library-validation exception')
assert architectures[0] == architectures[1], 'App and extension architectures differ'
if sys.argv[2] == 'true':
    assert {'arm64', 'x86_64'} <= architectures[0], 'Distribution requires a Universal 2 app and Finder extension'
framework = app / 'Contents/Frameworks/Sparkle.framework'
permission_resources = app / 'Contents/Resources/PermissionFlow_PermissionFlow.bundle'
assert permission_resources.is_dir(), 'PermissionFlow resources are missing'
for language in ('en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'de', 'fr', 'es'):
    assert (permission_resources / 'Contents/Resources' / (language + '.lproj') / 'Localizable.strings').is_file(), (
        f'Missing PermissionFlow localization: {language}')
assert (app / 'Contents/Resources/ThirdPartyNotices.txt').is_file(), 'Third-party license notice is missing'
assert framework.is_dir(), 'Sparkle framework is missing'
sparkle_binary = framework / 'Versions/B/Sparkle'
assert architectures[0] <= set(subprocess.check_output(['lipo', '-archs', str(sparkle_binary)], text=True).split())
with (framework / 'Versions/B/Resources/Info.plist').open('rb') as source:
    assert plistlib.load(source)['CFBundleShortVersionString'] == '2.10.0'
for component in ('Autoupdate', 'Updater.app', 'XPCServices/Installer.xpc', 'XPCServices/Downloader.xpc'):
    assert (framework / 'Versions/B' / component).exists(), f'Missing Sparkle component: {component}'
assert host_info['SURequireSignedFeed'] is True
assert host_info['SUVerifyUpdateBeforeExtraction'] is True
assert host_info['BuckleUpdaterEnabled'] in ('YES', 'NO')
if host_info['BuckleUpdaterEnabled'] == 'YES':
    assert host_info['SUFeedURL'] == 'https://slippindylan.github.io/homebrew-tap/buckle/appcast.xml'
result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(extension)], check=True, capture_output=True)
entitlements = plistlib.loads(result.stdout)
assert entitlements['com.apple.security.app-sandbox'] is True
assert 'com.apple.security.application-groups' not in entitlements
assert entitlements['com.apple.security.temporary-exception.files.home-relative-path.read-only'] == [
    '/Library/Application Support/Buckle/Finder/'
]
print('App, Finder extension and Sparkle: signatures, versions, architectures and update configuration verified.')
PY
