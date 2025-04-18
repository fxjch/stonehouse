#!/usr/bin/env bash
set -e

# =========================================
# 作者: jinqians
# 日期: 2025年3月
# 网站：jinqians.com
# 描述: Shadowsocks Rust 管理脚本
# =========================================

# 版本信息
SCRIPT_VERSION="1.5.3"
SS_VERSION=""

# 系统路径
SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
SCRIPT_NAME=$(basename "$0")

# 安装路径
INSTALL_DIR="/etc/ss-rust"
BINARY_PATH="/usr/local/bin/ss-rust"
CONFIG_PATH="/etc/ss-rust/config.json"
VERSION_FILE="/etc/ss-rust/ver.txt"
SYSCTL_CONF="/etc/sysctl.d/local.conf"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'

# 状态提示
readonly INFO="${GREEN}[信息]${PLAIN}"
readonly ERROR="${RED}[错误]${PLAIN}"
readonly WARNING="${YELLOW}[警告]${PLAIN}"
readonly SUCCESS="${GREEN}[成功]${PLAIN}"

# 系统信息
OS_TYPE=""
OS_ARCH=""
OS_VERSION=""

# 配置信息
SS_PORT=""
SS_PASSWORD=""
SS_METHOD=""
SS_TFO=""
SS_DNS=""

# 错误处理函数
error_exit() {
    echo -e "${ERROR} $1" >&2
    exit 1
}

# 检查 root 权限
check_root() {
    if [[ $EUID != 0 ]]; then
        error_exit "当前非ROOT账号(或没有ROOT权限)，请使用 sudo su 获取临时ROOT权限"
    fi
}

# 检测操作系统
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        OS_TYPE="centos"
    elif grep -q -E -i "debian" /etc/issue || grep -q -E -i "debian" /proc/version; then
        OS_TYPE="debian"
    elif grep -q -E -i "ubuntu" /etc/issue || grep -q -E -i "ubuntu" /proc/version; then
        OS_TYPE="ubuntu"
    elif grep -q -E -i "centos|red hat|redhat" /etc/issue || grep -q -E -i "centos|red hat|redhat" /proc/version; then
        OS_TYPE="centos"
    else
        error_exit "不支持的操作系统"
    fi
    echo -e "${INFO} 检测到操作系统为 [ ${OS_TYPE} ]"
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    local os=$(uname -s)
    
    case "${os}" in
        "Darwin")
            case "${arch}" in
                "arm64") OS_ARCH="aarch64-apple-darwin" ;;
                "x86_64") OS_ARCH="x86_64-apple-darwin" ;;
            esac
            ;;
        "Linux")
            case "${arch}" in
                "x86_64") OS_ARCH="x86_64-unknown-linux-gnu" ;;
                "aarch64") OS_ARCH="aarch64-unknown-linux-gnu" ;;
                "armv7l"|"armv7")
                    if grep -q "gnueabihf" /proc/cpuinfo; then
                        OS_ARCH="armv7-unknown-linux-gnueabihf"
                    else
                        OS_ARCH="arm-unknown-linux-gnueabi"
                    fi
                    ;;
                "armv6l") OS_ARCH="arm-unknown-linux-gnueabi" ;;
                "i686"|"i386") OS_ARCH="i686-unknown-linux-musl" ;;
                *) error_exit "不支持的CPU架构: ${arch}" ;;
            esac
            ;;
        *) error_exit "不支持的操作系统: ${os}" ;;
    esac
    
    echo -e "${INFO} 检测到系统架构为 [ ${OS_ARCH} ]"
}

# 检查安装状态
check_installed_status() {
    if [[ ! -e ${BINARY_PATH} ]]; then
        echo -e "${ERROR} Shadowsocks Rust 未安装，请先安装！"
        return 1
    fi
    return 0
}

# 检查服务状态
check_status() {
    if systemctl is-active ss-rust >/dev/null 2>&1; then
        status="running"
    else
        status="stopped"
    fi
}

