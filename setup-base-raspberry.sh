#!/bin/bash

set -e

# ============================================================
# CONFIGURAÇÃO BASE RASPBERRY PI
#
# - Configura teclado Português Brasil ABNT2
# - Habilita SSH
# - Pergunta IP estático antes da instalação
# - Configura IP estático
# - Detecta NetworkManager ou dhcpcd
# ============================================================

# ============================================================
# VERIFICAR ROOT
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo
    echo "Erro: este script precisa ser executado como root."
    echo
    echo "Execute:"
    echo
    echo "  curl -fsSL https://raw.githubusercontent.com/weto/rasp-project/main/setup-base-raspberry | sudo bash"
    echo
    exit 1
fi

# Usuário original
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# ============================================================
# INÍCIO
# ============================================================

clear

echo
echo "=============================================="
echo "       SETUP BASE - RASPBERRY PI"
echo "=============================================="
echo
echo "Este script irá:"
echo
echo "  1. Configurar teclado Português Brasil ABNT2"
echo "  2. Habilitar SSH"
echo "  3. Configurar IP estático"
echo
echo "=============================================="
echo

# ============================================================
# DETECTAR INTERFACE DE REDE
# ============================================================

echo "==> Detectando configuração atual de rede..."
echo

INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$INTERFACE" ]; then
    echo
    echo "ERRO: não foi possível detectar a interface de rede."
    echo
    exit 1
fi

CURRENT_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | \
    awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)

CURRENT_GATEWAY=$(ip route | \
    awk '/default/ {print $3; exit}')

echo "Interface detectada : $INTERFACE"
echo "IP atual             : ${CURRENT_IP:-não detectado}"
echo "Gateway atual        : ${CURRENT_GATEWAY:-não detectado}"
echo

# ============================================================
# PERGUNTAR IP ESTÁTICO
# ============================================================

echo "=============================================="
echo "       CONFIGURAÇÃO DO IP ESTÁTICO"
echo "=============================================="
echo

