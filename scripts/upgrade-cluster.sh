#!/bin/bash

# This is a workaround since Ansible does not support parallel execution of different host groups
# within a single playbook per Chat GPT 4. I did not invest in further research as this is good enough
# for me and all attempts to execute host groups in parallel failed (and the attempts became harder to read).

# Execute this script from the root directory of the project, i.e. ./scripts/upgrade-cluster.sh, instead of switching
# to the scripts folder and executing from there.

ansible-playbook --inventory ./hosts.ini --limit jtwnodes ./playbooks/upgrade-cluster.yaml &
ansible-playbook --inventory ./hosts.ini --limit pfenodes ./playbooks/upgrade-cluster.yaml &

wait