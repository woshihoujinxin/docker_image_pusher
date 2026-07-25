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

# === 步骤 1: 动态配置 GitHub hosts ===
echo -e "${YELLOW}[1/5] 动态配置 GitHub hosts...${NC}"

if [ -f "update-github-hosts.sh" ]; then
    bash update-github-hosts.sh
else
    echo -e "${RED}❌ update-github-hosts.sh 不存在${NC}"
    exit 1
fi

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

if [ -f "docker-sync.sh" ]; then
    cp docker-sync.sh "$HOME/docker-sync.sh"
    chmod +x "$HOME/docker-sync.sh"
    echo -e "${GREEN}✅ 同步脚本已安装: ~/docker-sync.sh${NC}"
else
    echo -e "${RED}❌ docker-sync.sh 不存在${NC}"
    exit 1
fi

# 添加定时更新 hosts（可选）
echo ""
echo -e "${YELLOW}是否设置定时更新 GitHub hosts? (每周一凌晨3点)${NC}"
read -p "y/N: " auto_update
if [[ "$auto_update" =~ ^[Yy]$ ]]; then
    # 安装到 crontab
    CRON_JOB="0 3 * * 1 bash $PWD/update-github-hosts.sh > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "update-github-hosts"; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✅ 已设置定时更新${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 部署完成!"
echo "==========================================${NC}"
echo ""
echo "使用方法:"
echo "  bash ~/docker-sync.sh <镜像名>"
echo ""
echo "更新 GitHub hosts:"
echo "  bash ~/docker_image_pusher/update-github-hosts.sh"
echo ""
echo "示例:"
echo "  bash ~/docker-sync.sh nginx:latest"
echo "  bash ~/docker-sync.sh redis:latest postgres:15"
