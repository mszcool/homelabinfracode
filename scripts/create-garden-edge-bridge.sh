#!/bin/bash

# To remember, how I created the gardenedge host for the home environment.

if [ "$SKIP_BOOTSTRAP" = "true" ]; then
    ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini \
                    --limit "gardenedge" \
                    --extra-vars "@configs.private/infra-bootstrap/hw-net-wifi/pi-bridge/pi-edge-bridge-garden-extra-vars.yaml" \
                    --extra-vars "skip_bootstrap=true" \
                    ./playbooks/hw-net-wifi/create-edge-bridgewifi.yaml
else
    ansible-playbook --inventory ./configs.private/infra-bootstrap/hosts.ini \
                    --limit "gardenedge" \
                    --extra-vars "@configs.private/infra-bootstrap/hw-net-wifi/pi-bridge/pi-edge-bridge-garden-extra-vars.yaml" \
                    ./playbooks/hw-net-wifi/create-edge-bridgewifi.yaml
fi
wait