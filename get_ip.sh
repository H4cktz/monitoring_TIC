#!/bin/bash
echo $(ifconfig | grep -B1 "inet addr:&REMOTE_ADDRESS" | awk '$1!="inet" && $1!="--" {print $1}')