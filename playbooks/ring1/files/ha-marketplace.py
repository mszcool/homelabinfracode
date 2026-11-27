#!/usr/bin/env python3
"""Reconcile Marketplace repositories through the Supervisor Core proxy."""

import json
import os
import sys
import time

from websockets.sync.client import connect


class APIError(RuntimeError):
    def __init__(self, command, error):
        self.code = error.get("code", "unknown")
        super().__init__(f"{command}: {self.code}: {error.get('message', '')}")


class Marketplace:
    def __init__(self, socket):
        self.socket = socket
        self.next_id = 0

    def request(self, command, **arguments):
        self.next_id += 1
        request_id = self.next_id
        self.socket.send(json.dumps({"id": request_id, "type": command, **arguments}))
        while True:
            response = json.loads(self.socket.recv(timeout=180))
            if response.get("id") != request_id:
                continue
            if not response.get("success"):
                raise APIError(command, response.get("error", {}))
            return response.get("result")


def reconcile(api, components):
    deadline = time.monotonic() + 180
    while True:
        try:
            info = api.request("marketplace/info")
        except APIError as error:
            if error.code not in ("not_loaded", "unknown_command") or time.monotonic() >= deadline:
                raise
        else:
            if info["disabled_reason"]:
                raise RuntimeError(f"Marketplace disabled: {info['disabled_reason']}")
            if info["stage"] == "running" and not info["startup"]:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Marketplace did not become ready: {info['stage']}")
        time.sleep(3)

    changed = False
    if not info["warning_accepted"]:
        api.request("marketplace/warning/accept")
        changed = True

    results = []
    for component in components:
        repository_id = component["repo_id"]
        try:
            repository = api.request("marketplace/repository/info", repository_id=repository_id)
        except APIError as error:
            if error.code != "repository_not_found":
                raise
            if not info["github_connected"]:
                raise RuntimeError(
                    f"{component['full_name']} is not in the Marketplace catalog; "
                    "connect a GitHub account to add custom repositories"
                ) from error
            api.request(
                "marketplace/repositories/add",
                repository=component["full_name"],
                category=component["category"],
            )
            changed = True
            repository = api.request("marketplace/repository/info", repository_id=repository_id)

        if (
            str(repository["id"]) != repository_id
            or repository["full_name"].lower() != component["full_name"].lower()
            or repository["category"] != component["category"]
        ):
            raise RuntimeError(f"Marketplace repository identity mismatch: {component['full_name']}")

        if not repository["installed"]:
            api.request(
                "marketplace/repository/install",
                repository=repository_id,
                version=component["tag"],
            )
            changed = True
            repository = api.request("marketplace/repository/info", repository_id=repository_id)
            if not repository["installed"]:
                raise RuntimeError(f"Marketplace did not install {component['full_name']}")
            if repository["installed_version"] != component["tag"]:
                raise RuntimeError(
                    f"Marketplace installed {component['full_name']} at "
                    f"{repository['installed_version']!r}, not {component['tag']!r}"
                )
        results.append(
            {
                "full_name": component["full_name"],
                "installed_version": repository["installed_version"],
                "local_path": repository["local_path"],
                "status": repository["status"],
            }
        )
    return {"changed": changed, "repositories": results}


def main():
    token = os.environ.get("SUPERVISOR_TOKEN")
    if not token:
        raise RuntimeError("SUPERVISOR_TOKEN is missing")
    components = json.loads(sys.argv[1])
    with connect("ws://supervisor/core/websocket", open_timeout=30) as socket:
        greeting = json.loads(socket.recv(timeout=30))
        if greeting.get("type") != "auth_required":
            raise RuntimeError(f"Unexpected WebSocket greeting: {greeting.get('type')}")
        socket.send(json.dumps({"type": "auth", "access_token": token}))
        auth = json.loads(socket.recv(timeout=30))
        if auth.get("type") == "auth_invalid":
            raise RuntimeError(
                "Supervisor rejected the WebSocket token. Check that the SSH app has "
                "homeassistant_api permission and that its token is valid; the official "
                "Terminal & SSH app does not grant this permission."
            )
        if auth.get("type") != "auth_ok":
            raise RuntimeError(f"Home Assistant WebSocket authentication failed: {auth.get('type')}")
        print(json.dumps(reconcile(Marketplace(socket), components)))


if __name__ == "__main__":
    try:
        main()
    except (APIError, KeyError, ValueError, OSError, TimeoutError, RuntimeError) as error:
        print(f"Marketplace reconciliation failed: {error}", file=sys.stderr)
        sys.exit(1)
