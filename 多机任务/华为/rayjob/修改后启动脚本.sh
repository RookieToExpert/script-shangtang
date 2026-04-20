set -ex

# 1. 基础环境
source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /usr/local/Ascend/nnal/atb/set_env.sh --cxx_abi=1

# 2. 路径配置
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver
export XTUNER_DIR="/mnt/hw/hw-linyifei2/nengx/xtuner_fork/xtuner"
export CONFIG_PATH="${XTUNER_DIR}/examples/v1/config/new_rl_qwen3_30B_grpo.py"
export MODEL_PATH="/mnt/hw/huawei/weight/Qwen3-30B-A3B"
export DATA_PATH="/mnt/hw/hw-linyifei2/nengx/datasets/gsm8k/train.jsonl"
export OUTPUT_DIR="/mnt/hw/hw-linyifei2/nengx/rl_log/rl_qwen3_output/$(date "+%Y%m%d_%H%M%S")"
mkdir -p "$OUTPUT_DIR"

# 3. 设置核心环境变量
# 按照建议，把 /workspace/vllm 和 XTuner 加入系统路径
export PYTHONPATH="$PYTHONPATH:/workspace/vllm:$XTUNER_DIR"

# 4. 生成 Runtime Env JSON
python3 -c "
import json, os
env_vars = {
    'WORK_DIR': os.environ['OUTPUT_DIR'],
    'MODEL_PATH': os.environ['MODEL_PATH'],
    'DATA_PATH': os.environ['DATA_PATH'],
    'EVAL_DATA_PATH': '',
    'PYTHONPATH': os.environ.get('PYTHONPATH', ''),
    'XTUNER_MAX_CONCURRENCY': '8192',
    'XTUNER_LOG_LEVEL': 'INFO',
    'XTUNER_USE_VLLM': '1',
    # ⚠️ 绝对核心：强行关闭 V1 引擎，避开含有循环导入 Bug 的源码！
    'VLLM_USE_V1': '0', 
    'PYTHONUNBUFFERED': '1',
    'HF_DATASETS_OFFLINE': '1',
    'TRANSFORMERS_OFFLINE': '1',
    'PYTORCH_NPU_ALLOC_CONF': 'expandable_segments:True',
    'LD_LIBRARY_PATH': os.environ.get('LD_LIBRARY_PATH', ''),
    'PATH': os.environ.get('PATH', ''),
    'ASCEND_HOME_PATH': os.environ.get('ASCEND_HOME_PATH', ''),
    'ASCEND_OPP_PATH': os.environ.get('ASCEND_OPP_PATH', ''),
    'ASCEND_AICPU_PATH': os.environ.get('ASCEND_AICPU_PATH', ''),
    'TOOLCHAIN_HOME': os.environ.get('TOOLCHAIN_HOME', ''),
    'ATB_HOME_PATH': os.environ.get('ATB_HOME_PATH', '')
}
with open('runtime_env_final.json', 'w') as f:
    json.dump({'env_vars': env_vars}, f)
"

# 5. 提交任务
# ray job submit --address="http://127.0.0.1:8265" \
#     --runtime-env runtime_env_final.json \
#     -- bash -c "python $XTUNER_DIR/xtuner/v1/train/cli/new.rl.py --config $CONFIG_PATH" \
#     2>&1 | tee -a "${OUTPUT_DIR}/training_log.txt"

#多机
ray job submit --address="http://127.0.0.1:8265" \
    --runtime-env runtime_env_final.json \
    -- bash -c "source /usr/local/Ascend/ascend-toolkit/set_env.sh && \
                source /usr/local/Ascend/nnal/atb/set_env.sh --cxx_abi=1 && \
                export LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver && \
                python $XTUNER_DIR/xtuner/v1/train/cli/new.rl.py --config $CONFIG_PATH" \
    2>&1 | tee -a "${OUTPUT_DIR}/training_log.txt"