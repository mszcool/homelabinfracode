#
# Cookbook:: mszlx_baseline
# Recipe:: default
#
# Copyright:: 2019, The Authors, All Rights Reserved.

#apt_repository 'cockpit' do
#    uri         'ppa:cockpit-project/cockpit'
#end


# 
# Webmin used for Web-based adhoc administration if needed
#

apt_package 'perl'
apt_package 'perl-openssl-abi-1.1'
apt_package 'libnet-ssleay-perl'
apt_package 'openssl'
apt_package 'libauthen-pam-perl'
apt_package 'libpam-runtime'
apt_package 'libio-pty-perl'
apt_package 'apt-show-versions'
apt_package 'python'

remote_file '/home/marioszp/downloads/webmin.dpkg' do
    source 'http://prdownloads.sourceforge.net/webadmin/webmin_1.940_all.deb'
    owner 'marioszp'
    mode '0600'
    action :create 
end

dpkg_package 'webmin.dpkg' do
    source '/home/marioszp/downloads/webmin.dpkg'
    action :install
end

#
# Setup iptables by running the default cookbook recipe for iptables
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