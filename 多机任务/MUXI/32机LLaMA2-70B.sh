#! /bin/bash
if [ -e /dev/infiniband/uverbs4 ] && [ ! -e /dev/infiniband/uverbs0 ]; then
    ln -s /dev/infiniband/uverbs4 /dev/infiniband/uverbs0
    ln -s /dev/infiniband/uverbs5 /dev/infiniband/uverbs1
    ln -s /dev/infiniband/uverbs6 /dev/infiniband/uverbs2
    ln -s /dev/infiniband/uverbs7 /dev/infiniband/uverbs3
    echo "Successfully aliased uverbs4-7 to uverbs0-3"
fi
# env variables
export LD_PRELOAD=${MACA_PATH}/lib/libmccl.so  
export MACA_PATH=/opt/maca
export MACA_CLANG_PATH=${MACA_PATH}/mxgpu_llvm/bin
export MACA_CLANG=${MACA_PATH}/mxgpu_llvm
export DEVINFO_ROOT=${MACA_PATH}
export CUCC_PATH=${MACA_PATH}/tools/cu-bridge
export CUDA_PATH=${CUCC_PATH}
export PATH=/opt/conda/bin:${CUCC_PATH}:${MACA_PATH}/bin:${MACA_CLANG}/bin:${PATH}
export LD_LIBRARY_PATH=${MACA_PATH}/lib:${MACA_PATH}/lib64:${MACA_PATH}/ompi/lib:${MACA_PATH}/mxgpu_llvm/lib:${LD_LIBRARY_PATH}


# env varilables for MCCL and RoCE
export MCCL_SOCKET_IFNAME=eth0          
export GLOO_SOCKET_IFNAME=eth0
export MCCL_IB_HCA=xscale_0,xscale_1,xscale_2,xscale_3 
export MCCL_IB_GID_INDEX=5              
export MCCL_IB_TC=128
#export MACA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export MCCL_FAST_WRITE_BACK=1
export MCCL_EARLY_WRITE_BACK=15
export MCCL_ENABLE_VSWITCH=1
export MCCL_CROSS_NIC=1                 
export MCCL_ALGO=Ring
# export MCCL_USE_FILE_TUNING=0                 
export MCCL_DEBUG=INFO
export MCCL_DEBUG_SUBSYS=GRAPH,INIT,NET

# CUDA and memory settings
export CUDA_DEVICE_MAX_CONNECTIONS=1
export MACA_SMALL_PAGESIZE_ENABLE=1
export MHA_USE_BLAS=ON
export MHA_BWD_NO_ATOMIC_F64=1
export SET_DEVICE_NUMA_PREFERRED=1
export MCPYTORCH_DISABLE_PRINT=1
export MALLOC_THRESHOLD=99

# Distributed training settings
NNODES=${WORLD_SIZE}
GPUS_PER_NODE=8
MASTER_PORT=${MASTER_PORT} 
MASTER_ADDR=${MASTER_ADDR}
NODE_RANK=${RANK}

# Parallel strategy
TP=8
PP=8
DP=$((${NNODES} * ${GPUS_PER_NODE} / ${TP} / ${PP}))


MODEL_SIZE=70
HIDDEN_SIZE=8192
NUM_HEAD=64
NUM_QUERY_GROUP=8
NUM_LAYERS=80
FFN_HIDDEN_SIZE=28672
NORM_EPS=1e-5

DROP_OUT=0.0
MAX_SEQ_LEN=4096
MAX_POSITION_EMBEDDINGS=4096

BASE_PATH=/workspace/Megatron-LM-0.8.0/examples
SRC_PATH=/workspace/Megatron-LM-0.8.0/pretrain_gpt.py
DATA_PATH=/data/llama2_7B/oscar-en-10k/oscar-en-10k-meg-llama_text_document
TOKENIZER_PATH=/data/llama2_7B/tokenizer/tokenizer.model

DATA_ARGS=" \
       --data-path ${DATA_PATH} \
       --split 1 \
       --seq-length ${MAX_SEQ_LEN} \
       --tokenizer-type Llama2Tokenizer \
       --tokenizer-model ${TOKENIZER_PATH} \
       "

LOG_NAME=llama2-70b_pretrain_WS${NNODES}_TP${TP}_PP${PP}_RoCE
LOG_PATH=${BASE_PATH}/log/${LOG_NAME}/node${NODE_RANK}.log
mkdir -p ${BASE_PATH}/log/${LOG_NAME}

LAUNCHER=" \
       torchrun \
       --nproc_per_node ${GPUS_PER_NODE} \
       --nnodes ${NNODES} \
       --node_rank ${NODE_RANK} \
       --master_addr ${MASTER_ADDR} \
       --master_port ${MASTER_PORT} \
       "

DISTRIBUTED_ARGS=" \
       --tensor-model-parallel-size ${TP} \
       --pipeline-model-parallel-size ${PP} \
       --use-distributed-optimizer \
       --sequence-parallel \
       "   

NETWORK_SIZE_ARGS=" \
       --num-layers ${NUM_LAYERS} \
       --hidden-size ${HIDDEN_SIZE} \
       --num-attention-heads ${NUM_HEAD} \
       --group-query-attention \
       --num-query-groups ${NUM_QUERY_GROUP} \
       --ffn-hidden-size ${FFN_HIDDEN_SIZE} \
       --max-position-embeddings ${MAX_POSITION_EMBEDDINGS} \
       --norm-epsilon ${NORM_EPS} \
       --normalization RMSNorm \
       --use-rotary-position-embeddings \
       --no-position-embedding \
       --swiglu \
       --untie-embeddings-and-output-weights \
       --transformer-impl local \
       --use-flash-attn \
       --use-qkv-flash-attn \
       --accumulate-bf16 \
       --use-flash-fusion \
       "

TRAINING_ARGS=" \
       --micro-batch-size 1 \
       --global-batch-size 1536 \
       --train-iters 500 \
       --disable-bias-linear \
       --log-interval 1 \
       --enable-zero-bubble \
       "

REGULATIZATION_ARGS="--attention-dropout 0.0 --hidden-dropout 0.0 --weight-decay 1e-2 --clip-grad 1.0"
INITIALIZATION_ARGS="--seed 1024 --init-method-std 0.02"
LEARNING_RATE_ARGS="--lr 1e-4 --lr-decay-style cosine --min-lr 1e-5"
MIXED_PRECISION_ARGS="--bf16"

CMD="${LAUNCHER} ${SRC_PATH} ${DISTRIBUTED_ARGS} ${NETWORK_SIZE_ARGS} ${TRAINING_ARGS} ${REGULATIZATION_ARGS} ${INITIALIZATION_ARGS} ${LEARNING_RATE_ARGS} ${MIXED_PRECISION_ARGS} ${DATA_ARGS}"

echo "Executing 24-node 70B Task..."
${CMD} 2>&1 | tee ${LOG_PATH}