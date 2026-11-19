"""xcresult attachments are authoritative; simulator test runner cannot always write host SHOTS_DIR."""
import json
import pathlib
import re
import shutil
import subprocess
import sys

result, output = sys.argv[1:3]
folder = pathlib.Path(output)
folder.mkdir(parents=True, exist_ok=True)
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result,
                "--output-path", str(folder)], check=True)

# Retain the XCTest names used by the store screenshot configuration even
# when xcresulttool exports the PNG itself under an opaque filename.
manifest_path = folder / "manifest.json"
if manifest_path.is_file():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    named_shot = re.compile(r"^((?:en|zh-Hans|zh-Hant)-\d{2}-store-[a-z-]+|11-paywall)(?=[_.]|$)")
    for test in manifest:
        for attachment in test["attachments"]:
            match = named_shot.match(attachment.get("suggestedHumanReadableName", ""))
            source = folder / attachment["exportedFileName"]
            if match and source.suffix.lower() == ".png":
                target = folder / (match[1] + ".png")
                if source != target:
                    shutil.copy2(source, target)

pngs = list(folder.glob("**/*.png"))
if not pngs:
    sys.exit("界面测试没有导出 PNG 截图")
for index, path in enumerate(sorted(pngs), 1):
    if path.parent != folder:
        shutil.copy2(path, folder / f"{index:03d}-{path.name}")
print(f"已导出 {len(pngs)} 张界面测试截图到 {folder}")
