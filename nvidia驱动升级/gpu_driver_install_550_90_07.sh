#!/bin/bash
#yum install dkms -y

TARGET_VERSION="550.90.07"

# 判断当前用户是否为root用户，不是贼报错
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 root 权限，请用 sudo 重新执行："
    echo "sudo $0 $@"
    exit 1
fi

# 判断当前设备是否为 nvidia GPU 服务器，不是则退出
lspci |grep -i nvidia > /dev/null 2>&1
if [[ $? != 0 ]];then
    exception_output "Non-GPU machine"
    exit 1
fi

# ================================================================
# 驱动版本检查
if command -v nvidia-smi > /dev/null 2>&1; then
    # 获取当前驱动版本号(取第一行以防多卡输出异常)
    CURRENT_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1 | tr -d ' ')

    if [[ -n "$CURRENT_VERSION" ]]; then
        echo "检查当前 NVIDIA 驱动版本: $CURRENT_VERSION"

        # 1. 判断是否完全一致
        if [[ "$CURRENT_VERSION" == "$TARGET_VERSION "]]; then
            echo "当前驱动版本 ($CURRENT_VERSION) 与目标版本一致，跳过安装。"
            exit 0
        fi
    
        # 2. 比较版本号高低
        # sort -V 会按版本号从小到大排序，tail -n 1 取出最大的那个
        HIGHEST_VERSION=$(printf "%s\n%s" "$CURRENT_VERSION" "$TARGET_VERSION" | sort -V | tail -n 1)

        if [[ "$HIGHEST_VERSION" == "$CURRENT_VERSION" ]]; then
            echo "当前驱动版本 ($CURRENT_VERSION) 高于目标版本 ($TARGET_VERSION)，无需升级，退出脚本。"
            exit 0
        else
            echo "当前驱动版本 ($CURRENT_VERSION) 低于目标版本 ($TARGET_VERSION)，准备开始升级..."
        fi
    fi
else
    echo "未检测到已安装的 NVIDIA 驱动 (找不到 nvidia-smi)，准备全新安装..."
fi
# ================================================================

# 下载 x86_64 NVIDIA 驱动 Runfile
cd /tmp/ && wget http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/NVIDIA-Linux-x86_64-550.90.07.run
#cd /tmp/ && wget http://10.123.72.100:9999/NVIDIA-Linux-x86_64-550.90.07.run
chmod +x NVIDIA-Linux-x86_64-550.90.07.run
cd /tmp && ./NVIDIA-Linux-x86_64-550.90.07.run -a -s -Z
#nvidia-smi -pm 1
nvidia-smi --auto-boost-default=0
nvidia-smi
# 安装 nvidia-persistenced 服务
cd /usr/share/doc/NVIDIA_GLX-1.0/samples/ &&  tar -jxf nvidia-persistenced-init.tar.bz2
cd nvidia-persistenced-init/ && bash install.sh
systemctl enable nvidia-persistenced.service


# 检查是否安装了 nvidia-fabric-manager 包
if rpm -q nvidia-fabric-manager >/dev/null 2>&1; then
    echo "nvidia-fabric-manager package is installed. Removing..."
    rpm -e nvidia-fabric-manager-devel
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabric-manager-550.90.07-1.x86_64.rpm
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabric-manager-devel-550.90.07-1.x86_64.rpm
    #rpm -ivh http://10.123.72.100:9999/nvidia-fabric-manager-550.90.07-1.x86_64.rpm
    #rpm -ivh http://10.123.72.100:9999/nvidia-fabric-manager-devel-550.90.07-1.x86_64.rpm
    # dnf info nvidia-fabric-manager
    rpm -qa | grep nvidia-fabric-manager
    systemctl start nvidia-fabricmanager.service
    systemctl enable  nvidia-fabricmanager.service
    systemctl status nvidia-fabricmanager.service
else
    echo "nvidia-fabric-manager package is not installed. Installing..."
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabric-manager-550.90.07-1.x86_64.rpm
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabric-manager-devel-550.90.07-1.x86_64.rpm
    #rpm -ivh http://10.123.72.100:9999/nvidia-fabric-manager-550.90.07-1.x86_64.rpm
    #rpm -ivh http://10.123.72.100:9999/nvidia-fabric-manager-devel-550.90.07-1.x86_64.rpm
    #dnf info nvidia-fabric-manager
    rpm -qa | grep nvidia-fabric-manager
    systemctl start nvidia-fabricmanager.service
    systemctl enable  nvidia-fabricmanager.service
    systemctl status nvidia-fabricmanager.service
fi

rm -rf /tmp/NVIDIA-Linux-x86_64-550.90.07.run


if `cat /etc/os-release | grep ^ID= |grep -q ubuntu && cat /etc/os-release | grep ^VERSION= | egrep -q "20|22|24" && lscpu | grep ^Architecture: | grep  -q x86`
then
        cd /tmp && wget  http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabricmanager-550_550.90.07-1_amd64.deb
        cd /tmp && wget  http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_550_90_07/nvidia-fabricmanager-dev-550_550.90.07-1_amd64.deb
        cd /tmp && dpkg -i nvidia-fabricmanager-550_550.90.07-1_amd64.deb
        cd /tmp && dpkg -i nvidia-fabricmanager-dev-550_550.90.07-1_amd64.deb
        systemctl start nvidia-fabricmanager.service
        systemctl enable  nvidia-fabricmanager.service
        systemctl status nvidia-fabricmanager.service
fi