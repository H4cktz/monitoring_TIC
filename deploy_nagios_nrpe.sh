#! /bin/bash
DIR=$PWD
PROXY_CMD='export http_proxy="http://10.240.142.150:8443" && export https_proxy="http://10.240.142.150:8443"'
NAGIOS_ADDRESS=10.240.152.164

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist"
}

install_sys_libs() {
  echo "Copy SysLibs"
  scp -r nrpe/Sys-Statistics-Linux-0.66.tar.gz $ssh_address:/${tokens[1]}  
  ssh -t $ssh_address "mkdir -p /"${tokens[1]}"/sys_linux  && tar -xvf /"${tokens[1]}"/Sys-Statistics-Linux-0.66.tar.gz -C /"${tokens[1]}"/sys_linux/ && cd /"${tokens[1]}"/sys_linux/Sys-Statistics-Linux-0.66/ && perl Makefile.PL && make -f /"${tokens[1]}"/sys_linux/Sys-Statistics-Linux-0.66/Makefile && sudo make install -f /"${tokens[1]}"/sys_linux/Sys-Statistics-Linux-0.66/Makefile"
}

for i in `cat ${DIR}/nodes_list`; do  
  if [[ "$i" = *"#"* ]]; then
    continue
  fi
  echo "---------------------------------------"  
  tokens=(${i//:/ })
  tokens_2=(${tokens[0]//@/ })
  ssh_address=${tokens[0]}
  node_address=${tokens_2[1]}  
  echo "Start $node_address"
  
  
  echo "Copy NRPE config"
  scp -r nrpe/nrpe.cfg $ssh_address:/${tokens[1]}  
  # echo "Install NRPE agent"
  # ssh -t $ssh_address "${PROXY_CMD} && sudo apt-get install -y nagios-plugins nagios-nrpe-server"
  
  INTERFACE_NAME=$(ssh srv_177 "bash -s" < get_ip.sh)

  echo "Copy NRPE libs"
  scp -r nrpe/nrpe_libs/* $ssh_address:/${tokens[1]}/nrpe_libs
  ssh -t $ssh_address "sudo cp -ar /"${tokens[1]}"/nrpe_libs/. /usr/lib/nagios/plugins/ && sudo chmod +x -R /usr/lib/nagios/plugins/"
  
  echo "Modify NRPE config"
  ssh -t $ssh_address "sed -i -e 's/&REMOTE_NET_INF/"${INTERFACE_NAME}"/g' /"${tokens[1]}"/nrpe.cfg && sed -i -e 's/&REMOTE_ADDRESS/"${node_address}"/g' /"${tokens[1]}"/nrpe.cfg && sed -i -e 's/&NAGIOS_ADDRESS/"${NAGIOS_ADDRESS}"/g' /"${tokens[1]}"/nrpe.cfg && sudo cp /"${tokens[1]}"/nrpe.cfg /etc/nagios/nrpe.cfg"
  
  echo "Restart NRPE agent"
  ssh -t $ssh_address "sudo service nagios-nrpe-server restart"
  # echo "Open port"
  # ssh -t $ssh_address "sudo iptables -A INPUT -p tcp -m state --state NEW --dport 5666 -j ACCEPT && sudo iptables -A OUTPUT -p tcp -m state --state NEW --dport 5666 -j ACCEPT"  
  echo "Done $node_address"
done
echo "========== DONE =========="
# sudo cp -ar /home/huanpc/nrpe_libs/. /usr/lib/nagios/plugins/ && sudo chmod +x -R /usr/lib/nagios/plugins/ && sudo cp /home/huanpc/nrpe.cfg /etc/nagios/nrpe.cf && sudo service nagios-nrpe-server restart

