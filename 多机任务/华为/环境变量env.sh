cat <<'EOF' > /root/mpi_env.sh
. /usr/local/Ascend/ascend-toolkit/set_env.sh

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:/usr/local/mpich-3.2.1/lib
rank=${PMI_RANK:-$OMPI_COMM_WORLD_RANK}
host=$(hostname)
export HCCL_BUFFSIZE=8096
export HCCL_LOGIC_SUPERPOD_ID=$(npu-smi info -t spod-info -i 0 -c 0 | grep -i 'Pod ID' | awk '{print $5}')
echo "HOST=$host, RANK=$rank, HCCL_LOGIC_SUPERPOD_ID=$HCCL_LOGIC_SUPERPOD_ID"
exec "$@"
EOF

chmod +x /root/mpi_env.sh

mkdir -p /var/run/sshd
/usr/sbin/sshd -p 22
sleep inf



export HCCL_IF_IP=$(hostname -i | awk '{print $1}')