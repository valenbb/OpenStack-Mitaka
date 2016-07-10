#!/bin/bash

set -e +x

#SECONDS=0
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
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

if [ -f /tmp/os_logs/prepped.log ]; then
  printf ${bold}${RED}"Server already prepped, exiting now./nPlease delete /svr_prereq.log file first."${NC}${normal}
  exit 2
fi

source env_var.cfg
source functions.sh

printf ${bold}${BLUE}"PREPARING SERVER FOR OPENSTACK"${NC}${normal}
sleep 2

until [ -f /tmp/os_logs/svr_prep.log ]; do
  printf ${GREEN}"Disabling firewall"${NC}
  systemctl stop firewalld
  systemctl disable firewalld

  printf ${GREEN}"Disabling Network Manager"${NC}
  systemctl stop NetworkManager
  systemctl disable NetworkManager

  printf ${GREEN}"Disabling SELinux"${NC}
  # Temporarily disable SELinux
  /usr/sbin/setenforce 0
  # Permanently disable SELinux; reboot needed
  sed -i "s/enforcing/disabled/g" /etc/selinux/config /etc/selinux/config
  sleep 3

  printf ${GREEN}"Sourcing Global Research proxy"${NC}
  echo "export http_proxy=http://proxy.research.ge.com:8080" >> /etc/environment
  echo "export https_proxy=http://proxy.research.ge.com:8080" >> /etc/environment
  echo "export no_proxy=127.0.0.1,localhost,ge.com,3.1.52.41,3.1.52.42" >> /etc/environment
  source /etc/environment

  printf ${GREEN}"Installing GE SSL certs"${NC}
  update-ca-trust enable
  wget -O /etc/pki/ca-trust/source/anchors/GE_External_Certificate1.pem http://Internet.ge.com/GE_External_Certificate1.pem
  wget -O /etc/pki/ca-trust/source/anchors/GE_External_Certificate2.pem http://Internet.ge.com/GE_External_Certificate2.pem
  update-ca-trust extract
  sleep 2

  printf ${GREEN}"Setting up hosts file (results not displayed in terminal)"${NC}
  # Add extra echo lines if setup is greater that 2 nodes
  mv /etc/hosts /tmp
  cat > /etc/hosts <<EOF
127.0.0.1   $HOST_CTL localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
3.1.52.41       $HOST_CTL
3.1.52.42       $HOST_COM1
EOF

  printf ${GREEN}"Configuring IPv4 forwarding"${NC}
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  echo 'net.ipv4.conf.default.rp_filter=0' >> /etc/sysctl.conf
  echo 'net.ipv4.conf.all.rp_filter=0' >> /etc/sysctl.conf
  sysctl -p
  sleep 3

  printf ${GREEN}"Backing up network interfaces"${NC}
  mkdir /tmp/nic_backup
  cp /etc/sysconfig/network-scripts/ifcfg-eno1 /tmp/nic_backup
  cp /etc/sysconfig/network-scripts/ifcfg-eno2 /tmp/nic_backup
  sleep 3

  echo "Server was prepped on $(date)." >> /tmp/os_logs/svr_prep.log
done
sleep 3

printf ${BLUE}${bold}"INSTALLING OPENSTACK PRE-REQUISITES"${NC}${normal}
sleep 2

