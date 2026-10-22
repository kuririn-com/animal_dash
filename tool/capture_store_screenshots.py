"""Capture the real iOS UI on the builder's large iPhone and iPad simulators."""
import json
import re
import subprocess
from pathlib import Path


def run(*args):
    subprocess.run(args, check=True)


devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
))["devices"]
candidates = [d for runtime, rows in devices.items() if "iOS" in runtime
              for d in rows if d.get("isAvailable")]
for label, pattern in [("iphone", r"iPhone .*Pro Max"),
                       ("ipad", r"iPad Pro 13")]:
    matches = [d for d in candidates if re.search(pattern, d["name"])]
    if not matches:
        raise RuntimeError(f"No supported large {label} simulator: {candidates}")
    device = sorted(matches, key=lambda d: d["name"], reverse=True)[0]
    device_id = device["udid"]
    print(f"Capturing {device['name']} ({device_id})", flush=True)
    if device["state"] != "Booted":
        run("xcrun", "simctl", "boot", device_id)
    run("xcrun", "simctl", "bootstatus", device_id, "-b")
    run("xcrun", "simctl", "status_bar", device_id, "override", "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--batteryState", "charged", "--batteryLevel", "100")
    run("flutter", "drive", "--driver=test_driver/store_screenshots.dart",
        "--target=integration_test/store_screenshots.dart", "-d", device_id,
        "--dart-define=CAPTURE_SCREENSHOTS=true",
        f"--dart-define=SCREENSHOT_DEVICE={label}")
    run("xcrun", "simctl", "shutdown", device_id)

# Retain original screenshots and verify their PNG header dimensions.
dimensions = {}
for path in Path("store-assets").glob("*.png"):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"Invalid screenshot: {path}")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if width <= height:
        raise RuntimeError(f"Expected landscape screenshot: {path} {width}x{height}")
    dimensions[path.name] = [width, height]
Path("store-assets/dimensions.json").write_text(json.dumps(dimensions, indent=2))
print(json.dumps(dimensions, indent=2))
