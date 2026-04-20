set -ex
ray stop --force
# examples of usage:
# qwen3_8B_grpo_gsm8k training: bash examples/v1/scripts/run_rl.sh examples/v1/config/rl_qwen3_8B_grpo.py "sglang" $MODEL_PATH $DATA_PATH $EVAL_DATA_PATH
# qwen2.5_7B_dapo_math training: bash examples/v1/scripts/run_rl.sh  examples/v1/config/rl_qwen25_7B_dapo.py "sglang" $MODEL_PATH $DATA_PATH $EVAL_DATA_PATH
source /usr/local/Ascend/ascend-toolkit/set_env.sh

CONFIG_PATH="./examples/v1/config/rl_qwen3_30B_grpo.py"
INFER_BACKEND="vllm"
MODEL_PATH="/mnt/huawei/weight/Qwen3-30B-A3B"
DATA_PATH="/mnt/hw-linyifei2/nengx/datasets/gsm8k/train.jsonl"
# EVAL_DATA_PATH=${5:-""}
ACCELERATOR=${6:-"npu"} # "gpu" or "npu"
ACCELERATOR=$(echo "$ACCELERATOR" | tr '[:lower:]' '[:upper:]')
if [ $ACCELERATOR != "GPU" ] && [ $ACCELERATOR != "NPU" ]; then
  echo "Error: ACCELERATOR must be either 'gpu' or 'npu'!"
  exit 1
fi
if [ "$ACCELERATOR" = "NPU" ]; then
  ACCELERATOR_PER_NODE=${7:-16}
else
  ACCELERATOR_PER_NODE=${7:-8}
fi

export PYTHONPATH=$(pwd):$PYTHONPATH
# NOTE: if you add new env vars, please also add them to RUNTIME_ENV_JSON in step 4.
# master 节点的 IP 地址
export MASTER_PORT=6000
export WORLD_SIZE=$NODE_COUNT
export RANK=$NODE_RANK
export RAY_MASTER_ADDR=${MASTER_ADDR:-"127.0.0.1"}
# 0 代表主节点, >0 代表工作节点
export RAY_RANK=${RANK:-0}
export RAY_HEAD_PORT=${RAY_HEAD_PORT:-"6379"}
export RAY_CLIENT_PORT=${RAY_CLIENT_PORT:-"10001"}
export RAY_DASHBOARD_PORT=${RAY_DASHBOARD_PORT:-"8265"}
# TODO: 提供非环境变量方式配置 ray_max_concurrency
export RAY_MAX_CONCURRENCY=${RAY_MAX_CONCURRENCY:-1024} # dataflow_max_concurrency * prompt_repeat_k

export MODEL_PATH=$MODEL_PATH
export DATA_PATH=$DATA_PATH
export EVAL_DATA_PATH=$EVAL_DATA_PATH
export XTUNER_USE_FA3=${XTUNER_USE_FA3:-1}
export XTUNER_LOG_LEVEL=${XTUNER_LOG_LEVEL:-"INFO"}
export PYTHONUNBUFFERED=1

yum install dnsutils -y
source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /usr/local/Ascend/nnal/atb/set_env.sh --cxx_abi=1
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver
export CPU_AFFINITY_CONF=0

export PYTHONUNBUFFERED=1

export HF_HOME=/workspace

export HF_DATASETS_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_EVALUATE_OFFLINE=1
export HF_HUB_OFFLINE=1

#export XTUNER_USE_FA3=1
export XTUNER_MAX_CONCURRENCY=8192
export XTUNER_LOG_LEVEL="INFO"
export UVICORN_LOG_LEVEL="CRITICAl"
export PYTORCH_NPU_ALLOC_CONF="expandable_segments:True"
export XTUNER_USE_SGLANG=0
export XTUNER_USE_LMDEPLOY=0
export XTUNER_USE_VLLM=1
export VLLM_VERSION=0.11.0

export MASTER_PORT=6000
export VLLM_USE_V1=1
export WORLD_SIZE=$WORLD_SIZE
export RANK=$RANK
export TORCH_HCCL_ZERO_COPY=1
unset TORCH_HCCL_ZERO_COPY
export XTUNER_ACTIVATION_OFFLOAD=1
#export monitor_path=/mnt/huawei/wjw/rl_partial_rollout/rollout_vllm_bs64_0307.json
#export monitor_path=/mnt/huawei/wjw/rl_partial_rollout/rollout_entropy_2048_vllm_single_410_fixed_0307_greedy_2.json
export RAY_MAX_CONCURRENCY=2048
export RAY_CGRAPH_get_timeout=3600
 
infer_backend_lower=$(echo "$INFER_BACKEND" | tr '[:upper:]' '[:lower:]')
if [ "$infer_backend_lower" = "sglang" ]; then
  export XTUNER_USE_SGLANG=1
  unset PYTORCH_CUDA_ALLOC_CONF
  export SGLANG_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN=1
