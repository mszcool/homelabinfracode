#
# Cookbook:: mszlx_baseline
# Recipe:: firewallout
#
# Copyright:: 2019, Mario Szpuszta, All Rights Reserved.
#
# Sets up inbound firewall rules with iptables for the linux node
#

#
# SSH inbound allowed
#

iptables_rule 'inbound_ssh_external' do
    table 'filter'
    chain 'INPUT'
    match '-p tcp --dport 22 -i eth0'
    target 'ACCEPT'
end

#
# Webmin inbound allowed
#

iptables_rule 'inbound_cockpit_external' do
    table 'filter'
    chain 'INPUT'
    match '-p tcp --dport 9090 -i eth0'
    target 'ACCEPT'
end

#
# Deny all other inbound traffic
#

iptables_rule 'inbound_deny_all' do
    table 'filter'
    chain 'INPUT'
    match '-i eth0'
    target 'DROP'
end