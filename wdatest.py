#!/usr/bin/env python3
"""
grab_wda_screenshot.py
—————————
Fetch a single screenshot from WebDriverAgent and save it locally.

Prerequisites:
  • WDA running on the iPhone (blue “Running Tests” pill is visible).
  • Port 8100 on the Mac forwarded to the phone, e.g.
        iproxy 8100 8100 &
  • Python 3 with 'requests' installed   →  pip install requests
"""

import requests, base64, datetime, pathlib, sys

WDA_URL = "http://127.0.0.1:8100/screenshot"   # change if you forwarded to a different host port

def main() -> None:
    try:
        print(f"📡  Requesting {WDA_URL} …")
        r = requests.get(WDA_URL, timeout=5)
        r.raise_for_status()

        payload = r.json()
        if payload.get("status") not in (0, "0"):
            raise RuntimeError(f"WDA returned non-zero status: {payload}")

        b64 = payload["value"]          # raw base-64 PNG
        png = base64.b64decode(b64)

        ts  = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        fname = pathlib.Path(f"screenshot_{ts}.png")
        fname.write_bytes(png)

        kb = len(png) / 1024
        print(f"✅  Saved {fname}  ({kb:.1f} kB)")

    except (requests.exceptions.RequestException, ValueError) as e:
        sys.exit(f"❌  HTTP/JSON error: {e}")
    except Exception as e:
        sys.exit(f"❌  Unexpected error: {e}")

if __name__ == "__main__":
    main()