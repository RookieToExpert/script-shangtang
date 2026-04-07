#!/bin/bash

echo "Generating dynamic IP-based hostfile..."

# 1. 移除 sort -u，改用 tr 将逗号换成换行，并保持环境变量中的原始顺序
# 通常环境变量里的顺序是 master-0, worker-0, worker-1... 这样最符合 rank 逻辑
RAW_HOSTS=$(echo "$VC_MASTER_HOSTS,$VC_WORKER_HOSTS,$MPI_HOST" | tr ',' '\n' | grep -v '^$' | awk '!x[$0]++')

HOST_FILE="/root/hostfile"
rm -f $HOST_FILE
TEMP_DIR=$(mktemp -d)

resolve_host() {
    local host=$1
    local out_file=$2
    
    # 尝试解析 IP
    local IP=$(getent hosts "$host" | awk '{print $1}' | head -n1)
    
    if [ -z "$IP" ]; then
        local SHORT_HOST=$(echo $host | cut -d'.' -f1)
        IP=$(getent hosts "$SHORT_HOST" | awk '{print $1}' | head -n1)
    fi

    # 写入结果到临时文件
    if [ ! -z "$IP" ]; then
        echo "${IP}:16" > "$out_file"
    else
        echo "${host}:16" > "$out_file"
        echo "Warning: Could not resolve $host" >&2
    fi
}

echo "Resolving hosts in parallel while preserving order..."

# 2. 发起并行任务，使用数字索引作为文件名
index=0
for host in $RAW_HOSTS; do
    resolve_host "$host" "$TEMP_DIR/$index" &
    index=$((index + 1))
done

# 等待所有后台任务完成
wait

# 3. 关键修复：按数字顺序循环读取临时文件，而不是使用 * 通配符
# 这样能确保 rank 0 永远是第一个 host，rank 1 是第二个，以此类推
total_count=$index
for ((i=0; i<total_count; i++)); do
    if [ -f "$TEMP_DIR/$i" ]; then
        cat "$TEMP_DIR/$i" >> "$HOST_FILE"
    fi
done

rm -rf $TEMP_DIR

echo "----------------------------------------------------"
cat $HOST_FILE
echo "----------------------------------------------------"

HOST_FILE="/root/hostfile"
NODE_COUNT=$(cat $HOST_FILE | wc -l)
TOTAL_NPUS=$((NODE_COUNT * 16))
MPI_BIN=/usr/local/mpich-3.2.1/bin/mpirun
ENV_WRAPPER=/root/mpi_env.sh
TEST_BIN=/usr/local/Ascend/ascend-toolkit/8.1.RC1/tools/hccl_test/bin/all_reduce_test

export HYDRA_LAUNCHER_EXTRA_ARGS="-p 22 -o StrictHostKeyChecking=no"

echo "Launching HCCL test on $TOTAL_NPUS NPUs..."
$MPI_BIN -f $HOST_FILE -n $TOTAL_NPUS \
    $ENV_WRAPPER $TEST_BIN -p 16 -b 1G -e 8G -f 2 -w 5 -n 20 -c 1
    


# mpirun  --hostfile /root/hostfile  -n 1536 /root/mpi_env.sh /usr/local/Ascend/ascend-toolkit/8.1.RC1/tools/hccl_test/bin/all_reduce_test -p 16 -b 1G -e 16G -f 2 -w 5 -n 20 -c 1