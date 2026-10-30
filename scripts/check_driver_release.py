"""Check the mobile release identity without calling any hosted service.

pubspec.yaml owns the version; Android/iOS and CI must consume that value.
Only public client configuration is inspected. Never print credential values.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
from urllib.parse import urlparse


def check(root):
    versions = re.findall(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$",
                          (root / "pubspec.yaml").read_text(), re.MULTILINE)
    assert len(versions) == 1, "Declare one app version and positive build number in pubspec.yaml"
    name, build = versions[0]
    gradle = (root / "android/app/build.gradle.kts").read_text()
    assert "versionCode = flutter.versionCode" in gradle
    assert "versionName = flutter.versionName" in gradle
    assert 'gradleProperty("hiredApplicationId")' in gradle, "Preserve the isolated Android test package option"
    assert 'gradleProperty("hiredAppName")' in gradle, "Preserve the visible test app label"
    info = plistlib.loads((root / "ios/Runner/Info.plist").read_bytes())
    assert info["CFBundleShortVersionString"] == "$(FLUTTER_BUILD_NAME)"
    assert info["CFBundleVersion"] == "$(FLUTTER_BUILD_NUMBER)"

    required = {"API_URL", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY",
                "GOOGLE_WEB_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID"}
    configs = {}
    for filename in ("auth.json", "staging.json"):
        value = json.loads((root / "config" / filename).read_text())
        assert set(value) == required, "Client configuration must contain only the approved public fields"
        assert all(isinstance(v, str) for v in value.values())
        assert value["SUPABASE_PUBLISHABLE_KEY"].startswith("sb_publishable_"), "Use a publishable client key"
        urls = {}
        for key in ("API_URL", "SUPABASE_URL"):
            url = urlparse(value[key])
            assert url.scheme == "https" and url.hostname and not url.username and not url.password
            assert not url.query and not url.fragment, "Configuration URLs must not embed tokens"
            urls[key] = url
        assert urls["API_URL"].path.rstrip("/") == "/admin/api/v1"
        assert urls["SUPABASE_URL"].hostname.endswith(".supabase.co")
        assert not urls["SUPABASE_URL"].path.strip("/")
        configs[filename] = urls
    for key in ("API_URL", "SUPABASE_URL"):
        assert configs["auth.json"][key].hostname != configs["staging.json"][key].hostname, \
            "Staging and production must not use the same service"
    return {"version": name + "+" + build, "name": name, "build": build}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--field", choices=("version", "name", "build"))
    args = parser.parse_args()
    release = check(Path(__file__).resolve().parents[1])
    if args.field:
        print(release[args.field])
    else:
        print("Driver release " + release["version"] + ": native version mapping and isolated public configuration PASS")
