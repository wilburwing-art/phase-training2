# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]>=2.8", "requests>=2.31"]
# ///
"""Control whether TestFlight testers get a notification for a build.

    uv run scripts/asc/testflight_notify.py quiet  --build 171
    uv run scripts/asc/testflight_notify.py notify --build 171

`quiet` turns off the build's "automatically notify testers" flag
(buildBetaDetails.autoNotifyEnabled). It has to land while the build is still
processing, before TestFlight makes it available, so it polls for the build to
appear after the upload and patches it straight away.

`notify` sends the notification for an already-processed build
(POST buildBetaNotifications). Testers who already installed the build are not
notified again by TestFlight.

Reads ASC_API_KEY_ID, ASC_API_KEY_ISSUER_ID and the .p8 at
~/.appstoreconnect/private_keys/AuthKey_<id>.p8 (where the release workflow
writes it).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.phasetraining.app"


def token() -> str:
    key_id = os.environ["ASC_API_KEY_ID"]
    issuer = os.environ["ASC_API_KEY_ISSUER_ID"]
    key = (Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8").read_text()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def call(method: str, path: str, **kw) -> dict:
    r = requests.request(method, f"{API}{path}", headers={"Authorization": f"Bearer {token()}"}, timeout=30, **kw)
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:500]}")
    return r.json() if r.content else {}


def app_id() -> str:
    data = call("GET", "/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not data:
        sys.exit(f"no app with bundle id {BUNDLE_ID}")
    return data[0]["id"]


def find_build(build: str, wait_s: int) -> dict:
    """The build appears in the API a few minutes after upload; poll for it."""
    aid = app_id()
    deadline = time.time() + wait_s
    while True:
        data = call("GET", "/builds", params={"filter[app]": aid, "filter[version]": build,
                                               "include": "buildBetaDetail"})
        if data["data"]:
            return data
        if time.time() > deadline:
            sys.exit(f"build {build} did not appear within {wait_s}s")
        print(f"build {build} not visible yet; retrying in 20s", flush=True)
        time.sleep(20)


def quiet(build: str, wait_s: int) -> None:
    data = find_build(build, wait_s)
    b = data["data"][0]
    detail_id = b["relationships"]["buildBetaDetail"]["data"]["id"]
    call("PATCH", f"/buildBetaDetails/{detail_id}", json={"data": {
        "type": "buildBetaDetails", "id": detail_id, "attributes": {"autoNotifyEnabled": False}}})
    state = b["attributes"].get("processingState")
    print(f"build {build}: auto-notify off (processing state {state})")
    if state == "VALID":
        print("::warning::the build had already finished processing, so testers may have been notified")


def notify(build: str) -> None:
    b = find_build(build, 0)["data"][0]
    if b["attributes"].get("processingState") != "VALID":
        sys.exit(f"build {build} is {b['attributes'].get('processingState')}; wait for processing to finish")
    call("POST", "/buildBetaNotifications", json={"data": {
        "type": "buildBetaNotifications",
        "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
    print(f"build {build}: testers notified")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["quiet", "notify"])
    p.add_argument("--build", required=True, help="CFBundleVersion, e.g. 171")
    p.add_argument("--wait", type=int, default=900, help="seconds to wait for the build to appear (quiet)")
    a = p.parse_args()
    quiet(a.build, a.wait) if a.command == "quiet" else notify(a.build)


if __name__ == "__main__":
    main()
