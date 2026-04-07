#!/bin/bash
# 开启严格模式：遇到错误、未定义变量或管道错误均立即退出
set -euo pipefail

# ==========================================
# 0. 日志记录初始化 (兼容 CI/CD 和非交互环境)
# ==========================================
LOG_FILE="/data/xie/deploy_$(date +%F_%H%M%S).log"

# 尝试使用 process substitution 实现屏幕与文件双写
# 如果环境不支持（如某些 Cron/Jenkins），则降级为只写入文件
exec > >(tee -a "$LOG_FILE") 2>&1 || {
    echo "⚠️ tee 日志功能不可用，改为直接输出到日志文件"
    exec >> "$LOG_FILE" 2>&1
}
echo "📝 本次执行日志将保存在: $LOG_FILE"

# ==========================================
# 1. 环境与依赖检查
# ==========================================
command -v docker >/dev/null 2>&1 || { echo "❌ docker 未安装"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "❌ wget 未安装"; exit 1; }
BUILD_SCRIPT="/home/test6/tool/mcr-xsc-providers/build.sh"
[ -f "$BUILD_SCRIPT" ] || { echo "❌ build.sh 不存在: $BUILD_SCRIPT"; exit 1; }

# ==========================================
# 2. 智能 Docker 权限与参数解析
# ==========================================
# 检查 docker 是否需要 sudo
if docker info >/dev/null 2>&1; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

if [ -z "${1:-}" ]; then
    echo "使用方法: ./deploy_image.sh <HTTP_URL> [TARGET_TAG]"
    echo "示例(交互式): ./deploy_image.sh 'http://xxx.tar'"
    echo "示例(非交互式): ./deploy_image.sh 'http://xxx.tar' 'registry.xxx.com/a/b:v1'"
    exit 1
fi

URL="$1"
# 支持从第二个参数直接读取 Tag，实现自动化流水线无缝调用
TARGET_TAG="${2:-}"

# ==========================================
# 3. 创建临时文件 & 注册自动清理
# ==========================================
# 在空间充足的挂载盘生成临时文件
TMP_FILE=$(mktemp /data/xie/img_XXXXXX)
echo "✅ 生成临时文件: $TMP_FILE"

# Trap 垃圾回收：无论脚本如何退出，都会清理临时包
trap 'sudo rm -f "$TMP_FILE" 2>/dev/null || true; echo "🧹 已清理临时文件: $TMP_FILE"' EXIT

# ==========================================
# 4. 下载镜像包
# ==========================================
echo "--- 1. 开始下载镜像包 ---"
sudo wget -c -O "$TMP_FILE" "$URL" || { echo "❌ 下载失败，请检查网络或 URL"; exit 1; }

# ==========================================
# 5. 加载镜像并执行安全检测
# ==========================================
echo "--- 2. 加载 Docker 镜像 ---"
LOAD_OUTPUT=$($DOCKER_CMD load -i "$TMP_FILE")
echo "$LOAD_OUTPUT"

# 安全检测：确保 tar 包里只有一个镜像，防止不可控的批量 tag
IMAGE_COUNT=$(echo "$LOAD_OUTPUT" | grep -c "Loaded image")
if [ "$IMAGE_COUNT" -ne 1 ]; then
    echo "❌ 镜像包中包含多个或零个镜像 ($IMAGE_COUNT 个)，脚本无法自动处理，请手动介入。"
    exit 1
fi

SOURCE_IDENTIFIER=$(echo "$LOAD_OUTPUT" | grep "Loaded image" | awk '{print $NF}')
echo "✅ 提取源镜像标识: $SOURCE_IDENTIFIER"
echo "--------------------------------------------------"

# ==========================================
# 6. 确定目标 Tag (支持交互与非交互模式)
# ==========================================
if [ -z "$TARGET_TAG" ]; then
    read -p "请输入目标镜像的完整 Tag (例如 registry.xxx.com/xxx:v1): " TARGET_TAG
fi

if [ -z "$TARGET_TAG" ]; then
    echo "❌ 目标 Tag 不能为空"
    exit 1
