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
# iptables Firewall rules for the external network adapter
#
iptables_chain 'fw_external' do
    chain 'FW_EXTERNAL'
end

iptables_rule 'ssh_external' do
    chain 'FW_EXTERNAL'
    match '-p tcp --dport 22 -i eth0'
    target 'ACCEPT'
end

iptables_rule 'deny_all' do
    chain 'FW_EXTERNAL'
    match '-i eth0'
    target 'DENY'
end