#!/bin/bash

set -e

# ============================================================
# SETUP BASE - RASPBERRY PI
#
# - Configura teclado Português Brasil ABNT2
# - Habilita SSH
# - Configura IP estático
# - Valida Interface, IP, Gateway e DNS
# - Faz backup da configuração de rede
# - Comenta configurações antigas
# - Adiciona nova configuração no final do arquivo
# ============================================================

# ============================================================
# VERIFICAR ROOT
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo
    echo "Erro: execute este script como root."
    echo
    echo "Exemplo:"
    echo
    echo "sudo bash setup-base-raspberry"
    echo
    exit 1
fi

# ============================================================
# TERMINAL
# ============================================================

if [ ! -e /dev/tty ]; then
    echo "Erro: terminal interativo não encontrado."
    exit 1
fi

# ============================================================
# FUNÇÃO PARA PERGUNTAR AO USUÁRIO
# ============================================================

ask() {
    local PROMPT="$1"
    local VARIABLE="$2"

    printf "%s" "$PROMPT" > /dev/tty
    IFS= read -r "$VARIABLE" < /dev/tty
}

# ============================================================
# FUNÇÃO VALIDAR IPV4
# ============================================================

validar_ipv4() {

    local IP="$1"

    if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    IFS='.' read -r O1 O2 O3 O4 <<< "$IP"

    for OCTET in "$O1" "$O2" "$O3" "$O4"; do

        if ! [[ "$OCTET" =~ ^[0-9]+$ ]]; then
            return 1
        fi

        if (( OCTET < 0 || OCTET > 255 )); then
            return 1
        fi

    done

    return 0
}

# ============================================================
# FUNÇÃO VALIDAR INTERFACE
# ============================================================

