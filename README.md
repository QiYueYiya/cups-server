# CUPS 打印服务器

基于 Debian 的 Docker 化 CUPS 打印服务器，支持 AirPrint（iOS）和 Android 自动发现打印服务。

## 特性

- **AirPrint 支持**：iPhone/iPad 自动发现并打印
- **Android 打印**：通过 IPP 协议自动发现
- **USB 打印机热插拔**：无需重启容器即可识别新接入的 USB 打印机
- **网络打印机发现**：通过 Avahi/mDNS 自动发现局域网内共享的打印机
- **丰富的驱动**：预装 HP、Epson、Brother、Samsung 等主流打印机驱动
- **持久化配置**：CUPS 配置挂载到宿主机，容器重启不丢失

## 快速开始

### 使用 Docker Compose（推荐）

创建 `docker-compose.yml` 文件并启动：

```bash
cat > docker-compose.yml << 'EOF'
services:
  cups:
    image: ghcr.io/qiyueyiya/cups-server:latest
    container_name: cups
    user: root
    hostname: CUPS
    network_mode: host
    security_opt:
      - apparmor:unconfined
    environment:
      - CUPSADMIN=admin
      - CUPSPASSWORD=admin
      - TZ=Asia/Shanghai
    volumes:
      - ./cups-config:/etc/cups
      - /dev/bus/usb:/dev/bus/usb
      - /run/udev:/run/udev:ro
    device_cgroup_rules:
      - 'c 189:* rmw'
    restart: unless-stopped
EOF

docker compose up -d
```

### 使用 Docker 命令

```bash
docker run -d \
  --name cups \
  --network host \
  --user root \
  --hostname CUPS \
  --security-opt apparmor=unconfined \
  -e CUPSADMIN=admin \
  -e CUPSPASSWORD=admin \
  -e TZ=Asia/Shanghai \
  -v ./cups-config:/etc/cups \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /run/udev:/run/udev:ro \
  --device-cgroup-rule 'c 189:* rmw' \
  ghcr.io/qiyueyiya/cups-server:latest
```

## 访问管理界面

启动后通过浏览器访问：

```
http://<服务器IP>:631/admin
```

默认管理员账号：
- 用户名：`admin`
- 密码：`admin`

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CUPSADMIN` | `admin` | 管理员用户名 |
| `CUPSPASSWORD` | `admin` | 管理员密码 |
| `TZ` | `Asia/Shanghai` | 时区设置 |

## 手机打印

### iOS / iPadOS

1. 确保 iPhone/iPad 与服务器在同一局域网
2. 打开任意支持打印的应用（如"照片"、Safari）
3. 点击"分享" → "打印"
4. 系统会自动发现 CUPS 服务器上共享的打印机

### Android

1. 确保手机与服务器在同一局域网
2. 打开"设置" → "连接" → "打印" → "添加打印服务"
3. 系统会自动发现网络打印机

## 添加打印机

### 通过 Web 管理界面

1. 访问 `http://<服务器IP>:631/admin`
2. 点击"Administration" → "Add Printer"
3. 按照向导完成打印机添加

### 通过命令行

```bash
# 进入容器
docker exec -it cups bash

# 查看已连接的 USB 打印机
lpinfo -v

# 添加打印机（示例：HP LaserJet 1020）
lpadmin -p HP1020 -v usb://HP/LaserJet%201020?serial=xxx -m "HP LaserJet 1020, hpcups 3.21.2" -E

# 设置为默认打印机
lpoptions -d HP1020
```

## 卷挂载说明

| 宿主机路径 | 容器路径 | 说明 |
|-----------|---------|------|
| `./cups-config` | `/etc/cups` | CUPS 配置文件持久化 |
| `/dev/bus/usb` | `/dev/bus/usb` | USB 设备访问（打印机热插拔） |
| `/run/udev` | `/run/udev` | udev 设备信息（只读） |

## 网络模式说明

本项目使用 `network_mode: host`，原因：

- mDNS/DNS-SD 依赖局域网组播（UDP 5353），桥接模式下无法工作
- AirPrint 和 Android 打印发现依赖 mDNS
- 容器直接使用宿主机网络栈，无需端口映射

> **注意**：如果宿主机已运行 avahi-daemon，需先停止，否则会与容器内的 avahi 冲突。

## 自定义驱动安装

```bash
# 进入容器
docker exec -it cups bash

# 安装驱动包（示例：Canon 打印机驱动）
apt-get update
apt-get install printer-driver-gutenprint

# 重启 CUPS 使驱动生效
killall -HUP cupsd
```

## 常见问题

### 手机搜不到打印机

1. 确认手机与服务器在同一局域网/同一网段
2. 检查容器日志：`docker logs cups`
3. 确认 avahi 正常运行：`docker exec cups avahi-browse -a`
4. 确认宿主机未运行 avahi-daemon：`systemctl stop avahi-daemon`

### 打印任务卡住

```bash
# 查看打印队列
docker exec cups lpstat -o

# 取消所有任务
docker exec cups cancel -a
```

### 重置配置

```bash
# 停止容器
docker compose down

# 删除配置目录
rm -rf ./cups-config

# 重新启动（会自动生成默认配置）
docker compose up -d
```

## 项目结构

```
cups-server/
├── .github/
│   └── workflows/
│       └── docker-publish.yml   # GitHub Actions 自动构建
├── Dockerfile                    # 镜像构建文件
├── docker-compose.yml            # Docker Compose 配置
├── entrypoint.sh                 # 容器启动脚本
└── README.md                     # 项目说明
```

## 许可证

MIT License
