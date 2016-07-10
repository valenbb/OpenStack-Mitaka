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
  printf ${bold}${RED}"$0 must be run as root!"${NC}${normal}
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

if [ -f /tmp/os_logs/network_create.log ]; then
  printf ${bold}${RED}"Network create script already run, exiting now./nPlease delete /tmp/os_logs/network_create.log file first."${NC}${normal}
  exit 2
fi

source env_var.cfg
source functions.sh

printf ${bold}${BLUE}"CREATING NETWORK"${NC}${normal}
sleep 3

until [ -f /tmp/os_logs/network_create.log ]; do
  printf ${GREEN}"Creating the external network"${NC}
  neutron net-create ext-net --router:external True \
      --provider:physical_network provider --provider:network_type flat

  printf ${GREEN}"Create a subnet on the external network"${NC}
  neutron subnet-create ext-net --name ext-subnet --allocation-pool \
      start=172.16.33.11,end=172.16.33.254 --enable-dhcp \
      --dns-nameserver 10.220.220.221 --gateway 172.16.33.1 172.16.33.0/24
  sleep 3

  tenant_id=`openstack project show admin | egrep -w id | awk '{print $4}'`

  printf ${GREEN}"Create the project network"${NC}
  neutron net-create selfservice
  sleep 3

  printf ${GREEN}"Create a subnet on the project network"${NC}
  neutron subnet-create --name selfservice \
    --dns-nameserver 10.220.220.220 --gateway 192.168.10.1 \
    selfservice 192.168.10.0/24
    sleep 3

  printf ${GREEN}"Create a project router"${NC}
  neutron router-create admin-router
  sleep 3

  printf ${GREEN}"Add the project subnet as an interface on the router"${NC}
  neutron router-interface-add admin-router selfservice
  sleep 3

  printf ${GREEN}"Add a gateway to the external network on the router"${NC}
  neutron router-gateway-set admin-router ext-net
  sleep 3

  printf ${GREEN}"Allow SSH, ICMP protocol"${NC}
  openstack security group rule create default --proto icmp
  openstack security group rule create default --proto tcp --dst-port 22

  printf ${GREEN}"List network namespaces and ports on the router"${NC}
  ip netns
  neutron router-port-list admin-router

  echo "Network create script was run on $(date)." >> /tmp/os_logs/network_create.log
done
sleep 3

printf ${bold}${BLUE}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
exit
