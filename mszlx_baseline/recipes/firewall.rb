#
# Setup persistent IP tables (netfilter-persistent), needed on Ubuntu systems, specifically
#
include_recipe 'iptables::default'

#
# iptables Firewall rules for the external network adapter
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

iptables_rule 'inbound_ssh_external' do
    table 'filter'
    chain 'INPUT'
    match '-p tcp --dport 22 -i eth0'
    target 'ACCEPT'
end

iptables_rule 'inbound_webmin_external' do
    table 'filter'
    chain 'INPUT'
    match '-p tcp --dport 10000 -i eth0'
    target 'ACCEPT'
end

iptables_rule 'inbound_deny_all' do
    table 'filter'
    chain 'INPUT'
    match '-i eth0'
    target 'DROP'
end

service 'netfilter-persistent' do
    action :restart
    retries 3
end