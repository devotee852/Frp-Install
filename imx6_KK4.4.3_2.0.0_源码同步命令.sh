#!/bin/bash
# ==============================================================================
# i.MX6 Android KK4.4.3_2.0.0-ga 源码同步与编译（修复版）
# 适用版本：android_KK4.4.3_2.0.0-ga_core_source.tar.gz
# 推荐环境：Ubuntu 14.04 LTS 64位（EOL，脚本会自动切 old-releases 源）+ JDK 6
# 磁盘要求：请预留至少 100GB（源码约 30~40GB + 编译产物）
#
# 相对原脚本的修复点：
#   1) 14.04 EOL 后自动把 apt 源切到 old-releases.ubuntu.com（原文件备份为 .bak）
#   2) openjdk-6 在 14.04 官方源不存在：自动检测 JDK，缺失时给出安装指引并退出
#   3) repo 改为清华镜像 git-repo 并固定 v1.13.8（Python 2 兼容，14.04 可运行），
#      --repo-url 改用中科大镜像，不再依赖已失效的 ustclug 代理
#   4) repo init/sync 使用 HTTPS（中科大 git:// 协议已停用，实测连接被拒）
#   5) 删除原第4、5步：Boundary 内核/uboot 与官方补丁机制冲突，且 uboot 分支
#      在仓库中不存在；内核/U-Boot 一律以官方 core_source 补丁包为准（补丁自带并整体覆盖）
#   6) 同步重试循环改为 until 结构（原脚本重试逻辑被注释包住且判断对象错误）
#   7) make 增加 pipefail，编译失败能被脚本感知
# ==============================================================================

set -uo pipefail

VERSION_ID="${VERSION_ID:-}"

# ---------- 第0步：环境自检 ----------
echo "===== [0/7] 环境自检 ====="
. /etc/os-release 2>/dev/null || true
VERSION_ID="${VERSION_ID:-}"
echo "系统版本: ${PRETTY_NAME:-未知}"

if [ "$(id -u)" = "0" ]; then
    echo "请不要用 root 直接运行（repo 依赖普通用户的 HOME）"
    exit 1
fi

AVAIL=$(df -k "$HOME" | awk 'NR==2 {print $4}')
echo "磁盘剩余: $((AVAIL/1024/1024)) GB"
if [ "$((AVAIL/1024/1024))" -lt 100 ]; then
    echo "警告：磁盘不足 100GB，可能不够完成编译"
fi

if java -version 2>&1 | grep -q '1\.6'; then
    echo "JDK6 已就绪"
else
    echo "未检测到 JDK6（Android 4.4 必须用 JDK6 编译，JDK7/8 会直接报错）"
    echo "Ubuntu 14.04 官方源没有 openjdk-6，请二选一安装后重跑本脚本："
    echo "  A) Azul Zulu 6: https://www.azul.com/downloads/zulu-community/?version=java-6-lts"
    echo "  B) Oracle JDK 6 (jdk-6u45-linux-x64.bin, 第三方归档)"
    echo "安装示例：解压到 /opt/jdk1.6.0_45 后执行"
    echo "  sudo update-alternatives --install /usr/bin/java java /opt/jdk1.6.0_45/bin/java 100"
    echo "  sudo update-alternatives --install /usr/bin/javac javac /opt/jdk1.6.0_45/bin/javac 100"
    exit 1
fi

# ---------- 第1步：安装编译依赖 ----------
echo "===== [1/7] 安装编译依赖 ====="
if [ "$VERSION_ID" = "14.04" ]; then
    echo "Ubuntu 14.04 已 EOL，自动切换 apt 源到 old-releases（原文件备份为 sources.list.bak）"
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo sed -i -E 's|https?://(archive|security)\.ubuntu\.com|http://old-releases.ubuntu.com|g' /etc/apt/sources.list
fi
sudo apt-get update
sudo apt-get install -y \
    git curl uuid uuid-dev zlib1g-dev liblzma-dev liblzo2-2 liblzo2-dev \
    lzop u-boot-tools flex bison gperf libesd0-dev libwxgtk2.8-dev \
    build-essential libx11-dev libncurses5-dev genext2fs \
    libswitch-perl libxml2-utils gcc-multilib g++-multilib xsltproc python-markdown \
    lib32z1-dev lib32ncurses5-dev lib32bz2-1.0
