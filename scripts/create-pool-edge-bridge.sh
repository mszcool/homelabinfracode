#!/bin/bash

# To remember, how I created the gardenedge host for the home environment.

if [ "$SKIP_BOOTSTRAP" = "true" ]; then
    ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini \
                    --limit "pooledge" \
                    --extra-vars "@configs.private/infra-bootstrap/pi-edge-bridge-pool-extra-vars.yaml" \
                    --extra-vars "skip_bootstrap=true" \
                    ./playbooks/create-edge-bridgewifi.yaml
else
    ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini \
                    --limit "pooledge" \
                    --extra-vars "@configs.private/infra-bootstrap/pi-edge-bridge-pool-extra-vars.yaml" \
                    ./playbooks/create-edge-bridgewifi.yaml
fi
wait