import importlib.util
import json
from pathlib import Path
import sys
import threading

import pytest
from websockets.sync.client import connect
from websockets.sync.server import serve


SCRIPT = Path(__file__).resolve().parents[2] / "playbooks/ring1/files/ha-marketplace.py"
spec = importlib.util.spec_from_file_location("ha_marketplace", SCRIPT)
marketplace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(marketplace)


class FakeAPI:
    def __init__(self, *, installed=True, known=True, github=True):
        self.installed = installed
        self.known = known
        self.github = github
        self.accepted = False
        self.version = "v2" if installed else ""
        self.calls = []

    def request(self, command, **arguments):
        self.calls.append((command, arguments))
        if command == "marketplace/info":
            return {
                "disabled_reason": None,
                "stage": "running",
                "startup": False,
                "github_connected": self.github,
                "warning_accepted": self.accepted,
            }
        if command == "marketplace/warning/accept":
            self.accepted = True
        elif command == "marketplace/repositories/add":
            self.known = True
        elif command == "marketplace/repository/install":
            self.installed = True
            self.version = arguments["version"]
        elif command == "marketplace/repository/info":
            if not self.known:
                raise marketplace.APIError(command, {"code": "repository_not_found"})
            return {
                "id": "123",
                "full_name": "owner/card",
                "category": "plugin",
                "installed": self.installed,
                "installed_version": self.version,
                "local_path": "/config/www/community/card",
                "status": "installed" if self.installed else "default",
            }


COMPONENTS = [{"repo_id": "123", "full_name": "owner/card", "category": "plugin", "tag": "v1"}]


def test_existing_install_is_not_downgraded_and_second_run_is_unchanged():
    api = FakeAPI()
    first = marketplace.reconcile(api, COMPONENTS)
    second = marketplace.reconcile(api, COMPONENTS)
    assert first["changed"] is True
    assert second["changed"] is False
    assert second["repositories"][0]["installed_version"] == "v2"
    assert not any(command == "marketplace/repository/install" for command, _ in api.calls)


def test_adds_custom_repository_and_installs_pinned_version():
    api = FakeAPI(installed=False, known=False)
    result = marketplace.reconcile(api, COMPONENTS)
    assert result["changed"] is True
    assert ("marketplace/repositories/add", {"repository": "owner/card", "category": "plugin"}) in api.calls
    assert ("marketplace/repository/install", {"repository": "123", "version": "v1"}) in api.calls


def test_unknown_repository_requires_github():
    api = FakeAPI(known=False, github=False)
    with pytest.raises(RuntimeError, match="connect a GitHub account"):
        marketplace.reconcile(api, COMPONENTS)
    assert not any(command == "marketplace/repositories/add" for command, _ in api.calls)


def test_install_rejects_an_unexpected_version():
    api = FakeAPI(installed=False)
    original = api.request

    def request(command, **arguments):
        result = original(command, **arguments)
        if command == "marketplace/repository/install":
            api.version = "v2"
        return result

    api.request = request
    with pytest.raises(RuntimeError, match="not 'v1'"):
        marketplace.reconcile(api, COMPONENTS)


def test_other_api_errors_are_not_treated_as_missing_repositories():
    api = FakeAPI()
    original = api.request

    def request(command, **arguments):
        if command == "marketplace/repository/info":
            raise marketplace.APIError(command, {"code": "github_rate_limited"})
        return original(command, **arguments)

    api.request = request
    with pytest.raises(marketplace.APIError, match="github_rate_limited"):
        marketplace.reconcile(api, COMPONENTS)


@pytest.mark.parametrize("auth_ok", [True, False])
def test_websocket_authentication_and_request_protocol(monkeypatch, capsys, auth_ok):
    observed = []

    def handle(socket):
        socket.send(json.dumps({"type": "auth_required"}))
        observed.append(json.loads(socket.recv()))
        socket.send(json.dumps({"type": "auth_ok" if auth_ok else "auth_invalid"}))
        if not auth_ok:
            return
        request = json.loads(socket.recv())
        observed.append(request)
        socket.send(json.dumps({
            "id": request["id"], "type": "result", "success": True,
            "result": {
                "disabled_reason": None, "stage": "running", "startup": False,
                "github_connected": False, "warning_accepted": True,
            },
        }))

    server = serve(handle, "127.0.0.1", 0)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        port = server.socket.getsockname()[1]
        monkeypatch.setattr(marketplace, "connect", lambda *args, **kwargs: connect(f"ws://127.0.0.1:{port}"))
        monkeypatch.setenv("SUPERVISOR_TOKEN", "test-token")
        monkeypatch.setattr(sys, "argv", ["ha-marketplace.py", "[]"])
        if auth_ok:
            marketplace.main()
        else:
            with pytest.raises(RuntimeError, match="homeassistant_api permission"):
                marketplace.main()
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert observed[0] == {"type": "auth", "access_token": "test-token"}
    if auth_ok:
        assert observed[1:] == [{"id": 1, "type": "marketplace/info"}]
        assert json.loads(capsys.readouterr().out) == {"changed": False, "repositories": []}
    else:
        assert len(observed) == 1
