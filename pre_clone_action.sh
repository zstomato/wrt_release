#!/usr/bin/env bash
#
# Copyright (C) 2025 Gemini
#
# 完整的 OpenWrt 编译前置脚本 - 修复分支冲突版

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
# 注意：这里去掉了容易报错的 ;main 后缀，让 git 自动检测 master 或 main 分支
sed -i '/kenzo/d' feeds.conf.default
sed -i '/small/d' feeds.conf.default

echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small-package.git" >> feeds.conf.default

# --- 2. 更新 feeds (带容错处理) ---
echo "正在更新插件 Feeds..."
# 即使其中一个 feed 失败，也允许继续，避免 exit 1 导致 Action 中断
./scripts/feeds update -a || echo "警告：部分 Feeds 更新失败，但尝试继续执行..."

# --- 3. 解决包冲突 ---
# 必须删除源码自带的旧版包，否则无法安装 kenzo 源里的新版
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
./scripts/feeds install -a

# --- 5. 自动修正 .config 确保插件名对应 ---
if [ -f "$CONFIG_FILE" ]; then
    echo "正在同步 .config 插件配置..."
    
    # 检查 small 源中 passwall2 的实际位置
    # 如果源里有 luci-app-passwall2 文件夹，说明之前的 .config 无需修改
    if [ -d "feeds/small/luci-app-passwall2" ]; then
        echo "检测到独立 PassWall 2 包，配置正确。"
    elif [ -d "feeds/small/luci-app-passwall" ]; then
        echo "未发现独立 passwall2 包，正在将配置指向 luci-app-passwall (源内最新版)..."
        sed -i 's/CONFIG_PACKAGE_luci-app-passwall2=y/CONFIG_PACKAGE_luci-app-passwall=y/g' "$CONFIG_FILE"
        sed -i 's/CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y/CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y/g' "$CONFIG_FILE"
    fi
    
    # 强制补全 Passwall 所需的中文语言包
    echo "CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y" >> "$CONFIG_FILE"
fi

# --- 6. 打印确认信息 ---
echo "==============================================="
echo "脚本执行完毕，Kenzo 与 Small 源已就绪。"
echo "==============================================="

exit 0
