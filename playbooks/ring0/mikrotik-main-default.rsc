#
# Default configuration for a new Mikrotik router.
# This part of the configuration needs to be done before automation with Ansible can start
# from remote configuration hosts. Use Winbox with MAC-based access to configure the router
# and copy & paste these contents to the router Terminal, or upload it as script to the router.
#

:local routerHostName "mszMikrotikTest"
:local routerTimeZone "Europe/Vienna"
:local wanInterfaceList "WAN"
:local lanInterfaceList "LAN"
:local loopbackInterfaceName "lo"
:local wanInterfaceName "ether1"
:local lanInterfaceName "localBridge"
:local lanInterfaceMembers "ether2"
:local lanBridgeAddress "10.10.0.1"

# First, set the hostname and time zone.
:put "Setting hostname and time zone"
/system identity set name=$routerHostName
/system clock set time-zone-name=$routerTimeZone

# Now configure DHCP for the WAN interface.
:put "Configuring DHCP for WAN interface"
:if ([:len [/ip dhcp-client find interface=$wanInterfaceName]] > 0) do={
    /ip dhcp-client remove [find interface=$wanInterfaceName]
}
/ip dhcp-client add interface=$wanInterfaceName disabled=no default-route-distance=5 comment="default configuration / DHCP client for WAN"

# Now configure the LAN bridge-interface with all members.
:put "Configuring LAN bridge interface and members"
/interface bridge
:if ([:len [/interface bridge find name=$lanInterfaceName]] > 0) do={
    :local bridgePorts [/interface bridge port find bridge=$lanInterfaceName]
    :foreach port in=$bridgePorts do={
        /interface bridge port remove $port
    }
    /interface bridge remove [find name=$lanInterfaceName]
}
add name=$lanInterfaceName comment="default configuration / local bridge interface"
/interface bridge port
:local interfaceArray [:toarray $lanInterfaceMembers]
:foreach i in=$interfaceArray do={
  :local interfaceName $i
  add bridge=$lanInterfaceName interface=$interfaceName
}

# Configure the static IP for the LAN bridge interface.
:put "Configuring static IP for LAN bridge interface"
:local bridgeIpAddress "$lanBridgeAddress/24"
:if ([:len [/ip address find address=$bridgeIpAddress]] > 0) do={
    /ip address remove [find address=$bridgeIpAddress]
}
/ip address add address=$bridgeIpAddress interface=$lanInterfaceName comment="default configuration / LAN bridge address"

# Configure the interface lists for LAN and WAN
:put "Configuring interface lists for LAN and WAN"
/interface list
:if ([:len [/interface list find name=$wanInterfaceList]] = 0) do={
    add name=$wanInterfaceList comment="default configuration / WAN interface list"
}
:if ([:len [/interface list find name=$lanInterfaceList]] = 0) do={
    add name=$lanInterfaceList comment="default configuration / LAN interface list"
}

/interface list member
:local existingMembers [/interface list member find]
:foreach member in=$existingMembers do={
    /interface list member remove $member
}
:if ([:len [/interface list member find interface=$lanInterfaceName list=$lanInterfaceList]] = 0) do={
    add interface=$lanInterfaceName list=$lanInterfaceList comment="default configuration / add LAN bridge to LAN interface list"
}
:if ([:len [/interface list member find interface=$wanInterfaceName list=$wanInterfaceList]] = 0) do={
    add interface=$wanInterfaceName list=$wanInterfaceList comment="default configuration / add LAN bridge to WAN interface list"
}

# Set the default firewall rules which allow outbound traffic for LAN and block all inbound traffic from WAN.
:put "Configuring default firewall rules"
/ip firewall filter
:if ([:len [/ip firewall filter find where comment~"default_300"]] = 0) do={
    add chain=input action=accept connection-state=established,related comment="default_300 / allow established and related connections"
}
:if ([:len [/ip firewall filter find where comment~"default_310"]] = 0) do={
    add chain=input action=accept in-interface-list=$lanInterfaceList protocol=icmp comment="default_310 / allow ICMP traffic from all except WAN"
}
:if ([:len [/ip firewall filter find where comment~"default_320"]] = 0) do={
    add chain=input action=accept dst-address=127.0.0.1 in-interface=$loopbackInterfaceName comment="default_320 / allow traffic to the router itself (for CAPsMAN)"
}
:if ([:len [/ip firewall filter find where comment~"default_330"]] = 0) do={
    add chain=forward action=accept connection-state=established,related comment="default_330 / allow established and related connections"
}
:if ([:len [/ip firewall filter find where comment~"default_340"]] = 0) do={
    add chain=forward action=accept out-interface-list=$wanInterfaceList comment="default_340 / allow all outbound traffic from LAN"
}
:if ([:len [/ip firewall filter find where comment~"default_500"]] = 0) do={
    add chain=input action=drop in-interface-list=$wanInterfaceList comment="default_500 / drop all inbound traffic from WAN"
}
:if ([:len [/ip firewall filter find where comment~"default_510"]] = 0) do={
    add chain=input action=drop in-interface-list="!$lanInterfaceList" comment="default_510 / drop all inbound traffic not from LAN"
}
:if ([:len [/ip firewall filter find where comment~"default_520"]] = 0) do={
    add chain=forward action=drop connection-state=invalid comment="default_520 / drop invalid connections"
}
:if ([:len [/ip firewall filter find where comment~"default_530"]] = 0) do={
    add chain=forward action=drop connection-nat-state=!dstnat connection-state=new in-interface-list=$wanInterfaceList comment="default_530 / drop all new connections from WAN without destination NAT"
}

# Disable insecure services.
:put "Disabling insecure services, setting up SSL will follow in ring1 with GitOps"
/ip service disable telnet,ftp