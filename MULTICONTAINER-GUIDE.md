# Moltbot 多容器 Docker 部署指南

这是 Moltbot 的多容器部署方案，将 Gateway、Browser 和 CLI 分离在独立容器中，并通过自定义网络 `moltbot-internal` 实现隔离通信。

## 📋 特点

- ✅ 多容器架构，服务隔离
- ✅ 自定义网络 `moltbot-internal` 用于容器间通信
- ✅ Browser CDP 端口仅容器内部访问，不暴露到主机
- ✅ Gateway 暴露 18789 端口，支持飞书长轮询集成
- ✅ 一键部署脚本，简化操作
- ✅ 自动健康检查和服务依赖管理
- ✅ 适合生产环境部署

## 🏗️ 架构说明

### 容器组成

```
┌─────────────────────────────────────────────────────┐
│           Docker Host (服务器)                       │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │    moltbot-internal network (bridge)          │ │
│  │                                               │ │
│  │  ┌──────────────────────────────┐            │ │
│  │  │  moltbot-gateway             │            │ │
│  │  │  • 端口: 18789 (暴露到主机)   │            │ │
│  │  │  • 职责: 接收飞书消息          │            │ │
│  │  │         调用 AI               │            │ │
│  │  │         执行工具              │──┐         │ │
│  │  └──────────────────────────────┘  │         │ │
│  │                │                    │         │ │
│  │                │ http://moltbot-    │         │ │
│  │                │ browser:9222       │         │ │
│  │                ↓                    │         │ │
│  │  ┌──────────────────────────────┐  │         │ │
│  │  │  moltbot-browser             │  │         │ │
│  │  │  • 端口: 9222 (仅内部)        │  │         │ │
│  │  │  • 职责: 提供浏览器服务        │  │         │ │
│  │  │         Chromium + Xvfb       │  │         │ │
│  │  └──────────────────────────────┘  │         │ │
│  │                                     │         │ │
│  │  ┌──────────────────────────────┐  │         │ │
│  │  │  moltbot-cli                 │──┘         │ │
│  │  │  • 职责: 管理和配置工具       │            │ │
│  │  └──────────────────────────────┘            │ │
│  │                                               │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  外部访问:                                           │
│  飞书服务器 → http://服务器IP:18789 → Gateway        │
└─────────────────────────────────────────────────────┘
```

### 网络通信

- **容器间通信**: 通过自定义网络 `moltbot-internal`，容器可以使用容器名称作为主机名互相访问
  - Gateway → Browser: `http://moltbot-browser:9222`
- **外部访问**: Gateway 的 18789 端口映射到主机，用于接收飞书回调
- **安全隔离**: Browser 的 CDP 端口 (9222) 不暴露到主机，仅容器内部可访问

## 🚀 快速部署

### 方式 1: 自动部署脚本（推荐）

```bash
# 1. 在服务器上解压项目
cd /ai-proc
unzip moltbot.zip
cd moltbot

# 2. 赋予脚本执行权限
chmod +x deploy-multicontainer.sh

# 3. 运行部署脚本
./deploy-multicontainer.sh
```

部署脚本会自动完成：
- ✅ 检查 Docker 和 Docker Compose 环境
- ✅ 构建 Gateway 镜像 (`moltbot:local`)
- ✅ 构建 Browser 镜像 (`moltbot-sandbox-browser:bookworm-slim`)
- ✅ 创建配置目录 (`~/.clawdbot`, `~/clawd`)
- ✅ 生成 Gateway Token (64 位 hex)
- ✅ 创建 `.env.multicontainer` 配置文件
- ✅ 启动所有容器
- ✅ 验证部署状态

### 方式 2: 手动部署

