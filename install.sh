#!/bin/bash

#######
## Openshift 3.11 install script
## Author srikant noorani @ broadcom.com
## Dec 16th, 2020
########

######## INSTRUCTIONS ######
### 1. Provide your master and node IPs. 
### 2. Replace with your hostname (fqdn ) in host.ini file
### 3. ensure passwordless access between master and nodes
### 4. both install.sh and host.ini has be under /root/OpenShiftInstall folder ( sorry its hardcoded)
### 5. Run the same ./install.sh twice .. once before the reboot one after ...
######

MAIN_FOLDER=`dirname $BASH_SOURCE`

export MASTER="10.x.x.x"
export NODES="10.x.x.x 10.x.x.x 10.x.x.x"
export ALL_SYSTEMS="$NODES  $MASTER "

#. $MAIN_FOLDER/scripts/include.sh

clear
echo "Ensure its a fresh Linux System with passwordless access enabled between masters and nodes and firewall disabled completely on all nodes. "
echo "pls open install.sh file and read through the instructions at the TOP before proceeding .. Press Enter to continue OR Ctr-C"

read

prepMaster () {

	echo "installing Ansible 2.9"

	yum -y groupinstall "Development Tools"
	yum -y install python-virtualenv libffi-devel openssl-devel
	mkdir ~/.virtual_envs
	cd ~/.virtual_envs
	virtualenv ansible

	. ~/.virtual_envs/ansible/bin/activate

	pip install -U pip
	pip install -U setuptools
	pip install 'ansible==2.9'

	ansible --version

	echo " Ansible Installed - Ansible version " + `ansible --version`

	yum install -y nfs-server

	sleep 5
}


prepOSENodes () {
	echo "Preparing the OSE nodes"

	remoteExecutor -a "yum -y update"
	remoteExecutor -a "systemctl stop firewalld; systemctl disable firewalld"
	remoteExecutor -a "yum remove -y docker-ce docker-ce-cli dnsmasq"
	remoteExecutor -a "yum install -y wget git net-tools bind-utils yum-utils nfs-utils iptables-services bridge-utils bash-completion kexec-tools sos psacct docker-1.13.1 dnsmasq"
        remoteExecutor -a "systemctl enable docker; systemctl start docker"
    	remoteExecutor -a "systemctl stop firewalld; systemctl disable firewalld"
        remoteExecutor -a "sudo ln -s /usr/libexec/docker/docker-runc-current /usr/bin/docker-runc"
        remoteExecutor -a "echo NM_CONTROLLED=yes >> /etc/sysconfig/network-scripts/ifcfg-eth0"
        remoteExecutor -a "touch /.autorelabel"
        remoteExecutor -a "sed -i 's/=disabled/=enforcing/g' /etc/selinux/config"
	remoteExecutor -a "echo \"nameserver `hostname -i`\" >> /etc/resolv.conf"

}


rebootAllSystems () {
	echo "Rebooting all sysmtems - Press Enter or Ctrl-C"
        read
	remoteExecutor -a "reboot"
}


verifyOSENodes () {

	echo "Verify OSE nodes Post reboot"

	remoteExecutor -a "systemctl stop firewalld; systemctl disable firewalld"
	remoteExecutor -a "cat /etc/sysconfig/network-scripts/ifcfg-eth0"
	remoteExecutor -a "cat /etc/selinux/config"
	remoteExecutor -a "cat /etc/resolv.conf"
}


onOSEFailures () {
	echo "When OSE fails - do the following two "
	echo "    nameserver <YOUR_NAMESERVER> > /etc/origin/node/resolv.conf "
	echo "    open /root/openshift-ansible/roles/calico/tasks/certs.yml and remove \"become\" in line 24"
}


installOpenShift () {
	echo "installing OSE - step 1 - clone OSE from git. Step 2 install OSE"

	cd ~
	git clone https://github.com/openshift/openshift-ansible
	cd openshift-ansible
	git checkout release-3.11

	sed -i '/become:/d' ~/openshift-ansible/roles/calico/tasks/certs.yml

	. ~/.virtual_envs/ansible/bin/activate

	ansible-playbook -i ~/OpenShiftInstall/hosts.ini ~/openshift-ansible/playbooks/prerequisites.yml


	echo ""
	echo ""
	echo "OSE Pre-Req Done .. starting OSE cluster Deploy... Press Enter"

	read

	ansible-playbook -i ~/OpenShiftInstall/hosts.ini ~/openshift-ansible/playbooks/deploy_cluster.yml -vvv
}


remoteExecutor () {

	COMMANDS=$2

	#Execute only on Nodes
	if [ x"$1" != "x-a" ]; then
		export ALL_SYSTEMS=$NODES
	fi

	for i in $ALL_SYSTEMS
	do
  		printf "\n** $i : $COMMANDS\n"
  		ssh $i "$COMMANDS"
	done

	printf "\n"
}

remoteSCP () {
	SOURCE=$1
	DESTINATION=$2

	#Execute only on Nodes
	if [ x"$1" != "x-a" ]; then
		export ALL_SYSTEMS=$NODES
	fi

	for host in $ALL_SYSTEMS; do printf "\n** $host : $SOURCE $DESTINATION \n"; scp "$SOURCE" root@$host:$DESTINATION; done
}



if [ -f ~/.osePhase1Done ]; then
####OSE install Phase-2 - After the Reboot

	echo "OSE install Post-Reboot Phase Starting ..."

	verifyOSENodes

	echo "press enter if all looks good"
	read

	installOpenShift

	#echo "nameserver 192.x.x.x" >> /etc/origin/node/resolv.conf

	/bin/rm ~/.osePhase1Done
else
####OSE install Phase-1 - Before the Reboot

	echo "OSE Pre-Reboot Phase Starting ..."
	prepMaster

	prepOSENodes

	touch ~/.osePhase1Done
	rebootAllSystems
fi
