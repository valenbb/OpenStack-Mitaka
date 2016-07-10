#!/bin/bash

set -e +x

source env_var.cfg
source functions.sh

if [ "${USER}" != "root" ]; then
  printf ${RED}${bold}"$0 must be run as root!"${normal}${NC}
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

if [ -f /tmp/os_logs/os_commands.log ]; then
  printf ${RED}${bold}"Server already prepped, exiting now./nPlease delete /os_commands.log file first."${normal}${NC}
  exit 2
fi

source env_var.cfg
source functions.sh

printf ${BLUE}${bold}"RUNNING OPENSTACK COMMANDS"${NC}${normal}
sleep 2

until [ -f /tmp/os_logs/os_commands.log ]; do
  unset http_proxy
  unset https_proxy
  unset no_proxy
  
	###  Identity service
	openstack service create \
	    --name keystone --description "OpenStack Identity" identity

	openstack endpoint create --region RegionOne \
	identity public http://$CTL_MGNT_IP:5000/v3

	openstack endpoint create --region RegionOne \
	identity internal http://$CTL_MGNT_IP:5000/v3

	openstack endpoint create --region RegionOne \
	identity admin http://$CTL_MGNT_IP:35357/v3

	openstack domain create --description "Default Domain" default

	openstack project create --domain default --description "Admin Project" admin

	openstack user create admin --domain default --password $ADMIN_PASS

	openstack role create admin

	openstack role add --project admin --user admin admin

	openstack project create --domain default \
	    --description "Service Project" service

	openstack project create --domain default --description "Demo Project" demo

	openstack user create demo --domain default --password $ADMIN_PASS

	openstack role create user

	openstack role add --project demo --user demo user

	unset OS_TOKEN OS_URL

	# Create environment file
	cat << EOF > admin-openrc
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$CTL_MGNT_IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
	sleep 5

	printf ${GREEN}"Execute environment script"${NC}
	chmod +x admin-openrc
	cat  admin-openrc >> /etc/profile
	cp  admin-openrc /root/admin-openrc
	source admin-openrc

	cat << EOF > demo-openrc
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=$DEMO_PASS
export OS_AUTH_URL=http://$CTL_MGNT_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
	chmod +x demo-openrc
	cp  demo-openrc /root/demo-openrc

	printf ${GREEN}"Verify keystone"${NC}
	openstack token issue

	###  Imaging service
	printf ${GREEN}"Create user, endpoint for Glance"${NC}
	source admin-openrc

	openstack user create glance --domain default --password $GLANCE_PASS

	openstack role add --project service --user glance admin

	openstack service create --name glance --description \
	"OpenStack Image service" image

	openstack endpoint create --region RegionOne \
	    image public http://$CTL_MGNT_IP:9292

	openstack endpoint create --region RegionOne \
	    image internal http://$CTL_MGNT_IP:9292

	openstack endpoint create --region RegionOne \
	    image admin http://$CTL_MGNT_IP:9292

	printf ${GREEN}"Registering Cirros IMAGE for GLANCE"${NC}
	mkdir -p /tmp/images
	cd /tmp/images
	wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img

	openstack image create "cirros" \
	    --file cirros-0.3.4-x86_64-disk.img \
	    --disk-format qcow2 --container-format bare \
	    --public

	cd /root/
	# rm -r /tmp/images

	printf ${GREEN}"Testing Glance"${NC}
	openstack image list

	###  Nova service
	printf ${GREEN}"Create user, endpoint for Nova"${NC}

	openstack user create nova --domain default  --password $NOVA_PASS

	openstack role add --project service --user nova admin

	openstack service create --name nova --description "OpenStack Compute" compute

	openstack endpoint create --region RegionOne \
	    compute public http://$CTL_MGNT_IP:8774/v2.1/%\(tenant_id\)s

	openstack endpoint create --region RegionOne \
	    compute internal http://$CTL_MGNT_IP:8774/v2.1/%\(tenant_id\)s

	openstack endpoint create --region RegionOne \
	    compute admin http://$CTL_MGNT_IP:8774/v2.1/%\(tenant_id\)s

	sleep 5

	###  Neutron service
	printf ${GREEN}"Create  user, endpoint for Neutron"${NC}
	openstack user create neutron --domain default --password $NEUTRON_PASS

	openstack role add --project service --user neutron admin

	openstack service create --name neutron \
	    --description "OpenStack Networking" network

	openstack endpoint create --region RegionOne \
	    network public http://$CTL_MGNT_IP:9696

	openstack endpoint create --region RegionOne \
	    network internal http://$CTL_MGNT_IP:9696

	openstack endpoint create --region RegionOne \
	    network admin http://$CTL_MGNT_IP:9696

	exec bash create_network_CentOS7.sh

	echo "Openstack commands were run on $(date)." >> /tmp//os_logs/os_commands.log
done
sleep 3

printf ${bold}${BLUE}"Script Execution Time:${normal} $SECONDS seconds"${NC}
sleep 3
exit
