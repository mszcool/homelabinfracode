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
package 'perl'
package 'perl-openssl-abi-1.1'
package 'libnet-ssleay-perl'
package 'openssl'
package 'libauthen-pam-perl'
package 'libpam-runtime'
package 'libio-pty-perl'
package 'apt-show-versions'
package 'python3'

#
# Cockpit: for basic web-based administration tasks
#
package 'cockpit'

service 'cockpit.socket' do
    action [ :enable, :start ]
    retries 3
end

#
# Webmin used for Web-based adhoc administration if needed
#
# remote_file '/home/marioszp/downloads/webmin.dpkg' do
#     source 'http://prdownloads.sourceforge.net/webadmin/webmin_1.940_all.deb'
#     owner 'marioszp'
#     mode '0600'
#     action :create 
# end

# dpkg_package 'webmin.dpkg' do
#     source '/home/marioszp/downloads/webmin.dpkg'
#     action :install
# end