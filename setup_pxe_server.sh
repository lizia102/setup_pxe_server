#!/bin/bash

# PXE服务器配置脚本

# 默认配置
DEFAULT_INTERFACE="eth0"          # 默认网络接口
DEFAULT_SUBNET="192.168.1.0"      # 默认子网
DEFAULT_NETMASK="255.255.255.0"   # 默认子网掩码
DEFAULT_GATEWAY="192.168.1.1"     # 默认网关
DEFAULT_DNS="8.8.8.8"             # 默认DNS服务器
DEFAULT_RANGE_START="192.168.1.100" # DHCP地址池起始
DEFAULT_RANGE_END="192.168.1.200"   # DHCP地址池结束
TFTP_ROOT="/var/lib/tftpboot"      # TFTP根目录
HTTP_ROOT="/var/www/html"          # HTTP根目录

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --interface <interface>  网络接口名称 (默认: $DEFAULT_INTERFACE)"
    echo "  --subnet <subnet>        子网地址 (默认: $DEFAULT_SUBNET)"
    echo "  --netmask <netmask>      子网掩码 (默认: $DEFAULT_NETMASK)"
    echo "  --gateway <gateway>      网关地址 (默认: $DEFAULT_GATEWAY)"
    echo "  --dns <dns>              DNS服务器 (默认: $DEFAULT_DNS)"
    echo "  --range-start <ip>       DHCP地址池起始 (默认: $DEFAULT_RANGE_START)"
    echo "  --range-end <ip>         DHCP地址池结束 (默认: $DEFAULT_RANGE_END)"
    echo "  --iso <path>             Linux安装ISO路径 (必需)"
    echo "  --help                   显示此帮助信息"
}

# 参数解析
INTERFACE=$DEFAULT_INTERFACE
SUBNET=$DEFAULT_SUBNET
NETMASK=$DEFAULT_NETMASK
GATEWAY=$DEFAULT_GATEWAY
DNS=$DEFAULT_DNS
RANGE_START=$DEFAULT_RANGE_START
RANGE_END=$DEFAULT_RANGE_END
ISO_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --subnet)
            SUBNET="$2"
            shift 2
            ;;
        --netmask)
            NETMASK="$2"
            shift 2
            ;;
        --gateway)
            GATEWAY="$2"
            shift 2
            ;;
        --dns)
            DNS="$2"
            shift 2
            ;;
        --range-start)
            RANGE_START="$2"
            shift 2
            ;;
        --range-end)
            RANGE_END="$2"
            shift 2
            ;;
        --iso)
            ISO_PATH="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "错误：未知选项 $1"
            show_usage
            exit 1
            ;;
    esac
done

# 检查必需参数
if [ -z "$ISO_PATH" ]; then
    echo "错误：必须指定ISO镜像路径 (--iso)"
    show_usage
    exit 1
fi

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

# 检查ISO文件
check_iso() {
    if [ ! -f "$ISO_PATH" ]; then
        echo "错误：ISO文件不存在：$ISO_PATH"
        exit 1
    fi
}

# 安装必需的软件包
install_packages() {
    echo "正在安装必需的软件包..."
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu系统
        apt-get update
        apt-get install -y isc-dhcp-server tftpd-hpa apache2 syslinux pxelinux
    elif command -v dnf &> /dev/null; then
        # RHEL/CentOS/Fedora系统
        dnf install -y dhcp-server tftp-server httpd syslinux
    elif command -v yum &> /dev/null; then
        # 旧版RHEL/CentOS系统
        yum install -y dhcp tftp-server httpd syslinux
    else
        echo "错误：不支持的Linux发行版"
        exit 1
    fi
}

