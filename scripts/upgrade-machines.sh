#!/bin/bash

# This is a workaround since Ansible does not support parallel execution of different host groups
# within a single playbook per Chat GPT 4. I did not invest in further research as this is good enough
# for me and all attempts to execute host groups in parallel failed (and the attempts became harder to read).

# Execute this script from the root directory of the project, i.e. ./scripts/upgrade-cluster.sh, instead of switching
# to the scripts folder and executing from there.

# Note about "hosts.ini": this script uses a hosts.ini which is NOT checked into source code, hence 
# the reference hosts.nopush.ini which I take from a private repository.

if [ "$ISPRIVATE" = "true" ]; then
    hostsIni="./configs.private/infra-bootstrap/hosts.ini"
else
    hostsIni="./configs/hosts.ini"
fi

echo "Using '$hostsIni' as inventory..."

ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini --limit jtwmasters,jtwnodes ./playbooks/all-base/upgrade-machines.yaml &
ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini --limit pfemasters,pfeagents ./playbooks/all-base/upgrade-machines.yaml &

wait