#!/bin/bash
set -euo pipefail

# Moltbot 多容器部署脚本
# 用途：一键构建镜像、生成配置、启动多容器环境

echo "========================================="
echo "  Moltbot 多容器部署脚本"
echo "  Multi-Container Deployment"
echo "========================================="
echo ""

# ===== 配置变量 =====
COMPOSE_FILE="docker-compose.multicontainer.yml"
ENV_FILE=".env.multicontainer"
ENV_EXAMPLE=".env.multicontainer.example"
CONFIG_DIR="${HOME}/.clawdbot"
WORKSPACE_DIR="${HOME}/clawd"
GATEWAY_IMAGE="moltbot:local"
BROWSER_IMAGE="moltbot-sandbox-browser:bookworm-slim"

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== 辅助函数 =====
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ===== 1. 前置检查 =====
log_info "检查运行环境..."

# 检查是否在项目根目录
if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_error "未找到 ${COMPOSE_FILE}"
    log_error "请在 moltbot 项目根目录运行此脚本"
    exit 1
fi

if [[ ! -f "Dockerfile" ]]; then
    log_error "未找到 Dockerfile"
    log_error "请确认当前目录是 moltbot 项目根目录"
    exit 1
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装，请先安装 Docker"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker 服务未运行，请启动 Docker"
    exit 1
fi

log_success "Docker 已就绪"

# 检查 Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log_error "Docker Compose 未安装"
    log_error "请安装 Docker Compose v2 或更高版本"
    exit 1
fi

# 使用 docker compose 或 docker-compose
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

log_success "Docker Compose 已就绪"

echo ""

# ===== 2. 停止旧容器（如果存在）=====
log_info "检查并停止旧容器..."

if ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" ps | grep -q "moltbot-gateway\|moltbot-browser"; then
    log_warning "发现运行中的容器，正在停止..."
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down 2>/dev/null || true
    log_success "旧容器已停止"
else
    log_info "未发现运行中的容器"
fi

echo ""

# ===== 3. 构建镜像 =====
log_info "开始构建 Docker 镜像（这可能需要几分钟）..."

# 构建 Gateway 镜像
log_info "构建 Gateway 镜像: ${GATEWAY_IMAGE}"
if docker build -t "${GATEWAY_IMAGE}" -f Dockerfile . ; then
    log_success "Gateway 镜像构建成功"
else
    log_error "Gateway 镜像构建失败"
    exit 1
fi

echo ""

# 构建 Browser 镜像
log_info "构建 Browser 镜像: ${BROWSER_IMAGE}"
if [[ -f "scripts/sandbox-browser-setup.sh" ]]; then
    if bash scripts/sandbox-browser-setup.sh; then
        log_success "Browser 镜像构建成功"
    else
        log_error "Browser 镜像构建失败"
        exit 1
    fi
else
    log_error "未找到 scripts/sandbox-browser-setup.sh"
    exit 1
fi

echo ""

# ===== 4. 创建配置目录 =====
log_info "创建配置目录..."

mkdir -p "${CONFIG_DIR}"
mkdir -p "${WORKSPACE_DIR}"

log_success "配置目录已创建"
log_info "  配置目录: ${CONFIG_DIR}"
log_info "  工作区目录: ${WORKSPACE_DIR}"

echo ""

# ===== 5. 生成环境变量文件 =====
log_info "生成环境变量文件..."

# 检查是否已存在 .env 文件
if [[ -f "${ENV_FILE}" ]]; then
    log_warning "${ENV_FILE} 已存在"
    read -p "是否覆盖？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "跳过环境变量生成，使用现有文件"
    else
        rm -f "${ENV_FILE}"
        CREATE_ENV=true
    fi
else
    CREATE_ENV=true
fi

if [[ "${CREATE_ENV:-false}" == "true" ]]; then
    # 生成 Gateway Token
    if command -v openssl &> /dev/null; then
        GATEWAY_TOKEN=$(openssl rand -hex 32)
    else
        # fallback: 使用 /dev/urandom
        GATEWAY_TOKEN=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
    fi

    # 创建 .env 文件
    cat > "${ENV_FILE}" << EOF
# ===== Moltbot Gateway 配置 =====
CLAWDBOT_GATEWAY_TOKEN=${GATEWAY_TOKEN}
CLAWDBOT_GATEWAY_PORT=18789
CLAWDBOT_GATEWAY_BIND=lan
CLAWDBOT_BRIDGE_PORT=18790

# ===== 目录配置 =====
CLAWDBOT_CONFIG_DIR=${CONFIG_DIR}
CLAWDBOT_WORKSPACE_DIR=${WORKSPACE_DIR}

# ===== 镜像配置 =====
CLAWDBOT_IMAGE=${GATEWAY_IMAGE}

# ===== Claude API（可选）=====
CLAUDE_AI_SESSION_KEY=
CLAUDE_WEB_SESSION_KEY=
CLAUDE_WEB_COOKIE=
EOF

    log_success "环境变量文件已生成: ${ENV_FILE}"
    echo ""
    log_warning "重要：请保存以下 Gateway Token"
    echo "========================================"
    echo "  ${GATEWAY_TOKEN}"
    echo "========================================"
    echo ""
fi

# ===== 6. 启动容器 =====
log_info "启动多容器服务..."

if ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d; then
    log_success "容器启动成功"
else
    log_error "容器启动失败"
    log_error "请查看日志: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} logs"
    exit 1
fi

echo ""

# ===== 7. 等待服务就绪 =====
log_info "等待服务启动..."
sleep 5

# ===== 8. 验证部署 =====
log_info "验证部署状态..."

# 检查容器状态
GATEWAY_STATUS=$(docker inspect -f '{{.State.Running}}' moltbot-gateway 2>/dev/null || echo "false")
BROWSER_STATUS=$(docker inspect -f '{{.State.Running}}' moltbot-browser 2>/dev/null || echo "false")

if [[ "${GATEWAY_STATUS}" == "true" ]] && [[ "${BROWSER_STATUS}" == "true" ]]; then
    log_success "所有容器运行正常"
else
    log_error "部分容器未正常运行"
    log_info "查看容器状态: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} ps"
fi

echo ""

# ===== 9. 显示访问信息 =====
echo "========================================="
echo "  ✅ 部署完成！"
echo "========================================="
echo ""
echo "📋 服务信息:"
echo "  Gateway: http://localhost:18789"
echo "  或访问: http://服务器IP:18789"
echo ""
echo "📝 后续步骤:"
echo ""
echo "1️⃣  配置 Moltbot"
echo "   编辑: ${CONFIG_DIR}/config.json"
echo "   参考: config.multicontainer.json"
echo ""
echo "2️⃣  配置飞书集成"
echo "   在配置文件中添加飞书 App 信息"
echo "   回调地址: http://服务器IP:18789"
echo ""
echo "3️⃣  重启 Gateway"
echo "   ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} restart moltbot-gateway"
echo ""
echo "📚 常用命令:"
echo "  查看状态: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} ps"
echo "  查看日志: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} logs -f"
echo "  重启服务: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} restart"
echo "  停止服务: ${DOCKER_COMPOSE} -f ${COMPOSE_FILE} down"
echo ""
echo "🔍 验证部署:"
echo "  健康检查: curl http://localhost:18789/health"
echo "  容器通信: docker exec moltbot-gateway curl http://moltbot-browser:9222/json/version"
echo "  网络详情: docker network inspect moltbot-internal"
echo ""
echo "📖 完整文档: MULTICONTAINER-GUIDE.md"
echo ""
echo "========================================="