validar_interface() {

    local IFACE="$1"

    if [ -z "$IFACE" ]; then
        return 1
    fi

    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# ============================================================
# INÍCIO
# ============================================================

clear

echo
echo "=============================================="
echo "       SETUP BASE - RASPBERRY PI"
echo "=============================================="
echo
echo "Este script irá configurar:"
echo
echo "  - Interface de rede"
echo "  - IP estático"
echo "  - Gateway"
echo "  - DNS"
echo "  - Teclado Português Brasil ABNT2"
echo "  - SSH"
echo
echo "=============================================="
echo

# ============================================================
# DETECTAR CONFIGURAÇÃO ATUAL
# ============================================================

CURRENT_INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

CURRENT_IP=""

if [ -n "$CURRENT_INTERFACE" ]; then

    CURRENT_IP=$(ip -4 addr show "$CURRENT_INTERFACE" 2>/dev/null |
        awk '/inet / {print $2}' |
        cut -d/ -f1 |
        head -n1)

fi

CURRENT_GATEWAY=$(ip route |
    awk '/default/ {print $3; exit}')

CURRENT_DNS="8.8.8.8"

echo "Configuração atual detectada:"
echo
echo "  Interface : ${CURRENT_INTERFACE:-não detectada}"
echo "  IP        : ${CURRENT_IP:-não detectado}"
echo "  Gateway   : ${CURRENT_GATEWAY:-não detectado}"
echo "  DNS       : $CURRENT_DNS"
echo

# ============================================================
# PERGUNTAR INTERFACE
# ============================================================

while true; do

    ask "Interface [$CURRENT_INTERFACE]: " INTERFACE

    if [ -z "$INTERFACE" ]; then
        INTERFACE="$CURRENT_INTERFACE"
    fi

    if validar_interface "$INTERFACE"; then
        break
    fi

    echo
    echo "Erro: a interface '$INTERFACE' não existe."
    echo
    echo "Interfaces disponíveis:"
    ip -br link
    echo

done

# ============================================================
# PERGUNTAR IP
# ============================================================

while true; do

    ask "IP estático: " STATIC_IP

    if validar_ipv4 "$STATIC_IP"; then
        break
    fi

    echo
    echo "Erro: IP inválido."
    echo "Exemplo: 192.168.1.50"
    echo

done

# ============================================================
# PERGUNTAR GATEWAY
# ============================================================

while true; do

    ask "Gateway [$CURRENT_GATEWAY]: " GATEWAY

    if [ -z "$GATEWAY" ]; then
        GATEWAY="$CURRENT_GATEWAY"
    fi

    if validar_ipv4 "$GATEWAY"; then
        break
    fi

    echo
    echo "Erro: Gateway inválido."
    echo

done

# ============================================================
# PERGUNTAR DNS
# ============================================================

while true; do

    ask "DNS [$CURRENT_DNS]: " DNS

    if [ -z "$DNS" ]; then
        DNS="$CURRENT_DNS"
    fi

    if validar_ipv4 "$DNS"; then
        break
    fi

    echo
    echo "Erro: DNS inválido."
    echo

done

# ============================================================
# MOSTRAR CONFIGURAÇÃO
# ============================================================

echo
echo "=============================================="
echo "       NOVA CONFIGURAÇÃO"
echo "=============================================="
echo
echo "Interface : $INTERFACE"
echo "IP        : $STATIC_IP"
echo "Máscara   : /24"
echo "Gateway   : $GATEWAY"
echo "DNS       : $DNS"
echo

# ============================================================
# CONFIRMAR
# ============================================================

ask "Gravar esta configuração? [s/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then

    echo
    echo "Operação cancelada."
    exit 0

fi

# ============================================================
# INSTALAR PACOTES
# ============================================================

echo
echo "=============================================="
echo "       INSTALAÇÃO"
echo "=============================================="
echo

echo "==> Atualizando lista de pacotes..."

apt-get update

echo
echo "==> Instalando suporte ao teclado e SSH..."

apt-get install -y \
    keyboard-configuration \
    console-setup \
    openssh-server

# ============================================================
# TECLADO
# ============================================================

echo
echo "==> Configurando teclado Português Brasil ABNT2..."

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
# CONFIGURAÇÃO DE REDE
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURAÇÃO DE REDE"
echo "=============================================="
echo

# ============================================================
# NETWORKMANAGER
# ============================================================

if command -v nmcli >/dev/null 2>&1 &&
   systemctl is-active --quiet NetworkManager; then

    echo "NetworkManager detectado."

    CONNECTION=$(nmcli -t -f NAME,DEVICE connection show |
        awk -F: -v dev="$INTERFACE" '$2 == dev {print $1; exit}')

    if [ -z "$CONNECTION" ]; then

        echo "Criando conexão..."

        nmcli connection add \
            type ethernet \
            ifname "$INTERFACE" \
            con-name "static-$INTERFACE"

        CONNECTION="static-$INTERFACE"

    fi

    echo
    echo "Configuração atual do NetworkManager:"
    nmcli connection show "$CONNECTION"

    echo
    echo "==> Gravando nova configuração..."

    nmcli connection modify "$CONNECTION" \
        ipv4.method manual \
        ipv4.addresses "$STATIC_IP/24" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS" \
        connection.autoconnect yes

    echo
    echo "==> Aplicando configuração..."

    nmcli connection up "$CONNECTION"

# ============================================================
# DHCPCD
# ============================================================

elif systemctl list-unit-files |
    grep -q "^dhcpcd.service"; then

    echo "dhcpcd detectado."

    DHCPCD_CONF="/etc/dhcpcd.conf"

    # --------------------------------------------------------
    # BACKUP
    # --------------------------------------------------------

    BACKUP="${DHCPCD_CONF}.backup.$(date +%Y%m%d-%H%M%S)"

    cp "$DHCPCD_CONF" "$BACKUP"

    echo
    echo "Backup criado:"
    echo "$BACKUP"

    # --------------------------------------------------------
    # CRIAR ARQUIVO TEMPORÁRIO
    # --------------------------------------------------------

    TEMP_FILE=$(mktemp)

    # --------------------------------------------------------
    # COMENTAR CONFIGURAÇÕES EXISTENTES
    # --------------------------------------------------------

    echo
    echo "==> Procurando configurações anteriores..."

    awk '
    /^[[:space:]]*interface[[:space:]]+/ {
        print "# [comentado pelo setup-base-raspberry] " $0
        next
    }

    /^[[:space:]]*static[[:space:]]+ip_address=/ {
        print "# [comentado pelo setup-base-raspberry] " $0
        next
    }

    /^[[:space:]]*static[[:space:]]+routers=/ {
        print "# [comentado pelo setup-base-raspberry] " $0
        next
    }

    /^[[:space:]]*static[[:space:]]+domain_name_servers=/ {
        print "# [comentado pelo setup-base-raspberry] " $0
        next
    }

    { print }
    ' "$DHCPCD_CONF" > "$TEMP_FILE"

    # --------------------------------------------------------
    # ADICIONAR NOVA CONFIGURAÇÃO NO FINAL
    # --------------------------------------------------------

    cat >> "$TEMP_FILE" <<EOF


# ============================================================
# CONFIGURAÇÃO DE REDE
# Adicionada pelo setup-base-raspberry
# Data: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

interface $INTERFACE
static ip_address=$STATIC_IP/24
static routers=$GATEWAY
static domain_name_servers=$GATEWAY $DNS

# ============================================================
EOF

    # --------------------------------------------------------
    # VALIDAR ANTES DE GRAVAR
    # --------------------------------------------------------

    echo
    echo "==> Validando configuração antes de gravar..."

    if grep -q "^interface $INTERFACE$" "$TEMP_FILE" &&
       grep -q "^static ip_address=$STATIC_IP/24$" "$TEMP_FILE" &&
       grep -q "^static routers=$GATEWAY$" "$TEMP_FILE" &&
       grep -q "^static domain_name_servers=$GATEWAY $DNS$" "$TEMP_FILE"; then

        echo "Configuração validada."

    else

        echo
        echo "ERRO: a nova configuração não passou na validação."
        echo
        rm -f "$TEMP_FILE"
        exit 1

    fi

    # --------------------------------------------------------
    # GRAVAR
    # --------------------------------------------------------

    echo
    echo "==> Gravando configuração..."

    cp "$TEMP_FILE" "$DHCPCD_CONF"

    rm -f "$TEMP_FILE"

    # --------------------------------------------------------
    # VALIDAR ARQUIVO FINAL
    # --------------------------------------------------------

    echo
    echo "==> Validando arquivo final..."

    if grep -q "^interface $INTERFACE$" "$DHCPCD_CONF" &&
       grep -q "^static ip_address=$STATIC_IP/24$" "$DHCPCD_CONF" &&
       grep -q "^static routers=$GATEWAY$" "$DHCPCD_CONF" &&
       grep -q "^static domain_name_servers=$GATEWAY $DNS$" "$DHCPCD_CONF"; then

        echo "Arquivo validado com sucesso."

    else

        echo
        echo "ERRO: configuração não encontrada no arquivo."
        echo "Restaurando backup..."

        cp "$BACKUP" "$DHCPCD_CONF"

        exit 1

    fi

    # --------------------------------------------------------
    # REINICIAR DHCPCD
    # --------------------------------------------------------

    echo
    echo "==> Reiniciando dhcpcd..."

    systemctl restart dhcpcd

# ============================================================
# GERENCIADOR NÃO ENCONTRADO
# ============================================================

else

    echo
    echo "ERRO: nenhum gerenciador de rede suportado foi encontrado."
    echo
    echo "Esperado:"
    echo "  - NetworkManager"
    echo "  - dhcpcd"
    echo

    exit 1

fi

# ============================================================
# AGUARDAR REDE
# ============================================================

echo
echo "==> Aguardando rede..."

sleep 5

# ============================================================
# VERIFICAR CONFIGURAÇÃO FINAL
# ============================================================

FINAL_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null |
    awk '/inet / {print $2}' |
    cut -d/ -f1 |
    head -n1)

FINAL_GATEWAY=$(ip route |
    awk '/default/ {print $3; exit}')

# ============================================================
# RESULTADO
# ============================================================

echo
echo "=============================================="
echo "       CONFIGURAÇÃO CONCLUÍDA"
echo "=============================================="
echo
echo "Teclado:"
echo "  Português Brasil ABNT2"
echo
echo "SSH:"
echo "  Habilitado"
echo
echo "Rede:"
echo "  Interface : $INTERFACE"
echo "  IP        : ${FINAL_IP:-$STATIC_IP}"
echo "  Gateway   : ${FINAL_GATEWAY:-$GATEWAY}"
echo "  DNS       : $DNS"
echo
echo "=============================================="
echo
echo "Acesso SSH:"
echo
echo "  ssh $REAL_USER@$STATIC_IP"
echo
echo "=============================================="
