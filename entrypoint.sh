#!/bin/sh
set -xe

CONFIG_FILE=/etc/ocserv/ocserv.conf
CLIENT="${VPN_USERNAME}@${VPN_DOMAIN}"

function changeConfig() {
        local prop=$1
        local var=$2
        if [ -n "$var" ]; then
                echo "[INFO] Setting $prop to $var"
                sed -i "/$prop\s*=/ c $prop=$var" $CONFIG_FILE
        fi
}

# Select Server Certs
if [ "$OC_GENERATE_KEY" = "false" ]; then
        changeConfig "server-key" "/etc/ocserv/certs/${VPN_DOMAIN}.key"
        changeConfig "server-cert" "/etc/ocserv/certs/${VPN_DOMAIN}.crt"
else
        changeConfig "server-key" "/etc/ocserv/certs/${VPN_DOMAIN}.self-signed.key"
        changeConfig "server-cert" "/etc/ocserv/certs/${VPN_DOMAIN}.self-signed.crt"
fi

# Init Ocserv
/init.sh

# Enable TUN device
if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 600 /dev/net/tun
fi

# OCServ Network Settings
sed -i -e "s@^ipv4-network =.*@ipv4-network = ${VPN_NETWORK}@" \
        -e "s@^default-domain =.*@default-domain = ${VPN_DOMAIN}@" \
        -e "s@^ipv4-netmask =.*@ipv4-netmask = ${VPN_NETMASK}@" $CONFIG_FILE
#changeConfig "udp-port" "$PORT"
changeConfig "tcp-port" "$PORT"

# Config V2Ray-Client
sed -i "s/d.c.b.a/${V2RAY_SERVER}/g" /etc/v2ray/config.json
sed -i "s/10011/${V2RAY_PORT}/g" /etc/v2ray/config.json
sed -i "s/64/${V2RAY_ALTERID}/g" /etc/v2ray/config.json
sed -i "s/v2ray/${V2RAY_PATH}/g" /etc/v2ray/config.json
sed -i "s/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/${V2RAY_ID}/g" /etc/v2ray/config.json

# Radius Client Config
cat > /etc/radiusclient/radiusclient.conf <<_EOF_
login_tries     4
login_timeout   60
nologin                 /etc/nologin
issue                   /etc/radiusclient/issue
authserver              $RADIUS_SERVER
acctserver              $RADIUS_SERVER
servers                 /etc/radiusclient/servers
dictionary              /etc/radiusclient/dictionary
login_radius    /usr/sbin/login.radius
seqfile         /var/run/radius.seq
mapfile         /etc/radiusclient/port-id-map
default_realm
radius_timeout  10
radius_retries  3
bindaddr                *
_EOF_

# Radius Share Key
cat > /etc/radiusclient/servers << _EOF_
$RADIUS_SERVER          $RADIUS_SHAREKEY
_EOF_

# Add to PAC
cat >> /etc/ocserv/ocserv.conf << _EOF_
proxy-url = ${PAC_URL}
_EOF_

# Auto adapt MTU
iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Masquerade VPN subnet traffic
iptables -t nat -A POSTROUTING -s ${VPN_NETWORK}/${VPN_NETMASK} -j MASQUERADE

# Run v2oc Server
exec nohup /usr/bin/v2ray -config=/etc/v2ray/config.json >/dev/null 2>%1 &
exec nohup ocserv -c /etc/ocserv/ocserv.conf -f -d 1 "$@"
