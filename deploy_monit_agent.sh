USER=$1
# for i in `cat /etc/hosts | grep hadoop | awk '{print $2}'`; do
for i in `cat hosts`; do
  # install docker
  ssh -t $USER@$i "export http_proxy=\"http://10.240.142.150:8443\" && export https_proxy=\"http://10.240.142.150:8443\" wget -qO- https://get.docker.com/ | sh"
  scp google_cadvisor_img $USER@$i:/home/$USER/google_cadvisor_img
  ssh -t $USER@$i "sudo docker load -i /home/vtadmin/google_cadvisor_img && sudo docker tag f9ba08bafdea google/cadvisor:latest"
  ssh -t $USER@$i "export HOSTNAME=$i && sudo docker run --hostname $i --volume=/:/rootfs:ro --volume=/var/run:/var/run:rw --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro --volume=/dev/disk/:/dev/disk:ro    --detach=true   --name=cadvisor  google/cadvisor:latest -logtostderr -docker_only -storage_driver=influxdb -storage_driver_db=cadvisor -storage_driver_host=10.240.152.164:8086"
done



for i in {1..1000}; do
  curl -X POST \
    -H 'Authorization: Bearer d61c66ef801583c07299b041aac78436' \
    -H 'cache-control: no-cache' \
    -H 'Content-Type: application/json' \
    -H 'Connection: keep-alive' \
    -H 'Host: hoidap.itrithuc.vn' \
    -H 'Accept: application/json, text/javascript, */*; q=0.01' \
    -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0' \
    -d '{"title": "Test.", "img_cover_url": "http://image.url"}' \
    https://hoidap.itrithuc.vn/qa/questions
done
