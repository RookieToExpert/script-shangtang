#!/bin/bash

# 1. 权限检查
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 root 权限，请用 sudo 重新执行。"
    exit 1
fi

# 2. GPU 检查
lspci | grep -i nvidia > /dev/null 2>&1
if [[ $? != 0 ]]; then
    echo "错误: 未检测到 NVIDIA GPU 设备。"
    exit 1
fi

# 定义版本变量，方便统一修改
DRIVER_VER="550.90.07"
BASE_URL="http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07"

echo "--- 开始安装 NVIDIA 驱动 $DRIVER_VER ---"

# 3. 下载并安装 NVIDIA 驱动
cd /tmp
if [ ! -f "NVIDIA-Linux-x86_64-${DRIVER_VER}.run" ]; then
    wget ${BASE_URL}/NVIDIA-Linux-x86_64-${DRIVER_VER}.run
fi
chmod +x NVIDIA-Linux-x86_64-${DRIVER_VER}.run
./NVIDIA-Linux-x86_64-${DRIVER_VER}.run -a -s -Z

# 配置 GPU
nvidia-smi --auto-boost-default=0
nvidia-smi

# 4. 安装 nvidia-persistenced 服务
echo "--- 配置 nvidia-persistenced 服务 ---"
if [ -d "/usr/share/doc/NVIDIA_GLX-1.0/samples/" ]; then
    cd /usr/share/doc/NVIDIA_GLX-1.0/samples/
    tar -jxf nvidia-persistenced-init.tar.bz2
    cd nvidia-persistenced-init/ && bash install.sh
    systemctl enable nvidia-persistenced.service
    systemctl restart nvidia-persistenced.service
fi

# 5. 安装 Fabric Manager (区分系统类型)
echo "--- 安装 Fabric Manager $DRIVER_VER ---"

# 情况 A: RHEL/CentOS/Kylin (RPM 系统)
if [ -f /etc/redhat-release ] || grep -q "ID_LIKE=.*fedora" /etc/os-release; then
    echo "检测到 RPM 相关系统，正在处理..."
    
    # 彻底停止旧服务并卸载所有旧版本 FM 包，防止冲突
    systemctl stop nvidia-fabricmanager > /dev/null 2>&1
    rpm -qa | grep nvidia-fabric-manager | xargs -r rpm -e --nodeps
    
    cd /tmp
    wget ${BASE_URL}/nvidia-fabric-manager-${DRIVER_VER}-1.x86_64.rpm
    wget ${BASE_URL}/nvidia-fabric-manager-devel-${DRIVER_VER}-1.x86_64.rpm
    
    rpm -ivh nvidia-fabric-manager-${DRIVER_VER}-1.x86_64.rpm
    rpm -ivh nvidia-fabric-manager-devel-${DRIVER_VER}-1.x86_64.rpm
    
    systemctl daemon-reload
    systemctl enable nvidia-fabricmanager
    systemctl restart nvidia-fabricmanager
    systemctl status nvidia-fabricmanager --no-pager

# 情况 B: Ubuntu/Debian (DEB 系统)
elif grep -q "ID=.*ubuntu\|ID=.*debian" /etc/os-release; then
    echo "检测到 Ubuntu/Debian 系统，正在处理..."
    
    systemctl stop nvidia-fabricmanager > /dev/null 2>&1
    apt-get purge -y nvidia-fabricmanager-* 2>/dev/null
    
    cd /tmp
    wget ${BASE_URL}/nvidia-fabricmanager-550_${DRIVER_VER}-1_amd64.deb
    wget ${BASE_URL}/nvidia-fabricmanager-dev-550_${DRIVER_VER}-1_amd64.deb
    
    dpkg -i nvidia-fabricmanager-550_${DRIVER_VER}-1_amd64.deb
    dpkg -i nvidia-fabricmanager-dev-550_${DRIVER_VER}-1_amd64.deb
    # 修复可能的依赖问题
    apt-get install -f -y 
    
    systemctl daemon-reload
    systemctl enable nvidia-fabricmanager
    systemctl restart nvidia-fabricmanager
    systemctl status nvidia-fabricmanager --no-pager
fi

# 6. 清理安装包
rm -f /tmp/NVIDIA-Linux-x86_64-${DRIVER_VER}.run
rm -f /tmp/nvidia-fabric-manager*.rpm
rm -f /tmp/nvidia-fabricmanager*.deb

echo "脚本执行完毕。"