#!/bin/bash

# To remember, how I created the gardenedge host for the home environment.

if [ "$SKIP_BOOTSTRAP" = "true" ]; then
    ansible-playbook --inventory ./configs.private/hosts.ini \
                     --limit "gardenedge" \
                     --extra-vars "@configs.private/infra-bootstrap/pi-edge-router-garden-extra-vars.yaml" \
                     --extra-vars "skip_bootstrap=true" \
                     ./playbooks/create-edge-multiwifi.yaml 
else
    ansible-playbook --inventory ./configs.private/hosts.ini \
                     --limit "gardenedge" \
                     --extra-vars "@configs.private/infra-bootstrap/pi-edge-router-garden-extra-vars.yaml" \
                     ./playbooks/create-edge-multiwifi.yaml 
fi
wait