elif [ "$infer_backend_lower" = "lmdeploy" ]; then
  export XTUNER_USE_LMDEPLOY=1
  export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'
  export PYTHONPATH=$LMDEPLOY_PATH:$PYTHONPATH
elif [ "$infer_backend_lower" = "vllm" ]; then
  export XTUNER_USE_VLLM=1
  export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'
else
  echo "Error: INFER_BACKEND '$INFER_BACKEND' is not supported or not specified!"
  exit 1
fi 

current_time=$(date "+%m%d%H")
# 取模型路径的最后一级作为model_name，取数据路径的倒数第二级作为data_name
model_dir_name=$(basename "$MODEL_PATH")
data_dir_name=$(basename "$(dirname "$DATA_PATH")")
DIR=$(pwd)
export WORK_DIR="${DIR}/work_dirs/${model_dir_name}_${data_dir_name}_${infer_backend_lower}"
if [ ! -d "$WORK_DIR" ]; then
  mkdir -p "$WORK_DIR"
fi
export LMDEPLOY_LOG_FILE="${WORK_DIR}/lmdeploy_log_${current_time}.txt"
if [ "$ACCELERATOR" = "GPU" ]; then
    # TODO: support NPU RL Memory Monitor
    export XTUNER_RL_MEM_DIR="${WORK_DIR}/mem_${current_time}"
fi

# 2. Launch Ray cluster
# 根据 NODE_COUNT 分配 num_cpus, 防止内存OOM
# node_count=${NODE_COUNT:-1}
# if [ "$ACCELERATOR" = "GPU" ]; then
#   total_cpus=$((node_count * 128))
# elif [ "$ACCELERATOR" = "NPU" ]; then
#   total_cpus=$((node_count * 256))
# fi

# if [ "$RAY_RANK" -eq 0 ]; then
#   rm -rf /tmp/ray_log
#   export RAY_LOG_DIR="${WORK_DIR}/ray_${current_time}/"
#   mkdir -p ${RAY_LOG_DIR}
#   ln -sfn "${RAY_LOG_DIR}" /tmp/ray_log 
#   ray start --head \
#     --node-ip-address="$RAY_MASTER_ADDR" \
#     --port="$RAY_HEAD_PORT" \
#     --dashboard-host=0.0.0.0 \
#     --dashboard-port=$RAY_DASHBOARD_PORT \
#     --include-dashboard=true \
#     --disable-usage-stats \
#     --num-cpus=$total_cpus \
#     --temp-dir="/tmp/ray_log/"
# else
#   while true; do
#     if curl --connect-timeout 2 "http://${RAY_MASTER_ADDR}:${RAY_DASHBOARD_PORT}" >/dev/null 2>&1; then
#       echo "Successfully connected to Ray master at ${RAY_MASTER_ADDR}:${RAY_DASHBOARD_PORT}"
#       break
#     else
#       echo "Waiting for Ray master at ${RAY_MASTER_ADDR}:${RAY_DASHBOARD_PORT} to be available..."
#       sleep 2
#     fi
#   done
#   ray start --address="$RAY_MASTER_ADDR:$RAY_HEAD_PORT" --block --disable-usage-stats
# fi

# while true; do
#   result=$(ray status | grep ${ACCELERATOR} | cut -d ' ' -f2 | cut -d '/' -f2)
#   expected_accelerator_count=$((node_count * ${ACCELERATOR_PER_NODE}))
#   if [ "$result" = "$expected_accelerator_count.0" ]; then
#     break
#   else
#     echo "Waiting for ${ACCELERATOR} count to be $expected_accelerator_count, current: $result"
#     sleep 2
#   fi
# done

# SCRIPT_NAME=$(basename "$0")
# cp "$0" "${WORK_DIR}/${SCRIPT_NAME}"
# cp "$CONFIG_PATH" "${WORK_DIR}/config.py"
# LOG_FILE="${WORK_DIR}/training_log_${current_time}.txt"

# # 3. Submit training job on Head node
# if [ "$RAY_RANK" -eq 0 ]; then
#   RUNTIME_ENV_JSON="{
#       \"env_vars\": {
#         \"WORK_DIR\": \"${WORK_DIR}\",
#         \"MODEL_PATH\": \"${MODEL_PATH}\",
#         \"DATA_PATH\": \"${DATA_PATH}\",
#         \"EVAL_DATA_PATH\": \"${EVAL_DATA_PATH}\",
#         \"XTUNER_USE_FA3\": \"${XTUNER_USE_FA3}\",
#         \"XTUNER_MAX_CONCURRENCY\": \"${XTUNER_MAX_CONCURRENCY}\",
#         \"XTUNER_LOG_LEVEL\": \"${XTUNER_LOG_LEVEL}\",
#         \"PYTHONPATH\": \"${PYTHONPATH}\",
#         \"MASTER_ADDR\": \"${RAY_MASTER_ADDR}\",
#         \"XTUNER_USE_SGLANG\": \"${XTUNER_USE_SGLANG:-}\",
#         \"XTUNER_USE_LMDEPLOY\": \"${XTUNER_USE_LMDEPLOY:-}\",
#         \"XTUNER_USE_VLLM\": \"${XTUNER_USE_VLLM:-}\",
#         \"PYTORCH_CUDA_ALLOC_CONF\": \"${PYTORCH_CUDA_ALLOC_CONF:-}\",
#         \"CUDA_DEVICE_MAX_CONNECTIONS\": \"1\",
#         \"PYTHONUNBUFFERED\": \"1\",
#         \"SGLANG_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN\": \"1\"
#       }
#     }"

