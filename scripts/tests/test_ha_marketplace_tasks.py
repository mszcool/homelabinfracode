import json
import os
from pathlib import Path
import subprocess

import pytest


TASK = Path(__file__).resolve().parents[2] / "playbooks/ring1/tasks/ha-install-marketplace.yaml"


@pytest.mark.parametrize("check", [False, True])
def test_marketplace_tasks_in_normal_and_check_mode(tmp_path, check):
    files = tmp_path / "files"
    files.mkdir()
    marker = tmp_path / "client-ran"
    (files / "ha-marketplace.py").write_text(
        "import json\n"
        f"open({str(marker)!r}, 'w').close()\n"
        'print(json.dumps({"changed": False, "repositories": ['
        '{"full_name": "owner/card", "status": "installed"}]}))\n'
    )
    playbook = tmp_path / "test.yml"
    playbook.write_text(f"""\
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ha_marketplace_components: []
    ha_config_path: /config
  tasks:
    - include_tasks: {json.dumps(str(TASK))}
""")
    environment = {**os.environ, "ANSIBLE_LOCAL_TEMP": str(tmp_path / "ansible-tmp")}
    environment.pop("ANSIBLE_CONFIG", None)
    command = ["ansible-playbook", "-i", "localhost,", str(playbook)]
    if check:
        command.append("--check")
    result = subprocess.run(command, capture_output=True, text=True, env=environment, cwd=tmp_path, timeout=120)
    assert result.returncode == 0, result.stdout + result.stderr
    assert marker.exists() is not check


def test_marketplace_script_failure_is_not_masked_by_json_error(tmp_path):
    files = tmp_path / "files"
    files.mkdir()
    (files / "ha-marketplace.py").write_text(
        "import sys\n"
        "print('Marketplace authentication failed', file=sys.stderr)\n"
        "sys.exit(1)\n"
    )
    playbook = tmp_path / "test.yml"
    playbook.write_text(f"""\
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ha_marketplace_components: []
  tasks:
    - include_tasks: {json.dumps(str(TASK))}
""")
    environment = {**os.environ, "ANSIBLE_LOCAL_TEMP": str(tmp_path / "ansible-tmp")}
    environment.pop("ANSIBLE_CONFIG", None)
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", str(playbook)],
        capture_output=True, text=True, env=environment, cwd=tmp_path, timeout=120,
    )
    assert result.returncode != 0
    assert "Marketplace authentication failed" in result.stdout + result.stderr
    assert "A 'changed_when' expression failed" not in result.stdout + result.stderr
