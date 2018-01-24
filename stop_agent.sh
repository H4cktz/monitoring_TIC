#! /bin/bash
# stop docker
for i in `cat ${PWD}/nodes_list`; do
  tokens=(${i//:/ })
  ssh_address=${tokens[0]}
  ssh -t ${ssh_address} "docker rm -f tick_telegraf"
done
