#
# Cookbook:: mszlx_baseline
# Recipe:: firewall
#
# Copyright:: 2019, Mario Szpuszta, All Rights Reserved.
#
# Sets up an iptables-based firewall for the linux node:
# - Activate persistent iptables using the default recipe from the iptables cookbook
# - Add all outbound rules by including the outbound rules recipe
# - Add all inbound rules by including the inbound rules recipe
#

#
# Setup persistent IP tables (netfilter-persistent), needed on Ubuntu systems, specifically
#
include_recipe 'iptables::default'

#
# Outbound rules to be added before inbound as the last rule which will be added is always "DENY all inbound"
#
include_recipe 'mszlx_baseline::firewallout'
include_recipe 'mszlx_baseline::firewallin'

#
# Restart the persistent network filter service to re-load iptables
#
service 'netfilter-persistent' do
    action :restart
    retries 3
end