#   ray job submit --address="http://127.0.0.1:$RAY_DASHBOARD_PORT" \
#        --runtime-env-json="$RUNTIME_ENV_JSON" \
#        -- python xtuner/v1/train/cli/rl.py \
#        --config $CONFIG_PATH \
#        2>&1 | tee -a "$LOG_FILE"

#   echo "训练任务提交完成。日志文件: $LOG_FILE"
# fi
node_count=${WORLD_SIZE:-1}
total_cpus=$((node_count * 256))

if [ "$RAY_RANK" -eq 0 ]; then
  RAY_memory_monitor_refresh_ms=0 ray start --head \
    --node-ip-address="$RAY_MASTER_ADDR" \
    --port="$RAY_HEAD_PORT" \
    --dashboard-host=0.0.0.0 \
    --dashboard-port=$RAY_DASHBOARD_PORT \
    --include-dashboard=true \
    --disable-usage-stats \
    --num-cpus=$total_cpus
else
  RAY_RESOLVED_IP=$(nslookup $MASTER_ADDR | awk '/^Address: / { addr=$2 } END { print addr }')
  if [ -z "$RAY_RESOLVED_IP" ]; then
      echo "Warning: nslookup failed, falling back to original MASTER_ADDR"
      RAY_RESOLVED_IP=$MASTER_ADDR
  fi
  echo "Resolved Master IP from $MASTER_ADDR: $RAY_RESOLVED_IP"
  WAIT_TIME=$(awk "BEGIN {print 10 + 1.5 * $RAY_RANK}")
  echo "Rank $RAY_RANK is sleeping for $WAIT_TIME seconds before connecting to Head..."
  sleep $WAIT_TIME
  export RAY_gcs_rpc_server_reconnect_timeout_s=600
  export RAY_gcs_grpc_max_reconnect_attempts=100
  export RAY_rpc_grpc_timeout_ms=30000
  RAY_memory_monitor_refresh_ms=0 ray start --address="$RAY_RESOLVED_IP:$RAY_HEAD_PORT" \
              --node-ip-address="$(hostname -i)" \
              --block \
              --disable-usage-stats
fi

sleep 10

OUTPUT_DIR=/mnt/hw-linyifei2/nengx/rl_log/rl_qwen3_output/$(date "+%Y%m%d_%H%M%S")
mkdir -p $OUTPUT_DIR

SCRIPT_NAME=$(basename "$0")
cp "$0" "${OUTPUT_DIR}/${SCRIPT_NAME}"
cp "$CONFIG_PATH" "${OUTPUT_DIR}/config.py"

echo OUPUT_DIR is ${OUTPUT_DIR}
# 4. Submit training job on Head node
        #\"XTUNER_USE_FA3\": \"${XTUNER_USE_FA3}\",
        #\"PYTORCH_CUDA_ALLOC_CONF\": \"${PYTORCH_CUDA_ALLOC_CONF:-}\",
if [ "$RAY_RANK" -eq 0 ]; then
  RUNTIME_ENV_JSON="{
      \"env_vars\": {
        \"XTUNER_MAX_CONCURRENCY\": \"${XTUNER_MAX_CONCURRENCY}\",
        \"XTUNER_LOG_LEVEL\": \"${XTUNER_LOG_LEVEL}\",
        \"PYTHONPATH\": \"${PYTHONPATH}\",
        \"MASTER_ADDR\": \"${RAY_MASTER_ADDR}\",
        \"XTUNER_USE_SGLANG\": \"${XTUNER_USE_SGLANG:-}\",
        \"XTUNER_USE_LMDEPLOY\": \"${XTUNER_USE_LMDEPLOY:-}\",
        \"XTUNER_USE_VLLM\": \"${XTUNER_USE_VLLM:-}\",
        \"PYTORCH_NPU_ALLOC_CONF\": \"${PYTORCH_NPU_ALLOC_CONF:-}\",
        \"CUDA_DEVICE_MAX_CONNECTIONS\": \"1\",
        \"RAY_CGRAPH_get_timeout\": \"3600\"
      }
    }"

  ray job submit --address="http://127.0.0.1:$RAY_DASHBOARD_PORT" \
       --runtime-env-json="$RUNTIME_ENV_JSON" \
       -- python xtuner/v1/train/cli/rl.py \
       --config $CONFIG_PATH \
       2>&1 | tee -a "${OUTPUT_DIR}/training_log.txt"
  # echo $WORK_DIR
  echo "训练任务提交完成。日志文件: ${OUTPUT_DIR}/training_log.txt"
fi