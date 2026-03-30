export http_proxy=http://10.140.3.216:5907/
export https_proxy=http://10.140.3.216:5907/
export HTTP_PROXY=http://10.140.3.216:5907/ 
export HTTPS_PROXY=http://10.140.3.216:5907/
apt install -y iproute2 && apt install -y infiniband-diags && apt install -y vim
/usr/sbin/sshd -p 22 -D &
sleep 20
echo "$VC_MASTER_HOSTS,$MPI_HOST" | tr ',' '\n' | sed 's/$/ slots=8/' > /hostfile2
sysctl -w net.core.somaxconn=1000000
ulimit -n 1000000
sleep inf