# 配置DHCP服务
configure_dhcp() {
    echo "正在配置DHCP服务..."
    
    # 创建DHCP配置文件
    cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;

allow booting;
allow bootp;

subnet ${SUBNET%.*}.0 netmask $NETMASK {
    range $RANGE_START $RANGE_END;
    option routers $GATEWAY;
    option domain-name-servers $DNS;
    option subnet-mask $NETMASK;
    filename "pxelinux.0";
    next-server ${GATEWAY};
}
EOF

    # 配置DHCP服务监听接口
    if [ -f /etc/default/isc-dhcp-server ]; then
        # Debian/Ubuntu
        sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    elif [ -f /etc/sysconfig/dhcpd ]; then
        # RHEL/CentOS
        echo "DHCPDARGS=$INTERFACE" > /etc/sysconfig/dhcpd
    fi
}

# 配置TFTP服务
configure_tftp() {
    echo "正在配置TFTP服务..."
    
    # 创建TFTP根目录
    mkdir -p $TFTP_ROOT
    
    # 复制PXELINUX文件
    if [ -d /usr/lib/PXELINUX ]; then
        cp /usr/lib/PXELINUX/pxelinux.0 $TFTP_ROOT/
    elif [ -d /usr/share/syslinux ]; then
        cp /usr/share/syslinux/pxelinux.0 $TFTP_ROOT/
    fi
    
    # 创建PXELINUX配置目录
    mkdir -p $TFTP_ROOT/pxelinux.cfg
    
    # 创建默认配置文件
    cat > $TFTP_ROOT/pxelinux.cfg/default << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 300
ONTIMEOUT local

MENU TITLE PXE Boot Menu

LABEL linux
    MENU LABEL Install Linux
    KERNEL vmlinuz
    APPEND initrd=initrd.img inst.repo=http://$GATEWAY/linux

LABEL local
    MENU LABEL Boot from local drive
    LOCALBOOT 0
EOF
}

# 配置HTTP服务
configure_http() {
    echo "正在配置HTTP服务..."
    
    # 创建HTTP目录
    mkdir -p $HTTP_ROOT/linux
    
    # 挂载ISO并复制文件
    local MOUNT_POINT="/mnt/iso"
    mkdir -p $MOUNT_POINT
    mount -o loop "$ISO_PATH" $MOUNT_POINT
    
    # 复制内核和initrd
    if [ -f $MOUNT_POINT/images/pxeboot/vmlinuz ]; then
        cp $MOUNT_POINT/images/pxeboot/vmlinuz $TFTP_ROOT/
        cp $MOUNT_POINT/images/pxeboot/initrd.img $TFTP_ROOT/
    elif [ -f $MOUNT_POINT/casper/vmlinuz ]; then
        cp $MOUNT_POINT/casper/vmlinuz $TFTP_ROOT/
        cp $MOUNT_POINT/casper/initrd $TFTP_ROOT/initrd.img
    else
        echo "错误：无法找到内核和initrd文件"
        umount $MOUNT_POINT
        exit 1
    fi
    
    # 复制安装文件
    cp -r $MOUNT_POINT/* $HTTP_ROOT/linux/
    
    # 卸载ISO
    umount $MOUNT_POINT
}

# 启动服务
start_services() {
    echo "正在启动服务..."
    
    # 启动DHCP服务
    if command -v systemctl &> /dev/null; then
        systemctl enable --now isc-dhcp-server || systemctl enable --now dhcpd
        systemctl enable --now tftpd-hpa || systemctl enable --now tftp
        systemctl enable --now apache2 || systemctl enable --now httpd
    else
        service isc-dhcp-server start || service dhcpd start
        service tftpd-hpa start || service tftp start
        service apache2 start || service httpd start
    fi
}

# 主程序
echo "=== 开始配置PXE服务器 ==="
echo "网络接口: $INTERFACE"
echo "子网: $SUBNET"
echo "子网掩码: $NETMASK"
echo "网关: $GATEWAY"
echo "DNS服务器: $DNS"
echo "DHCP地址池: $RANGE_START - $RANGE_END"
echo "ISO镜像: $ISO_PATH"
echo "========================"

# 执行配置
check_iso
install_packages
configure_dhcp
configure_tftp
configure_http
start_services

echo "=== PXE服务器配置完成 ==="
echo "现在你可以通过PXE启动客户端机器进行安装了"
echo "请确保客户端机器的网络启动（PXE Boot）已启用"

exit 0