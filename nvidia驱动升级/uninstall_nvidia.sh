#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 root 权限，请用 sudo 重新执行："
    echo "sudo $0 $@"
    exit 1
fi
echo "开始清理 NVIDIA 相关组件..."
pgrep -f dcgm >/dev/null && { echo "杀死 DCGM 进程..."; pkill -9 -f dcgm; }
echo "运行 NVIDIA 官方卸载程序..."
/usr/bin/nvidia-uninstall -q -s || echo "nvidia-uninstall 未找到或已无驱动"
systemctl stop nvidia-fabricmanager.service 2>/dev/null || echo "Fabric Manager 服务已停止或不存在"
yum -y remove nvidia-fabric-manager-devel 2>/dev/null || echo "devel 包已卸载或不存在"