```bash
# 1. 构建 Gateway 镜像
docker build -t moltbot:local -f Dockerfile .

# 2. 构建 Browser 镜像
bash scripts/sandbox-browser-setup.sh

# 3. 创建配置目录
mkdir -p ~/.clawdbot
mkdir -p ~/clawd

# 4. 生成 Gateway Token
export CLAWDBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "请保存此 Token: ${CLAWDBOT_GATEWAY_TOKEN}"

# 5. 创建环境变量文件
cp .env.multicontainer.example .env.multicontainer

# 编辑 .env.multicontainer，填写以下关键配置:
# - CLAWDBOT_GATEWAY_TOKEN (刚才生成的 Token)
# - CLAWDBOT_CONFIG_DIR (默认 ~/.clawdbot)
# - CLAWDBOT_WORKSPACE_DIR (默认 ~/clawd)

# 6. 启动容器
docker-compose -f docker-compose.multicontainer.yml --env-file .env.multicontainer up -d

# 7. 查看容器状态
docker-compose -f docker-compose.multicontainer.yml ps
```

## ⚙️ 环境变量配置

编辑 `.env.multicontainer` 文件：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `CLAWDBOT_GATEWAY_TOKEN` | (必填) | Gateway 访问令牌，64 位 hex |
| `CLAWDBOT_GATEWAY_BIND` | `lan` | 监听地址 (`loopback`/`lan`) |
| `CLAWDBOT_GATEWAY_PORT` | `18789` | Gateway HTTP 端口 |
| `CLAWDBOT_BRIDGE_PORT` | `18790` | WebSocket 桥接端口（如需要）|
| `CLAWDBOT_CONFIG_DIR` | `~/.clawdbot` | Moltbot 配置目录 |
| `CLAWDBOT_WORKSPACE_DIR` | `~/clawd` | Agent 工作区目录 |
| `CLAWDBOT_IMAGE` | `moltbot:local` | Gateway 镜像名称 |
| `CLAUDE_AI_SESSION_KEY` | (可选) | Claude AI Session Key |
| `CLAUDE_WEB_SESSION_KEY` | (可选) | Claude Web Session Key |
| `CLAUDE_WEB_COOKIE` | (可选) | Claude Web Cookie |

### 生成 Gateway Token

```bash
# 使用 openssl 生成 64 位 hex token
openssl rand -hex 32

# 或使用 /dev/urandom
cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1
```

## 📝 配置 Moltbot

### 1. 创建配置文件

复制配置示例到配置目录：

```bash
cp config.multicontainer.json ~/.clawdbot/config.json
```

### 2. 编辑配置文件

编辑 `~/.clawdbot/config.json`，关键配置如下：

```json5
{
  "$schema": "https://raw.githubusercontent.com/moltbot/moltbot/main/src/config/config.schema.json",

  // Agent 配置
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "scope": "agent",
        "browser": {
          "enabled": true,
          "image": "moltbot-sandbox-browser:bookworm-slim",
          // 关键：通过容器名访问 Browser
          "controlUrl": "http://moltbot-browser:9222",
          "headless": false,
          "autoStart": true,
          "autoStartTimeoutMs": 30000
        },
        "docker": {
          "image": "moltbot-sandbox:bookworm-slim",
          "workdir": "/workspace",
          "readOnlyRoot": true,
          "tmpfs": ["/tmp", "/var/tmp", "/run"],
          "network": "none",
          "user": "1000:1000",
          "capDrop": ["ALL"],
          "pidsLimit": 256,
          "memory": "1g",
          "memorySwap": "2g"
        },
        "workspaceAccess": "none"
      }
    }
  },

  // Gateway 配置
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789
  },

  // 飞书集成配置（见下一节）
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "cli_xxxxxxxxxxxxx",
      "appSecret": "your_app_secret_here",
      "verificationToken": "your_verification_token_here",
      "encryptKey": "your_encrypt_key_here"
    }
  },

  // 工具配置
  "tools": {
    "sandbox": {
      "tools": {
        "allow": [
          "exec",
          "process",
          "read",
          "write",
          "edit",
          "browser",
          "sessions_list",
          "sessions_history",
          "sessions_send"
        ],
        "deny": [
          "canvas",
          "nodes",
          "cron",
          "discord",
          "gateway"
        ]
      }
    }
  },

  // Provider 配置
  "providers": {
    "anthropic": {
      "enabled": true
    }
  }
}
```