# 获取最新版本
check_new_ver() {
    new_ver=$(wget -qO- --timeout=5 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases | \
              jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')
    if [[ -z ${new_ver} ]]; then
        echo -e "${ERROR} 获取 Shadowsocks Rust 最新版本失败！"
        return 1
    fi
    new_ver=${new_ver#v}
    echo -e "${INFO} 检测到 Shadowsocks Rust 最新版本为 [ ${new_ver} ]"
    return 0
}

# 下载 Shadowsocks Rust
download_ss() {
    local version=$1
    local arch=$2
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${version}"
    local filename=""

    case "${arch}" in
        "aarch64-apple-darwin"|"x86_64-apple-darwin"|"x86_64-unknown-linux-gnu"|"x86_64-unknown-linux-musl"|"aarch64-unknown-linux-gnu"|"aarch64-unknown-linux-musl"|"arm-unknown-linux-gnueabi"|"arm-unknown-linux-gnueabihf"|"armv7-unknown-linux-gnueabihf"|"i686-unknown-linux-musl")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        "x86_64-pc-windows-gnu"|"x86_64-pc-windows-msvc")
            filename="shadowsocks-v${version}.${arch}.zip"
            ;;
        *) error_exit "不支持的系统架构: ${arch}" ;;
    esac
    
    echo -e "${INFO} 开始下载 Shadowsocks Rust ${version}..."
    echo -e "${INFO} 下载地址：${url}/${filename}"
    if ! wget --no-check-certificate -N "${url}/${filename}"; then
        error_exit "Shadowsocks Rust 下载失败！"
    fi
    
    if [[ "${filename}" == *.tar.xz ]]; then
        if ! tar -xf "${filename}"; then
            error_exit "Shadowsocks Rust 解压失败！"
        fi
    elif [[ "${filename}" == *.zip ]]; then
        if ! unzip -o "${filename}"; then
            error_exit "Shadowsocks Rust 解压失败！"
        fi
    fi
    
    if [[ ! -e "ssserver" ]]; then
        error_exit "Shadowsocks Rust 解压后未找到主程序！"
    fi
    
    rm -f "${filename}"
    chmod +x ssserver
    mv -f ssserver "${BINARY_PATH}"
    rm -f sslocal ssmanager ssservice ssurl
    
    echo "${version}" > "${VERSION_FILE}"
    echo -e "${SUCCESS} Shadowsocks Rust ${version} 下载安装完成！"
}

# 下载主函数
download() {
    if [[ ! -e "${INSTALL_DIR}" ]]; then
        mkdir -p "${INSTALL_DIR}"
    fi
    
    local version=${SS_VERSION}
    local arch=${OS_ARCH}
    download_ss "${version}" "${arch}"
}

# 安装系统服务
install_service() {
    echo -e "${INFO} 开始安装系统服务..."
    cat > /etc/systemd/system/ss-rust.service << EOF
[Unit]
Description=Shadowsocks Rust Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_PATH}
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ss-rust
    echo -e "${SUCCESS} Shadowsocks Rust 服务配置完成！"
}

