#! /bin/bash
DIR=$PWD
for i in `cat ${DIR}/nodes_list`; do  
  tokens=(${i//:/ })
  tokens_2=(${tokens[0]//@/ })
  ssh_address=${tokens[0]}  
  node_address=${tokens_2[1]}
#   ssh -t $ssh_address "mkdir -p ~/tick_agent"
#   scp -r ${DIR}/data/* $ssh_address:/${tokens[1]}/tick_agent
  ssh -t $ssh_address 'docker load --input '${tokens[1]}'/tick_agent/telegraf.v1.5.tar && docker run -d --name tick_telegraf -v '${tokens[1]}'/tick_agent/telegraf.conf:/etc/telegraf/telegraf.conf:ro -h "$(hostname)"_'${node_address}' telegraf:1.5'
done

# docker run -d --name tick_telegraf -v $PWD/telegraf.conf:/etc/telegraf/telegraf.conf:ro -h ${HOSTNAME} -e OUTPUTS_INFLUXDB_URLS=udp://10.240.152.164:8089 telegraf:1.5
# docker save -o telegraf.v1.5.tar telegraf:1.5
# 