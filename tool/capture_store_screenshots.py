"""Capture the real iOS UI on the builder's large iPhone and iPad simulators."""
import json
import re
import subprocess
from contextlib import contextmanager
from pathlib import Path


def run(*args):
    subprocess.run(args, check=True)


@contextmanager
def local_storekit_capture():
    """Use Apple's local StoreKit Test only for this simulator capture job."""
    delegate = Path("ios/Runner/AppDelegate.swift")
    original = delegate.read_text()
    debug_config = Path("ios/Flutter/Debug.xcconfig")
    original_debug = debug_config.read_text()
    # StoreKitTest is a developer framework rather than an app SDK framework.
    platform = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-platform-path"],
        text=True).strip()
    frameworks = Path(platform) / "Developer/Library/Frameworks"
    if not (frameworks / "StoreKitTest.framework").exists():
        raise RuntimeError(f"StoreKit Test framework not installed: {frameworks}")
    config = {
        "identifier": "A11DA500",
        "nonRenewingSubscriptions": [],
        "products": [{
            "displayPrice": "100", "familyShareable": False,
            "internalID": "6820531328",
            "localizations": [{
                "description": "バナー広告と全画面広告を削除します。",
                "displayName": "広告を削除", "locale": "ja_JP"}],
            "productID": "com.example.animalDash.remove_ads",
            "referenceName": "Remove Ads", "type": "NonConsumable",
        }],
        "settings": {"_failTransactionsEnabled": False,
                     "_locale": "ja_JP", "_storefront": "JPN"},
        "subscriptionGroups": [], "version": {"major": 3, "minor": 0},
    }
    source = original.replace(
        "import StoreKit\n",
        "import StoreKit\n#if DEBUG && targetEnvironment(simulator)\n"
        "import StoreKitTest\n#endif\n", 1)
    source = source.replace(
        "  private let channel: FlutterMethodChannel",
        "#if DEBUG && targetEnvironment(simulator)\n"
        "  private var screenshotStore: SKTestSession?\n#endif\n"
        "  private let channel: FlutterMethodChannel", 1)
    setup = r'''
#if DEBUG && targetEnvironment(simulator)
    do {
      let config = #"CONFIG_JSON"#
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("AnimalDash.storekit")
      try Data(config.utf8).write(to: url)
      let session = try SKTestSession(contentsOf: url)
      session.storefront = "JPN"
      session.locale = Locale(identifier: "ja_JP")
      session.disableDialogs = false
      session.clearTransactions()
      screenshotStore = session
    } catch {
      fatalError("StoreKit screenshot session failed: \(error)")
    }
#endif
'''.replace("CONFIG_JSON", json.dumps(config, ensure_ascii=False))
    needle = "    self.channel = channel\n"
    if source.count(needle) != 1:
        raise RuntimeError("Unexpected StoreKit bridge source")
    source = source.replace(needle, needle + setup, 1)
    if source == original or "import StoreKitTest" not in source:
        raise RuntimeError("Screenshot StoreKit setup was not applied")
    delegate.write_text(source)
    debug_config.write_text(original_debug + "\n"
        "FRAMEWORK_SEARCH_PATHS = $(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks\n"
        "LD_RUNPATH_SEARCH_PATHS = $(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks\n")
    try:
        yield
        Path("store-assets/capture-environment.json").write_text(json.dumps({
            "store": "Apple StoreKit Test local configuration",
            "storefront": "JPN", "price": "100 JPY",
            "productID": "com.example.animalDash.remove_ads",
            "purchasePerformed": False,
            "releaseBinaryModified": False,
        }, indent=2))
    finally:
        delegate.write_text(original)
        debug_config.write_text(original_debug)


devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
))["devices"]
candidates = [d for runtime, rows in devices.items() if "iOS" in runtime
              for d in rows if d.get("isAvailable")]
def capture():
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

with local_storekit_capture():
    capture()

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