# 安装依赖
install_dependencies() {
    echo -e "${INFO} 开始安装系统依赖..."
    
    if [[ ${OS_TYPE} == "centos" ]]; then
        yum update -y
        yum install -y jq gzip wget curl unzip xz openssl qrencode tar epel-release
    else
        apt-get update
        apt-get install -y jq gzip wget curl unzip xz-utils openssl qrencode tar
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${ERROR} jq 安装失败，请手动安装！"
        return 1
    fi
    
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${WARNING} qrencode 安装失败，二维码功能将不可用！"
    fi
    
    if [ -f "/usr/share/zoneinfo/Asia/Shanghai" ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone
        echo -e "${INFO} 时区已设置为 Asia/Shanghai"
    else
        echo -e "${WARNING} 时区文件不存在，跳过设置"
    fi
    echo -e "${SUCCESS} 系统依赖安装完成！"
}

# 写入配置文件
write_config() {
    cat > ${CONFIG_PATH} << EOF
{
    "server": "::",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "method": "${SS_METHOD}",
    "fast_open": ${SS_TFO},
    "mode": "tcp_and_udp",
    "user": "nobody",
    "timeout": 300${SS_DNS:+",\n    \"nameserver\":\"${SS_DNS}\""}
}
EOF
    echo -e "${SUCCESS} 配置文件写入完成！"
    check_firewall "${SS_PORT}"
}

# 读取配置文件
read_config() {
    if [[ ! -e ${CONFIG_PATH} ]]; then
        echo -e "${ERROR} Shadowsocks Rust 配置文件不存在！"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${ERROR} jq 未安装，请先安装 jq！"
        return 1
    fi
    
    if ! jq empty ${CONFIG_PATH} >/dev/null 2>&1; then
        echo -e "${ERROR} 配置文件 ${CONFIG_PATH} 格式错误！"
        return 1
    fi
    
    SS_PORT=$(jq -r '.server_port' ${CONFIG_PATH})
    SS_PASSWORD=$(jq -r '.password' ${CONFIG_PATH})
    SS_METHOD=$(jq -r '.method' ${CONFIG_PATH})
    SS_TFO=$(jq -r '.fast_open' ${CONFIG_PATH})
    SS_DNS=$(jq -r '.nameserver // empty' ${CONFIG_PATH})
    
    if [[ -z "${SS_PORT}" || -z "${SS_PASSWORD}" || -z "${SS_METHOD}" ]]; then
        echo -e "${ERROR} 配置文件缺少必要字段！"
        return 1
    fi
    
    return 0
}

# 检查防火墙并开放端口
check_firewall() {
    local port=$1
    echo -e "${INFO} 检查防火墙配置..."
    
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw active; then
        echo -e "${INFO} 检测到 UFW 防火墙，开放端口 ${port}..."
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
        echo -e "${SUCCESS} UFW 端口开放完成！"
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 iptables 防火墙，开放端口 ${port}..."
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT
        if [[ ${OS_TYPE} == "centos" ]]; then
            service iptables save 2>/dev/null || true
        else
            iptables-save > /etc/iptables.rules 2>/dev/null || true
        fi
        echo -e "${SUCCESS} iptables 端口开放完成！"
    fi
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65535
    echo $(shuf -i ${min_port}-${max_port} -n 1)
}

# 设置端口
set_port() {
    SS_PORT=$(generate_random_port)
    echo -e "${INFO} 已生成随机端口：${SS_PORT}"
    echo -e "${WARNING} 是否使用该随机端口？"
    echo "=================================="
    echo -e " ${GREEN}1.${PLAIN} 是"
    echo -e " ${GREEN}2.${PLAIN} 否，我要自定义端口"
    echo "=================================="
    
    read -e -p "(默认: 1. 使用随机端口)：" port_choice
    [[ -z "${port_choice}" ]] && port_choice="1"
    
    if [[ ${port_choice} == "2" ]]; then
        while true; do
            echo -e "请输入 Shadowsocks Rust 端口 [1-65535]"
            read -e -p "(默认：2525)：" SS_PORT
            [[ -z "${SS_PORT}" ]] && SS_PORT="2525"
            
            if [[ ${SS_PORT} =~ ^[0-9]+$ ]] && (( SS_PORT >= 1 && SS_PORT <= 65535 )); then
                break
            else
                echo -e "${ERROR} 输入错误，端口范围必须在 1-65535 之间"
            fi
        done
    fi
    
    echo && echo "=================================="
    echo -e "端口：${RED}${SS_PORT}${PLAIN}"
    echo "=================================="
}

# 设置密码
set_password() {
    echo "请输入 Shadowsocks Rust 密码 [0-9][a-z][A-Z]"
    read -e -p "(默认：随机生成 Base64)：" SS_PASSWORD
    if [[ -z "${SS_PASSWORD}" ]]; then
        case "${SS_METHOD}" in
            "2022-blake3-aes-128-gcm")
                SS_PASSWORD=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64)
                ;;
            "2022-blake3-aes-256-gcm"|"2022-blake3-chacha20-poly1305"|"2022-blake3-chacha8-poly1305")
                raw_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
                while [[ ${#raw_key} -ne 44 ]]; do
                    raw_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
                done
                SS_PASSWORD="${raw_key}"
                ;;
            *)
                SS_PASSWORD=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64)
                ;;
        esac
    fi
    
    if [[ "${SS_METHOD}" == "2022-blake3-aes-256-gcm" || "${SS_METHOD}" == "2022-blake3-chacha20-poly1305" || "${SS_METHOD}" == "2022-blake3-chacha8-poly1305" ]]; then
        decoded_length=$(echo -n "${SS_PASSWORD}" | base64 -d | wc -c)
        if [[ ${decoded_length} -ne 32 ]]; then
            echo -e "${WARNING} 密码长度不符合要求（需要32字节），请重新设置密码！"
            set_password
            return
        fi
    fi
    
    echo && echo "=================================="
    echo -e "密码：${RED}${SS_PASSWORD}${PLAIN}"
    echo "==================================" && echo
}

