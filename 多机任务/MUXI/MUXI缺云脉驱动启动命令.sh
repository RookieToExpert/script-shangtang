dpkg -i /mnt/xie/ibverbs-providers-xsc_47.7-1_amd64.deb
export http_proxy=http://10.140.3.216:5907/
export https_proxy=http://10.140.3.216:5907/
export HTTP_PROXY=http://10.140.3.216:5907/ 
export HTTPS_PROXY=http://10.140.3.216:5907/
apt install -y iproute2 && apt install -y infiniband-diags
cp /mnt/xie/show_gids /usr/bin/show_gids
chmod /usr/bin/show_gids
show_gids
ibv_devinfo
cd /opt/maca/samples/mccl_tests/perf
bash mccl.sh
cd /mnt/xie
bash multihostmccl.sh
sleep inf