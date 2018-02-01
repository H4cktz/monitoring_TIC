#!/bin/bash
echo $(ifconfig | grep -B1 "inet addr:10.240.142.177" | awk '$1!="inet" && $1!="--" {print $1}')