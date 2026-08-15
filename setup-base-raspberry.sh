#!/bin/bash

set -e

# ============================================================
# SETUP BASE - RASPBERRY PI
# ============================================================

# ------------------------------------------------------------
# Verificar terminal interativo
# ------------------------------------------------------------

if [ ! -e /dev/tty ]; then
    echo "Erro: terminal interativo não encontrado."
    echo
    echo "Execute o script diretamente no terminal."
    exit 1
fi

# ------------------------------------------------------------
# Verificar root
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo
    echo "Este script precisa ser executado como root."
    echo
    echo "Execute:"
    echo
    echo "curl -fsSL https://raw.githubusercontent.com/weto/rasp-project/main/setup-base-raspberry | sudo bash"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Função para ler do terminal
# ------------------------------------------------------------

ask() {
    local PROMPT="$1"
    local VARIABLE="$2"

    printf "%s" "$PROMPT" > /dev/tty

    IFS= read -r "$VARIABLE" < /dev/tty
}

# ============================================================
# INÍCIO
# ============================================================

clear

echo "=============================================="
echo "       SETUP BASE - RASPBERRY PI"
echo "=============================================="
echo
echo "Configurações:"
echo
echo "  - Teclado Português Brasil ABNT2"
echo "  - SSH"
echo "  - IP estático"
echo
echo "=============================================="
echo

# ============================================================
# DETECTAR INTERFACE
# ============================================================

INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$INTERFACE" ]; then
    echo "Erro: interface de rede não encontrada."
    exit 1
fi

CURRENT_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null |
    awk '/inet / {print $2}' |
    cut -d/ -f1 |
    head -n1)

CURRENT_GATEWAY=$(ip route |
    awk '/default/ {print $3; exit}')

echo "Interface : $INTERFACE"
echo "IP atual  : ${CURRENT_IP:-não detectado}"
echo "Gateway   : ${CURRENT_GATEWAY:-não detectado}"
echo

# ============================================================
# PERGUNTAR IP
# ============================================================

while true; do

    ask "Digite o IP estático que deseja utilizar: " STATIC_IP

    echo

    if [ -z "$STATIC_IP" ]; then
        echo "Erro: nenhum IP informado."
        echo
        continue
    fi

    # Verificar formato
    if ! [[ "$STATIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Erro: formato de IP inválido."
        echo
        continue
    fi

    # Validar octetos
    IFS='.' read -r O1 O2 O3 O4 <<< "$STATIC_IP"

    if (( O1 > 255 || O2 > 255 || O3 > 255 || O4 > 255 )); then
        echo "Erro: IP inválido."
        echo
        continue
    fi

    break

done

# ============================================================
# GATEWAY
# ============================================================

echo

if [ -n "$CURRENT_GATEWAY" ]; then

    ask "Gateway [$CURRENT_GATEWAY]: " GATEWAY

    if [ -z "$GATEWAY" ]; then
        GATEWAY="$CURRENT_GATEWAY"
    fi

else

    ask "Digite o gateway: " GATEWAY

fi

# ============================================================
# DNS
# ============================================================

echo

ask "Servidor DNS [8.8.8.8]: " DNS

if [ -z "$DNS" ]; then
    DNS="8.8.8.8"
fi

# ============================================================
# CONFIRMAÇÃO
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURAÇÃO DE REDE"
echo "=============================================="
echo
echo "Interface : $INTERFACE"
echo "IP        : $STATIC_IP"
echo "Máscara   : /24"
echo "Gateway   : $GATEWAY"
echo "DNS       : $DNS"
echo
echo "=============================================="
echo

ask "Aplicar esta configuração? [s/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo
    echo "Operação cancelada."
    exit 0
fi

# ============================================================
# INSTALAÇÃO
# ============================================================

echo
echo "=============================================="
echo "       INSTALAÇÃO DOS PACOTES"
echo "=============================================="
echo

echo "==> Atualizando pacotes..."

apt-get update

echo
echo "==> Instalando teclado e SSH..."

apt-get install -y \
    keyboard-configuration \
    console-setup \
    openssh-server

# ============================================================
# TECLADO
# ============================================================

echo
echo "==> Configurando teclado ABNT2..."

cat > /etc/default/keyboard <<'EOF'
XKBMODEL="abnt2"
XKBLAYOUT="br"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

dpkg-reconfigure -f noninteractive keyboard-configuration || true

# ============================================================
# SSH
# ============================================================

echo
echo "==> Habilitando SSH..."

systemctl enable ssh
systemctl start ssh

# ============================================================
# CONFIGURAR REDE
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURANDO IP ESTÁTICO"
echo "=============================================="
echo

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

if command -v nmcli >/dev/null 2>&1 &&
   systemctl is-active --quiet NetworkManager; then

    echo "NetworkManager detectado."

    CONNECTION=$(nmcli -t -f NAME,DEVICE connection show |
        awk -F: -v dev="$INTERFACE" '$2 == dev {print $1; exit}')

    if [ -z "$CONNECTION" ]; then

        nmcli connection add \
            type ethernet \
            ifname "$INTERFACE" \
            con-name "static-$INTERFACE"

        CONNECTION="static-$INTERFACE"

    fi

    nmcli connection modify "$CONNECTION" \
        ipv4.method manual \
        ipv4.addresses "$STATIC_IP/24" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS" \
        connection.autoconnect yes

    echo "Aplicando configuração..."

    nmcli connection up "$CONNECTION"

# ------------------------------------------------------------
# dhcpcd
# ------------------------------------------------------------

elif systemctl list-unit-files |
    grep -q "^dhcpcd.service"; then

    echo "dhcpcd detectado."

    BACKUP="/etc/dhcpcd.conf.backup.$(date +%Y%m%d-%H%M%S)"

    cp /etc/dhcpcd.conf "$BACKUP"

    echo "Backup:"
    echo "$BACKUP"

    cat >> /etc/dhcpcd.conf <<EOF

# Configuração adicionada pelo setup-base-raspberry
interface $INTERFACE
static ip_address=$STATIC_IP/24
static routers=$GATEWAY
static domain_name_servers=$DNS
EOF

    systemctl restart dhcpcd

else

    echo
    echo "Erro: NetworkManager ou dhcpcd não encontrado."
    exit 1

fi

# ============================================================
# FINAL
# ============================================================

sleep 3

FINAL_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null |
    awk '/inet / {print $2}' |
    cut -d/ -f1 |
    head -n1)

echo
echo "=============================================="
echo "       CONFIGURAÇÃO CONCLUÍDA"
echo "=============================================="
echo
echo "Teclado : Português Brasil ABNT2"
echo "SSH     : habilitado"
echo
echo "Rede:"
echo "  Interface : $INTERFACE"
echo "  IP        : ${FINAL_IP:-$STATIC_IP}"
echo "  Gateway   : $GATEWAY"
echo "  DNS       : $DNS"
echo
echo "Acesso SSH:"
echo
echo "  ssh $REAL_USER@$STATIC_IP"
echo
