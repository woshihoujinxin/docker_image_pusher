#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_DIR="$HOME/docker_image_pusher"
GITHUB_USER="woshihoujinxin"
GITHUB_REPO="docker_image_pusher"
GITHUB_TOKEN_FILE="$HOME/.github_token"

ALIYUN_REGISTRY="registry.cn-hangzhou.aliyuncs.com"
ALIYUN_NAMESPACE="houjinxin"

if ! docker info &>/dev/null; then
    if ! groups | grep -q "\bdocker\b"; then
        sudo usermod -aG docker "$USER" >/dev/null 2>&1
    fi
    DOCKER="sudo docker"
else
    DOCKER="docker"
fi

convert_image_name() {
    local image="$1"
    image="${image%%@*}"
    local image_name_tag=$(echo "$image" | awk -F'/' '{print $NF}')
    local name_space=$(echo "$image" | awk -F'/' '{if (NF==3) print $2; else if (NF==2) print $1; else print ""}')
    local image_name=$(echo "$image_name_tag" | awk -F':' '{print $1}')
    
    if [ -n "$name_space" ]; then
        echo "${name_space}_${image_name_tag}"
    else
        echo "$image_name_tag"
    fi
}

get_status() {
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('status', 'unknown'))"
}

get_conclusion() {
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('conclusion', 'none'))"
}

echo -e "${GREEN}=========================================="
echo "  Docker 镜像自动同步"
echo "==========================================${NC}"

if [ $# -eq 0 ]; then
    echo -e "${YELLOW}用法: $0 <镜像1[:标签1]> [镜像2[:标签2]] ...${NC}"
    exit 1
fi

IMAGES=()
for arg in "$@"; do
    if [[ "$arg" == *:* ]]; then
        IMAGES+=("$arg")
    else
        IMAGES+=("$arg:latest")
    fi
done

echo
echo -e "待同步镜像:"
for img in "${IMAGES[@]}"; do
    echo -e "  ${YELLOW}${img}${NC}"
done

GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE")

echo
echo -e "${YELLOW}[1/3] 触发 GitHub Action 同步...${NC}"

cd "$REPO_DIR" || exit 1

> images.txt
for img in "${IMAGES[@]}"; do
    echo "$img" >> images.txt
done

git config --local url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

git pull && git add images.txt && git commit -m "Sync: ${IMAGES[*]}" && git push
echo -e "${GREEN}✅ 镜像已在同步队列中${NC}"

echo
echo -e "${YELLOW}[2/3] 等待同步完成...${NC}"
echo "查看: https://github.com/${GITHUB_USER}/${GITHUB_REPO}/actions"
echo

RUN_ID=""
WAIT_TIME=0
MAX_WAIT=300
CHECK_INTERVAL=5

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if [ -z "$RUN_ID" ]; then
        RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs?per_page=1")
        RUN_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); runs=data.get('workflow_runs', []); print(runs[0].get('id') if runs else '')" 2>/dev/null)
    fi

    if [ -n "$RUN_ID" ]; then
        RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs/$RUN_ID")
        
        STATUS=$(echo "$RESPONSE" | get_status)
        CONCLUSION=$(echo "$RESPONSE" | get_conclusion)

        if [ "$STATUS" = "completed" ]; then
            if [ "$CONCLUSION" = "success" ]; then
                printf "\r${GREEN}✅ 同步成功!${NC}        "
                break
            else
                printf "\r${RED}❌ 同步失败 ($CONCLUSION)${NC}        "
                exit 1
            fi
        fi

        case "$STATUS" in
            "queued") MSG="队列中..." ;;
            "in_progress") MSG="同步中..." ;;
            *) MSG="等待中...[$STATUS]" ;;
        esac
        printf "\r${BLUE}⏳  ${MSG} %d 秒 [Run ID: $RUN_ID]${NC}" $WAIT_TIME
    else
        printf "\r${YELLOW}⏳ 等待 Action 启动... %d 秒${NC}" $WAIT_TIME
    fi

    sleep $CHECK_INTERVAL
    WAIT_TIME=$((WAIT_TIME + CHECK_INTERVAL))
done

echo

sleep 10

echo
echo -e "${YELLOW}[3/3] 从阿里云拉取镜像...${NC}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for img in "${IMAGES[@]}"; do
    echo -n "  拉取 ${img}... "
    converted_name=$(convert_image_name "$img")
    ALIYUN_IMAGE="${ALIYUN_REGISTRY}/${ALIYUN_NAMESPACE}/${converted_name}"
    
    if $DOCKER pull "$ALIYUN_IMAGE" 2>/dev/null; then
        $DOCKER tag "$ALIYUN_IMAGE" "${img}"
        $DOCKER rmi "$ALIYUN_IMAGE" 2>/dev/null || true
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