while true; do

    read -rp \
        "Digite o IP estático que deseja utilizar: " \
        STATIC_IP </dev/tty

    if [ -z "$STATIC_IP" ]; then
        echo
        echo "Erro: informe um IP."
        echo
        continue
    fi

    # Validar formato IPv4
    if ! [[ "$STATIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo
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
            break
        fi

    done

    if [ "$VALID" = true ]; then
        break
    fi

    echo
    echo "Erro: endereço IP inválido."
    echo
done

# ============================================================
# GATEWAY
# ============================================================

echo

read -rp \
    "Gateway [$CURRENT_GATEWAY]: " \
    GATEWAY </dev/tty

if [ -z "$GATEWAY" ]; then
    GATEWAY="$CURRENT_GATEWAY"
fi

if [ -z "$GATEWAY" ]; then

    echo
    echo "Nenhum gateway foi detectado."

    read -rp \
        "Digite o gateway: " \
        GATEWAY </dev/tty

fi

if [ -z "$GATEWAY" ]; then
    echo
    echo "Erro: gateway não informado."
    exit 1
fi

# ============================================================
# DNS
# ============================================================

echo

read -rp \
    "Servidor DNS [8.8.8.8]: " \
    DNS </dev/tty

if [ -z "$DNS" ]; then
    DNS="8.8.8.8"
fi

# ============================================================
# CONFIRMAÇÃO
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURAÇÃO SELECIONADA"
echo "=============================================="
echo
echo "Interface : $INTERFACE"
echo "IP        : $STATIC_IP"
echo "Máscara   : /24"
echo "Gateway   : $GATEWAY"
echo "DNS       : $DNS"
echo

read -rp \
    "Confirma esta configuração? [s/N]: " \
    CONFIRM </dev/tty

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then

    echo
    echo "Configuração cancelada pelo usuário."
    echo

    exit 0
fi

# ============================================================
# ATUALIZAR PACOTES
# ============================================================

echo
echo "=============================================="
echo "       INSTALAÇÃO"
echo "=============================================="
echo

echo "==> Atualizando lista de pacotes..."

apt-get update

# ============================================================
# INSTALAR PACOTES
# ============================================================

echo
echo "==> Instalando suporte ao teclado e SSH..."

apt-get install -y \
    keyboard-configuration \
    console-setup \
    openssh-server

# ============================================================
# CONFIGURAR TECLADO
# ============================================================

echo
echo "==> Configurando teclado Português do Brasil ABNT2..."

cat > /etc/default/keyboard <<'EOF'
XKBMODEL="abnt2"
XKBLAYOUT="br"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# Aplicar configuração
dpkg-reconfigure -f noninteractive keyboard-configuration || true

# ============================================================
# HABILITAR SSH
# ============================================================

echo
echo "==> Habilitando SSH..."

systemctl enable ssh
systemctl start ssh

# ============================================================
# CONFIGURAR IP ESTÁTICO
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURANDO IP ESTÁTICO"
echo "=============================================="
echo

# ============================================================
# NETWORKMANAGER
# ============================================================

if command -v nmcli >/dev/null 2>&1 && \
   systemctl is-active --quiet NetworkManager; then

    echo "==> NetworkManager detectado."

    CONNECTION=$(nmcli -t -f NAME,DEVICE connection show | \
        awk -F: -v dev="$INTERFACE" '$2 == dev {print $1; exit}')

    if [ -z "$CONNECTION" ]; then

        echo "==> Criando conexão para $INTERFACE..."

        nmcli connection add \
            type ethernet \
            ifname "$INTERFACE" \
            con-name "static-$INTERFACE"

        CONNECTION="static-$INTERFACE"
    fi

    echo "==> Configurando endereço IP..."

    nmcli connection modify "$CONNECTION" \
        ipv4.method manual \
        ipv4.addresses "$STATIC_IP/24" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS" \
        connection.autoconnect yes

    echo "==> Aplicando configuração..."

    nmcli connection up "$CONNECTION"

# ============================================================
# DHCPCD
# ============================================================

elif systemctl list-unit-files | grep -q "^dhcpcd.service"; then

    echo "==> dhcpcd detectado."

    # Backup
    BACKUP="/etc/dhcpcd.conf.backup.$(date +%Y%m%d-%H%M%S)"

    cp /etc/dhcpcd.conf "$BACKUP"

    echo
    echo "Backup criado:"
    echo "$BACKUP"

    # ========================================================
    # Remover configuração anterior criada pelo script
    # ========================================================

    sed -i \
        '/# Configuração adicionada pelo setup-base-raspberry/,+4d' \
        /etc/dhcpcd.conf

    # ========================================================
    # Adicionar configuração
    # ========================================================

    cat >> /etc/dhcpcd.conf <<EOF

# Configuração adicionada pelo setup-base-raspberry
interface $INTERFACE
static ip_address=$STATIC_IP/24
static routers=$GATEWAY
static domain_name_servers=$DNS
EOF

    echo
    echo "==> Reiniciando serviço dhcpcd..."

    systemctl restart dhcpcd

# ============================================================
# GERENCIADOR NÃO ENCONTRADO
# ============================================================

else

    echo
    echo "=============================================="
    echo " ERRO DE CONFIGURAÇÃO DE REDE"
    echo "=============================================="
    echo
    echo "Não foi possível identificar:"
    echo
    echo "  NetworkManager"
    echo "  ou"
    echo "  dhcpcd"
    echo
    echo "O IP estático NÃO foi configurado."
    echo

    exit 1
fi

# ============================================================
# AGUARDAR REDE
# ============================================================

echo
echo "==> Aguardando configuração da rede..."

sleep 3

# ============================================================
# VERIFICAR IP
# ============================================================

FINAL_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | \
    awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)

# ============================================================
# RESULTADO
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURAÇÃO CONCLUÍDA"
echo "=============================================="
echo
echo "Teclado : Português do Brasil (ABNT2)"
echo "SSH     : habilitado"
echo
echo "REDE"
echo "----------------------------------------------"
echo "Interface : $INTERFACE"
echo "IP        : ${FINAL_IP:-$STATIC_IP}"
echo "Gateway   : $GATEWAY"
echo "DNS       : $DNS"
echo

echo "SSH"
echo "----------------------------------------------"
echo
echo "Para conectar ao Raspberry Pi:"
echo
echo "ssh $REAL_USER@$STATIC_IP"
echo

echo "=============================================="
echo "             FIM DO SETUP"
echo "=============================================="
echo
