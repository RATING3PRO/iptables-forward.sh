#!/bin/bash

if [ -z "$FORCE_TTY_FIXED" ]; then
  if [ ! -t 0 ] && [ -r /dev/tty ]; then
    export FORCE_TTY_FIXED=1
    exec </dev/tty
  fi
fi

set -e

echo "=============================="
echo " iptables 端口转发配置向导 "
echo "=============================="
echo

# 监听 IP
read -p "监听 IP（默认 0.0.0.0）: " LISTEN_IP
LISTEN_IP=${LISTEN_IP:-0.0.0.0}

# 监听端口
read -p "监听端口（支持 80,443,8000-8010）: " LISTEN_PORTS
if [ -z "$LISTEN_PORTS" ]; then
  echo "[!] 端口不能为空"
  exit 1
fi

# 目标地址
read -p "转发目标 IP / 域名: " TARGET_HOST
if [ -z "$TARGET_HOST" ]; then
  echo "[!] 目标不能为空"
  exit 1
fi

# 端口是否保持一致
read -p "目标端口是否与监听端口一致？[Y/n]: " SAME_PORT
SAME_PORT=${SAME_PORT:-Y}

if [ "$SAME_PORT" = "n" ] || [ "$SAME_PORT" = "N" ]; then
  read -p "目标端口（单个端口）: " TARGET_PORT
  if [ -z "$TARGET_PORT" ]; then
    echo "[!] 目标端口不能为空"
    exit 1
  fi
else
  TARGET_PORT=""
fi

# 协议
echo
echo "选择协议："
echo " 1) TCP"
echo " 2) UDP"
echo " 3) TCP + UDP"
read -p "请输入 [1-3]（默认 1）: " PROTO_CHOICE
PROTO_CHOICE=${PROTO_CHOICE:-1}

case "$PROTO_CHOICE" in
  1) PROTOS="tcp" ;;
  2) PROTOS="udp" ;;
  3) PROTOS="tcp udp" ;;
  *) echo "[!] 无效选择"; exit 1 ;;
esac

echo
echo "[*] 解析目标地址..."

TARGET_IP=$(getent ahostsv4 "$TARGET_HOST" | awk '{print $1}' | head -n1)

if [ -z "$TARGET_IP" ]; then
  echo "[!] 无法解析目标地址"
  exit 1
fi

echo "[+] 目标 IP: $TARGET_IP"

echo
echo "[*] 开启 IP Forward"
echo 1 > /proc/sys/net/ipv4/ip_forward

# 拆分端口
parse_ports() {
  echo "$1" | tr ',' '\n'
}

apply_rule() {
  proto=$1
  dport=$2
  to_port=$3

  if [ -z "$to_port" ]; then
    to_port="$dport"
  fi

  iptables -t nat -A PREROUTING \
    -p "$proto" -d "$LISTEN_IP" --dport "$dport" \
    -j DNAT --to-destination "$TARGET_IP:$to_port"

  iptables -A FORWARD \
    -p "$proto" -d "$TARGET_IP" --dport "$to_port" -j ACCEPT
}

echo
echo "[*] 应用规则..."

for proto in $PROTOS; do
  for p in $(parse_ports "$LISTEN_PORTS"); do
    if echo "$p" | grep -q "-"; then
      START=$(echo "$p" | cut -d- -f1)
      END=$(echo "$p" | cut -d- -f2)
      for port in $(seq "$START" "$END"); do
        apply_rule "$proto" "$port" "$TARGET_PORT"
      done
    else
      apply_rule "$proto" "$p" "$TARGET_PORT"
    fi
  done
done

iptables -t nat -A POSTROUTING -d "$TARGET_IP" -j MASQUERADE

echo
echo "=============================="
echo " 转发规则已成功生效 ✅"
echo "=============================="