# 设置加密方式
set_method() {
    echo -e "请选择 Shadowsocks Rust 加密方式
==================================
 ${GREEN} 1.${PLAIN} aes-128-gcm
 ${GREEN} 2.${PLAIN} aes-256-gcm
 ${GREEN} 3.${PLAIN} chacha20-ietf-poly1305
 ${GREEN} 4.${PLAIN} plain
 ${GREEN} 5.${PLAIN} none
 ${GREEN} 6.${PLAIN} table
 ${GREEN} 7.${PLAIN} aes-128-cfb
 ${GREEN} 8.${PLAIN} aes-256-cfb
 ${GREEN} 9.${PLAIN} aes-256-ctr
 ${GREEN}10.${PLAIN} camellia-256-cfb
 ${GREEN}11.${PLAIN} rc4-md5
 ${GREEN}12.${PLAIN} chacha20-ietf
==================================
 ${WARNING} AEAD 2022 加密（使用随机加密）
==================================
 ${GREEN}13.${PLAIN} 2022-blake3-aes-128-gcm ${GREEN}(默认)${PLAIN}
 ${GREEN}14.${PLAIN} 2022-blake3-aes-256-gcm ${GREEN}(推荐)${PLAIN}
 ${GREEN}15.${PLAIN} 2022-blake3-chacha20-poly1305
 ${GREEN}16.${PLAIN} 2022-blake3-chacha8-poly1305
=================================="
    
    read -e -p "(默认: 13. 2022-blake3-aes-128-gcm)：" method_choice
    [[ -z "${method_choice}" ]] && method_choice="13"
    
    case ${method_choice} in
        1) SS_METHOD="aes-128-gcm" ;;
        2) SS_METHOD="aes-256-gcm" ;;
        3) SS_METHOD="chacha20-ietf-poly1305" ;;
        4) SS_METHOD="plain" ;;
        5) SS_METHOD="none" ;;
        6) SS_METHOD="table" ;;
        7) SS_METHOD="aes-128-cfb" ;;
        8) SS_METHOD="aes-256-cfb" ;;
        9) SS_METHOD="aes-256-ctr" ;;
        10) SS_METHOD="camellia-256-cfb" ;;
        11) SS_METHOD="rc4-md5" ;;
        12) SS_METHOD="chacha20-ietf" ;;
        13) SS_METHOD="2022-blake3-aes-128-gcm" ;;
        14) SS_METHOD="2022-blake3-aes-256-gcm" ;;
        15) SS_METHOD="2022-blake3-chacha20-poly1305" ;;
        16) SS_METHOD="2022-blake3-chacha8-poly1305" ;;
        *) SS_METHOD="2022-blake3-aes-128-gcm" ;;
    esac
    
    echo && echo "=================================="
    echo -e "加密：${RED}${SS_METHOD}${PLAIN}"
    echo "==================================" && echo
}

# 设置 TFO
set_tfo() {
    echo -e "是否启用 TFO？
==================================
 ${GREEN}1.${PLAIN} 启用
 ${GREEN}2.${PLAIN} 禁用
=================================="
    read -e -p "(默认：1)：" tfo_choice
    [[ -z "${tfo_choice}" ]] && tfo_choice="1"
    
    if [[ ${tfo_choice} == "1" ]]; then
        SS_TFO="true"
    else
        SS_TFO="false"
    fi
    
    echo && echo "=================================="
    echo -e "TFO：${RED}${SS_TFO}${PLAIN}"
    echo "==================================" && echo
}

# 设置 DNS
set_dns() {
    echo -e "请选择 DNS 配置方式：
==================================
 ${GREEN}1.${PLAIN} 使用系统默认 DNS ${GREEN}(推荐)${PLAIN}
 ${GREEN}2.${PLAIN} 自定义 DNS 服务器
=================================="
    read -e -p "(默认：1)：" dns_choice
    [[ -z "${dns_choice}" ]] && dns_choice="1"
    
    if [[ ${dns_choice} == "2" ]]; then
        echo -e "请输入自定义 DNS 服务器地址（多个 DNS 用逗号分隔，如：8.8.8.8,8.8.4.4）"
        read -e -p "(默认：8.8.8.8)：" SS_DNS
        [[ -z "${SS_DNS}" ]] && SS_DNS="8.8.8.8"
        echo && echo "=================================="
        echo -e "DNS：${RED}${SS_DNS}${PLAIN}"
        echo "==================================" && echo
    else
        SS_DNS=""
        echo && echo "=================================="
        echo -e "DNS：${RED}使用系统默认 DNS${PLAIN}"
        echo "==================================" && echo
    fi
}

# 修改配置
modify_config() {
    if ! check_installed_status; then
        Before_Start_Menu
        return 1
    fi
    echo && echo -e "你要做什么？
==================================
 ${GREEN}1.${PLAIN} 修改 端口配置
 ${GREEN}2.${PLAIN} 修改 密码配置
 ${GREEN}3.${PLAIN} 修改 加密配置
 ${GREEN}4.${PLAIN} 修改 TFO 配置
 ${GREEN}5.${PLAIN} 修改 DNS 配置
 ${GREEN}6.${PLAIN} 修改 全部配置
==================================" && echo
    
    read -e -p "(默认：取消)：" modify
    [[ -z "${modify}" ]] && echo "已取消..." && Before_Start_Menu
    
    case "${modify}" in
        1)
            read_config && set_port && write_config && Restart
            ;;
        2)
            read_config && set_password && write_config && Restart
            ;;
        3)
            read_config && set_method && write_config && Restart
            ;;
        4)
            read_config && set_tfo && write_config && Restart
            ;;
        5)
            read_config && set_dns && write_config && Restart
            ;;
        6)
            read_config && set_port && set_password && set_method && set_tfo && set_dns && write_config && Restart
            ;;
        *)
            echo -e "${ERROR} 请输入正确的数字(1-6)"
            sleep 2s
            modify_config
            ;;
    esac
}

