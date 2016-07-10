#!/bin/bash

set -e +x

SECONDS=0
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

if [ -f /tmp/os_logs/svcs_db_setup.log ]; then
  printf ${bold}${RED}"Databases already configured, exiting now.\nPlease delete /tmp/dbinstall.log file first."${NC}${normal}
  exit 2
fi

source env_var.cfg
source functions.sh

# Main installation
until [ -f /tmp/os_logs/svcs_db_setup.log ]; do
# Setting up and configuring databases for OpenStack services
		printf ${bold}${BLUE}"SETTING UP DATABASES FOR CORE OPENSTACK SERVICES"${NC}${normal}
		sleep 2

		printf ${GREEN}"Configuring Keystone DB"${NC}
		cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"localhost" IDENTIFIED BY "$KEYSTONE_DBPASS";
GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"%" IDENTIFIED BY "$KEYSTONE_DBPASS";
FLUSH PRIVILEGES;
EOF
		sleep 2

		printf ${GREEN}"Configuring Glance DB"${NC}
		cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO "glance"@"localhost" IDENTIFIED BY "$GLANCE_DBPASS";
GRANT ALL PRIVILEGES ON glance.* TO "glance"@"%" IDENTIFIED BY "$GLANCE_DBPASS";
FLUSH PRIVILEGES;
EOF
		sleep 2

		printf ${GREEN}"Configuring Nova DBs"${NC}
		cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE nova_api;
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova_api.* TO "nova"@"localhost" IDENTIFIED BY "$NOVA_API_DBPASS";
GRANT ALL PRIVILEGES ON nova_api.* TO "nova"@"%" IDENTIFIED BY "$NOVA_API_DBPASS";
GRANT ALL PRIVILEGES ON nova.* TO "nova"@"localhost" IDENTIFIED BY "$NOVA_DBPASS";
GRANT ALL PRIVILEGES ON nova.* TO "nova"@"%" IDENTIFIED BY "$NOVA_DBPASS";
FLUSH PRIVILEGES;
EOF
		sleep 2

		printf ${GREEN}"Configuring Neutron DB "${NC}
		cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"localhost" IDENTIFIED BY "$NEUTRON_DBPASS";
GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"%" IDENTIFIED BY "$NEUTRON_DBPASS";
FLUSH PRIVILEGES;
EOF
		sleep 2

		printf ${GREEN}"Configuring Cinder DB"${NC}
		cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE cinder;
GRANT ALL ON cinder.* TO "cinder"@"localhost" IDENTIFIED BY "$NEUTRON_DBPASS";
GRANT ALL ON cinder.* TO "cinder"@"localhost" IDENTIFIED BY "$NEUTRON_DBPASS";
FLUSH PRIVILEGES;
EOF
		sleep 2

		echo "Databases for core openstack services have been setup on $(date)." >> /tmp/os_logs/svcs_db_setup.log
done

printf ${GREEN}"Openstack Core Databases Created"${NC}
cat << EOF | mysql -uroot -p$MYSQL_PASS
show databases;
EOF
sleep 3

printf ${bold}${BLUE}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
exit
