#!/bin/bash
set -x
echo "--- Multi-Node Shell Start ---"

# 1. 【保留】你原始单机脚本的所有路径配置
export NUM_NODES=3  # 🚀 你以后只需要改这一个数字！比如改成 4
export GPUS_PER_NODE=8
export TOTAL_GPUS=$((NUM_NODES * GPUS_PER_NODE))

# 自动推导 Batch Size (单卡分配 8 条数据，是 micro_batch 4 的倍数，完美整除)
export PPO_MINI_BATCH=$((TOTAL_GPUS * 8))
export TRAIN_BATCH=$((PPO_MINI_BATCH * 4))

echo ">>> 当前集群规模: ${NUM_NODES} 节点, 共 ${TOTAL_GPUS} 张卡"
echo ">>> 自动计算 Train Batch Size: ${TRAIN_BATCH}"
echo ">>> 自动计算 PPO Mini Batch Size: ${PPO_MINI_BATCH}"
export RAY_SCHEDULER_EVENTS=0
export MACA_PATH=/opt/maca
export CUCC_PATH=${MACA_PATH}/tools/cu-bridge
export CUDA_PATH=${CUCC_PATH}
export MACA_CLANG_PATH=$MACA_PATH/mxgpu_llvm/bin
export PATH=${CUDA_PATH}/bin:${MACA_CLANG_PATH}:${PATH}
export LD_LIBRARY_PATH=${MACA_PATH}/tools/cu-bridge/lib/:${MACA_PATH}/lib:${MACA_PATH}/ompi/lib:${MACA_PATH}/mxgpu_llvm/lib:${LD_LIBRARY_PATH}

# 2. 【保留】你原始脚本的 A100 兼容性与性能参数
export PYTORCH_ENABLE_SAME_RAND_A100=1
export PYTORCH_ENABLE_SAME_RANK_A100=1
export SET_DEVICE_NUMA_PREFERRED=1
export HYDRA_FULL_ERROR=1
export CUDA_DEVICE_MAX_CONNECTIONS=1
export MCPYTORCH_DISABLE_PRINT=1
export MAX_JOBS=20
export NVTE_FLASH_ATTN=1
export NVTE_FUSED_ATTN=0
export PYTHONPATH=/workspace/Megatron-LM-0.15.0/:$PYTHONPATH
export PYTHONUNBUFFERED=1
export MACA_DIRECT_DISPATCH=0

# 3. 【保留】你原始脚本的 Unset 操作
unset PAGEABLE_MEMCPY_ASYNC
unset PYTORCH_CUDA_ALLOC_CONF
unset RAY_EXPERIMENTAL_NOSET_CUDA_VISIBLE_DEVICES

# 4. 【新增】多机 MCCL 核心配置 (从你之前的多机脚本迁移)
export LD_PRELOAD=${MACA_PATH}/lib/libmccl.so  # 必须预加载
export MCCL_SOCKET_IFNAME=eth0                 # 根据实际网卡修改
export GLOO_SOCKET_IFNAME=eth0
export MCCL_IB_HCA=xscale_0,xscale_1,xscale_2,xscale_3 
export MCCL_IB_GID_INDEX=5              
export MCCL_IB_TC=128
export MCCL_FAST_WRITE_BACK=1
export MCCL_EARLY_WRITE_BACK=15
export MCCL_ENABLE_VSWITCH=1
export MCCL_CROSS_NIC=1                 
export MCCL_ALGO=Ring
export MCCL_DEBUG=INFO

# 5. 【核心】通过 Python 启动并强行注入 Ray 的 runtime_env
# 5. 【核心】通过 Ray Job Submission API 提交任务并提取 Job ID
echo "--- 正在通过 Ray Job API 提交 3 节点（24 GPU）训练任务 ---"

# 将 Python 打印出的 job_id 捕获到 Bash 变量中
JOB_ID=$(python3 <<EOF
import os
import sys
# 屏蔽一些无关的警告输出，防止干扰 Job ID 的捕获
import warnings
warnings.filterwarnings("ignore")

from ray.job_submission import JobSubmissionClient

current_env = dict(os.environ)

try:
    client = JobSubmissionClient("http://127.0.0.1:8265")
except Exception as e:
    print(f"连接失败: {e}", file=sys.stderr)
    sys.exit(1)

# 3. 构造原生终端命令 (注意这里变成了一个长字符串)
# 3. 构造原生终端命令 (注意这里变成了一个长字符串)
cmd = (
    "python3 -m verl.trainer.main_ppo "
    "algorithm.adv_estimator=gae "
    "data.train_files=/mnt/tangrui/models/qwen2.5-3b/train.parquet "
    "data.val_files=/mnt/tangrui/models/qwen2.5-3b/train.parquet "
    f"data.train_batch_size={os.environ['TRAIN_BATCH']} " # <--- 动态注入
    "data.max_prompt_length=512 "
    "data.max_response_length=512 "
    "actor_rollout_ref.model.path=/mnt/tangrui/models/qwen2.5-3b "
    "critic.model.path=/mnt/tangrui/models/qwen2.5-3b " 
    f"actor_rollout_ref.actor.ppo_mini_batch_size={os.environ['PPO_MINI_BATCH']} " # <--- 动态注入
    "actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=4 "
    "actor_rollout_ref.model.enable_gradient_checkpointing=True "
    "actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=32 "
    "actor_rollout_ref.rollout.tensor_model_parallel_size=4 "
    "actor_rollout_ref.rollout.name=vllm "
    "actor_rollout_ref.rollout.gpu_memory_utilization=0.4 "
    "critic.ppo_micro_batch_size_per_gpu=8 "
    "trainer.logger=['console'] "
    "trainer.n_gpus_per_node=8 "
    f"trainer.nnodes={os.environ['NUM_NODES']} " # <--- 动态注入
    "trainer.project_name='verl_example' "
    "trainer.experiment_name='Qwen2.5-7B-Instruct-Muxi-AutoNode' "
    "trainer.total_epochs=1"
)

# 提交任务
job_id = client.submit_job(
    entrypoint=cmd,
    runtime_env={"env_vars": current_env}
)
# 仅仅打印 job_id 给 Bash 捕获
print(job_id)
EOF
)

# 检查是否成功获取到了 job_id
if [[ "$JOB_ID" == raysubmit_* ]]; then
    echo "✅ 任务已成功提交! Job ID: $JOB_ID"
    echo "--- 正在实时拉取训练日志 ---"
    
    # 6. 使用 Ray 原生 CLI 工具实时拉取日志并写入文件
    ray job logs -f "$JOB_ID" | tee ppo_qwen25_7b.log
else
    echo "❌ 任务提交失败！输出信息: $JOB_ID"
    exit 1
fi