# 安装
Install() {
    [[ -e ${BINARY_PATH} ]] && echo -e "${ERROR} 检测到 Shadowsocks Rust 已安装！" && exit 1
    
    echo -e "${INFO} 开始设置配置..."
    set_port
    set_method
    set_password
    set_tfo
    set_dns
    
    echo -e "${INFO} 开始安装/配置依赖..."
    install_dependencies || exit 1
    
    echo -e "${INFO} 开始下载/安装..."
    detect_arch
    if ! check_new_ver; then
        exit 1
    fi
    SS_VERSION=${new_ver}
    download
    
    echo -e "${INFO} 开始写入配置文件..."
    write_config
    
    echo -e "${INFO} 开始安装系统服务..."
    install_service

    echo -e "${INFO} 创建命令快捷方式..."
    curl -L -s ss.jinqians.com -o "/usr/local/bin/ss-2022.sh"
    chmod +x "/usr/local/bin/ss-2022.sh"
    ln -sf "/usr/local/bin/ss-2022.sh" "/usr/local/bin/ssrust"
    
    echo -e "${INFO} 所有步骤安装完毕，开始启动服务..."
    start_service
    
    if [[ "$?" == "0" ]]; then
        echo -e "${SUCCESS} Shadowsocks Rust 安装并启动成功！"
        View
        echo -e "${INFO} 您可以使用 ${GREEN}ssrust${PLAIN} 命令进行管理"
    else
        echo -e "${ERROR} Shadowsocks Rust 启动失败，请检查日志！"
        echo -e "${INFO} 您可以使用以下命令查看详细日志："
        echo -e " - systemctl status ss-rust"
        echo -e " - journalctl -xe --unit ss-rust"
    fi
    Before_Start_Menu
}

# 启动服务
start_service() {
    if ! check_installed_status; then
        return 1
    fi
    
    check_status
    if [[ "$status" == "running" ]]; then
        echo -e "${INFO} Shadowsocks Rust 已在运行！"
        return 1
    fi
    
    echo -e "${INFO} 正在启动 Shadowsocks Rust..."
    systemctl start ss-rust
    
    sleep 2
    if ! systemctl is-active ss-rust >/dev/null 2>&1; then
        echo -e "${ERROR} Shadowsocks Rust 启动失败！"
        journalctl -xe --unit ss-rust
        return 1
    fi
    
    echo -e "${SUCCESS} Shadowsocks Rust 启动成功！"
    return 0
}

# 停止
Stop() {
    if ! check_installed_status; then
        return 1
    fi
    check_status
    if [[ ! "$status" == "running" ]]; then
        echo -e "${ERROR} Shadowsocks Rust 没有运行，请检查！"
        return 1
    fi
    systemctl stop ss-rust
    echo -e "${INFO} Shadowsocks Rust 已停止！"
}

# 重启
Restart() {
    if ! check_installed_status; then
        return 1
    fi
    systemctl restart ss-rust
    echo -e "${INFO} Shadowsocks Rust 重启完毕！"
}

# 更新
Update() {
    if ! check_installed_status; then
        return 1
    fi
    if ! check_new_ver; then
        return 1
    fi
    if [[ ! -f "${VERSION_FILE}" ]]; then
        echo -e "${INFO} 未找到版本文件，可能是首次安装"
        SS_VERSION=${new_ver}
        download
        echo -e "${INFO} Shadowsocks Rust 更新完毕！"
        sleep 3s
        Start_Menu
    fi
    
    local now_ver=$(cat ${VERSION_FILE})
    if [[ "${now_ver}" != "${new_ver}" ]]; then
        echo -e "${INFO} 发现 Shadowsocks Rust 新版本 [ ${new_ver} ]"
        echo -e "${INFO} 当前版本 [ ${now_ver} ]"
        SS_VERSION=${new_ver}
        download
        echo -e "${INFO} Shadowsocks Rust 更新完毕！"
    else
        echo -e "${INFO} 当前已是最新版本 [ ${new_ver} ]"
    fi
    sleep 3s
    Start_Menu
}

# 卸载
Uninstall() {
    if ! check_installed_status; then
        return 1
    fi
    echo "确定要卸载 Shadowsocks Rust ? (y/N)"
    read -e -p "(默认：n)：" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        check_status
        [[ "$status" == "running" ]] && systemctl stop ss-rust
        systemctl disable ss-rust
        rm -rf "${INSTALL_DIR}"
        rm -f "${BINARY_PATH}"
        rm -f "/usr/local/bin/ssrust"
        rm -f "/usr/local/bin/ss-2022.sh"
        echo -e "${INFO} Shadowsocks Rust 卸载完成！"
    else
        echo -e "${INFO} 卸载已取消..."
    fi
}

