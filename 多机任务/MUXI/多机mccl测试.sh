#!/bin/bash
MACA_PATH=/opt/maca
HOST_IP=$1
# Define RBAC network device and parameters
# IP_MASK=10.120.0.0/16
IP_MASK=eth0
IB_PORT=xscale_0,xscale_1,xscale_2,xscale_3
SOCKET_NIC=eth0
GID_INDEX=5
CARD_NUM=$2

# Define the benchmark test path and name
TEST_DIR=${MACA_PATH}/samples/mccl_tests/perf/mccl_perf
#BENCH_NAMES="all_reduce_perf all_gather_perf reduce_scatter_perf sendrecv_perf alltoall_perf"
BENCH_NAME=all_reduce_perf

LIB_PATH_ENV="-x LD_LIBRARY_PATH=${MACA_PATH}/lib:${MACA_PATH}/lib64:${MACA_PATH}/ompi/lib"
MCCL_ENV="-x MCCL_IB_GID_INDEX=${GID_INDEX} \
-x MCCL_IB_TC=128 \
-x MCCL_FAST_WRITE_BACK=1 \
-x MCCL_EARLY_WRITE_BACK=15 \
-x MCCL_CROSS_NIC=1 \
-x MCCL_ALGO=Ring \
-x MCCL_ENABLE_VSWITCH=1 \
-x MCCL_SOCKET_IFNAME=${SOCKET_NIC} \
-x MCCL_IB_HCA=${IB_PORT} \
${LIB_PATH_ENV} \
-x MCCL_USE_FILE_TUNING=0 \
-x FORCE_ACTIVE_WAIT=2 \
-x MCCL_SHM_DISABLE=1 \
-x MCCL_PCIE_BUFFER_MODE=0 \
-x MCCL_LIMIT_RING_LL_THREADTHRESHOLDS=1"

MPI_ENV="--allow-run-as-root \
-mca plm_rsh_num_concurrent 256 \
-mca pml ^ucx \
-mca btl ^openib \
-mca routed direct \
-mca osc ^ucx \
-mca btl_tcp_if_include ${IP_MASK} \
-mca oob_tcp_if_include ${IP_MASK}"
                  
echo "Starting default all reduce test..."
${MACA_PATH}/ompi/bin/mpirun -n ${CARD_NUM} --hostfile $HOST_IP ${MPI_ENV} ${MCCL_ENV} \
       bash -c "ulimit -n 1000000 && exec ${TEST_DIR}/${BENCH_NAME} -b 1G -e 8G -f 2 -n 20 -w 10"

# If wanna test all benchmarks, uncomment the following lines and the BENCH_NAMES variable above
# for BENCH in ${BENCH_NAMES}; do
# echo "Starting default ${BENCH} test..."
# ${MACA_PATH}/ompi/bin/mpirun -n ${CARD_NUM} --hostfile HOST_IP ${MPI_ENV} ${MCCL_ENV} \
#        bash -c "ulimit -n 1000000 && exec ${TEST_DIR}/${BENCH} -b 1K -e 1G -f 2 -n 10 -g 1"
# done
# echo "All tests completed."



