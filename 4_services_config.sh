#!/bin/bash

set -e +x

#SECONDS=0
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

bold=$(tput bold)
normal=$(tput sgr0)

if [ "${USER}" != "root" ]; then
	printf ${RED}${bold}"WARNING:${normal}$0 must be run as root!"${NC}
	exit 2
fi

directory=/tmp/os_logs

if [ -d $directory ]; then
	printf ${BLUE}"Central logging directory exists"${NC}
elif [ ! -d $directory ]; then
	printf ${BLUE}"Central logging directory does not exists, creating now..."${NC}
	sleep 3
	mkdir -p /tmp/os_logs
	printf ${BLUE}"Central logging directory created."${NC}
fi
sleep 3

if [ -f /tmp/os_logs/services_config.log ]; then
  echo ${RED}"Openstack core services already configured, exiting now./nPlease delete /tmp/os_logs/services_config.log file first."${NC}
  exit 2
fi

source env_var.cfg
source functions.sh

printf ${BLUE}${bold}"CONFIGURING OPENSTACK CORE SERVICES"${normal}${NC}

until [ -f /tmp/os_logs/services_config.log ]; do
  printf ${GREEN}"=====KEYSTONE SERVICE====="${NC}
  # Back-up file keystone.conf
  filekeystone=/etc/keystone/keystone.conf
  test -f $filekeystone.orig || cp $filekeystone $filekeystone.orig

  # Config file /etc/keystone/keystone.conf
  ops_edit $filekeystone DEFAULT admin_token $TOKEN_PASS
  ops_edit $filekeystone database \
  connection mysql+pymysql://keystone:$KEYSTONE_DBPASS@$CTL_MGNT_IP/keystone

  ops_edit $filekeystone token provider fernet

  su -s /bin/sh -c "keystone-manage db_sync" keystone

  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

  echo "ServerName $CTL_MGNT_IP" >>   /etc/httpd/conf/httpd.conf

  cat << EOF > /etc/httpd/conf.d/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
  WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
  WSGIProcessGroup keystone-public
  WSGIScriptAlias / /usr/bin/keystone-wsgi-public
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
  ErrorLogFormat "%{cu}t %M"
  ErrorLog /var/log/httpd/keystone-error.log
  CustomLog /var/log/httpd/keystone-access.log combined

  <Directory /usr/bin>
      Require all granted
  </Directory>
</VirtualHost>

<VirtualHost *:35357>
  WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
  WSGIProcessGroup keystone-admin
  WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
  ErrorLogFormat "%{cu}t %M"
  ErrorLog /var/log/httpd/keystone-error.log
  CustomLog /var/log/httpd/keystone-access.log combined

  <Directory /usr/bin>
      Require all granted
  </Directory>
