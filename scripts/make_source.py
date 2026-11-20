# Builds source.json so SideStore can install PitaLoc and auto-update it.
# usage: python3 scripts/make_source.py <owner/repo>
import datetime, json, os, plistlib, sys

repo = sys.argv[1]
base = f"https://github.com/{repo}/releases/download/latest"
info = plistlib.load(open("build/Build/Products/Release-iphoneos/PitaLoc.app/Info.plist", "rb"))
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
size = os.path.getsize("PitaLoc.ipa")
desc = "地図で選んだ場所に iPhone の位置を固定するアプリ。自然な揺らぎ・自動解除タイマー・移動シミュレーション付き。"
ver = {
    "version": version,
    "buildVersion": build,
    "date": now,
    "localizedDescription": f"PitaLoc {version} (build {build})",
    "downloadURL": f"{base}/PitaLoc.ipa",
    "size": size,
    "minOSVersion": info.get("MinimumOSVersion", "17.0"),
}
app = {
    "name": "PitaLoc",
    "bundleIdentifier": info["CFBundleIdentifier"],
    "developerName": repo.split("/")[0],
    "subtitle": "iPhone の位置を固定",
    "localizedDescription": desc,
    "iconURL": f"{base}/icon.png",
    "tintColor": "#2866E8",
    "category": "utilities",
    "versions": [ver],
    # 旧形式との互換用
    "version": version,
    "versionDate": now,
    "downloadURL": ver["downloadURL"],
    "size": size,
    "appPermissions": {
        "entitlements": [],
        "privacy": {
            k: info[k] for k in (
                "NSLocationWhenInUseUsageDescription",
                "NSLocationAlwaysAndWhenInUseUsageDescription",
                "NSLocalNetworkUsageDescription",
            ) if k in info
        },
    },
}
source = {
    "name": "PitaLoc",
    "identifier": f"io.github.{repo.split('/')[0].lower()}.pitaloc",
    "subtitle": "PitaLoc の配信元",
    "iconURL": f"{base}/icon.png",
    "website": f"https://github.com/{repo}",
    "apps": [app],
    "news": [],
}
json.dump(source, open("source.json", "w"), ensure_ascii=False, indent=2)
print(json.dumps(ver, ensure_ascii=False))
