#!/bin/bash
# 配置 GitHub Token
# 执行方式: bash scripts/setup-token.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GITHUB_TOKEN_FILE="$HOME/.github_token"

echo -e "${GREEN}=========================================="
echo "  配置 GitHub Token"
echo -e "==========================================${NC}"
echo

# 检查是否已存在
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    echo -e "${YELLOW}Token 文件已存在: $GITHUB_TOKEN_FILE${NC}"
    read -p "是否覆盖? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 获取 Token
echo -e "${YELLOW}请输入 GitHub Token:${NC}"
echo "获取方式: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)"
echo
read -s -p "Token: " TOKEN
echo

if [ -z "$TOKEN" ]; then
    echo -e "\033[0;31m❌ Token 不能为空${NC}"
    exit 1
fi

# 保存 Token
echo "$TOKEN" > "$GITHUB_TOKEN_FILE"
chmod 600 "$GITHUB_TOKEN_FILE"

echo
echo -e "${GREEN}✅ Token 已保存到 $GITHUB_TOKEN_FILE${NC}"
echo
echo -e "${YELLOW}验证 Token:${NC}"
if curl -s -H "Authorization: token $TOKEN" "https://api.github.com/user" | grep -q "login"; then
    echo -e "${GREEN}✅ Token 验证成功${NC}"
else
    echo -e "\033[0;31m❌ Token 验证失败，请检查${NC}"
    rm "$GITHUB_TOKEN_FILE"
    exit 1
fi
