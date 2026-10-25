"""Configure Flutter-generated native shells without replacing Dart source or tests.
Run flutter create into a separate directory, then pass that directory here.
"""
import pathlib,shutil,sys,plistlib,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1]
shell=pathlib.Path(sys.argv[1]).resolve()
for platform in ('android','ios'):
    target=root/platform
    if not target.exists(): shutil.copytree(shell/platform,target)
manifest=root/'android/app/src/main/AndroidManifest.xml'
ET.register_namespace('android','http://schemas.android.com/apk/res/android')
tree=ET.parse(manifest);a='{http://schemas.android.com/apk/res/android}'
for permission in ('android.permission.INTERNET','android.permission.CAMERA'):
    if not any(x.get(a+'name')==permission for x in tree.getroot().findall('uses-permission')):
        tree.getroot().insert(0,ET.Element('uses-permission',{a+'name':permission}))
# ImagePicker launches system camera/gallery; do not request broad storage access.
tree.getroot().find('application').set(a+'label','HireD')
tree.write(manifest,encoding='utf-8',xml_declaration=True)
info=root/'ios/Runner/Info.plist'
with info.open('rb') as f: data=plistlib.load(f)
data.update({'CFBundleDisplayName':'HireD','NSCameraUsageDescription':'Take your driver photo and duty selfie for HireD review.','NSPhotoLibraryUsageDescription':'Choose your driver onboarding documents for private HireD review.'})
with info.open('wb') as f: plistlib.dump(data,f,sort_keys=False)