# 获取IPv4地址
getipv4() {
    ipv4=$(wget -qO- -4 --timeout=2 --tries=1 ipinfo.io/ip 2>/dev/null)
    if [[ -z "${ipv4}" ]]; then
        ipv4=$(wget -qO- -4 --timeout=2 --tries=1 api.ip.sb/ip 2>/dev/null)
        if [[ -z "${ipv4}" ]]; then
            ipv4=$(wget -qO- -4 --timeout=2 --tries=1 members.3322.org/dyndns/getip 2>/dev/null)
            if [[ -z "${ipv4}" ]]; then
                ipv4="IPv4_Error"
                echo -e "${WARNING} 无法获取 IPv4 地址，请检查网络！"
            fi
        fi
    fi
}

# 获取IPv6地址
getipv6() {
    ipv6=$(wget -qO- -6 --timeout=2 --tries=1 ifconfig.co 2>/dev/null)
    if [[ -z "${ipv6}" ]]; then
        ipv6=$(wget -qO- -6 --timeout=2 --tries=1 ip6.me/api/ 2>/dev/null | grep -o '[0-9a-f:]\+')
        if [[ -z "${ipv6}" ]]; then
            ipv6="IPv6_Error"
            echo -e "${WARNING} 无法获取 IPv6 地址，请检查网络！"
        fi
    fi
}

# 生成安全的Base64编码
urlsafe_base64() {
    echo -n "$1" | base64 | sed ':a;N;s/\n/ /g;ta' | sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g'
}

