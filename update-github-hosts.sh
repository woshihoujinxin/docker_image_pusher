#!/bin/bash
# 动态获取 GitHub hosts 配置 - GitHub520
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "  更新 GitHub Hosts (GitHub520)"
echo "==========================================${NC}"
echo ""

# 测试源地址是否可访问
GITHUB520_URL="https://raw.hellogithub.com/hosts"
GITHUB520_OFFICIAL="https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"

echo -e "${YELLOW}[1/3] 测试源地址可用性...${NC}"

WORKABLE_URL=""
for url in "$GITHUB520_URL" "$GITHUB520_OFFICIAL"; do
    echo -n "  测试 $(basename $url)... "
    if curl -s --head --connect-timeout 5 "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 可用${NC}"
        WORKABLE_URL="$url"
        break
    else
        echo -e "${RED}✗ 不可用${NC}"
    fi
done

if [ -z "$WORKABLE_URL" ]; then
    echo -e "${RED}❌ 所有源地址都不可用，放弃更新${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 使用: $WORKABLE_URL${NC}"

# 获取 hosts 内容
echo ""
echo -e "${YELLOW}[2/3] 获取 hosts 内容...${NC}"
HOSTS_CONTENT=$(curl -s "$WORKABLE_URL")

if [ -z "$HOSTS_CONTENT" ]; then
    echo -e "${RED}❌ 获取内容失败${NC}"
    exit 1
fi

if ! echo "$HOSTS_CONTENT" | grep -q "github.com"; then
    echo -e "${RED}❌ 内容格式错误（未找到 github.com）${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 内容获取成功${NC}"

# 备份和清理
echo ""
echo -e "${YELLOW}[3/3] 更新 hosts 配置...${NC}"

sudo cp /etc/hosts /etc/hosts.backup-$(date +%Y%m%d-%H%M%S)
echo "  已备份 /etc/hosts"

sudo sed -i '/# GitHub 配置/,/# GitHub 配置结束/d' /etc/hosts
echo "  已清理旧配置"

# 添加新配置
sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 配置 - $(date +%Y-%m-%d)
# 数据源: GitHub520 (https://github.com/521xueweihan/GitHub520)
# 源地址: $WORKABLE_URL
# 更新方式: bash ~/docker_image_pusher/update-github-hosts.sh
EOFMARKER

echo "$HOSTS_CONTENT" | grep -E "^[0-9]" | while read -r line; do
    if echo "$line" | grep -qiE "github|githubusercontent|githubstatic"; then
        echo "$line" | sudo tee -a /etc/hosts > /dev/null
    fi
done

sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 配置结束
EOFMARKER

echo -e "${GREEN}✅ 配置已更新${NC}"

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 完成!"
echo "==========================================${NC}"
echo ""
echo "GitHub520 项目: https://github.com/521xueweihan/GitHub520"
echo "备份文件: /etc/hosts.backup-*"
echo ""
echo "如遇问题可恢复:"
echo "  sudo cp /etc/hosts.backup-$(date +%Y%m%d-*) /etc/hosts"
