# TICK (Telegraf + InfluxDB + Chronograf + Kapacitor)

# Nagios Alert

## Nagios Server

1. Copy `nagios/etc`, `nagios/ext_bin`, `nagios/ext_lib`, `data/nagios4.tar` to Nagios server
2. Run 
```sh
$ docker load -i nagios4.tar
```
3. Run 
```sh
$ docker run -d -v ~/nagios/etc/:/opt/nagios/etc/ -v ~/nagios/ext_bin:/opt/nagios/ext_bin  -v ~/nagios/ext_lib/check_mongodb.py:/opt/nagios/libexec/check_mongodb.py --name nagios4 -p 8443:80 -p 5667:5666 nagios4
```


## Nagios Agent

## Presequite

1. Public key is installed and your host can ssh to remote servers.
2. Nagios server is running.
3. Port `5666` in the remote servers are availble and open for input/output network.

### Install

1. Correct `node_list` with real server address
2. Run `deploy_nagios_nrpe.sh`