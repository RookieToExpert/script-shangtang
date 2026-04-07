#!/bin/bash

RAW_HOST_LIST=$(echo "$VC_MASTER_HOSTS,$VC_WORKER_HOSTS,$MPI_HOST" | tr ',' '\n' | grep -v '^$' | sort -u)

echo "Step 1: Detecting Pod IDs and sorting hosts..."
TEMP_SORT_FILE=$(mktemp)

for host in $RAW_HOST_LIST; do
    POD_ID=$(ssh -o StrictHostKeyChecking=no $host "npu-smi info -t spod-info -i 0 -c 0 | grep -i 'Pod ID' | awk '{print \$5}'" 2>/dev/null)
    POD_ID=${POD_ID:-0} 
    echo "$POD_ID $host" >> "$TEMP_SORT_FILE"
    echo "Host $host is in Physical Pod $POD_ID"
done

SORTED_HOSTS=$(sort -n "$TEMP_SORT_FILE" | awk '{print $2}')
rm "$TEMP_SORT_FILE"

echo "Step 2: Resolving IPs in sorted order..."
HOST_FILE="/root/hostfile"
rm -f $HOST_FILE
TEMP_DIR=$(mktemp -d)

resolve_host() {
    local host=$1
    local out_file=$2
    local IP=$(getent hosts "$host" | awk '{print $1}' | head -n1)
    if [ -z "$IP" ]; then
        local SHORT_HOST=$(echo $host | cut -d'.' -f1)
        IP=$(getent hosts "$SHORT_HOST" | awk '{print $1}' | head -n1)
    fi
    if [ ! -z "$IP" ]; then
        echo "${IP}:16" > "$out_file"
    else
        echo "${host}:16" > "$out_file"
    fi
}

index=0
declare -a task_files
for host in $SORTED_HOSTS; do
    task_file="$TEMP_DIR/$index"
    task_files+=("$task_file")
    resolve_host "$host" "$task_file" &
    index=$((index + 1))
done
wait

for f in "${task_files[@]}"; do
    cat "$f" >> $HOST_FILE
done
rm -rf $TEMP_DIR

echo "------------------- Sorted Hostfile --------------------"
cat $HOST_FILE
echo "--------------------------------------------------------"
NODE_COUNT=$(cat $HOST_FILE | wc -l)
TOTAL_NPUS=$((NODE_COUNT * 16))
MPI_BIN=/usr/local/mpich-3.2.1/bin/mpirun
ENV_WRAPPER=/root/mpi_env.sh
TEST_BIN=/usr/local/Ascend/ascend-toolkit/8.1.RC1/tools/hccl_test/bin/all_reduce_test

export HYDRA_LAUNCHER_EXTRA_ARGS="-p 22 -o StrictHostKeyChecking=no"

echo "Launching HCCL test on $TOTAL_NPUS NPUs..."
$MPI_BIN -f $HOST_FILE -n $TOTAL_NPUS \
    $ENV_WRAPPER $TEST_BIN -p 16 -b 1G -e 8G -f 2 -w 5 -n 20 -c 1




