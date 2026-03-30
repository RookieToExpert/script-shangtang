cat <<'EOF' > /root/mpi_env.sh
. /usr/local/Ascend/ascend-toolkit/set_env.sh
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:/usr/local/mpich-3.2.1/lib
export CPU_AFFINITY_CONF=1,npu0:12-25,npu1:26-39,npu2:52-65,npu3:66-79,npu4:92-105,npu5:106-119,npu6:132-145,npu7:146-159,npu8:172-185,npu9:186-199,npu10:212-225,npu11:226-239,npu12:252-265,npu13:266-279,npu14:292-305,npu15:306-319
export HCCL_BUFFERSIZE=8192
export HCCL_SUPERPOD_MODE=1
export HCCL_LOGIC_SUPERPOD_ID=$(npu-smi info -t spod-info -i 0 -c 0 | grep -i 'Pod ID' | awk '{print $5}')
export HCCL_IF_IP=$(hostname -i | awk '{print $1}')
exec "$@"
EOF

chmod +x /root/mpi_env.sh

mkdir -p /var/run/sshd
/usr/sbin/sshd -p 2222