sudo apt-get install -y liblz-dev 2>/dev/null || echo "liblz-dev 无此包（忽略，liblzma-dev 已装）"

# ---------- 第2步：安装 repo（清华镜像 + 固定 v1.13.8，兼容 Python 2） ----------
echo "===== [2/7] 安装 repo ====="
mkdir -p ~/bin
if [ ! -x ~/bin/repo ]; then
    git clone -b v1.13.8 --depth 1 https://mirrors.tuna.tsinghua.edu.cn/git/git-repo /tmp/git-repo
    cp /tmp/git-repo/repo ~/bin/repo
    chmod a+x ~/bin/repo
fi
export PATH="$HOME/bin:$PATH"
git config --global user.email "build@localhost" 2>/dev/null || true
git config --global user.name "build" 2>/dev/null || true
echo "repo 版本: $(repo --version 2>&1 | head -1)"
echo "提示：新终端里需要先执行 export PATH=\$HOME/bin:\$PATH"

# ---------- 第3步：同步 AOSP android-4.4.3_r1（中科大 HTTPS 镜像） ----------
echo "===== [3/7] repo init + sync（约 30~40GB，网络慢可把 -j4 改 -j2） ====="
mkdir -p ~/myandroid
cd ~/myandroid || exit 1
repo init -u https://mirrors.ustc.edu.cn/aosp/platform/manifest.git \
          -b android-4.4.3_r1 \
          --repo-url=https://mirrors.ustc.edu.cn/aosp/git-repo || exit 1
n=0
until repo sync -f -j4; do
    n=$((n+1))
    echo "同步中断，3 秒后第 ${n} 次重试..."
    sleep 3
done
echo "===== AOSP 基础源码同步完成 ====="

# ---------- 第4步：解压并应用 NXP 官方补丁包（内核/U-Boot 均由补丁包提供） ----------
echo "===== [4/7] 应用官方补丁 ====="
PATCH_TAR=/opt/android_KK4.4.3_2.0.0-ga_core_source.tar.gz
if [ ! -f "$PATCH_TAR" ]; then
    echo "错误：请先把 $PATCH_TAR 放入 /opt 后重跑本脚本"
    exit 1
fi
cd /opt
sudo tar xzvf "$PATCH_TAR"
cd /opt/android_KK4.4.3_2.0.0-ga_core_source/code
sudo tar xzvf KK4.4.3_2.0.0-ga.tar.gz
sudo chmod -R a+rwX /opt/android_KK4.4.3_2.0.0-ga_core_source
cd ~/myandroid
source /opt/android_KK4.4.3_2.0.0-ga_core_source/code/KK4.4.3_2.0.0-ga/and_patch.sh
c_patch /opt/android_KK4.4.3_2.0.0-ga_core_source/code/KK4.4.3_2.0.0-ga imx_KK4.4.3_2.0.0-ga
echo "补丁执行完毕，应看到 Success: Now you can build the Android code for FSL i.MX platform"

# ---------- 第5步：配置编译环境 ----------
echo "===== [5/7] 配置编译环境 ====="
cd ~/myandroid
source build/envsetup.sh
lunch sabresd_6dq-userdebug

# ---------- 第6步：编译 ----------
echo "===== [6/7] 开始编译（-j8 可按 CPU 核数 x2 调整） ====="
make -j8 2>&1 | tee build.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "编译失败，请查看 build.log"
    exit 1
fi
echo "===== 编译成功，产物在 out/target/product/sabresd_6dq/ ====="
