FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV CUPSADMIN=admin
ENV CUPSPASSWORD=admin

# ── CUPS 核心 + AirPrint/Android 自动发现依赖 ──
RUN apt-get update && apt-get install -y --no-install-recommends \
      cups \
      cups-bsd \
      cups-client \
      cups-daemon \
      cups-filters \
      cups-ipp-utils \
      cups-browsed \
      avahi-daemon \
      avahi-utils \
      dbus \
      libnss-mdns \
      ipp-usb \
      ghostscript \
      fonts-noto-cjk \
      fonts-wqy-zenhei \
      fonts-wqy-microhei \
      ca-certificates \
    && apt-get install -y \
      printer-driver-all \
    && fc-cache -f \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── CUPS 配置：远程访问 + AirPrint/iOS/Android 兼容 ──
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/log>/<Location \/admin\/log>\n  Allow All/' /etc/cups/cupsd.conf && \
    echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
    echo "ReadyPaperSizes A4,A3,A5,A6,EnvDL" >> /etc/cups/cupsd.conf

# ssl 目录：cupsd 不会自建，缺了它 AirPrint/ipps 握手会失败
RUN mkdir -p /etc/cups/ssl && chmod 700 /etc/cups/ssl

# 备份默认配置供 entrypoint 还原
RUN cp -rp /etc/cups /etc/cups-bak

EXPOSE 631

VOLUME ["/etc/cups"]

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
