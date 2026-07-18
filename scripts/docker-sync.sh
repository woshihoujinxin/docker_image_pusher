#!/bin/bash
# Docker 镜像同步脚本 - 通过 GitHub Action 自动同步并拉取到本地
# 执行方式: ./docker-sync.sh <镜像1[:标签1]> [镜像2[:标签2]] ...

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查用户
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ 请不要使用 root 用户执行此脚本${NC}"
    exit 1
fi

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_USER="woshihoujinxin"
GITHUB_REPO="docker_image_pusher"
GITHUB_TOKEN_FILE="$HOME/.github_token"

# 阿里云配置
ALIYUN_REGISTRY="registry.cn-hangzhou.aliyuncs.com"
ALIYUN_NAMESPACE="shrimp-images"

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}用法: $0 <镜像1[:标签1]> [镜像2[:标签2]] ...${NC}"
    echo "示例: $0 nginx redis:alpine"
    exit 1
fi

# 解析参数
IMAGES=()
for arg in "$@"; do
    if [[ "$arg" == *:* ]]; then
        IMAGES+=("$arg")
    else
        IMAGES+=("$arg:latest")
    fi
done

echo -e "${GREEN}=========================================="
echo "  Docker 镜像自动同步"
echo "==========================================${NC}"
echo
echo -e "待同步镜像:"
for img in "${IMAGES[@]}"; do
    echo -e "  ${YELLOW}${img}${NC}"
done
echo

# === 读取 Token ===
if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
    echo -e "${RED}❌ 未找到 GitHub Token${NC}"
    echo -e "${YELLOW}请先运行: bash scripts/setup-token.sh${NC}"
    exit 1
fi

GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE")

# === 步骤 1: 更新 images.txt ===
echo -e "${YELLOW}[1/3] 触发 GitHub Action 同步...${NC}"

cd "$REPO_DIR"

# 检查是否有变化
NEED_SYNC=false
for img in "${IMAGES[@]}"; do
    if ! grep -qx "^${img}$" images.txt 2>/dev/null; then
        NEED_SYNC=true
        break
    fi
done

if [ "$NEED_SYNC" = true ]; then
    > images.txt
    for img in "${IMAGES[@]}"; do
        echo "$img" >> images.txt
    done

    git remote set-url origin "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
    git pull

    git config user.name "Docker Sync"
    git config user.email "sync@local"
    git add images.txt
    git commit -m "Sync: ${IMAGES[*]}"
    git push "https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git" main
    echo -e "${GREEN}✅ 已触发同步${NC}"
else
    echo -e "${GREEN}✅ 镜像已在同步队列中${NC}"
fi

# === 步骤 2: 等待完成 ===
echo
echo -e "${YELLOW}[2/3] 等待同步完成...${NC}"
echo -e "${YELLOW}查看: https://github.com/${GITHUB_USER}/${GITHUB_REPO}/actions${NC}"
echo

MAX_WAIT=600
WAIT_TIME=0
CHECK_INTERVAL=5

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs?per_page=1" 2>/dev/null)

    # 使用 Python 解析 JSON（更可靠）
    STATUS=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('workflow_runs', [{}])[0].get('status', ''))" 2>/dev/null)
    CONCLUSION=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('workflow_runs', [{}])[0].get('conclusion', ''))" 2>/dev/null)

    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" = "success" ]; then
            echo -e "\r${GREEN}✅ 同步成功!${NC}                    "
            break
        else
            echo -e "\r${RED}❌ 同步失败 (${CONCLUSION})${NC}        "
            exit 1
        fi
    fi

    # 检查是否超时
    if [ -z "$STATUS" ]; then
        # STATUS 为空，可能是 API 错误，尝试继续
        printf "\r${YELLOW}⏳ 等待中... %d 秒${NC}" $WAIT_TIME
    else
        case "$STATUS" in
            "queued") MSG="队列中..." ;;
            "in_progress") MSG="同步中..." ;;
            *) MSG="等待中... [$STATUS]" ;;
        esac
        printf "\r${BLUE}⏳  ${MSG} %d 秒${NC}" $WAIT_TIME
    fi

    sleep $CHECK_INTERVAL
    WAIT_TIME=$((WAIT_TIME + CHECK_INTERVAL))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo
    echo -e "${RED}⏰ 等待超时${NC}"
    exit 1
fi
echo

# === 步骤 3: 拉取并重命名 ===
echo
echo -e "${YELLOW}[3/3] 从阿里云拉取镜像...${NC}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for img in "${IMAGES[@]}"; do
    IMAGE_NAME="${img%:*}"
    IMAGE_TAG="${img##*:}"
    TARGET_IMAGE=$(echo "$IMAGE_NAME" | sed 's/[\/]/-/g')
    ALIYUN_IMAGE="${ALIYUN_REGISTRY}/${ALIYUN_NAMESPACE}/${TARGET_IMAGE}:${IMAGE_TAG}"

    echo -n "  拉取 ${img}... "

    if docker pull "$ALIYUN_IMAGE" 2>/dev/null; then
        docker tag "$ALIYUN_IMAGE" "${img}"
        docker rmi "$ALIYUN_IMAGE" 2>/dev/null || true
        echo -e "${GREEN}✅${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}❌${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo
echo -e "${GREEN}=========================================="
echo "  ✅ 完成!"
echo "==========================================${NC}"
echo
echo -e "成功: ${GREEN}${SUCCESS_COUNT}${NC}  失败: ${RED}${FAIL_COUNT}${NC}"
echo
echo -e "本地镜像:${NC}"
docker images | head -10
