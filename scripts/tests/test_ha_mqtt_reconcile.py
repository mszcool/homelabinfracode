import json
import os
from pathlib import Path
import subprocess


TASK = Path(__file__).resolve().parents[2] / "playbooks/ring1/tasks/ha-configure-mqtt-integration.yaml"


def test_mqtt_reconciliation_preserves_unmanaged_fields(tmp_path):
    entries = [
        {"domain": "other", "entry_id": "before"},
        {
            "domain": "mqtt",
            "entry_id": "mqtt-id",
            "created_at": "old",
            "modified_at": "old",
            "data": {"broker": "broker", "port": 1883, "username": "user", "password": "old", "protocol": "5"},
            "options": {"discovery": False},
            "subentries": [{"entry_id": "subentry"}],
            "other_metadata": {"keep": True},
        },
        {"domain": "other", "entry_id": "after"},
    ]
    storage = tmp_path / ".storage"
    storage.mkdir()
    (storage / "core.config_entries").write_text(json.dumps({
        "version": 1, "key": "core.config_entries", "data": {"entries": entries, "other": "keep"},
    }))
    expected = json.loads(json.dumps(entries))
    expected[1]["data"]["password"] = "new"
    playbook = tmp_path / "test.yml"
    playbook.write_text(f"""\
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ha_config_path: {json.dumps(str(tmp_path))}
    ha_mqtt_broker: broker
    ha_mqtt_port: 1883
    ha_mqtt_username: user
    ha_mqtt_password: new
  tasks:
    - include_tasks: {json.dumps(str(TASK))}
    - assert:
        that:
          - _mqtt_entry_write_needed | bool
          - _mqtt_config_entries_proposed.data.entries == expected
          - _mqtt_config_entries_proposed.data.other == 'keep'
      vars:
        expected: {json.dumps(expected)}
    - copy:
        content: "{{{{ _mqtt_config_entries_proposed | to_json }}}}"
        dest: "{{{{ ha_config_path }}}}/.storage/core.config_entries"
    - include_tasks: {json.dumps(str(TASK))}
    - assert:
        that:
          - not (_mqtt_entry_write_needed | bool)
""")
    environment = {**os.environ, "ANSIBLE_LOCAL_TEMP": str(tmp_path / "ansible-tmp")}
    environment.pop("ANSIBLE_CONFIG", None)
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", str(playbook)],
        capture_output=True, text=True, env=environment, cwd=tmp_path, timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_missing_mqtt_entry_is_created_without_touching_other_entries(tmp_path):
    storage = tmp_path / ".storage"
    storage.mkdir()
    (storage / "core.config_entries").write_text(json.dumps({
        "version": 1, "key": "core.config_entries",
        "data": {"entries": [{"domain": "other", "entry_id": "keep"}]},
    }))
    playbook = tmp_path / "test.yml"
    playbook.write_text(f"""\
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ha_config_path: {json.dumps(str(tmp_path))}
    ha_mqtt_broker: broker
    ha_mqtt_port: 1883
    ha_mqtt_username: user
    ha_mqtt_password: secret
  tasks:
    - include_tasks: {json.dumps(str(TASK))}
    - assert:
        that:
          - _mqtt_entry_write_needed | bool
          - _mqtt_config_entries_proposed.data.entries | length == 2
          - _mqtt_config_entries_proposed.data.entries[0].entry_id == 'keep'
          - _mqtt_config_entries_proposed.data.entries[1].data.password == 'secret'
          - _mqtt_config_entries_proposed.data.entries[1].entry_id | length == 32
          - _mqtt_config_entries_proposed.data.entries[1].subentries == []
""")
    environment = {**os.environ, "ANSIBLE_LOCAL_TEMP": str(tmp_path / "ansible-tmp")}
    environment.pop("ANSIBLE_CONFIG", None)
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", str(playbook)],
        capture_output=True, text=True, env=environment, cwd=tmp_path, timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr
