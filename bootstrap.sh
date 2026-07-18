#!/bin/bash
# Docker 镜像同步环境一键部署脚本
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# 从仓库复制脚本
if [ -f "docker-sync.sh" ]; then
    cp docker-sync.sh "$HOME/docker-sync.sh"
    chmod +x "$HOME/docker-sync.sh"
    echo -e "${GREEN}✅ 同步脚本已安装: ~/docker-sync.sh${NC}"
else
    echo -e "${RED}❌ docker-sync.sh 不存在${NC}"
    exit 1
fi

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
