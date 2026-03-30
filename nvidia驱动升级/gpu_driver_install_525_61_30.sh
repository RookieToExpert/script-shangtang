#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 root 权限，请用 sudo 重新执行："
    echo "sudo $0 $@"
    exit 1
fi

lspci |grep -i nvidia > /dev/null 2>&1
if [[ $? != 0 ]];then
    exception_output "Non-GPU machine"
    exit 1
fi

cd /tmp && wget http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_525_60_13/NVIDIA-Linux-x86_64-525.60.13.run
chmod +x NVIDIA-Linux-x86_64-525.60.13.run
cd /tmp && ./NVIDIA-Linux-x86_64-525.60.13.run -a -s -Z
nvidia-smi -pm 1
nvidia-smi --auto-boost-default=0
nvidia-smi


if rpm -q nvidia-fabric-manager >/dev/null 2>&1; then
    echo "nvidia-fabric-manager package is installed. Removing..."
    rpm -e nvidia-fabric-manager-devel
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_525_60_13/nvidia-fabric-manager-525.60.13-1.x86_64.rpm
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_525_60_13/nvidia-fabric-manager-devel-525.60.13-1.x86_64.rpm
    #rpm -i nvidia-fabric-manager-515.65.01-1.x86_64.rpm
    #dnf info nvidia-fabric-manager
    rpm -qa | grep nvidia-fabric-manager
    systemctl daemon-reload
    systemctl start nvidia-fabricmanager.service
    systemctl enable nvidia-fabricmanager.service
    systemctl status nvidia-fabricmanager.service
else
    echo "nvidia-fabric-manager package is not installed. Installing..."
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_525_60_13/nvidia-fabric-manager-525.60.13-1.x86_64.rpm
    rpm -ivh http://eyes.sensetime.com:9999/gpu_install/gpu_software/gpu_driver_525_60_13/nvidia-fabric-manager-devel-525.60.13-1.x86_64.rpm
    #rpm -i nvidia-fabric-manager-515.65.01-1.x86_64.rpm
    #dnf info nvidia-fabric-manager
    rpm -qa | grep nvidia-fabric-manager
    systemctl daemon-reload
    systemctl start nvidia-fabricmanager.service
    systemctl enable  nvidia-fabricmanager.service
    systemctl status nvidia-fabricmanager.service

rm -rf /tmp/NVIDIA-Linux-x86_64-525.60.13.run