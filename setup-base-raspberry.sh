#!/bin/bash

set -e

# ============================================================
# CONFIGURAÇÃO RASPBERRY PI / RASPBIAN / RASPBERRY PI OS
#
# - Configurando teclado PT-BR
# - Liberando conexão SSH
# - Configurando o IP estático local
# ============================================================

#!/bin/bash

set -e

# ============================================================
# CONFIGURAÇÃO BASE RASPBERRY PI
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root:"
    echo
    echo "sudo $0"
    exit 1
fi

# ============================================================
# CONFIGURAÇÃO DE REDE - PRIMEIRO PASSO
# ============================================================

echo
echo "========================================"
echo " CONFIGURAÇÃO DE REDE"
echo "========================================"
echo

# Detectar interface
INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$INTERFACE" ]; then
    echo "Erro: não foi possível detectar a interface de rede."
    exit 1
fi

# Detectar IP atual
CURRENT_IP=$(ip -4 addr show "$INTERFACE" | \
    awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)

# Detectar gateway
CURRENT_GATEWAY=$(ip route | \
    awk '/default/ {print $3; exit}')

echo "Interface detectada : $INTERFACE"
echo "IP atual             : ${CURRENT_IP:-não detectado}"
echo "Gateway atual        : ${CURRENT_GATEWAY:-não detectado}"
echo

# ============================================================
# PERGUNTAR IP ESTÁTICO
# ============================================================

while true; do

    read -rp "Digite o IP estático que deseja utilizar: " STATIC_IP

    if [ -z "$STATIC_IP" ]; then
        echo "Erro: informe um IP."
        echo
        continue
    fi

    # Validar formato IPv4
    if ! [[ "$STATIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Erro: formato de IP inválido."
        echo
        continue
    fi

    # Validar octetos
    IFS='.' read -ra OCTETS <<< "$STATIC_IP"

    VALID=true

    for OCTET in "${OCTETS[@]}"; do
        if (( OCTET < 0 || OCTET > 255 )); then
            VALID=false
        fi
    done

    if [ "$VALID" = true ]; then
        break
    fi

    echo "Erro: IP inválido."
    echo
done

# ============================================================
# GATEWAY
# ============================================================

echo

read -rp "Gateway [$CURRENT_GATEWAY]: " GATEWAY

if [ -z "$GATEWAY" ]; then
    GATEWAY="$CURRENT_GATEWAY"
fi

if [ -z "$GATEWAY" ]; then
    echo "Erro: gateway não informado."
    exit 1
fi

# ============================================================
# DNS
# ============================================================

echo

read -rp "DNS [8.8.8.8]: " DNS

if [ -z "$DNS" ]; then
    DNS="8.8.8.8"
fi

# ============================================================
# CONFIRMAÇÃO
# ============================================================

echo
echo "========================================"
echo " CONFIGURAÇÃO DE REDE"
echo "========================================"
echo
echo "Interface : $INTERFACE"
echo "IP        : $STATIC_IP"
echo "Máscara   : /24"
echo "Gateway   : $GATEWAY"
echo "DNS       : $DNS"
echo

read -rp "Confirma a configuração? [s/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo
    echo "Configuração cancelada."
    exit 0
fi

# ============================================================
# AGORA COMEÇA A INSTALAÇÃO
# ============================================================

echo
echo "========================================"
echo " INSTALAÇÃO"
echo "========================================"
echo

echo "==> Atualizando lista de pacotes..."
apt-get update

echo "==> Instalando suporte ao teclado e SSH..."
apt-get install -y \
    keyboard-configuration \
    console-setup \
    openssh-server

# ============================================================
# TECLADO
# ============================================================

echo "==> Configurando teclado Português do Brasil ABNT2..."

cat > /etc/default/keyboard <<'EOF'
XKBMODEL="abnt2"
XKBLAYOUT="br"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# ============================================================
# SSH
# ============================================================

echo "==> Habilitando SSH..."

systemctl enable ssh
systemctl start ssh

# ============================================================
# CONFIGURAR IP
# ============================================================

echo
echo "========================================"
echo " CONFIGURANDO IP ESTÁTICO"
echo "========================================"
echo

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

if command -v nmcli >/dev/null 2>&1 && \
   systemctl is-active --quiet NetworkManager; then

    echo "NetworkManager detectado."

    CONNECTION=$(nmcli -t -f NAME,DEVICE connection show | \
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
        ipv4.dns "$DNS"

    nmcli connection up "$CONNECTION"

# ------------------------------------------------------------
# dhcpcd
# ------------------------------------------------------------

elif systemctl list-unit-files | grep -q "^dhcpcd.service"; then

    echo "dhcpcd detectado."

    BACKUP="/etc/dhcpcd.conf.backup.$(date +%Y%m%d-%H%M%S)"

    cp /etc/dhcpcd.conf "$BACKUP"

    echo "Backup criado:"
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
    echo "ERRO: NetworkManager ou dhcpcd não encontrado."
    exit 1

fi

# ============================================================
# FINAL
# ============================================================

echo
echo "========================================"
echo " CONFIGURAÇÃO CONCLUÍDA"
echo "========================================"
echo
echo "Teclado : Português do Brasil (ABNT2)"
echo "SSH     : habilitado"
echo "IP      : $STATIC_IP"
echo "Gateway : $GATEWAY"
echo "DNS     : $DNS"
echo

echo "Conecte usando:"
echo
echo "ssh $SUDO_USER@$STATIC_IP"
echo
