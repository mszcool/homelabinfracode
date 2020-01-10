#
# Cookbook:: mszlx_baseline
# Recipe:: firewallout
#
# Copyright:: 2019, Mario Szpuszta, All Rights Reserved.
#
# Sets up outbound firewall rules with iptables for the linux node
#


#
# By default, allow all outbound traffic which requires two rules to be added
#

iptables_rule 'outbound_allowall' do
    table 'filter'
    chain 'OUTPUT'
    match '-o eth0 -d 0.0.0.0/0'
    target 'ACCEPT'
end

iptables_rule 'outbound_allowall_response' do
    table 'filter'
    chain 'INPUT'
    match '-i eth0 -m state --state ESTABLISHED,RELATED'
    target 'ACCEPT'
end