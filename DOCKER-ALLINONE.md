# Moltbot All-in-One Docker 部署指南

这是 Moltbot 的单容器部署方案，将 Gateway 和 Browser 打包在一个容器中。

## 📋 特点

- ✅ 单个容器，管理简单
- ✅ 内置 Chromium + Xvfb (虚拟显示)
- ✅ 自动启动和健康检查
- ✅ 适合个人测试和小规模部署

## 🚀 快速部署

### 方式 1: 自动部署脚本（推荐）

```bash
# 在服务器上解压项目
cd /ai-proc
unzip moltbot.zip
cd moltbot

# 赋予脚本执行权限
chmod +x docker-allinone-deploy.sh

# 运行部署脚本
./docker-allinone-deploy.sh
```

### 方式 2: 手动部署

```bash
# 1. 构建镜像
docker build -t moltbot-allinone:latest -f Dockerfile.all-in-one .

# 2. 生成 Token
export CLAWDBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "保存此 Token: ${CLAWDBOT_GATEWAY_TOKEN}"

# 3. 创建配置目录
mkdir -p ~/.clawdbot
mkdir -p ~/clawd

# 4. 启动容器
docker run -d \
  --name moltbot \
  -p 18789:18789 \
  -v ~/.clawdbot:/home/node/.clawdbot \
  -v ~/clawd:/home/node/clawd \
  -e CLAWDBOT_GATEWAY_TOKEN="${CLAWDBOT_GATEWAY_TOKEN}" \
  -e CLAWDBOT_GATEWAY_BIND="lan" \
  --restart unless-stopped \
  --shm-size 2g \
  moltbot-allinone:latest
```

## ⚙️ 环境变量配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `CLAWDBOT_GATEWAY_TOKEN` | (必填) | Gateway 访问令牌 |
| `CLAWDBOT_GATEWAY_BIND` | `lan` | 监听地址 (`loopback`/`lan`) |
| `CLAWDBOT_GATEWAY_PORT` | `18789` | Gateway 端口 |
| `CLAWDBOT_BROWSER_CDP_PORT` | `9222` | Chrome CDP 端口 |
| `CLAWDBOT_BROWSER_HEADLESS` | `0` | 无头模式 (0=关闭, 1=开启) |

## 📝 配置文件

编辑 `~/.clawdbot/config.json`:

```json5
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "off",  // 单容器不需要沙箱模式
        "browser": {
          "enabled": true,
          "controlUrl": "http://localhost:9222",
          "headless": false
        }
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789
  },
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "你的飞书 App ID",
      "appSecret": "你的飞书 App Secret"
    }
  }
}
```

## 🔍 验证部署

```bash
# 查看容器状态
docker ps | grep moltbot

# 查看日志
docker logs -f moltbot

# 测试健康检查
curl http://localhost:18789/health

# 测试 Browser CDP (容器内)
docker exec moltbot curl http://localhost:9222/json/version
```

## 🛠️ 常用命令

```bash
# 查看实时日志
docker logs -f moltbot

# 进入容器
docker exec -it moltbot bash

# 重启容器
docker restart moltbot

# 停止容器
docker stop moltbot

# 删除容器
docker rm moltbot

# 查看资源占用
docker stats moltbot
```

## 🐛 故障排查

### 容器无法启动

```bash
# 查看详细日志
docker logs moltbot

# 检查端口占用
netstat -tlnp | grep 18789
```

### Browser 无法连接

```bash
# 进入容器检查
docker exec -it moltbot bash

# 测试 CDP
curl http://localhost:9222/json/version

# 检查 Chromium 进程
ps aux | grep chromium

# 检查 Xvfb 进程
ps aux | grep Xvfb
```

### 内存不足

```bash
# Chromium 需要较多内存，建议:
# - 系统内存: 至少 2GB
# - --shm-size: 至少 2g
# - 如果仍然崩溃，增加 swap

# 调整启动参数
docker run -d \
  --name moltbot \
  --shm-size 4g \
  --memory 2g \
  --memory-swap 4g \
  ...其他参数
```

### 查看启动过程

```bash
# 实时监控启动日志
docker logs -f moltbot

# 应该看到类似输出:
# [1/3] Starting Xvfb...
# ✓ Xvfb started (PID: 123)
# [2/3] Starting Chromium with CDP...
# ✓ Chromium CDP is ready (PID: 456)
# [3/3] Starting Moltbot Gateway...
# Gateway: http://0.0.0.0:18789
```

## 📦 目录结构

```
~/.clawdbot/          # Moltbot 配置目录
  ├── config.json     # 主配置文件
  ├── credentials/    # 登录凭证
  └── agents/         # Agent 会话数据

~/clawd/              # 工作区目录
  └── (Agent 工作文件)
```

## 🔄 更新版本

```bash
# 1. 停止并删除旧容器
docker stop moltbot
docker rm moltbot

# 2. 重新构建镜像
cd moltbot
git pull  # 如果使用 git
docker build -t moltbot-allinone:latest -f Dockerfile.all-in-one .

# 3. 重新启动
./docker-allinone-deploy.sh
```

## ⚠️ 限制说明

- **不支持沙箱隔离**: Browser 和 Gateway 在同一容器，无法实现工具沙箱
- **进程管理**: Browser 崩溃会导致整个容器重启
- **资源共享**: CPU/内存由所有进程共享

## 🆚 与多容器方案对比

如需更好的隔离性、可扩展性和稳定性，建议使用多容器方案：
- 参考 `docker-compose.yml`
- 或查看官方文档: https://docs.molt.bot/install/docker

## 📞 获取帮助

- GitHub Issues: https://github.com/moltbot/moltbot/issues
- 官方文档: https://docs.molt.bot

---

**提示**: 这是社区贡献的单容器方案，官方推荐使用 Docker Compose 多容器部署。
