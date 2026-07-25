#!/bin/bash
# 动态获取 GitHub hosts 配置 - 使用稳定源
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "  动态更新 GitHub Hosts"
echo "==========================================${NC}"
echo ""

# 备份当前 hosts
sudo cp /etc/hosts /etc/hosts.backup-$(date +%Y%m%d-%H%M%S)
echo "✅ 已备份 /etc/hosts"

# 清理旧的 GitHub 配置
sudo sed -i '/# GitHub 动态配置/,/# GitHub 动态配置结束/d' /etc/hosts
echo "✅ 已清理旧配置"

# 定义稳定的 hosts 源
SOURCES=(
    "https://raw.hellogithub.com/hosts|GitHub520"
    "https://raw.githubusercontent.com/hostsx/hosts/master/hosts|HostsX"
    "https://hostsfile.github.io/hosts/|HostsFile"
)

# 尝试从多个源获取
HOSTS_CONTENT=""
SOURCE_NAME=""

echo -e "${YELLOW}[1/2] 从稳定源获取 hosts 配置...${NC}"
for source in "${SOURCES[@]}"; do
    URL=$(echo "$source" | cut -d'|' -f1)
    NAME=$(echo "$source" | cut -d'|' -f2)
    
    echo -n "  尝试 $NAME... "
    CONTENT=$(curl -s --connect-timeout 5 "$URL" 2>/dev/null)
    
    if [ -n "$CONTENT" ] && echo "$CONTENT" | grep -q "github.com"; then
        echo -e "${GREEN}✓ 成功${NC}"
        HOSTS_CONTENT="$CONTENT"
        SOURCE_NAME="$NAME"
        break
    else
        echo -e "${RED}✗ 失败${NC}"
    fi
done

if [ -z "$HOSTS_CONTENT" ]; then
    echo -e "${RED}❌ 所有源都失败，使用 DNS 查询${NC}"
    SOURCE_NAME="DNS"
fi

# 添加配置到 hosts
sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 动态配置 - $(date +%Y-%m-%d)
# 数据源: $SOURCE_NAME
# 更新方式: bash ~/docker_image_pusher/update-github-hosts.sh
# 如遇问题可访问: https://raw.hellogithub.com/hosts
EOFMARKER

if [ "$SOURCE_NAME" = "DNS" ]; then
    # DNS 查询方式
    DOMAINS=("github.com" "api.github.com" "raw.githubusercontent.com" "user-images.githubusercontent.com" "avatars.githubusercontent.com")
    
    for domain in "${DOMAINS[@]}"; do
        for dns in "223.5.5.5" "119.29.29.29" "8.8.8.8" "1.1.1.1"; do
            IP=$(dig @$dns +short "$domain" +time=2 2>/dev/null | head -1)
            if [ -n "$IP" ] && [[ ! "$IP" =~ ";" ]]; then
                echo "$IP $domain" | sudo tee -a /etc/hosts > /dev/null
                echo -e "  ${GREEN}✓${NC} $domain → $IP"
                break
            fi
        done
    done
else
    # 从在线源提取 GitHub 相关配置
    echo "$HOSTS_CONTENT" | grep -E "^[0-9]" | while read -r line; do
        # 只添加 GitHub 相关的域名
        if echo "$line" | grep -qiE "github|githubusercontent|githubstatic"; then
            echo "$line" | sudo tee -a /etc/hosts > /dev/null
        fi
    done
    echo -e "  ${GREEN}✓${NC} 已添加 $SOURCE_NAME 配置"
fi

sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 动态配置结束
EOFMARKER

echo ""
echo -e "${YELLOW}[2/2] 测试连接...${NC}"

# 测试连接
if curl -I --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ GitHub 连接正常${NC}"
else
    echo -e "${YELLOW}⚠️  GitHub 连接测试失败，但配置已更新${NC}"
    echo -e "${YELLOW}  可能需要等待 DNS 生效或重启网络${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 更新完成!"
echo "==========================================${NC}"
echo ""
echo "使用说明:"
echo "  - 定期运行此脚本更新 hosts"
echo "  - 如遇问题可手动访问: https://raw.hellogithub.com/hosts"
echo "  - 备份文件: /etc/hosts.backup-*"
