# Docker Images Pusher

使用Github Action将国外的Docker镜像转存到阿里云私有仓库，供国内服务器使用，免费易用<br>
支持DockerHub, gcr.io, k8s.io, quay.io, ghcr.io等任意仓库

视频教程：https://www.bilibili.com/video/BV1Zn4y19743/

作者：**技术爬爬虾**<br>
B站，抖音，Youtube全网同名，转载请注明作者<br>

---

## 🚀 快速开始（本地客户端）

### 一键部署

```bash
curl -fsSL https://raw.githubusercontent.com/woshihoujinxin/docker_image_pusher/main/bootstrap.sh | bash
source ~/.bashrc
```

### 使用方法

```bash
# 同步单个镜像
docker-sync nginx

# 同步多个镜像
docker-sync nginx redis postgres

# 指定标签
docker-sync nginx:alpine postgres:16
```

**工作流程：**
```
docker-sync nginx
→ 触发 GitHub Action 同步
→ 等待完成（约 2-3 分钟）
→ 从阿里云拉取
→ 重命名为官方镜像名
→ 完成！
```

**效果：**
- 无需访问 Docker Hub
- 镜像自动同步到阿里云
- 本地显示为官方镜像名（如 `nginx:latest`）

---

## 📋 手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/woshihoujinxin/docker_image_pusher.git ~/docker_image_pusher
cd ~/docker_image_pusher

# 2. 配置 GitHub Token
bash scripts/setup-token.sh

# 3. 添加别名（可选）
echo "alias docker-sync='$HOME/docker_image_pusher/scripts/docker-sync.sh'" >> ~/.bashrc
source ~/.bashrc
```

---

## 🔧 GitHub 原始使用方式

### 配置阿里云
登录阿里云容器镜像服务<br>
https://cr.console.aliyun.com/<br>
启用个人实例，创建一个命名空间（**ALIYUN_NAME_SPACE**）

访问凭证–>获取环境变量<br>
- 用户名（**ALIYUN_REGISTRY_USER**）
- 密码（**ALIYUN_REGISTRY_PASSWORD**）
- 仓库地址（**ALIYUN_REGISTRY**）

### Fork 本项目并配置
1. Fork 本项目
2. 进入 Actions，启用 GitHub Action
3. Settings → Secrets and variables → Actions → New repository secret
4. 添加环境变量：
   - `ALIYUN_NAME_SPACE`
   - `ALIYUN_REGISTRY_USER`
   - `ALIYUN_REGISTRY_PASSWORD`
   - `ALIYUN_REGISTRY`

### 添加镜像
编辑 `images.txt` 文件，添加你想要的镜像：
```
nginx
postgres:16
redis:alpine
```

提交后自动触发 GitHub Action 构建。

### 使用镜像
```bash
docker pull registry.cn-hangzhou.aliyuncs.com/shrimp-images/nginx
```

---

## 📝 脚本说明

| 脚本 | 说明 |
|------|------|
| `bootstrap.sh` | 一键部署脚本 |
| `scripts/docker-sync.sh` | 镜像同步主脚本 |
| `scripts/setup-token.sh` | GitHub Token 配置 |

---

## 📖 高级功能

### 多架构镜像
在 `images.txt` 中添加 `--platform` 参数：
```
nginx --platform=linux/arm64
```

### 私有仓库镜像
支持 gcr.io, k8s.io, quay.io, ghcr.io 等任意仓库：
```
k8s.gcr.io/kube-state-metrics/kube-state-metrics
```

### 定时同步
修改 `.github/workflows/docker.yaml` 添加 schedule（UTC 时区）：
```yaml
schedule:
  - cron: '0 2 * * *'  # 每天凌晨 2 点
```
