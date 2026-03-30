#!/bin/bash

source /usr/local/Ascend/ascend-toolkit/set_env.sh

MPI_BIN=/usr/local/mpich-3.2.1/bin/mpirun
TEST_BIN=/usr/local/Ascend/ascend-toolkit/8.1.RC1/tools/hccl_test/bin/all_reduce_test
HOST_FILE=./hostfile

export HCCL_SOCKET_IFNAME=eth0

export CPU_AFFINITY_CONF=1,npu0:12-25,npu1:26-39,npu2:52-65,npu3:66-79,npu4:92-105,npu5:106-119,npu6:132-145,npu7:146-159,npu8:172-185,npu9:186-199,npu10:212-225,npu11:226-239,npu12:252-265,npu13:266-279,npu14:292-305,npu15:306-319

export HCCL_DETERMINISTIC=1
export HCCL_OP_EXPANSION_MODE="AIV"
export HCCL_BUFFSIZE=2048           # 多机建议调大 buffer
export HCCL_INTRA_ROCE_ENABLE=1     # 显式开启 RoCE 通信

TOTAL_NPUS=32    # 总卡数 (16卡 * 2台)
NPUS_PER_NODE=16 # 每台机器的卡数

echo "--------------------------------------------------------"
echo "开始多机 32 卡 All-Reduce 测试"
echo "Hostfile: $HOST_FILE"
echo "--------------------------------------------------------"

$MPI_BIN -f ${HOST_FILE} -n ${TOTAL_NPUS} \
    -x LD_LIBRARY_PATH \
    -x PYTHONPATH \
    -x ASCEND_AICPU_PATH \
    -x HCCL_SOCKET_IFNAME \
    -x CPU_AFFINITY_CONF \
    -x HCCL_DETERMINISTIC \
    -x HCCL_OP_EXPANSION_MODE \
    -x HCCL_BUFFSIZE \
    -x HCCL_INTRA_ROCE_ENABLE \
    ${TEST_BIN} \
    -b 1K \
    -e 8G \
    -f 2 \
    -d fp16 \
    -o sum \
    -n 20 \
    -p ${NPUS_PER_NODE} \
    -c 1