### 3. 重启 Gateway 使配置生效

```bash
docker-compose -f docker-compose.multicontainer.yml restart moltbot-gateway
```

## 🔗 飞书集成配置

### 1. 创建飞书应用

1. 访问[飞书开放平台](https://open.feishu.cn/)
2. 创建企业自建应用
3. 获取以下信息：
   - **App ID** (cli_xxxxxxxxxxxxx)
   - **App Secret**
   - **Verification Token**
   - **Encrypt Key**

### 2. 配置飞书应用权限

在飞书应用管理后台，开通以下权限：
- 获取与发送单聊、群组消息
- 获取用户 ID
- 以应用的身份发送消息

### 3. 设置事件回调地址

在飞书应用的"事件订阅"中配置：

```
回调地址: http://你的服务器IP:18789
```

**重要提示**：
- 确保服务器防火墙开放 18789 端口
- 如果使用内网服务器，需要配置公网 IP 或使用内网穿透工具

### 4. 订阅飞书事件

在事件订阅中添加以下事件：
- `im.message.receive_v1` - 接收消息

### 5. 更新 Moltbot 配置

编辑 `~/.clawdbot/config.json`，填写飞书信息：

```json5
{
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "cli_your_actual_app_id",
      "appSecret": "your_actual_app_secret",
      "verificationToken": "your_actual_verification_token",
      "encryptKey": "your_actual_encrypt_key"
    }
  }
}
```

### 6. 重启 Gateway

```bash
docker-compose -f docker-compose.multicontainer.yml restart moltbot-gateway
```

### 7. 验证飞书集成

在飞书中给应用发送消息，检查是否收到回复。

查看 Gateway 日志：

```bash
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-gateway
```

## 🔍 验证部署

### 1. 检查容器状态

```bash
docker-compose -f docker-compose.multicontainer.yml ps
```

**预期输出**：

```
NAME                IMAGE                                      STATUS
moltbot-gateway     moltbot:local                              Up (healthy)
moltbot-browser     moltbot-sandbox-browser:bookworm-slim      Up (healthy)
moltbot-cli         moltbot:local                              Exit 0
```

### 2. 验证 Gateway 健康

```bash
# 在服务器本地测试
curl http://localhost:18789/health

# 从外部测试（需要替换为实际 IP）
curl http://服务器IP:18789/health
```

**预期输出**: HTTP 200 OK

### 3. 验证容器间网络连通性

测试 Gateway 能否访问 Browser:

```bash
docker exec moltbot-gateway curl -s http://moltbot-browser:9222/json/version
```

**预期输出**: Chromium 版本信息的 JSON

```json
{
  "Browser": "Chrome/120.0.6099.109",
  "Protocol-Version": "1.3",
  "User-Agent": "Mozilla/5.0 ...",
  "V8-Version": "12.0.267.8",
  "WebKit-Version": "537.36"
}
```

### 4. 验证网络隔离

从主机尝试访问 Browser CDP 端口（应该失败）:

```bash
curl http://localhost:9222
```

**预期结果**: `Connection refused` 或超时（端口未暴露）

### 5. 检查自定义网络

```bash
docker network inspect moltbot-internal
```

**预期**: 看到 3 个容器都在此网络中：
- `moltbot-gateway`
- `moltbot-browser`
- `moltbot-cli`

### 6. 查看容器日志

```bash
# Gateway 日志
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-gateway

# Browser 日志
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-browser

# 所有容器日志
docker-compose -f docker-compose.multicontainer.yml logs -f
```

## 🛠️ 常用命令

### 容器管理

```bash
# 查看容器状态
docker-compose -f docker-compose.multicontainer.yml ps

# 查看实时日志
docker-compose -f docker-compose.multicontainer.yml logs -f

# 查看特定容器日志
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-gateway
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-browser

# 重启所有服务
docker-compose -f docker-compose.multicontainer.yml restart

# 重启特定服务
docker-compose -f docker-compose.multicontainer.yml restart moltbot-gateway
docker-compose -f docker-compose.multicontainer.yml restart moltbot-browser

# 停止所有服务
docker-compose -f docker-compose.multicontainer.yml stop

# 启动所有服务
docker-compose -f docker-compose.multicontainer.yml start

# 停止并删除容器
docker-compose -f docker-compose.multicontainer.yml down

# 停止、删除容器，并删除数据卷
docker-compose -f docker-compose.multicontainer.yml down -v
```

### 进入容器

```bash
# 进入 Gateway 容器
docker exec -it moltbot-gateway bash

# 进入 Browser 容器
docker exec -it moltbot-browser bash

# 使用 CLI 工具
docker-compose -f docker-compose.multicontainer.yml run --rm moltbot-cli --help
```

### 资源监控

```bash
# 查看容器资源占用
docker stats moltbot-gateway moltbot-browser

# 查看 Docker 磁盘占用
docker system df

# 清理未使用的镜像、容器、网络
docker system prune
```

### 网络调试

```bash
# 查看网络详情
docker network inspect moltbot-internal

# 测试 Gateway → Browser 连通性
docker exec moltbot-gateway curl http://moltbot-browser:9222/json/version

# 测试 Gateway → Browser 延迟
docker exec moltbot-gateway ping moltbot-browser

# 检查端口监听
docker exec moltbot-gateway ss -tlnp
docker exec moltbot-browser ss -tlnp
```

## 🐛 故障排查

### 容器无法启动

**症状**: 容器启动后立即退出

**排查步骤**:

```bash
# 1. 查看容器日志
docker-compose -f docker-compose.multicontainer.yml logs moltbot-gateway
docker-compose -f docker-compose.multicontainer.yml logs moltbot-browser

# 2. 检查镜像是否存在
docker images | grep moltbot

# 3. 检查环境变量
cat .env.multicontainer

# 4. 检查配置文件
cat ~/.clawdbot/config.json | jq .

# 5. 检查端口占用
netstat -tlnp | grep 18789
```

**常见原因**:
- ❌ Gateway Token 未设置或格式错误
- ❌ 配置文件 JSON 语法错误
- ❌ 端口 18789 被其他程序占用
- ❌ 配置目录挂载路径不存在

### Browser 无法连接

**症状**: Gateway 日志显示无法连接到 Browser

**排查步骤**:

```bash
# 1. 检查 Browser 容器状态
docker ps | grep moltbot-browser

# 2. 测试 CDP 端点
docker exec moltbot-gateway curl http://moltbot-browser:9222/json/version

# 3. 检查 Browser 日志
docker logs moltbot-browser

# 4. 检查网络连通性
docker exec moltbot-gateway ping moltbot-browser

# 5. 检查自定义网络
docker network inspect moltbot-internal
```

**常见原因**:
- ❌ Browser 容器未正常启动
- ❌ Chromium 进程崩溃（内存不足）
- ❌ 网络配置错误
- ❌ 配置文件中的 `controlUrl` 不正确

**解决方案**:
```bash
# 重启 Browser 容器
docker-compose -f docker-compose.multicontainer.yml restart moltbot-browser

# 如果是内存问题，增加 shm_size
# 编辑 docker-compose.multicontainer.yml:
#   moltbot-browser:
#     shm_size: 4gb  # 从 2gb 增加到 4gb
```

### 内存不足

**症状**: Browser 容器频繁重启，日志显示 OOM (Out of Memory)

**排查步骤**:

```bash
# 1. 检查系统内存
free -h

# 2. 查看容器内存限制
docker inspect moltbot-browser | grep -i memory

# 3. 查看容器资源占用
docker stats moltbot-browser
```

**解决方案**:

```bash
# 增加 shm_size（共享内存）
# 编辑 docker-compose.multicontainer.yml:
services:
  moltbot-browser:
    shm_size: 4gb  # 增加到 4GB

# 如果系统内存不足，添加 swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 重启容器
docker-compose -f docker-compose.multicontainer.yml restart moltbot-browser
```

### 飞书回调失败

**症状**: 飞书消息发送后无响应

**排查步骤**:

```bash
# 1. 检查 Gateway 日志
docker-compose -f docker-compose.multicontainer.yml logs -f moltbot-gateway

# 2. 检查端口是否开放
curl http://localhost:18789/health
curl http://服务器公网IP:18789/health

# 3. 检查防火墙规则
sudo iptables -L -n | grep 18789
sudo ufw status | grep 18789

# 4. 验证飞书配置
cat ~/.clawdbot/config.json | jq '.channels.feishu'
```

**常见原因**:
- ❌ 防火墙未开放 18789 端口
- ❌ 飞书回调地址配置错误
- ❌ 飞书应用配置信息错误
- ❌ Gateway 未正常启动

**解决方案**:

```bash
# 开放防火墙端口（Ubuntu/Debian）
sudo ufw allow 18789/tcp
sudo ufw reload

# 开放防火墙端口（CentOS/RHEL）
sudo firewall-cmd --zone=public --add-port=18789/tcp --permanent
sudo firewall-cmd --reload

# 重启 Gateway
docker-compose -f docker-compose.multicontainer.yml restart moltbot-gateway
```

### 网络连通性问题

**症状**: 容器间无法通信

**排查步骤**:

```bash
# 1. 检查自定义网络
docker network ls | grep moltbot-internal

# 2. 查看网络详情
docker network inspect moltbot-internal

# 3. 测试容器间 DNS 解析
docker exec moltbot-gateway nslookup moltbot-browser
docker exec moltbot-gateway ping -c 3 moltbot-browser

# 4. 检查容器是否在同一网络
docker inspect moltbot-gateway | grep -A 10 Networks
docker inspect moltbot-browser | grep -A 10 Networks
```

**解决方案**:

```bash
# 重新创建网络和容器
docker-compose -f docker-compose.multicontainer.yml down
docker network rm moltbot-internal
docker-compose -f docker-compose.multicontainer.yml up -d
```

### 配置文件错误

**症状**: Gateway 启动失败，日志显示配置错误

**排查步骤**:

```bash
# 1. 验证 JSON 语法
cat ~/.clawdbot/config.json | jq .

# 2. 检查配置文件路径
ls -la ~/.clawdbot/config.json

# 3. 检查文件权限
ls -l ~/.clawdbot/config.json
```

**解决方案**:

```bash
# 恢复配置示例
cp config.multicontainer.json ~/.clawdbot/config.json

# 修复文件权限
chmod 644 ~/.clawdbot/config.json

# 重启 Gateway
docker-compose -f docker-compose.multicontainer.yml restart moltbot-gateway
```

## 📦 目录结构

```
~/.clawdbot/              # Moltbot 配置目录
  ├── config.json         # 主配置文件
  ├── credentials/        # 登录凭证
  │   └── ...
  ├── agents/             # Agent 会话数据
  │   └── ...
  └── sessions/           # 会话历史

~/clawd/                  # Agent 工作区目录
  └── (Agent 工作文件)

/ai-proc/moltbot/         # 项目根目录
  ├── docker-compose.multicontainer.yml  # 多容器配置
  ├── deploy-multicontainer.sh           # 部署脚本
  ├── .env.multicontainer                # 环境变量（不提交）
  ├── .env.multicontainer.example        # 环境变量模板
  └── config.multicontainer.json         # 配置示例
```

## 🔄 更新版本

```bash
# 1. 停止并删除旧容器
docker-compose -f docker-compose.multicontainer.yml down

# 2. 获取最新代码
cd /ai-proc/moltbot
git pull  # 如果使用 git
# 或重新上传/解压新版本

# 3. 重新构建镜像
docker build -t moltbot:local -f Dockerfile .
bash scripts/sandbox-browser-setup.sh

# 4. 启动新容器
docker-compose -f docker-compose.multicontainer.yml up -d

# 5. 验证部署
docker-compose -f docker-compose.multicontainer.yml ps
curl http://localhost:18789/health
```

## 🔒 安全建议

1. **Gateway Token 管理**
   - 使用强随机生成的 Token (64 位 hex)
   - 定期轮换 Token
   - 不要在日志或公开文档中暴露 Token

2. **网络隔离**
   - Browser CDP 端口不对外暴露
   - 仅必要的端口映射到主机
   - 使用防火墙限制访问来源

3. **容器权限**
   - 避免使用 root 用户运行容器
   - 限制容器资源使用（CPU、内存）
   - 使用只读文件系统（readonly）

4. **配置文件权限**
   ```bash
   chmod 600 ~/.clawdbot/config.json
   chmod 600 .env.multicontainer
   ```

5. **日志管理**
   - 定期清理容器日志
   - 避免在日志中记录敏感信息
   ```bash
   # 配置日志轮转
   docker-compose -f docker-compose.multicontainer.yml \
     --env-file .env.multicontainer \
     --log-opt max-size=10m \
     --log-opt max-file=3 \
     up -d
   ```

## 📊 资源要求

### 最低配置

- **CPU**: 2 核
- **内存**: 4GB
- **磁盘**: 20GB
- **网络**: 稳定的互联网连接

### 推荐配置

- **CPU**: 4 核或更多
- **内存**: 8GB 或更多
- **磁盘**: 50GB SSD
- **网络**: 10Mbps 上行/下行

### 资源分配

- **moltbot-gateway**: 1GB 内存
- **moltbot-browser**: 2GB 内存 + 2GB shm
- **系统预留**: 1GB+ 内存

## 🆚 与其他部署方式对比

| 特性 | 多容器方案 | All-in-One 单容器 | 主机部署 |
|------|-----------|------------------|---------|
| 服务隔离 | ✅ 完全隔离 | ❌ 共享进程空间 | ❌ 无隔离 |
| 可扩展性 | ✅ 可独立扩展 | ❌ 整体扩展 | ❌ 难以扩展 |
| 故障隔离 | ✅ 单服务故障不影响其他 | ❌ 单点故障 | ❌ 单点故障 |
| 资源管理 | ✅ 独立资源限制 | ⚠️ 共享资源 | ⚠️ 依赖系统 |
| 部署复杂度 | ⚠️ 中等 | ✅ 简单 | ❌ 复杂 |
| 维护成本 | ⚠️ 中等 | ✅ 低 | ❌ 高 |
| 生产环境推荐 | ✅ 推荐 | ⚠️ 小规模可用 | ❌ 不推荐 |

## 📞 获取帮助

- **GitHub Issues**: https://github.com/moltbot/moltbot/issues
- **官方文档**: https://docs.molt.bot
- **项目仓库**: https://github.com/moltbot/moltbot

## 📚 相关文档

- [Moltbot 安装指南](https://docs.molt.bot/install)
- [Docker 部署文档](https://docs.molt.bot/install/docker)
- [飞书集成文档](https://docs.molt.bot/channels/feishu)
- [配置参考](https://docs.molt.bot/configuration)
- [沙箱模式说明](https://docs.molt.bot/gateway/sandboxing)

---

**提示**: 这是 Moltbot 官方推荐的多容器部署方案，适合生产环境使用。如需其他部署方式，请参考项目文档。
