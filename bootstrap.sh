#!/bin/bash
# Docker 镜像同步环境一键部署脚本
# 适用于新环境快速配置

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "  Docker 镜像同步环境 - 一键部署"
echo "==========================================${NC}"
echo ""

# === 步骤 1: 配置 GitHub hosts ===
echo -e "${YELLOW}[1/5] 配置 GitHub hosts...${NC}"
sudo cp /etc/hosts /etc/hosts.backup-$(date +%Y%m%d)
sudo sed -i '/github.com/d' /etc/hosts
sudo sed -i '/githubusercontent/d' /etc/hosts
sudo sed -i '/githubstatic/d' /etc/hosts
sudo sed -i '/api.github.com/d' /etc/hosts

sudo tee -a /etc/hosts > /dev/null << 'HOSTS'

# GitHub 国内加速
140.82.113.3 github.com
140.82.112.5 api.github.com
185.199.108.133 raw.githubusercontent.com
185.199.108.133 user-images.githubusercontent.com
185.199.108.133 avatars.githubusercontent.com
185.199.108.153 assets-cdn.github.com
HOSTS

echo -e "${GREEN}✅ hosts 配置完成${NC}"

# === 步骤 2: 配置 GitHub Token ===
echo ""
echo -e "${YELLOW}[2/5] 配置 GitHub Token...${NC}"

if [ -f "$HOME/.github_token" ]; then
    echo -e "${GREEN}✅ Token 已存在${NC}"
else
    echo "请输入 GitHub Token (获取: https://github.com/settings/tokens)"
    echo "需要勾选 'repo' 权限"
    read -sp "Token: " TOKEN
    echo
    echo "$TOKEN" > "$HOME/.github_token"
    chmod 600 "$HOME/.github_token"
    echo -e "${GREEN}✅ Token 已保存${NC}"
fi

# === 步骤 3: 配置 Git ===
echo ""
echo -e "${YELLOW}[3/5] 配置 Git...${NC}"

TOKEN=$(cat "$HOME/.github_token")
git config --global url."https://${TOKEN}@github.com/".insteadOf "https://github.com/"
git config --global user.name "Docker Sync"
git config --global user.email "sync@local"

echo -e "${GREEN}✅ Git 配置完成${NC}"

# === 步骤 4: 安装 Docker ===
echo ""
echo -e "${YELLOW}[4/5] 检查 Docker...${NC}"

if ! command -v docker &>/dev/null; then
    echo "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}✅ Docker 安装完成${NC}"
    echo "⚠️  请执行 'newgrp docker' 或重新登录后生效"
else
    echo -e "${GREEN}✅ Docker 已安装${NC}"
fi

# === 步骤 5: 部署同步脚本 ===
echo ""
echo -e "${YELLOW}[5/5] 部署同步脚本...${NC}"

# 创建同步脚本
cat > "$HOME/docker-sync.sh" << 'SYNCSCRIPT'
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
        RUNS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs?per_page=1")
        RUN_ID=$(echo "$RUNS" | grep -oP '"id":\s*\K\d+' | head -1)
    fi

    if [ -n "$RUN_ID" ]; then
        STATUS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs/$RUN_ID" \
                | grep -oP '"status":"\K[^"]+' | head -1)
        CONCLUSION=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs/$RUN_ID" \
                | grep -oP '"conclusion":"\K[^"]+' | head -1)

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
            *) MSG="等待中..." ;;
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
SYNCSCRIPT

chmod +x "$HOME/docker-sync.sh"

echo -e "${GREEN}✅ 同步脚本已安装: ~/docker-sync.sh${NC}"

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 部署完成!"
echo "==========================================${NC}"
echo ""
echo "使用方法:"
echo "  bash ~/docker-sync.sh <镜像名>"
echo ""
echo "示例:"
echo "  bash ~/docker-sync.sh nginx:latest"
echo "  bash ~/docker-sync.sh redis:latest postgres:15"