until [ -f /tmp/os_logs/os_prereq.log ]; do
  printf ${GREEN}"Installing NTP service"${NC}
  yum install -y chrony

  printf ${GREEN}"Configuring NTP"${NC}
  cp /etc/chrony.conf /etc/chrony.conf.orig
  sed -i "3,6d" /etc/chrony.conf
  sed -i "20,23d" /etc/chrony.conf
  sleep 2

  if [ "$HOST" == "ats-controller" ]; then
    sed -i "18 a server "$NTP1" iburst" /etc/chrony.conf
    sed -i "19 a server "$NTP2" iburst" /etc/chrony.conf
    sed -i "20 a server "$NTP3" iburst" /etc/chrony.conf
    sed -i "21 a server "$NTP4" iburst" /etc/chrony.conf
    sed -i "22 a allow 3.1.45.0/24" /etc/chrony.conf
  elif [ "$HOST" != "ats-controller" ]; then
    sed -i "18 a server "$HOST_CTL" iburst" /etc/chrony.conf
  fi

  printf ${GREEN}"Restarting NTP service"${NC}
  systemctl enable chronyd.service
  systemctl start chronyd.service
  sleep 3

  printf ${GREEN}"NTP verification"${NC}
  chronyc sources

  printf ${GREEN}"Updating EPEL CentOS 7"${NC}
  wget http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-7.noarch.rpm
  rpm -ivh epel-release-7-7.noarch.rpm
  sleep 3

  printf ${GREEN}"Installing CRUDINI"${NC}
  yum -y install crudini

  printf ${GREEN}"Adding openstack repo"${NC}
  yum install -y centos-release-openstack-mitaka
  yum install -y deltarpm
  yum update -y && yum upgrade -y

  echo ${GREEN}"Installing OpenStack client"${NC}
  yum install -y python-openstackclient

  if [ "$HOST" == "ats-controller" ]; then
    echo ${GREEN}"Install SQL database-MariaDB"${NC}
    yum install -y mariadb mariadb-server python2-PyMySQL

    printf ${GREEN}"Configuring MariaDB"${NC}
    touch /etc/my.cnf.d/openstack.cnf
    cat << EOF > /etc/my.cnf.d/openstack.cnf
[mysqld]
bind-address = 3.1.45.8

default-storage-engine = innodb
innodb_file_per_table
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8

EOF
    sleep 3

    printf ${GREEN}"Starting MariaDB service"${NC}
    systemctl enable mariadb.service
    systemctl start mariadb.service

    printf ${GREEN}"Resetting db root user password"${NC}
    cat > /root/config.sql <<EOF
delete from mysql.user where user='';
update mysql.user set password=password("$MYSQL_PASS");
flush privileges;
EOF

    mysql -u root -e'source /root/config.sql'
    rm -rf /root/config.sql

    printf ${GREEN}"Installing RabbitMQ"${NC}
    yum -y install rabbitmq-server

    printf ${GREEN}"Starting rabbitmq-server"${NC}
    systemctl enable rabbitmq-server.service
    systemctl start rabbitmq-server.service
    sleep 3

    printf ${GREEN}"Configuring rabbitmq"${NC}
    rabbitmqctl add_user openstack $RABBIT_PASS
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    sleep 3

    printf ${GREEN}"Installing memcached"${NC}
    yum -y install memcached python-memcached
    sleep 3

    printf ${GREEN}"Starting memcached service"${NC}
    sleep 3
    systemctl enable memcached.service
    systemctl start memcached.service

    printf ${GREEN}"Installing Openvswitch"${NC}
    yum install -y openstack-neutron-openvswitch

    printf ${GREEN}"Starting openvswitch service"${NC}
    systemctl enable openvswitch.service
    systemctl start openvswitch.service

    printf ${GREEN}"Adding OVS bridge"${NC}
    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-ex
    #ovs-vsctl add-port br-ex eno1  <-- This will break networking

    printf ${GREEN}"Verifying OVS bridge"${NC}
    ovs-vsctl show
  elif [ "$HOST" != "ats-controller" ]; then
  printf ${GREEN}"Installing Openvswitch"${NC}
  yum install -y openstack-neutron-openvswitch

  printf ${GREEN}"Starting openvswitch service"${NC}
  systemctl enable openvswitch.service
  systemctl start openvswitch.service

  printf ${GREEN}"Adding OVS bridge"${NC}
  ovs-vsctl add-br br-int
  ovs-vsctl add-br br-ex
  #ovs-vsctl add-port br-ex eno1  <-- This will break networking

  printf ${GREEN}"Verifying OVS bridge"${NC}
  ovs-vsctl show

  echo "Openstack prereqs were installed on $(date)." >> /tmp/os_logs/os_prereq.log

  #printf ${RED}${bold}"Rebooting server"${NC}
  #init 6
done
sleep 3

printf ${BLUE}${bold}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
exit
