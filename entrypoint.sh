#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
# 1. CUPS admin user setup
# ══════════════════════════════════════════════════════════════
CUPSADMIN="${CUPSADMIN:-admin}"
CUPSPASSWORD="${CUPSPASSWORD:-admin}"
TZ="${TZ:-Asia/Shanghai}"

if [ "$(grep -ci "$CUPSADMIN" /etc/shadow 2>/dev/null)" -eq 0 ]; then
    useradd -r -G lpadmin -M "$CUPSADMIN"
    echo "$CUPSADMIN:$CUPSPASSWORD" | chpasswd
    echo "[entrypoint] admin user '$CUPSADMIN' created."
fi

# 时区
ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# 2. CUPS config restore
# ══════════════════════════════════════════════════════════════
if [ ! -f /etc/cups/cupsd.conf ]; then
    cp -rpn /etc/cups-bak/* /etc/cups/
fi

# ssl 目录：cupsd 不会自建，缺了它 AirPrint/ipps 握手会失败
mkdir -p /etc/cups/ssl 2>/dev/null || true
chmod 700 /etc/cups/ssl 2>/dev/null || true

# ReadyPaperSizes 补丁：iOS AirPrint 面板纸张列表依赖此项
if [ -f /etc/cups/cupsd.conf ] && ! grep -qiE '^[[:space:]]*ReadyPaperSizes' /etc/cups/cupsd.conf; then
    echo "ReadyPaperSizes A4,A3,A5,A6,EnvDL" >> /etc/cups/cupsd.conf
    echo "[entrypoint] appended ReadyPaperSizes for AirPrint paper list"
fi

# ══════════════════════════════════════════════════════════════
# 3. Start dbus + avahi (mDNS/DNS-SD for AirPrint & printer discovery)
# ══════════════════════════════════════════════════════════════
# ⚠️ 不要挂载宿主 /run/dbus/system_bus_socket，否则容器内 dbus-daemon 起不来
#    avahi 跟着失效，手机搜不到 AirPrint，CUPS 也发现不了网络打印机。
if command -v avahi-daemon >/dev/null 2>&1; then
    mkdir -p /var/run/dbus
    rm -f /run/dbus/pid
    if ! err=$(dbus-daemon --system --fork 2>&1); then
        echo "[entrypoint] WARN: dbus-daemon failed: ${err}"
    elif ! err=$(avahi-daemon --daemonize --no-chroot 2>&1); then
        echo "[entrypoint] WARN: avahi-daemon failed: ${err}"
    else
        echo "[entrypoint] avahi-daemon started (AirPrint broadcasting enabled)"
    fi
fi

# ipp-usb：USB 直连的 IPP Everywhere 打印机自动暴露为本地 IPP 端点
if command -v ipp-usb >/dev/null 2>&1; then
    mkdir -p /var/log/ipp-usb /var/lock/ipp-usb
    (ipp-usb >/var/log/ipp-usb/ipp-usb.log 2>&1 &) || true
fi

# ══════════════════════════════════════════════════════════════
# 4. Start cups-browsed (automatic network printer discovery via Avahi)
# ══════════════════════════════════════════════════════════════
if command -v cups-browsed >/dev/null 2>&1; then
    cups-browsed &
    echo "[entrypoint] cups-browsed started"
fi

# ══════════════════════════════════════════════════════════════
# 5. Start cupsd with watchdog (auto-restart on crash, fast-fail protection)
# ══════════════════════════════════════════════════════════════
CUPSD_MIN_UPTIME=5
CUPSD_MAX_FAST_FAILS=5
(
    fast_fails=0
    while true; do
        start_ts=$SECONDS
        /usr/sbin/cupsd -f
        rc=$?
        uptime=$((SECONDS - start_ts))

        if [ "$uptime" -lt "$CUPSD_MIN_UPTIME" ]; then
            fast_fails=$((fast_fails + 1))
        else
            fast_fails=0
        fi

        if [ "$fast_fails" -ge "$CUPSD_MAX_FAST_FAILS" ]; then
            echo "[entrypoint] ERROR: cupsd exited ${fast_fails} times within ${CUPSD_MIN_UPTIME}s (rc=${rc})."
            echo "[entrypoint] ERROR: 检查 /etc/cups/cupsd.conf 配置或 631 端口是否被占用。"
            break
        fi

        echo "[entrypoint] cupsd exited (rc=${rc}, uptime=${uptime}s), restarting in 2s..."
        sleep 2
    done
) &

# 等待 cupsd 就绪
for i in $(seq 1 30); do
    lpstat -r >/dev/null 2>&1 && break
    sleep 1
done

echo "[entrypoint] CUPS server ready"

# 保持容器运行：等待 cupsd watchdog 子进程
wait
