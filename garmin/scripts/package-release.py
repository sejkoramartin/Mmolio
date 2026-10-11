#!/usr/bin/env python3
"""Build local review ZIPs only. Never tags, pushes or publishes a GitHub release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
APPS = ("MmolioBridge", "MmolioWatchFace", "MmolioDataField")
DOCS = ("GARMIN-INSTALL.md", "GARMIN-INSTALL-CS.md", "DISCLAIMER.md", "DISCLAIMER-EN.md", "DISCLAIMER-CS.md", "FENIX.md", "FENIX-CS.md")
REPOSITORY = "https://github.com/sejkoramartin/Mmolio"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if git("status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("Commit the reviewed source first; the release must identify an exact clean revision.")
    revision = git("rev-parse", "HEAD")
    config = json.loads((ROOT / "garmin/release.json").read_text())
    sdk = Path(os.environ["CONNECTIQ_SDK"]).resolve()
    key = Path(os.environ["DEVELOPER_KEY"]).resolve()
    if (sdk / "bin/version.txt").read_text().strip() != config["sdk"]:
        raise SystemExit("Unexpected Connect IQ SDK version")
    # Hash the PUBLIC key only. Never write/copy the private signing key into output.
    public_key = subprocess.check_output([
        "openssl", "pkey", "-inform", "DER", "-in", str(key), "-pubout", "-outform", "DER"
    ], stderr=subprocess.PIPE)
    fingerprint = sha(public_key)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    summaries = {}
    for device, name in config["devices"].items():
        log = output / (device + "-build.log")
        with log.open("w") as stream:
            subprocess.run([str(ROOT / "garmin/scripts/build-device.sh"), device],
                           cwd=ROOT, check=True, stdout=stream, stderr=subprocess.STDOUT)
        contents = {"LICENSE": (ROOT / "LICENSE").read_bytes()}
        for doc in DOCS:
            data = (ROOT / "docs" / doc).read_text()
            # Keep the essential guide offline; supplemental technical material stays online.
            data = data.replace("../garmin/README.md", REPOSITORY + "/blob/" + revision + "/garmin/README.md")
            data = data.replace("../garmin/README-CS.md", REPOSITORY + "/blob/" + revision + "/garmin/README-CS.md")
            contents["docs/" + doc] = data.encode()
        contents["INSTALL-EN.txt"] = contents["docs/GARMIN-INSTALL.md"]
        contents["NAVOD-CS.txt"] = contents["docs/GARMIN-INSTALL-CS.md"]
        hashes = {}
        for app in APPS:
            data = (ROOT / "build" / device / "release" / (app + ".prg")).read_bytes()
            if not data:
                raise SystemExit("Empty program: " + app)
            contents["apps/" + app + ".prg"] = data
            hashes[app + ".prg"] = sha(data)
        manifest = {
            "version": config["version"], "tag": config["tag"], "status": config["status"],
            "device": device, "deviceName": name, "sdk": config["sdk"],
            "sourceCommit": revision, "sourceURL": REPOSITORY + "/tree/" + revision,
            "sourceArchiveURL": REPOSITORY + "/archive/" + revision + ".tar.gz",
            "signingPublicKeySHA256": fingerprint, "programSHA256": hashes,
            "buildValidation": "passed", "physicalValidation": config["physicalValidation"],
            "phoneIntegrationValidation": config["phoneIntegrationValidation"],
            "publishedByThisScript": False
        }
        contents["RELEASE.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
        contents["START-HERE.txt"] = (
            f"Mmolio {config['version']} — {name} ({device})\n\n"
            "LOCAL RELEASE CANDIDATE / TESTOVACÍ KANDIDÁT\n"
            "Physical validation is pending. / Fyzické ověření tohoto kandidáta čeká.\n\n"
            "English: open INSTALL-EN.txt. Čeština: otevřete NAVOD-CS.txt.\n"
            "Only for the exact model above. / Pouze pro model uvedený výše.\n"
            "Installation files are in apps/. / Instalační soubory jsou v apps/.\n"
            "Read the disclaimer in docs/ first. / Nejdřív přečtěte upozornění v docs/.\n"
            "License: LICENSE. Version and corresponding source: RELEASE.json.\n"
            "Licence: LICENSE. Verze a přesný zdroj: RELEASE.json.\n"
        ).encode()
        contents["SHA256SUMS"] = "".join(f"{sha(data)}  {path}\n" for path, data in sorted(contents.items())).encode()
        filename = f"Mmolio-{config['version']}-{device}.zip"
        archive = output / filename
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for path, data in sorted(contents.items()):
                info = zipfile.ZipInfo(path, date_time=(2026, 10, 11, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                package.writestr(info, data)
        # Verify actual ZIP content and checksums, including exact allow-listed membership.
        with zipfile.ZipFile(archive) as package:
            assert package.testzip() is None
            assert set(package.namelist()) == set(contents)
            for path, data in contents.items():
                assert package.read(path) == data, path
        summaries[filename] = sha(archive.read_bytes())
        print(f"Built and verified {filename}", flush=True)
    if git("rev-parse", "HEAD") != revision or git("status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("Source changed during packaging; do not distribute output.")
    (output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in summaries.items()))
    (output / "release-manifest.json").write_text(json.dumps({
        "sourceCommit": revision, "version": config["version"],
        "archives": summaries, "physicalValidation": config["physicalValidation"],
        "signingPublicKeySHA256": fingerprint
    }, indent=2) + "\n")
    print("Local preparation complete. Nothing published; physical and iOS validation remain pending.")


if __name__ == "__main__":
    main()
