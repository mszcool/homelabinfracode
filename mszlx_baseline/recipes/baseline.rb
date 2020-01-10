#
# Cookbook:: mszlx_baseline
# Recipe:: baseline
#
# Copyright:: 2019, Mario Szpuszta, All Rights Reserved.
#
# Sets up the baseline requirements for a linux node. This typically includes:
# - installing all required packages through package manager
# - downloading and installing packages, directly
#

# 
# Baseline package requirements (also required for Webmin)
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

#
# Webmin used for Web-based adhoc administration if needed
#
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