</VirtualHost>
EOF

  printf ${GREEN}"Restarting Apache (httpd) Server"${NC}
  systemctl enable httpd.service
  systemctl start httpd.service
	sleep 3

  rm -f /var/lib/keystone/keystone.db

  printf ${GREEN}"=====GLANCE SERVICE====="${NC}
  #/* Back-up file nova.conf
  glanceapi_ctl=/etc/glance/glance-api.conf
  test -f $glanceapi_ctl.orig || cp $glanceapi_ctl $glanceapi_ctl.orig

  #Configuring glance config file /etc/glance/glance-api.conf
  ops_edit $glanceapi_ctl database \
  connection  mysql+pymysql://glance:$GLANCE_DBPASS@$CTL_MGNT_IP/glance
  ops_del $glanceapi_ctl database sqlite_db

  ops_edit $glanceapi_ctl keystone_authtoken \
  auth_uri http://$CTL_MGNT_IP:5000
  ops_edit $glanceapi_ctl keystone_authtoken \
  auth_url http://$CTL_MGNT_IP:35357
  ops_edit $glanceapi_ctl keystone_authtoken \
      memcached_servers $CTL_MGNT_IP:11211
  ops_edit $glanceapi_ctl keystone_authtoken auth_type password
  ops_edit $glanceapi_ctl keystone_authtoken project_domain_name default
  ops_edit $glanceapi_ctl keystone_authtoken user_domain_name default
  ops_edit $glanceapi_ctl keystone_authtoken project_name service
  ops_edit $glanceapi_ctl keystone_authtoken username glance
  ops_edit $glanceapi_ctl keystone_authtoken password $GLANCE_PASS

  ops_edit $glanceapi_ctl paste_deploy flavor keystone

  ops_edit $glanceapi_ctl glance_store default_store file
  ops_edit $glanceapi_ctl glance_store stores file,http
  ops_edit $glanceapi_ctl glance_store \
  filesystem_store_datadir /var/lib/glance/images/

  sleep 10
  printf ${GREEN}"=====GLANCE REGISTER====="${NC}
  #/* Backup file file glance-registry.conf
  glancereg_ctl=/etc/glance/glance-registry.conf
  test -f $glancereg_ctl.orig || cp $glancereg_ctl $glancereg_ctl.orig

  ops_del $glancereg_ctl DEFAULT  verbose

  ops_edit $glancereg_ctl database \
  connection  mysql+pymysql://glance:$GLANCE_DBPASS@$CTL_MGNT_IP/glance
  ops_del $glancereg_ctl database sqlite_db

  ops_edit $glanceapi_ctl keystone_authtoken \
      auth_uri http://$CTL_MGNT_IP:5000
  ops_edit $glanceapi_ctl keystone_authtoken \
      auth_url http://$CTL_MGNT_IP:35357
  ops_edit $glanceapi_ctl keystone_authtoken \
      memcached_servers $CTL_MGNT_IP:11211
  ops_edit $glanceapi_ctl keystone_authtoken auth_type password
  ops_edit $glanceapi_ctl keystone_authtoken project_domain_name default
  ops_edit $glanceapi_ctl keystone_authtoken user_domain_name default
  ops_edit $glanceapi_ctl keystone_authtoken project_name service
  ops_edit $glanceapi_ctl keystone_authtoken username glance
  ops_edit $glanceapi_ctl keystone_authtoken password $GLANCE_PASS

  ops_edit $glanceapi_ctl paste_deploy flavor keystone

  printf ${GREEN}"Syncing DB for Glance"${NC}
  su -s /bin/sh -c "glance-manage db_sync" glance

  printf ${GREEN}"Restarting Glance service ..."${NC}
  systemctl enable openstack-glance-api.service \
      openstack-glance-registry.service
	sleep 5
  systemctl start openstack-glance-api.service \
      openstack-glance-registry.service
	sleep 5

  printf ${GREEN}"=====NOVA SERVICE====="${NC}
  nova_ctl=/etc/nova/nova.conf
  test -f $nova_ctl.orig || cp $nova_ctl $nova_ctl.orig

  printf ${GREEN}"Config file nova.conf"${NC}
  ops_del $nova_ctl DEFAULT logdir
  ops_del $nova_ctl DEFAULT verbose
  ops_edit $nova_ctl DEFAULT log-dir /var/log/nova
  ops_edit $nova_ctl DEFAULT enabled_apis osapi_compute,metadata
  ops_edit $nova_ctl DEFAULT rpc_backend rabbit
  ops_edit $nova_ctl DEFAULT auth_strategy keystone
  ops_edit $nova_ctl DEFAULT rootwrap_config /etc/nova/rootwrap.conf
  ops_edit $nova_ctl DEFAULT my_ip $CTL_MGNT_IP
  ops_edit $nova_ctl DEFAULT use_neutron True
  ops_edit $nova_ctl \
      DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

  ops_edit $nova_ctl api_database \
      connection mysql+pymysql://nova:$NOVA_API_DBPASS@$CTL_MGNT_IP/nova_api

  ops_edit $nova_ctl database \
      connection mysql+pymysql://nova:$NOVA_DBPASS@$CTL_MGNT_IP/nova

  ops_edit $nova_ctl oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
  ops_edit $nova_ctl oslo_messaging_rabbit rabbit_userid openstack
  ops_edit $nova_ctl oslo_messaging_rabbit rabbit_password $RABBIT_PASS

  ops_edit $nova_ctl keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
  ops_edit $nova_ctl keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
  ops_edit $nova_ctl keystone_authtoken memcached_servers $CTL_MGNT_IP:11211
  ops_edit $nova_ctl keystone_authtoken auth_type password
  ops_edit $nova_ctl keystone_authtoken project_domain_name default
  ops_edit $nova_ctl keystone_authtoken user_domain_name default
  ops_edit $nova_ctl keystone_authtoken project_name service
  ops_edit $nova_ctl keystone_authtoken username nova
  ops_edit $nova_ctl keystone_authtoken password $NOVA_PASS

  ops_edit $nova_ctl vnc vncserver_listen \$my_ip
  ops_edit $nova_ctl vnc vncserver_proxyclient_address \$my_ip

  ops_edit $nova_ctl glance api_servers http://$CTL_MGNT_IP:9292

  ops_edit $nova_ctl oslo_concurrency lock_path /var/lib/nova/tmp

  ops_edit $nova_ctl neutron url http://$CTL_MGNT_IP:9696
  ops_edit $nova_ctl neutron auth_url http://$CTL_MGNT_IP:35357
  ops_edit $nova_ctl neutron auth_type password
  ops_edit $nova_ctl neutron project_domain_name default
  ops_edit $nova_ctl neutron user_domain_name default
  ops_edit $nova_ctl neutron region_name RegionOne
  ops_edit $nova_ctl neutron project_name service
  ops_edit $nova_ctl neutron username neutron
  ops_edit $nova_ctl neutron password $NEUTRON_PASS
  ops_edit $nova_ctl neutron service_metadata_proxy True
  ops_edit $nova_ctl neutron metadata_proxy_shared_secret $METADATA_SECRET

  # [cinder] Section
  ops_edit $nova_ctl cinder os_region_name RegionOne

  printf ${GREEN}"Syncing Nova DB"${NC}
  su -s /bin/sh -c "nova-manage api_db sync" nova
	sleep 3

  su -s /bin/sh -c "nova-manage db sync" nova
	sleep 3

  printf ${GREEN}"Restarting Nova Services"${NC}
  systemctl enable openstack-nova-api.service \
      openstack-nova-consoleauth.service openstack-nova-scheduler.service \
      openstack-nova-conductor.service openstack-nova-novncproxy.service
	sleep 3

  systemctl start openstack-nova-api.service \
      openstack-nova-consoleauth.service openstack-nova-scheduler.service \
      openstack-nova-conductor.service openstack-nova-novncproxy.service
	sleep 3

	echo ${GREEN}"=====HORIZON DASHBOARD====="${NC}
	touch /var/www/html/index.html
  filehtml=/var/www/html/index.html
  test -f $filehtml.orig || cp $filehtml $filehtml.orig
  rm $filehtml
  touch $filehtml
  cat << EOF >> $filehtml
  <html>
  <head>
  <META HTTP-EQUIV="Refresh" Content="0.5; URL=http://$CTL_EXT_IP/dashboard">
  </head>
  <body>
  <center> <h1>Redirecting to OpenStack Dashboard</h1> </center>
  </body>
  </html>
