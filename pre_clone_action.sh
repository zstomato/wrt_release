#!/usr/bin/env bash
#
# Copyright (C) 2025 Gemini
#
# 完整的 OpenWrt 编译前置脚本 - 增强版

set -e

# --- 基础环境准备 ---
BASE_PATH=$(cd $(dirname $0) && pwd)
Dev=$1

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR="$BASE_PATH/action_build"

echo "正在克隆源码: $REPO_URL 分支: $REPO_BRANCH"
echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/repo_flag"
git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR

# --- 移除国内镜像源 (GitHub Actions 环境加速) ---
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"
if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

cd "$BUILD_DIR"

# --- 1. 配置核心插件源 (Kenzo & Small) ---
# 使用 sed 确保 feeds.conf.default 干净且不重复
sed -i '/kenzo/d' feeds.conf.default
sed -i '/small/d' feeds.conf.default

echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;main" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small-package.git;main" >> feeds.conf.default

# --- 2. 更新 feeds (带重试机制) ---
echo "正在更新插件 Feeds..."
./scripts/feeds update -a || ./scripts/feeds update -a

# --- 3. 解决包冲突 (这是你能选到 PassWall 2 的关键) ---
# 删除源码自带的、可能与 Kenzo 源冲突的旧包
# 使用 -f 确保即使目录不存在也不会报错停止
set +e
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-passwall2
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/sing-box
set -e

# --- 4. 安装全部插件 ---
echo "正在安装插件 Feeds..."
./scripts/feeds install -a || echo "部分插件安装有警告，继续编译..."

# --- 5. 自动修正 .config (确保 PassWall 2 被正确勾选) ---
if [ -f "$CONFIG_FILE" ]; then
    echo "正在同步 .config 插件配置..."
    # 如果你手动填了 passwall2，确保它能匹配到 kenzo 源里的包名
    # 有些源里叫 luci-app-passwall (内含2代)，有些叫 luci-app-passwall2
    # 我们先检查 kenzo 里到底叫什么
    if [ -d "feeds/small/luci-app-passwall2" ]; then
        echo "检测到独立 PassWall 2 包，保持配置..."
    else
        echo "未发现独立 passwall2 包，将配置降级适配至 luci-app-passwall (最新版)..."
        sed -i 's/CONFIG_PACKAGE_luci-app-passwall2=y/CONFIG_PACKAGE_luci-app-passwall=y/g' "$CONFIG_FILE"
        sed -i 's/CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y/CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y/g' "$CONFIG_FILE"
    fi
    
    # 强制补全中文语言包
    echo "CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y" >> "$CONFIG_FILE"
    echo "CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y" >> "$CONFIG_FILE"
fi

# --- 6. 打印可用插件清单 (方便在 GitHub Action 日志查看) ---
echo "==============================================="
echo "已就绪！你可以在 .config 中选择以下热门插件:"
ls feeds/kenzo/ | grep luci-app | head -n 20
echo "...(更多插件请查看日志全文)..."
echo "==============================================="

exit 0
