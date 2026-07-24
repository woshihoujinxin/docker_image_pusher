#!/bin/bash
# Docker 镜像同步环境一键部署脚本
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/woshihoujinxin/docker_image_pusher/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/woshihoujinxin/docker_image_pusher/main/bootstrap.sh | CONFIGURE_HOSTS=1 bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

GITHUB_USER="woshihoujinxin"
GITHUB_REPO="docker_image_pusher"

echo -e "${GREEN}=========================================="
echo "  Docker 镜像同步环境 - 一键部署"
echo -e "==========================================${NC}"
echo ""

# 检测系统类型，兼容 macOS(BSD) 与 Linux(GNU) 的差异
OS_TYPE="$(uname)"
if [[ "$OS_TYPE" == "Darwin" ]]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

# 根据当前登录 shell 选择 rc 文件
case "${SHELL:-}" in
    */zsh)  RC_FILE="$HOME/.zshrc" ;;
    */bash) RC_FILE="$HOME/.bashrc" ;;
    *)      RC_FILE="$HOME/.profile" ;;
esac

# === 步骤 1: 配置 GitHub hosts (可选) ===
# 默认跳过。多数环境可直接访问 GitHub，无需修改 hosts。
# 仅当设置 CONFIGURE_HOSTS=1 时才执行。
if [[ "${CONFIGURE_HOSTS:-0}" == "1" ]]; then
    echo -e "${YELLOW}[1/5] 配置 GitHub hosts...${NC}"
    sudo cp /etc/hosts "/etc/hosts.backup-$(date +%Y%m%d)"
    sudo sed "${SED_INPLACE[@]}" '/github.com/d' /etc/hosts
    sudo sed "${SED_INPLACE[@]}" '/githubusercontent/d' /etc/hosts
    sudo sed "${SED_INPLACE[@]}" '/githubstatic/d' /etc/hosts
    sudo sed "${SED_INPLACE[@]}" '/api.github.com/d' /etc/hosts

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
else
    echo -e "${YELLOW}[1/5] 跳过 hosts 配置 (如需启用: CONFIGURE_HOSTS=1)${NC}"
fi

# === 步骤 2: 配置 GitHub Token ===
echo ""
echo -e "${YELLOW}[2/5] 配置 GitHub Token...${NC}"

if [ -f "$HOME/.github_token" ]; then
    echo -e "${GREEN}✅ Token 已存在${NC}"
else
    echo "请输入 GitHub Token (获取: https://github.com/settings/tokens)"
    echo "需要勾选 'repo' 权限"
    # curl|bash 场景下 stdin 是管道，改从 /dev/tty 读取
    if [ -t 0 ]; then
        read -sp "Token: " TOKEN
    else
        read -sp "Token: " TOKEN < /dev/tty
    fi
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
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    echo -e "${GREEN}✅ Docker 安装完成${NC}"
    echo "⚠️  请执行 'newgrp docker' 或重新登录后生效"
else
    echo -e "${GREEN}✅ Docker 已安装${NC}"
fi

# === 步骤 5: 部署同步脚本 ===
echo ""
echo -e "${YELLOW}[5/5] 部署同步脚本...${NC}"

# 优先使用本地仓库中的脚本; curl|bash 场景下从 GitHub raw 下载
SYNC_SRC=""
for candidate in \
    "$HOME/docker_image_pusher/docker-sync.sh" \
    "./docker-sync.sh" \
    "$(pwd)/docker-sync.sh"; do
    if [ -f "$candidate" ]; then
        SYNC_SRC="$candidate"
        break
    fi
done

if [ -z "$SYNC_SRC" ]; then
    mkdir -p "$HOME/docker_image_pusher"
    SYNC_SRC="$HOME/docker_image_pusher/docker-sync.sh"
    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/docker-sync.sh" \
        -o "$SYNC_SRC" || true
fi

if [ -f "$SYNC_SRC" ]; then
    cp "$SYNC_SRC" "$HOME/docker-sync.sh"
    chmod +x "$HOME/docker-sync.sh"
    echo -e "${GREEN}✅ 同步脚本已安装: ~/docker-sync.sh${NC}"
else
    echo -e "${RED}❌ docker-sync.sh 未找到${NC}"
    exit 1
fi

# 写入 alias 到当前 shell 的 rc 文件 (不存在则创建)
touch "$RC_FILE"
if ! grep -q "alias docker-sync=" "$RC_FILE"; then
    echo "alias docker-sync='\$HOME/docker-sync.sh'" >> "$RC_FILE"
    echo -e "${GREEN}✅ alias 已写入 ${RC_FILE}${NC}"
else
    echo -e "${GREEN}✅ alias 已存在于 ${RC_FILE}${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 部署完成!"
echo -e "==========================================${NC}"
echo ""
echo "使用方法:"
echo "  source ${RC_FILE}        # 或重新打开终端"
echo "  docker-sync <镜像名>"
echo ""
echo "示例:"
echo "  docker-sync nginx:latest"
echo "  docker-sync redis:latest postgres:15"
echo ""
echo "也可直接调用:"
echo "  bash ~/docker-sync.sh <镜像名>"
