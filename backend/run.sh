#!/usr/bin/bash

# run.sh

set -e

CHMOD=777
DIR_PATH=$(realpath "$(dirname "$0")")

LOGS_DIR="$DIR_PATH/logs"
ENV_FILE="$DIR_PATH/.env"

COMMON_LOG="$LOGS_DIR/common.log"
XL2TPD_LOG="$LOGS_DIR/xl2tpd.log"
IPSEC_LOG="$LOGS_DIR/ipsec.log"

DOMAINS_LIST="$DIR_PATH/domains.list"

LIBRARY_FILE="$DIR_PATH/app_bash/library.sh"

. "$LIBRARY_FILE"
. "$ENV_FILE"


CleanUp() {
  rm -rf "$XL2TPD_LOG"
  touch "$XL2TPD_LOG"

  # disable ipv4 forwarding default net space
  if [ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]; then
    sysctl -w net.ipv4.ip_forward=0
  fi

  # delete NAT rule
  if iptables -t nat -C POSTROUTING -s "$SUBNET" -o "$LAN_INTFS" -j MASQUERADE >/dev/null 2>%1; then
    iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$LAN_INTFS" -j MASQUERADE
  fi

  # delete interface (default)
  if ip link show "$INTFS_DS" > /dev/null 2>%1; then
    ip link delete "$INTFS_DS"
  fi

  # delete net space
  if ip netns list | grep -q "$VPN_NAMESPACE"; then
    ip netns delete "$VPN_NAMESPACE"
  fi
}

Configure() {
  # configure DNS
  sed -i "s/nameserver.*/nameserver 8.8.8.8/" "/etc/resolv.conf"

  # crate virtual net space
  ip netns add "$VPN_NAMESPACE"

  # create virtual interface (default and peer)
  ip link add "$INTFS_DS" type veth peer name "$INTFS_VS"
  # set interface (peer) to net space
  ip link set "$INTFS_VS" netns "$VPN_NAMESPACE"

  ### configure default space ###

  # add ip address to interface (default)
  ip addr add "$IP_INTFS_DS" dev "$INTFS_DS"
  # set up interface (default)
  ip link set "$INTFS_DS" up

  # enable forwarding ipv4
  sysctl -w net.ipv4.ip_forward=1

  ### configure peer space ###

  # add ip address to interface (peer)
  ip netns exec "$VPN_NAMESPACE" ip addr add "$IP_INTFS_VS" dev "$INTFS_VS"
  # set up interface (peer)
  ip netns exec "$VPN_NAMESPACE" ip link set "$INTFS_VS" up
  # set gateway
  ip netns exec "$VPN_NAMESPACE" ip route add default via "$GATEWAY_VS"

  # enable forwarding ipv4
  ip netns exec "$VPN_NAMESPACE" sysctl -w net.ipv4.ip_forward=1

  ### configure iptables ###

  # add NAT rule
  iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$LAN_INTFS" -j MASQUERADE

#  ufw route allow in on $INTFS_DS out on $LAN_INTFS
#  ufw route allow in on $LAN_INTFS out on $INTFS_DS

  sudo ufw route allow proto any to 10.0.0.2
  sudo ufw route allow proto any from 10.0.0.2
}

ConfigureVPN() {
  ### configure vpn files ###
  cat > "/etc/ipsec.conf" <<EOF
conn $VPN_NAME
  auto=add
  keyexchange=ikev1
  authby=secret
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=$VPN_SERVER_IP
  ike=aes128-sha1-modp2048
  esp=aes128-sha1
EOF

  cat > "/etc/ipsec.secrets" <<EOF
%any $VPN_SERVER_IP : PSK "$VPN_IPSEC_PSK"
EOF

  chmod 600 "/etc/ipsec.secrets"

  cat > "/etc/xl2tpd/xl2tpd.conf" <<EOF
[lac $VPN_NAME]
lns = $VPN_SERVER_IP
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
EOF

  chmod 600 "/etc/xl2tpd/xl2tpd.conf"

  cat > "/etc/ppp/options.l2tpd.client" <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-chap
noccp
noauth
mtu 1280
mru 1280
noipdefault
defaultroute
usepeerdns
connect-delay 5000
name $VPN_USER
password $VPN_PASSWORD
EOF

  chmod 600 "/etc/ppp/options.l2tpd.client"
}

Start() {
  ip netns exec "$VPN_NAMESPACE" xl2tpd -c /etc/xl2tpd/xl2tpd.conf > /dev/null 2>%1 &
  sleep 1
  ip netns exec "$VPN_NAMESPACE" ipsec restart || true
  sleep 1
  ip netns exec "$VPN_NAMESPACE" ipsec up $VPN_NAME
  sleep 1
  bash -c "echo 'c $VPN_NAME' > /var/run/xl2tpd/l2tp-control"
  sleep 5

  ip netns exec vase ip route add "$VPN_SERVER_IP" via "$GATEWAY_VS" dev "$INTFS_VS"
  ip netns exec vase ip route del default via "$GATEWAY_VS" dev "$INTFS_VS"
  ip netns exec vase ip route add default dev ppp0
}

Stop() {
  ipsec stop || true
  pkill xl2tpd || true
  service xl2tpd stop || true
  rm -f "/var/run/xl2tpd/l2tp-control"
  mkdir -p "/var/run/xl2tpd"
  touch "/var/run/xl2tpd/l2tp-control"
}

Test() {
  while true; do
    res=$(ip netns exec "$VPN_NAMESPACE" curl -s ifconfig.me)

    if [ "$res" != "$VPN_SERVER_IP" ]; then
      exit 1
    fi

    echo "$res"
    sleep 5
  done
}

ExitFunction() {
  Stop > /dev/null 2>&1
  CleanUp > /dev/null 2>&1
}

set -x
trap ExitFunction EXIT

Stop > /dev/null 2>&1
CleanUp
Configure
ConfigureVPN > /dev/null 2>&1
Start

Test

exit 0