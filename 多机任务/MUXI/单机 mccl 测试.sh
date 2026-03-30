#!/bin/bash
export MACA_PATH=/opt/maca
export LD_LIBRARY_PATH=${MACA_PATH}/lib:${MACA_PATH}/ompi/lib
export FORCE_ACTIVE_WAIT=2
export MCCL_PCIE_BUFFER_MODE=0

GPU_NUM=4
if [[ $1 -gt 0 && $1 -lt 65 ]]; then
  GPU_NUM=$1
fi
TEST_DIR=${MACA_PATH}/samples/mccl_tests/perf/mccl_perf
BENCH_NAMES="all_reduce_perf all_gather_perf reduce_scatter_perf sendrecv_perf alltoall_perf"
#BENCH_NAMES=all_reduce_perf
MPI_PROCESS_NUM=${GPU_NUM}
MPI_RUN_OPT="--allow-run-as-root -mca pml ^ucx -mca osc ^ucx -mca btl ^openib"
for BENCH in ${BENCH_NAMES}; do
echo -n "The test is ${BENCH}, the maca version is " && realpath ${MACA_PATH}
${MACA_PATH}/ompi/bin/mpirun -x MCCL_PCIE_BUFFER_MODE -np ${MPI_PROCESS_NUM} ${MPI_RUN_OPT} ${TEST_DIR}/${BENCH} -b 1K -e 1G -d bfloat16 -f 2 -g 1 -n 10
done

# If wanna test all benchmarks, uncomment the following lines and the BENCH_NAMES variable above
# for BENCH in ${BENCH_NAMES}; do
# echo "Starting default ${BENCH} test..."
# ${MACA_PATH}/ompi/bin/mpirun -n ${CARD_NUM} --hostfile HOST_IP ${MPI_ENV} ${MCCL_ENV} \
#        bash -c "ulimit -n 1000000 && exec ${TEST_DIR}/${BENCH} -b 1K -e 1G -f 2 -n 10 -g 1"
# done
# echo "All tests completed."