#!/bin/bash
# 动态获取 GitHub hosts 配置

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# 方法1: 从 GitHubHosts 获取
echo ""
echo -e "${YELLOW}[1/3] 尝试从 GitHubHosts 获取...${NC}"
GITHUB_HOSTS_URL="https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"
HOSTS_CONTENT=$(curl -s --connect-timeout 5 "$GITHUB_HOSTS_URL" 2>/dev/null)

if [ -n "$HOSTS_CONTENT" ] && echo "$HOSTS_CONTENT" | grep -q "github.com"; then
    echo -e "${GREEN}✅ 从 GitHub520 获取成功${NC}"
else
    echo -e "${YELLOW}⚠️  GitHub520 获取失败，尝试其他方法${NC}"
fi

# 方法2: DNS 查询
echo ""
echo -e "${YELLOW}[2/3] 通过 DNS 查询 GitHub IP...${NC}"

# 定义要查询的域名
DOMAINS=("github.com" "api.github.com" "raw.githubusercontent.com" "assets-cdn.github.com" "user-images.githubusercontent.com" "avatars.githubusercontent.com")

# 动态添加配置
sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 动态配置 - $(date +%Y-%m-%d)
# 更新方式: bash ~/docker_image_pusher/update-github-hosts.sh
EOFMARKER

for domain in "${DOMAINS[@]}"; do
    # 尝试多个 DNS 服务器
    IP=""
    for dns_server in "8.8.8.8" "1.1.1.1" "223.5.5.5" "119.29.29.29"; do
        IP=$(dig @"$dns_server" +short "$domain" +time=2 +tries=1 2>/dev/null | head -1)
        if [ -n "$IP" ] && [[ ! "$IP" =~ ";" ]]; then
            break
        fi
    done
    
    if [ -n "$IP" ]; then
        echo "$IP $domain" | sudo tee -a /etc/hosts > /dev/null
        echo -e "  ${GREEN}✓${NC} $domain → $IP"
    else
        echo -e "  ${RED}✗${NC} $domain → 查询失败"
    fi
done

# 方法3: 添加备用 IP（从 GitHub520 或其他源）
if [ -n "$HOSTS_CONTENT" ] && echo "$HOSTS_CONTENT" | grep -q "github.com"; then
    echo ""
    echo -e "${YELLOW}[3/3] 添加 GitHub520 备用配置...${NC}"
    
    # 提取 GitHub 相关的行并添加
    echo "$HOSTS_CONTENT" | grep -E "github|githubusercontent|githubstatic" | while read -r line; do
        # 检查是否已存在
        domain=$(echo "$line" | awk '{print $2}')
        if ! grep -q "$domain" /etc/hosts; then
            echo "$line" | sudo tee -a /etc/hosts > /dev/null
            echo -e "  ${GREEN}+${NC} $line"
        fi
    done
fi

sudo tee -a /etc/hosts > /dev/null << EOFMARKER
# GitHub 动态配置结束
EOFMARKER

echo ""
echo -e "${GREEN}=========================================="
echo "  ✅ 更新完成!"
echo "==========================================${NC}"
echo ""
echo "测试连接:"
curl -I --connect-timeout 5 https://github.com 2>&1 | head -3
