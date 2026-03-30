## 标准单机pytorch训练方法如下:
```bash
cd <your-mnt-dir>/sample_project/mmdetection
# python -m torch.distributed.launch 等于 torchrun
python -m torch.distributed.launch \
    --nnodes 1 \
    --node_rank 0 \
    --master_addr 127.0.0.1 \
    --nproc_per_node 8 \
    --master_port 29500 \
    tools/train.py work_dirs/<your-name>/myconfig.py \
    --launcher pytorch
```

## 标准多机pytorch训练方法如下:
```bash
#!/usr/bin/env bash

CONFIG=$1
GPUS=$2
NNODES=${WORLD_SIZE:-1}
NODE_RANK=${RANK:-0}
PORT=${MASTER_PORT:-29500}
MASTER_ADDR=${MASTER_ADDR:-"127.0.0.1"}

# python -m torch.distributed.launch 等于 torchrun
PYTHONPATH="$(dirname $0)/..":$PYTHONPATH \
torchrun \
    --nnodes=$NNODES \
    --node_rank=$NODE_RANK \
    --master_addr=$MASTER_ADDR \
    --nproc_per_node=$GPUS \
    --master_port=$PORT \
    $(dirname "$0")/train.py \
    $CONFIG \
    --launcher pytorch ${@:3}
```