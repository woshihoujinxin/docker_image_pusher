#!/bin/bash
# 动态获取 GitHub hosts 配置 - 使用 GitHub520
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "  更新 GitHub Hosts (GitHub520)"
echo "==========================================${NC}"
echo ""

# 备份当前 hosts
sudo cp /etc/hosts /etc/hosts.backup-$(date +%Y%m%d-%H%M%S)
echo "✅ 已备份 /etc/hosts"

# 清理旧的 GitHub 配置
sudo sed -i '/# GitHub 配置/,/# GitHub 配置结束/d' /etc/hosts
echo "✅ 已清理旧配置"

# 从 GitHub520 获取
echo -e "${YELLOW}从 GitHub520 获取 hosts...${NC}"
GITHUB520_URL="https://raw.hellogithub.com/hosts"

if ! HOSTS_CONTENT=$(curl -s --connect-timeout 10 "$GITHUB520_URL"); then
    echo -e "${RED}❌ 获取失败${NC}"
    echo "请检查网络或手动访问: $GITHUB520_URL"
    exit 1
fi

# 添加配置
sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 配置 - $(date +%Y-%m-%d)
# 数据源: GitHub520 (https://github.com/521xueweihan/GitHub520)
# 更新方式: bash ~/docker_image_pusher/update-github-hosts.sh
# 手动查看: https://raw.hellogithub.com/hosts
EOFMARKER

# 只添加 GitHub 相关的行
echo "$HOSTS_CONTENT" | grep -E "^[0-9]" | while read -r line; do
    # 确保是 GitHub 相关域名
    if echo "$line" | grep -qiE "github|githubusercontent|githubstatic"; then
        echo "$line" | sudo tee -a /etc/hosts > /dev/null
    fi
done

sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 配置结束
EOFMARKER

echo -e "${GREEN}✅ 配置已更新${NC}"

# 测试连接
echo ""
if curl -I --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ GitHub 连接正常${NC}"
else
    echo -e "${YELLOW}⚠️  连接测试失败，配置已更新但可能需要生效时间${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 完成!"
echo "==========================================${NC}"
echo ""
echo "GitHub520 项目:"
echo "  https://github.com/521xueweihan/GitHub520 (29k+ stars)"
echo "  最后更新: 2026-07-25"
echo ""
echo "手动查看:"
echo "  https://raw.hellogithub.com/hosts"