# 查看配置信息
View() {
    if ! check_installed_status; then
        echo -e "${ERROR} Shadowsocks Rust 未安装！"
        return 1
    fi
    
    if ! read_config; then
        echo -e "${ERROR} 读取配置文件失败！"
        return 1
    fi
    
    getipv4
    getipv6
    
    echo -e "Shadowsocks Rust 配置："
    echo -e "——————————————————————————————————"
    [[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址：${GREEN}${ipv4}${PLAIN}"
    [[ "${ipv6}" != "IPv6_Error" ]] && echo -e " 地址：${GREEN}${ipv6}${PLAIN}"
    echo -e " 端口：${GREEN}${SS_PORT}${PLAIN}"
    echo -e " 密码：${GREEN}${SS_PASSWORD}${PLAIN}"
    echo -e " 加密：${GREEN}${SS_METHOD}${PLAIN}"
    echo -e " TFO ：${GREEN}${SS_TFO}${PLAIN}"
    [[ ! -z "${SS_DNS}" ]] && echo -e " DNS ：${GREEN}${SS_DNS}${PLAIN}"
    echo -e "——————————————————————————————————"

    local has_shadowtls=false
    local stls_listen_port=""
    local stls_password=""
    local stls_sni=""
    
    if [ -f "/etc/systemd/system/shadowtls-ss.service" ]; then
        has_shadowtls=true
        echo -e "\n${YELLOW}ShadowTLS 配置：${PLAIN}"
        echo -e "——————————————————————————————————"
        
        stls_listen_port=$(grep -oP '(?<=--listen ::0:)\d+' /etc/systemd/system/shadowtls-ss.service 2>/dev/null || echo "未知")
        stls_password=$(grep -oP '(?<=--password )\S+' /etc/systemd/system/shadowtls-ss.service 2>/dev/null || echo "未知")
        stls_sni=$(grep -oP '(?<=--tls )\S+' /etc/systemd/system/shadowtls-ss.service 2>/dev/null || echo "未知")

        echo -e " 监听端口：${GREEN}${stls_listen_port}${PLAIN}"
        echo -e " 密码：${GREEN}${stls_password}${PLAIN}"
        echo -e " SNI：${GREEN}${stls_sni}${PLAIN}"
        echo -e " 版本：3"
        echo -e "——————————————————————————————————"
    fi

    local ss_userinfo=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 | tr -d '\n')
    local ss_url_ipv4=""
    local ss_url_ipv6=""
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        ss_url_ipv4="ss://${ss_userinfo}@${ipv4}:${SS_PORT}#SS-${ipv4}"
    fi
    if [[ "${ipv6}" != "IPv6_Error" ]]; then
        ss_url_ipv6="ss://${ss_userinfo}@[${ipv6}]:${SS_PORT}#SS-${ipv6}"
    fi

    echo -e "\n${YELLOW}=== Shadowsocks 链接 ===${PLAIN}"
    [[ ! -z "${ss_url_ipv4}" ]] && echo -e "${GREEN}IPv4 链接：${PLAIN}${ss_url_ipv4}"
    [[ ! -z "${ss_url_ipv6}" ]] && echo -e "${GREEN}IPv6 链接：${PLAIN}${ss_url_ipv6}"

    echo -e "\n${YELLOW}=== Shadowsocks 二维码 ===${PLAIN}"
    if command -v qrencode &> /dev/null; then
        if [[ ! -z "${ss_url_ipv4}" ]]; then
            echo -e "${GREEN}IPv4 二维码：${PLAIN}"
            echo "${ss_url_ipv4}" | qrencode -t UTF8 || echo -e "${ERROR} 生成 IPv4 二维码失败！"
        fi
        if [[ ! -z "${ss_url_ipv6}" ]]; then
            echo -e "${GREEN}IPv6 二维码：${PLAIN}"
            echo "${ss_url_ipv6}" | qrencode -t UTF8 || echo -e "${ERROR} 生成 IPv6 二维码失败！"
        fi
    else
        echo -e "${RED}未安装 qrencode，无法生成二维码${PLAIN}"
    fi

    echo -e "\n${YELLOW}=== Surge Shadowsocks 配置 ===${PLAIN}"
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        echo -e "$(uname -n) = ss, ${ipv4}, ${SS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, tfo=${SS_TFO}, udp-relay=true"
    else
        echo -e "$(uname -n) = ss, ${ipv6}, ${SS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, tfo=${SS_TFO}, udp-relay=true"
    fi

    if [ "$has_shadowtls" = true ]; then
        local shadow_tls_config="{\"version\":\"3\",\"password\":\"${stls_password}\",\"host\":\"${stls_sni}\",\"port\":\"${stls_listen_port}\",\"address\":\"${ipv4}\"}"
        local shadow_tls_base64=$(echo -n "${shadow_tls_config}" | base64 | tr -d '\n')
        local ss_stls_url="ss://${ss_userinfo}@${ipv4}:${SS_PORT}?shadow-tls=${shadow_tls_base64}#SS-${ipv4}"

        echo -e "\n${YELLOW}=== SS + ShadowTLS 链接 ===${PLAIN}"
        echo -e "${GREEN}合并链接：${PLAIN}${ss_stls_url}"

        echo -e "\n${YELLOW}=== SS + ShadowTLS 二维码 ===${PLAIN}"
        if command -v qrencode &> /dev/null; then
            echo "${ss_stls_url}" | qrencode -t UTF8 || echo -e "${ERROR} 生成 ShadowTLS 二维码失败！"
        else
            echo -e "${RED}未安装 qrencode，无法生成二维码${PLAIN}"
        fi

        echo -e "\n${YELLOW}=== Surge Shadowsocks + ShadowTLS 配置 ===${PLAIN}"
        if [[ "${ipv4}" != "IPv4_Error" ]]; then
            echo -e "$(uname -n) = ss, ${ipv4}, ${stls_listen_port}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true"
        else
            echo -e "$(uname -n) = ss, ${ipv6}, ${stls_listen_port}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true"
        fi
    fi

    echo -e "—————————————————————————"
    return 0
}

# 查看运行状态
Status() {
    echo -e "${INFO} 获取 Shadowsocks Rust 活动日志 ……"
    echo -e "${WARNING} 返回主菜单请按 q ！"
    systemctl status ss-rust
    Start_Menu
}

# 更新脚本
Update_Shell() {
    echo -e "${INFO} 当前脚本版本为 [ ${SCRIPT_VERSION} ]"
    echo -e "${INFO} 开始检测脚本更新..."
    
    local temp_file="/tmp/ss-2022.sh"
    if ! wget --no-check-certificate -O ${temp_file} "https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/ss-2022.sh"; then
        echo -e "${ERROR} 下载最新脚本失败！"
        rm -f ${temp_file}
        return 1
    fi
    
    if [[ ! -s ${temp_file} ]]; then
        echo -e "${ERROR} 下载的脚本文件为空！"
        rm -f ${temp_file}
        return 1
    fi
    
    sh_new_ver=$(grep 'SCRIPT_VERSION="' ${temp_file} | awk -F '"' '{print $2}')
    if [[ -z ${sh_new_ver} ]]; then
        echo -e "${ERROR} 获取最新版本号失败！"
        rm -f ${temp_file}
        return 1
    fi
    
    if [[ ${sh_new_ver} != ${SCRIPT_VERSION} ]]; then
        echo -e "${INFO} 发现新版本 [ ${sh_new_ver} ]"
        echo -e "${INFO} 是否更新？[Y/n]"
        read -p "(默认: y)：" yn
        [[ -z "${yn}" ]] && yn="y"
        if [[ ${yn} == [Yy] ]]; then
            cp "${SCRIPT_PATH}/${SCRIPT_NAME}" "${SCRIPT_PATH}/${SCRIPT_NAME}.bak.${SCRIPT_VERSION}"
            echo -e "${INFO} 已备份当前版本到 ${SCRIPT_NAME}.bak.${SCRIPT_VERSION}"
            
            mv -f ${temp_file} "${SCRIPT_PATH}/${SCRIPT_NAME}"
            chmod +x "${SCRIPT_PATH}/${SCRIPT_NAME}"
            echo -e "${SUCCESS} 脚本已更新至 [ ${sh_new_ver} ]"
            echo -e "${INFO} 2秒后执行新脚本..."
            sleep 2s
            exec "${SCRIPT_PATH}/${SCRIPT_NAME}"
        else
            echo -e "${INFO} 已取消更新..."
            rm -f ${temp_file}
        fi
    else
        echo -e "${INFO} 当前已是最新版本 [ ${sh_new_ver} ]"
        rm -f ${temp_file}
    fi
}

# 安装 ShadowTLS
install_shadowtls() {
    echo -e "${INFO} 开始下载 ShadowTLS 安装脚本..."
    
    local shadowtls_url="https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/shadowtls.sh"
    local shadowtls_file="shadowtls.sh"
    
    if ! wget --no-check-certificate -O ${shadowtls_file} "${shadowtls_url}"; then
        echo -e "${ERROR} ShadowTLS 脚本下载失败！"
        return 1
    fi
    
    if [[ ! -s ${shadowtls_file} ]]; then
        echo -e "${ERROR} 下载的 ShadowTLS 脚本为空！"
        rm -f ${shadowtls_file}
        return 1
    fi
    
    chmod +x ${shadowtls_file}
    echo -e "${INFO} 开始安装 ShadowTLS..."
    bash ${shadowtls_file}
    
    rm -f ${shadowtls_file}
    Before_Start_Menu
}

# 返回主菜单
Before_Start_Menu() {
    echo && echo -n -e "${YELLOW}* 按回车返回主菜单 *${PLAIN}" && read temp
}

# 主菜单
Start_Menu() {
    while true; do
        clear
        check_root
        check_sys
        echo -e "${GREEN}============================================${PLAIN}"
        echo -e "${GREEN}          SS - 2022 管理脚本 ${PLAIN}"
        echo -e "${GREEN}============================================${PLAIN}"
        echo -e "${GREEN}            作者: jinqians${PLAIN}"
        echo -e "${GREEN}       网站：https://jinqians.com${PLAIN}"
        echo -e "${GREEN}============================================${PLAIN}"
        echo && echo -e "  
 ${GREEN}0.${PLAIN} 更新脚本
——————————————————————————————————
 ${GREEN}1.${PLAIN} 安装 Shadowsocks Rust
 ${GREEN}2.${PLAIN} 更新 Shadowsocks Rust
 ${GREEN}3.${PLAIN} 卸载 Shadowsocks Rust
——————————————————————————————————
 ${GREEN}4.${PLAIN} 启动 Shadowsocks Rust
 ${GREEN}5.${PLAIN} 停止 Shadowsocks Rust
 ${GREEN}6.${PLAIN} 重启 Shadowsocks Rust
——————————————————————————————————
 ${GREEN}7.${PLAIN} 设置 配置信息
 ${GREEN}8.${PLAIN} 查看 配置信息
 ${GREEN}9.${PLAIN} 查看 运行状态
——————————————————————————————————
 ${GREEN}10.${PLAIN} 安装 ShadowTLS
 ${GREEN}11.${PLAIN} 退出脚本
——————————————————————————————————
==================================" && echo
        if [[ -e ${BINARY_PATH} ]]; then
            check_status
            if [[ "$status" == "running" ]]; then
                echo -e " 当前状态：${GREEN}已安装${PLAIN} 并 ${GREEN}已启动${PLAIN}"
            else
                echo -e " 当前状态：${GREEN}已安装${PLAIN} 但 ${RED}未启动${PLAIN}"
            fi
        else
            echo -e " 当前状态：${RED}未安装${PLAIN}"
        fi
        echo
        read -e -p " 请输入数字 [0-11]：" num
        case "$num" in
            0)
                Update_Shell
                ;;
            1)
                Install
                ;;
            2)
                Update
                sleep 2
                ;;
            3)
                Uninstall
                sleep 2
                ;;
            4)
                start_service
                sleep 2
                ;;
            5)
                Stop
                sleep 2
                ;;
            6)
                Restart
                sleep 2
                ;;
            7)
                modify_config
                ;;
            8)
                if View; then
                    echo && echo -n -e "${YELLOW}* 按回车返回主菜单 *${PLAIN}" && read temp
                else
                    echo -e "${ERROR} 查看配置信息失败，请检查日志！"
                    echo && echo -n -e "${YELLOW}* 按回车返回主菜单 *${PLAIN}" && read temp
                fi
                ;;
            9)
                Status
                ;;
            10)
                install_shadowtls
                ;;
            11)
                echo -e "${INFO} 退出脚本..."
                rm -f /tmp/ss-2022.sh 2>/dev/null
                exit 0
                ;;
            *)
                echo -e "${ERROR} 请输入正确数字 [0-11]"
                sleep 2
                ;;
        esac
    done
}

# 启动脚本
Start_Menu "$@"