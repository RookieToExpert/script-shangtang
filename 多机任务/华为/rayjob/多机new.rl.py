import os
import sys
import subprocess
import threading
import time
from pathlib import Path
from typing import Annotated

import ray
import torch.distributed as dist
from cyclopts import App, Parameter
from cyclopts.group import Group

# =========================================================================
# [新增核心逻辑] 华为 910c 多机 HCCL Superpod ID 注入
# =========================================================================
def inject_npu_env():
    # 1. 检查环境变量（如果外层 Shell 或者调度器已经设置了，直接用）
    if "HCCL_LOGIC_SUPERPOD_ID" in os.environ:
        print(f"[HCCL Setup] Using existing Superpod ID: {os.environ['HCCL_LOGIC_SUPERPOD_ID']}")
        return

    # 2. 方案一：动态获取（最推荐，对应 npu-smi 逻辑）
    try:
        cmd = "npu-smi info -t spod-info -i 0 -c 0 | grep -i 'Pod ID' | awk '{print $5}'"
        pod_id = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode().strip()
        if pod_id:
            os.environ['HCCL_LOGIC_SUPERPOD_ID'] = pod_id
            print(f"[HCCL Setup] Auto-detected Superpod ID: {pod_id}")
            return
    except Exception as e:
        print(f"[HCCL Setup] Warning: npu-smi failed: {e}")

    # 3. 兜底方案：如果是多机且没拿到 ID，灵衢无法建环，直接抛出异常阻断！
    # 获取 WORLD_SIZE，有些框架如果不跨机默认是没设置或者设为实际卡数(比如8)
    world_size = int(os.environ.get("WORLD_SIZE", "1"))
    
    # 这里的判断逻辑：如果没有拿到 Pod ID，且检测到是多机环境（超过8卡通常是多机）
    if world_size > 8 or int(os.environ.get("NNODES", "1")) > 1:
        error_msg = (
            "[HCCL Setup] FATAL ERROR: Multi-node training detected but Superpod ID not found! "
            "HCCL cross-node communication will fail. Process terminated."
        )
        print(error_msg)
        # 强行阻断程序，避免底层卡死
        raise RuntimeError(error_msg)
        
# ⚠️ 立即执行注入逻辑，必须在 XTuner 相关组件 import 之前执行
inject_npu_env()
# =========================================================================


# 确保环境变量设置完毕后，再导入 XTuner 训练相关组件
from xtuner.v1.rl.utils import register_cleanup
from xtuner.v1.train.rl_trainer import RLTrainer
from xtuner.v1.utils import Config
from xtuner.v1.utils.track_rl_mem import monitor_actor_memory


app = App(
    help="XTuner's entry point for fine-tuning and training, launched using configuration files or arguments.",
)

def rl_monitor_actor_memory(work_dir, interval: int = 60):
    while True:
        try:
            ray.init(ignore_reinit_error=True)
            time.sleep(interval)
            break
        except KeyboardInterrupt:
            print("\n监控已停止")
            break
        except Exception:
            print("连接 Ray 集群失败, 等等")

    monitor_actor_memory(work_dir=work_dir, interval=interval)

@app.default()
def main(
    *,
    config: Annotated[Path, Parameter(group=Group("config-path", sort_key=0))],
):
    # 采用最稳健的集群内初始化方式
    if not ray.is_initialized():
        ray.init(ignore_reinit_error=True)

    if os.getenv("XTUNER_RL_MEM_DIR"):
        print("Start to monitor actor memory")
        track_thread = threading.Thread(target=rl_monitor_actor_memory, args=(os.getenv("XTUNER_RL_MEM_DIR"),))
        track_thread.daemon = True
        track_thread.start()

    trainer_cfg = Config.fromfile(config)["trainer"]
    trainer = RLTrainer.from_config(trainer_cfg)
    trainer.fit()

    if dist.is_initialized():
        dist.destroy_process_group()

if __name__ == "__main__":
    register_cleanup()
    app(exit_on_error=False)