EOF

  printf ${GREEN}"Configuring dashboard"${NC}
  cp /etc/openstack-dashboard/local_settings \
      /etc/openstack-dashboard/local_settings.orig

  filehorizon=/etc/openstack-dashboard/local_settings

  # Allowing insert password in dashboard ( only apply in image )
  sed -i "s/'can_set_password': False/'can_set_password': True/g" \
      $filehorizon

  sed -i "s/_member_/user/g" $filehorizon
  sed -i "s/127.0.0.1/$CTL_MGNT_IP/g" $filehorizon
  sed -i "s/http:\/\/\%s:5000\/v2.0/http:\/\/\%s:5000\/v3/g" \
      $filehorizon

  sed -e "s/django.core.cache.backends.locmem.LocMemCache/django.core.cache.backends.memcached.MemcachedCache,\
           'LOCATION': '$CTL_MGNT_IP:11211',/g" $filehorizon
  cat << EOF >> $filehorizon
  OPENSTACK_API_VERSIONS = {
  #    "data-processing": 1.1,
      "identity": 3,
      "volume": 2,
      "compute": 2,
  }
  SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
EOF
  sed -i "s/#OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'default'/\
  OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'default'/g" \
      $filehorizon
	sleep 3

  ## /* Restarting apache2 and memcached
  systemctl restart httpd.service memcached.service
	sleep 3

	printf ${GREEN}"Finish setting up Horizon"${NC}
  chown root:apache local_settings

  printf ${bold}${GREEN}"LOGIN INFORMATION IN HORIZON"${NC}${normal}
  printf ${bold}${GREEN}"URL:${normal} http://$CTL_EXT_IP/dashboard"${NC}
  printf ${bold}${GREEN}"User:${normal} admin or demo"${NC}
  printf ${bold}${GREEN}"Password:${normal} $ADMIN_PASS"${NC}
	sleep 3

  echo ${GREEN}"=====NEUTRON SERVICE====="${NC}
	sleep 3

  echo ${GREEN}"Configuring net forward for all VMs"${NC}
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
  echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
  sysctl -p
  sleep 3

  neutron_ctl=/etc/neutron/neutron.conf
  test -f $neutron_ctl.orig || cp $neutron_ctl $neutron_ctl.orig

  ## [DEFAULT] section
	ops_edit $neutron_ctl DEFAULT core_plugin ml2
	ops_edit $neutron_ctl DEFAULT service_plugins router
	ops_edit $neutron_ctl DEFAULT auth_strategy keystone
	ops_edit $neutron_ctl DEFAULT dhcp_agent_notification True
	ops_edit $neutron_ctl DEFAULT allow_overlapping_ips True
	ops_edit $neutron_ctl DEFAULT notify_nova_on_port_status_changes True
	ops_edit $neutron_ctl DEFAULT notify_nova_on_port_data_changes True
	ops_edit $neutron_ctl DEFAULT rpc_backend rabbit
	ops_edit $neutron_ctl DEFAULT verbose True

  ## [database] section
	ops_edit $neutron_ctl database connection mysql+pymysql://neutron:$NEUTRON_DBPASS@$CTL_MGNT_IP/neutron

  ## [keystone_authtoken] section
	ops_edit $neutron_ctl keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
	ops_edit $neutron_ctl keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
	ops_edit $neutron_ctl keystone_authtoken auth_plugin password
	ops_edit $neutron_ctl keystone_authtoken project_domain_id default
	ops_edit $neutron_ctl keystone_authtoken user_domain_id default
	ops_edit $neutron_ctl keystone_authtoken project_name service
	ops_edit $neutron_ctl keystone_authtoken username neutron
	ops_edit $neutron_ctl keystone_authtoken password $NEUTRON_PASS

	ops_del $neutron_ctl keystone_authtoken identity_uri
	ops_del $neutron_ctl keystone_authtoken admin_tenant_name
	ops_del $neutron_ctl keystone_authtoken admin_user
	ops_del $neutron_ctl keystone_authtoken admin_password

  ## [oslo_messaging_rabbit] section
	ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
	ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_port 5672
	ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_userid openstack
	ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_password $RABBIT_PASS

  ## [nova] section
	ops_edit $neutron_ctl nova auth_url http://$CTL_MGNT_IP:35357
	ops_edit $neutron_ctl nova auth_plugin password
	ops_edit $neutron_ctl nova project_domain_id default
	ops_edit $neutron_ctl nova user_domain_id default
	ops_edit $neutron_ctl nova region_name RegionOne
	ops_edit $neutron_ctl nova project_name service
	ops_edit $neutron_ctl nova username nova
	ops_edit $neutron_ctl nova password $NOVA_PASS

	printf ${GREEN}"Configuring ML2"${NC}
	sleep 3

	ml2_clt=/etc/neutron/plugins/ml2/ml2_conf.ini
	test -f $ml2_clt.orig || cp $ml2_clt $ml2_clt.orig

	## [ml2] section
	ops_edit $ml2_clt ml2 type_drivers flat,vlan,gre,vxlan
	ops_edit $ml2_clt ml2 tenant_network_types
	ops_edit $ml2_clt ml2 mechanism_drivers openvswitch
	ops_edit $ml2_clt ml2 extension_drivers port_security

	## [ml2_type_flat] section
	ops_edit $ml2_clt ml2_type_flat flat_networks physnet1

	## [securitygroup] section
	ops_edit $ml2_clt securitygroup enable_ipset True
	ops_edit $ml2_clt securitygroup enable_security_group True
	ops_edit $ml2_clt securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

	####################### Backup configuration of openvswitch_agent ################################
	printf ${GREEN}"Configuring openvswitch_agent"${NC}
	ovsfile=/etc/neutron/plugins/ml2/openvswitch_agent.ini
	test -f $ovsfile.orig || cp $ovsfile $ovsfile.orig

	# [ovs] section
	ops_edit $ovsfile ovs bridge_mappings physnet1:br-ex

	####################### Configuring  L3 AGENT ################################
	netl3=/etc/neutron/l3_agent.ini
	test -f $netl3.orig || cp $netl3 $netl3.orig

	ops_edit $netl3 DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
	ops_edit $netl3 DEFAULT external_network_bridge


	####################### Configuring DHCP AGENT ################################
	printf "Configuring DHCP Agent"${NC}
	netdhcp=/etc/neutron/dhcp_agent.ini
	test -f $netdhcp.orig || cp $netdhcp $netdhcp.orig

	## [DEFAULT] section
	ops_edit $netdhcp DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
	ops_edit $netdhcp DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq

	####################### Configuring METADATA AGENT ################################
	printf "Configuring Metadata Agent"${NC}
	netmetadata=/etc/neutron/metadata_agent.ini
	test -f $netmetadata.orig || cp $netmetadata $netmetadata.orig

	## [DEFAULT]
	ops_edit $netmetadata DEFAULT auth_uri http://$CTL_MGNT_IP:5000
	ops_edit $netmetadata DEFAULT auth_url http://$CTL_MGNT_IP:35357
	ops_edit $netmetadata DEFAULT auth_region  RegionOne
	ops_edit $netmetadata DEFAULT auth_plugin  password
	ops_edit $netmetadata DEFAULT project_domain_id  default
	ops_edit $netmetadata DEFAULT user_domain_id  default
	ops_edit $netmetadata DEFAULT project_name  service
	ops_edit $netmetadata DEFAULT username  neutron
	ops_edit $netmetadata DEFAULT password  $NEUTRON_PASS
	ops_edit $netmetadata DEFAULT nova_metadata_ip $CTL_MGNT_IP
	ops_edit $netmetadata DEFAULT nova_metadata_port 8775
	ops_edit $netmetadata DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
	ops_edit $netmetadata DEFAULT verbose True

	ops_del $netmetadata DEFAULT admin_tenant_name
	ops_del $netmetadata DEFAULT admin_user
	ops_del $netmetadata DEFAULT admin_password

	printf ${GREEN}"Create a symbolic link"${NC}
	ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	sleep 3

	printf ${GREEN}"Setup db"${NC}
	su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
	  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
	sleep 3

	### CONFIG NOVA FOR OVS
	nova_ctl=/etc/nova/nova.conf
	test -f $nova_ctl.orig1 || cp $nova_ctl $nova_ctl.orig1
	ops_edit $nova_ctl DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver

	# nmcli c add type bridge autoconnect yes con-name br-eth1 ifname br-eth1
	# nmcli c modify br-eth1 ipv4.addresses 172.16.69.40/24 ipv4.method manual
	# nmcli c modify br-eth1 ipv4.gateway 172.16.69.1
	# nmcli c modify br-eth1 ipv4.dns 8.8.8.8
	# nmcli c delete eth1 && nmcli c add type bridge-slave autoconnect yes con-name eth1 ifname eth1 master br-eth1

	printf ${GREEN}"Restarting Neutron services"${NC}
	systemctl start neutron-server
	systemctl enable neutron-server
	systemctl start openvswitch
	systemctl enable openvswitch
	systemctl restart neutron-openvswitch-agent
	systemctl restart openstack-nova-api
	sleep 3

	for service in dhcp-agent l3-agent metadata-agent openvswitch-agent; do
		systemctl start neutron-$service
		systemctl enable neutron-$service
	done

### Setup IP for bridge card
	printf ${GREEN}"Setup IP for bridge card"${NC}
	cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eno1
TYPE=Ethernet
DEVICE="eno1"
NAME=eno1
ONBOOT=yes
OVS_BRIDGE=br-ex
TYPE="OVSPort"
DEVICETYPE="ovs"
EOF

	cat << EOF > /etc/sysconfig/network-scripts/ifcfg-br-ex
DEVICE="br-ex"
BOOTPROTO="none"
IPADDR=$CTL_EXT_IP
PREFIX=$PREFIX_NETMASK_EXT
GATEWAY=$GATEWAY_IP_EXT
DNS1=$DNS1_SERVER
DNS2=$DNS2_SERVER
ONBOOT="yes"
TYPE="OVSBridge"
DEVICETYPE="ovs"
EOF

	printf ${GREEN}"Add bridge"${NC}
	ovs-vsctl add-port br-ex eno1

	printf ${GREEN}"Finished setting up Neutron on $HOST_CTL"${NC}
	sleep 3

	echo "OpenStack services were configured on $(date)" >> /tmp/svr_conf.log
done

printf ${BLUE}${bold}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
init 6
