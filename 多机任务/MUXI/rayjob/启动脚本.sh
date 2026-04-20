set -x
echo "---shell Start---"
export MACA_PATH=/opt/maca
export CUCC_PATH=${MACA_PATH}/tools/cu-bridge
export CUDA_PATH=${CUCC_PATH}
export MACA_CLANG_PATH=$MACA_PATH/mxgpu_llvm/bin
export PATH=${CUDA_PATH}/bin:${MACA_CLANG_PATH}:${PATH}
export LD_LIBRARY_PATH=${MACA_PATH}/tools/cu-bridge/lib/:${MACA_PATH}/lib:${MACA_PATH}/ompi/lib:${MACA_PATH}/mxgpu_llvm/lib:${LD_LIBRARY_PATH}
export PYTORCH_ENABLE_SAME_RAND_A100=1
# export MACA_SMALL_PAGESIZE_ENABLE=1
export PYTORCH_ENABLE_SAME_RANK_A100=1
export SET_DEVICE_NUMA_PREFERRED=1
export HYDRA_FULL_ERROR=1
export CUDA_DEVICE_MAX_CONNECTIONS=1
export MCPYTORCH_DISABLE_PRINT=1
export MAX_JOBS=20
#export VLLM_USE_V1=0
unset PAGEABLE_MEMCPY_ASYNC
unset PYTORCH_CUDA_ALLOC_CONF
export NVTE_FLASH_ATTN=1
export NVTE_FUSED_ATTN=0
# export MCCL_ENABLE_FC=0
export CUDA_VISIBLE_DEVICES="0,1,2,3,4,5,6,7"
unset RAY_EXPERIMENTAL_NOSET_CUDA_VISIBLE_DEVICES

export PYTHONPATH=/workspace/Megatron-LM-0.15.0/:$PYTHONPATH
export PYTHONUNBUFFERED=1
export MACA_DIRECT_DISPATCH=0

python3 -m verl.trainer.main_ppo \
    algorithm.adv_estimator=gae \
    data.train_files=/root/data/gsm8k/train.parquet \
    data.val_files=/root/data/gsm8k/train.parquet \
    data.train_batch_size=1024 \
    data.max_prompt_length=512 \
    data.max_response_length=1024 \
    data.filter_overlong_prompts=True \
    data.truncation='error' \
    actor_rollout_ref.model.path=/mnt/tangrui/models/qwen2.5-3b \
    actor_rollout_ref.model.enable_gradient_checkpointing=False \
    actor_rollout_ref.actor.optim.lr=1e-6 \
    actor_rollout_ref.model.use_remove_padding=True \
    actor_rollout_ref.actor.ppo_mini_batch_size=256 \
    actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=4 \
    actor_rollout_ref.model.enable_gradient_checkpointing=True \
    actor_rollout_ref.actor.fsdp_config.param_offload=False \
    actor_rollout_ref.actor.fsdp_config.optimizer_offload=False \
    actor_rollout_ref.actor.use_kl_loss=False \
    actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=32 \
    actor_rollout_ref.rollout.tensor_model_parallel_size=4 \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.5 \
    critic.optim.lr=1e-5 \
    critic.model.use_remove_padding=True \
    critic.model.path=/mnt/tangrui/models/qwen2.5-3b \
    critic.model.enable_gradient_checkpointing=False \
    critic.ppo_micro_batch_size_per_gpu=8 \
    critic.model.fsdp_config.param_offload=False \
    critic.model.fsdp_config.optimizer_offload=False \
    algorithm.use_kl_in_reward=False \
    trainer.critic_warmup=0 \
    trainer.logger='["console"]' \
    trainer.project_name='verl_example' \
    trainer.experiment_name='Qwen2.5-7B-Instruct' \
    trainer.n_gpus_per_node=8 \
    trainer.nnodes=1 \
    trainer.save_freq=-1 \
    trainer.test_freq=5 \
    trainer.total_epochs=1 2>&1 | tee ppo_qwen25_7b.log