#!/usr/bin/env python3
"""Write the manifest of the Amazon wake word models the image ships from DAVS.

DAVS hands its models only to a registered Echo, so the build cannot download
them. They live in the private amazon-davs-models repository, checked out next
to this one or wherever DAVS_MODELS points, one folder per set. This records
every file with its SHA-256 and size, and scripts/extract-fireos6-blobs.sh
checks the files against it before it installs them.

  scripts/make-davs-model-manifest.py
"""
import hashlib
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS = pathlib.Path(os.environ.get("DAVS_MODELS", ROOT.parent / "amazon-davs-models"))
LOCALES = ROOT / "device/amazon/biscuit/pryon/locales.txt"
MANIFEST = ROOT / "vendor/amazon/mt8163-common/biscuit-davs-model-files.txt"
FIRMWARE_SET = "alexa-en-US"


def main():
    sets = []
    for line in LOCALES.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            for name in line.split()[1:]:
                if name != FIRMWARE_SET and name not in sets:
                    sets.append(name)
    out = [
        "# set/path:sha256:size, written by scripts/make-davs-model-manifest.py",
        "# Amazon's wake word models from DAVS, installed under /system/etc/pryon.",
    ]
    artifacts = json.loads((MODELS / "artifacts.json").read_text())
    for name in sorted(sets):
        out.append(f"# {name}: DAVS artifact {artifacts[name].get('artifactIdentifier', 'unknown')}")
        base = MODELS / name
        for path in sorted(p for p in base.rglob("*") if p.is_file()):
            data = path.read_bytes()
            out.append(f"{name}/{path.relative_to(base)}:{hashlib.sha256(data).hexdigest()}:{len(data)}")
    MANIFEST.write_text("\n".join(out) + "\n")
    print(f"{len(sets)} sets, {sum(1 for l in out if not l.startswith('#'))} files -> {MANIFEST}")


if __name__ == "__main__":
    main()
