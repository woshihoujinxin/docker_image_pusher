#!/bin/bash
# Docker 镜像同步工具 - 一键部署脚本
# 执行方式: curl -fsSL https://raw.githubusercontent.com/woshihoujinxin/docker_image_pusher/main/bootstrap.sh | bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$HOME/docker_image_pusher"
REPO_URL="https://github.com/woshihoujinxin/docker_image_pusher"

echo -e "${GREEN}=========================================="
echo "  Docker 镜像同步工具 - 一键部署"
echo "==========================================${NC}"
echo

# 检查 Docker
echo -e "${YELLOW}[1/5] 检查环境...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker 未安装，请先安装 Docker${NC}"
    echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com | bash"
    exit 1
fi
echo -e "${GREEN}✅ Docker 已安装${NC}"

# 检查 Git
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}安装 Git...${NC}"
    sudo apt update && sudo apt install -y git
fi
echo -e "${GREEN}✅ Git 已安装${NC}"

# 克隆仓库
echo
echo -e "${YELLOW}[2/5] 克隆仓库...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    echo "目录已存在: $INSTALL_DIR"
    cd "$INSTALL_DIR"
    git pull
else
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi
echo -e "${GREEN}✅ 仓库已更新${NC}"

# 配置 Token
echo
echo -e "${YELLOW}[3/5] 配置 GitHub Token...${NC}"
if [ -f "$HOME/.github_token" ]; then
    echo -e "${GREEN}✅ Token 已配置${NC}"
else
    echo "请输入 GitHub Token（用于触发同步和查询状态）"
    echo "获取方式: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)"
    echo
    read -s -p "Token: " TOKEN
    echo
    if [ -n "$TOKEN" ]; then
        echo "$TOKEN" > "$HOME/.github_token"
        chmod 600 "$HOME/.github_token"
        echo -e "${GREEN}✅ Token 已保存${NC}"
    else
        echo -e "${YELLOW}跳过 Token 配置，稍后手动配置${NC}"
    fi
fi

# 设置脚本权限
echo
echo -e "${YELLOW}[4/5] 设置脚本权限...${NC}"
chmod +x "$INSTALL_DIR/scripts/"*.sh
echo -e "${GREEN}✅ 完成${NC}"

# 添加到 PATH
echo
echo -e "${YELLOW}[5/5] 配置快捷命令...${NC}"
SHELL_CONFIG="$HOME/.bashrc"
if ! grep -q "docker-sync" "$SHELL_CONFIG" 2>/dev/null; then
    cat >> "$SHELL_CONFIG" << 'EOF'

# Docker 镜像同步工具
alias docker-sync='$HOME/docker_image_pusher/scripts/docker-sync.sh'
EOF
    echo -e "${GREEN}✅ 已添加 docker-sync 别名${NC}"
    echo -e "${YELLOW}请运行: source ~/.bashrc${NC}"
else
    echo -e "${GREEN}✅ 别名已存在${NC}"
fi

echo
echo -e "${GREEN}=========================================="
echo "  ✅ 部署完成!"
echo "==========================================${NC}"
echo
echo -e "${YELLOW}使用方法:${NC}"
echo "  docker-sync nginx                    # 同步单个镜像"
echo "  docker-sync nginx redis postgres     # 同步多个镜像"
echo
echo -e "${YELLOW}其他命令:${NC}"
echo "  cd $INSTALL_DIR"
echo "  bash scripts/setup-token.sh         # 重新配置 Token"
echo
echo -e "${YELLOW}查看同步状态:${NC}"
echo "  https://github.com/woshihoujinxin/docker_image_pusher/actions"