fi

DRIVER_TAG="${TARGET_TAG}-driver"
echo "✅ 目标镜像标签: $TARGET_TAG"
echo "✅ Driver 标签: $DRIVER_TAG"
echo "--------------------------------------------------"

# ==========================================
# 7. 打标签与构建 (带脏数据回滚)
# ==========================================
echo "--- 3. 标记镜像标签 ---"
$DOCKER_CMD tag "$SOURCE_IDENTIFIER" "$TARGET_TAG" || { echo "❌ 标记镜像失败"; exit 1; }

echo "--- 4. 运行构建脚本 ---"
# 如果构建失败，自动清理刚刚打好的 Target Tag 本地缓存
if ! sudo "$BUILD_SCRIPT" "$TARGET_TAG" xsc-providers "$DRIVER_TAG"; then
    echo "❌ 构建脚本执行失败！需要手动介入"
    #$DOCKER_CMD rmi "$TARGET_TAG" 2>/dev/null || true
    exit 1
fi

# ==========================================
# 8. 推送镜像仓库
# ==========================================
# ==========================================
# 8. 推送镜像仓库 (带自动登录引导)
# ==========================================
echo "--- 5. 推送镜像至仓库 ---"
if ! $DOCKER_CMD push "$DRIVER_TAG"; then
    echo "⚠️ 第一次推送失败！检测到可能未登录镜像仓库或没有权限。"
    
    # 提取 Registry 地址
    TARGET_REGISTRY=$(echo "$TARGET_TAG" | awk -F/ '{print $1}')
    
    if [ -t 0 ]; then
        echo "🔄 正在尝试引导手动登录 [$TARGET_REGISTRY]..."
        read -p "是否现在输入账号密码登录? (y/n): " LOGIN_CHOICE
        
        if [[ "$LOGIN_CHOICE" =~ ^[Yy]$ ]]; then
            # 脚本自己接管账号密码的输入
            read -p "👤 请输入 Docker 用户名: " DOCKER_USER
            # -s 参数让密码输入时不可见（静默输入），保护隐私
            read -s -p "🔑 请输入 Docker 密码/Token: " DOCKER_PASS
            echo "" # 换行，因为 -s 吞掉了回车键的换行效果
            
            echo "⏳ 正在验证凭据..."
            # 【核心改进】使用标准输入安全传递密码，防止被 ps 抓取
            if echo "$DOCKER_PASS" | $DOCKER_CMD login "$TARGET_REGISTRY" -u "$DOCKER_USER" --password-stdin >/dev/null 2>&1; then
                echo "✅ 登录成功！正在重新尝试推送..."
                
                # 重新推送
                if ! $DOCKER_CMD push "$DRIVER_TAG"; then
                    echo "❌ 再次推送失败！请检查账号是否有该项目的 Push 权限。"
                    exit 1
                fi
            else
                echo "❌ 登录失败！账号或密码错误，任务终止。"
                exit 1
            fi
        else
            echo "❌ 用户取消登录，推送中止。"
            exit 1
        fi
    else
        echo "❌ 当前为非交互式环境，无法手动输入密码。"
        echo "💡 建议：在 CI/CD 中通过环境变量注入，或预置 ~/.docker/config.json"
        exit 1
     
fi

echo "--- 5. 推送镜像至仓库 ---"
if ! $DOCKER_CMD push "$DRIVER_TAG"; then
    echo "❌ 推送失败！请确认已通过 docker login 登录目标 Registry。"
    exit 1
fi

echo "--- 🎉 自动化流程全部完成 ---"

# ==========================================
# 9. 运维总结报表 (Summary)
# ==========================================
echo ""
echo "=================================================="
echo "✅ 部署完成信息汇总："
echo "源镜像标识 : $SOURCE_IDENTIFIER"
echo "目标基础镜像: $TARGET_TAG"
echo "含驱动子镜像: $DRIVER_TAG"
echo "完整日志存档: $LOG_FILE"
echo "=================================================="