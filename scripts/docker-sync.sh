#!/bin/bash
# Docker 镜像同步脚本 - 通过 GitHub Action 自动同步并拉取到本地
# 执行方式: ./docker-sync.sh <镜像1[:标签1]> [镜像2[:标签2]] ...

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
REPO_DIR="$HOME/docker_image_pusher"
GITHUB_USER="woshihoujinxin"
GITHUB_REPO="docker_image_pusher"
GITHUB_TOKEN_FILE="$HOME/.github_token"

# 阿里云配置
ALIYUN_REGISTRY="registry.cn-hangzhou.aliyuncs.com"
ALIYUN_NAMESPACE="houjinxin"

# 检查 docker 权限
if ! docker info &>/dev/null; then
    if ! groups | grep -q "\bdocker\b"; then
        sudo usermod -aG docker "$USER" >/dev/null 2>&1
    fi
    DOCKER="sudo docker"
else
    DOCKER="docker"
fi

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
    exit 1
fi

GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE")

# === 步骤 1: 更新 images.txt ===
echo -e "${YELLOW}[1/3] 触发 GitHub Action 同步...${NC}"

cd "$REPO_DIR"

# 清空并写入新镜像
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

# 重试推送
PUSH_SUCCESS=false
for i in {1..3}; do
    if git push "https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git" main 2>/dev/null; then
        PUSH_SUCCESS=true
        break
    else
        if [ $i -lt 3 ]; then
            echo -n "重试 $i/3... "
            sleep 2
        fi
    fi
done

if [ "$PUSH_SUCCESS" = false ]; then
    echo -e "${RED}❌ 推送失败${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 已触发同步${NC}"

# 获取触发时间，用于识别最新的 run
TRIGGER_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
echo -e "${YELLOW}触发时间: $TRIGGER_TIME${NC}"

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
        "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs?per_page=3" 2>/dev/null)

    # 找到最新的、包含我们镜像名的 run
    LATEST_RUN=$(echo "$RESPONSE" | python3 -c "
import sys, json, datetime
data = json.load(sys.stdin)
trigger_time = '$TRIGGER_TIME'
for run in data.get('workflow_runs', []):
    created = run.get('created_at', '')
    title = run.get('display_title', '')
    # 检查是否是我们刚触发的（时间匹配且包含 Sync）
    if created > trigger_time and 'Sync:' in title:
        print(f\"{run['id']}|{run.get('status', '')}|{run.get('conclusion', '')}\")
        break
" 2>/dev/null)

    if [ -n "$LATEST_RUN" ]; then
        RUN_ID=$(echo "$LATEST_RUN" | cut -d'|' -f1)
        STATUS=$(echo "$LATEST_RUN" | cut -d'|' -f2)
        CONCLUSION=$(echo "$LATEST_RUN" | cut -d'|' -f3)

        if [ "$STATUS" = "completed" ]; then
            if [ "$CONCLUSION" = "success" ]; then
                echo -e "\r${GREEN}✅ 同步成功!${NC}                    "
                break
            else
                echo -e "\r${RED}❌ 同步失败 (${CONCLUSION})${NC}        "
                exit 1
            fi
        fi

        case "$STATUS" in
            "queued") MSG="队列中..." ;;
            "in_progress") MSG="同步中..." ;;
            *) MSG="等待中... [$STATUS]" ;;
        esac
        printf "\r${BLUE}⏳  ${MSG} %d 秒 [Run ID: $RUN_ID]${NC}" $WAIT_TIME
    else
        printf "\r${YELLOW}⏳ 等待 Action 启动... %d 秒${NC}" $WAIT_TIME
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

# 等待阿里云镜像可用（额外缓冲时间）
echo -e "${YELLOW}等待镜像可用...${NC}"
sleep 10

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

    # 重试拉取
    PULLED=false
    for attempt in {1..5}; do
        if $DOCKER pull "$ALIYUN_IMAGE" 2>/dev/null; then
            PULLED=true
            break
        else
            if [ $attempt -lt 5 ]; then
                sleep 3
            fi
        fi
    done

    if [ "$PULLED" = true ]; then
        $DOCKER tag "$ALIYUN_IMAGE" "${img}"
        $DOCKER rmi "$ALIYUN_IMAGE" 2>/dev/null || true
        echo -e "${GREEN}✅${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}❌ (5次重试失败)${NC}"
        echo -e "  手动拉取: $DOCKER pull $ALIYUN_IMAGE"
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
$DOCKER images | head -10
