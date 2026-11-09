"""Build the standalone release from vendored sources; no downloads required."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parent


def build():
    controller = (ROOT / "src/controller.luau").read_text(encoding="utf-8")
    vendor = (ROOT / "vendor/SlimeUI.lua").read_text(encoding="utf-8")
    version = re.search(r'local VERSION = "([^"]+)"', controller).group(1)
    license_text = (ROOT / "licenses/SlimeUI-MIT.txt").read_text(encoding="utf-8")
    controller_license = (ROOT / "LICENSE").read_text(encoding="utf-8")
    banner = (
        f"-- Arsenal Controls {version} | public beta\n"
        "-- Source and instructions are included in the release archive.\n"
        "-- Controller and bundled SlimeUI licenses follow.\n--[====[\n"
        + controller_license.rstrip() + "\n\nSlimeUI:\n" + license_text.rstrip() + "\n]====]\n"
    )
    result = banner + "local SlimeUI = (function()\n" + vendor.rstrip() + "\nend)()\n\n" + controller
    destination = ROOT / "dist/ArsenalControls.lua"
    destination.parent.mkdir(exist_ok=True)
    destination.write_bytes(result.encode("utf-8"))
    print(f"Built {destination.name}: {hashlib.sha256(destination.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    build()
