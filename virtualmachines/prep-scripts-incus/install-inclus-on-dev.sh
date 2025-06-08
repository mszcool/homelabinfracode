#
# Installs the incus virtual machine manager on a development machine
#

# Create the admin group needed for incus
sudo groupadd incus-admin
sudo usermod -aG incus-admin $USER

# Now install incus
sudo apt install -y incus
sudo apt install -y incus-tools

# Finally init incus automatically
cat <<EOF | sudo incus admin init --preseed
config:
  core.https_address: 127.0.0.1:9443
  images.auto_update_interval: 15
networks:
- name: incusbr0
  type: bridge
  config:
    ipv4.address: auto
    ipv6.address: none
storage_pools:
- name: incus-data
  driver: dir
  config:
    source: /var/lib/incus/storage-pools/incus-data
projects:
- name: default
  config: {}
  description: Default Incus project
profiles:
- name: default
  description: "Standards for local virtual machines"
  devices:
    root:
      path: /
      pool: incus-data
      type: disk
    eth0:
      name: eth0
      nictype: bridged
      parent: incusbr0
      type: nic  
EOF
