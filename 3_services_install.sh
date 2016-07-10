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

if [ -f /tmp/os_logs/svcs_install.log ]; then
  printf ${RED}${bold}"WARNING:${normal}Openstack services already installed, exiting now.\nPlease delete /tmp/os_logs/svcs_install.log file first."${NC}
  exit 2
fi

source env_var.cfg
source functions.sh

printf ${BLUE}${bold}"INSTALLING OPENSTACK CORE SERVICES"${normal}${NC}

until [ -f /tmp/os_logs/svcs_install.log ]; do
  printf ${GREEN}"Installing Identity Service (Keystone)"${NC}
  yum install -y openstack-keystone httpd mod_wsgi memcached python-memcached
  systemctl enable memcached.service
  systemctl start memcached.service
	sleep 2

	printf ${GREEN}"Installing Imaging Service (Glance)"${NC}
	yum install -y openstack-glance python-glance python-glanceclient
	sleep 2

	printf ${GREEN}"Installing Compute Service (Nova)"${NC}
	yum install -y openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler python-novaclient openstack-nova-compute sysfsutils
	sleep 2

	printf ${GREEN}"Installing Networking Service (Neutron)"${NC}
	until [ -f /tmp/neutron_install.log ];
	do
	  clear
	  cat<<EOF
	  =======================================
	       Neutron Network Menu
	  =======================================
	  Select an option:
	  (1) Provider Service
	  (2) Self-Service
	  =======================================
EOF

	  read -n1 -s
	  case "$REPLY" in
	    "1") printf ${BLUE}"Setting up Provider Network"${NC};
			yum install -y openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge python-neutronclient ebtables ipset;
			;;

	    "2") printf ${BLUE}"Setting up Self-Serive Network"${NC};
			yum install -y openstack-neutron openstack-neutron-ml2 python-neutronclient ebtables ipset;
	    ;;

	     * ) printf ${RED}"Invalid option, try again!!!"${NC};
	     ;;

	   esac
	   sleep 1
		echo "Neutron service installed on $(date)" >> /tmp/os_logs/neutron_install.log
	done

	printf ${GREEN}"Installing Dashboard service (Horizon)"${NC}
	yum install -y openstack-dashboard

	printf ${GREEN}"Installing Block service (Cinder)"${NC}
	yum install -y openstack-cinder python-cinderclient lvm2 targetcli python-oslo-policy

	echo "OpenStack packages were installed on $(date)" >> /tmp/os_logs/svcs_install.log
done

printf ${BLUE}${bold}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
exit
