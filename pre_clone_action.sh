#!/usr/bin/env bash
#
# Copyright (C) 2025 ZqinKing
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
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

echo $REPO_URL $REPO_BRANCH
echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/repo_flag"
git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR

# GitHub Action 移除国内下载源
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

# ... 脚本前面部分保持不变 ...

cd $BUILD_DIR

# 1. 确保 feeds.conf.default 存在
[ -f feeds.conf.default ] || touch feeds.conf.default

# 2. 添加插件源 (使用强力覆盖模式)
# 先删除可能存在的重复定义
sed -i '/kenzo/d' feeds.conf.default
sed -i '/small/d' feeds.conf.default

echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;main" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small-package.git;main" >> feeds.conf.default

# 3. 更新 feeds (这是创建 feeds/kenzo 目录的步骤)
./scripts/feeds update -a

# 4. 【关键修正】在安装前删除冲突包
# 使用判断语句防止 "No such file or directory" 错误
[ -d "feeds/luci/applications/luci-app-passwall" ] && rm -rf feeds/luci/applications/luci-app-passwall
[ -d "feeds/luci/applications/luci-app-mosdns" ] && rm -rf feeds/luci/applications/luci-app-mosdns
[ -d "feeds/packages/net/mosdns" ] && rm -rf feeds/packages/net/mosdns

# 5. 安装全部插件
./scripts/feeds install -a
