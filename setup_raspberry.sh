#!/bin/bash

set -e

# ============================================================
# SETUP RASPBERRY PI
#
# - Instala Git
# - Instala Docker Engine
# - Instala Docker Buildx
# - NÃO instala Docker Compose
# - Libera SSH
# - Pergunta portas de aplicação
# - Aceita múltiplas portas
# - NÃO configura IP estático
# - NÃO ativa UFW automaticamente
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
    echo "sudo bash $0"
    echo

    exit 1
fi

# Usuário que executou sudo
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# ============================================================
# INÍCIO
# ============================================================

echo
echo "=============================================="
echo "       SETUP RASPBERRY PI"
echo "=============================================="
echo
echo "Usuário: $REAL_USER"
echo

# ============================================================
# DETECTAR INTERFACE DE REDE
# ============================================================

echo "==> Detectando interface de rede..."

INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$INTERFACE" ]; then

    echo
    echo "Aviso: não foi possível detectar a interface de rede."

else

    CURRENT_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null |
        awk '/inet / {print $2}' |
        cut -d/ -f1 |
        head -n1)

    CURRENT_GATEWAY=$(ip route |
        awk '/default/ {print $3; exit}')

    echo "Interface : $INTERFACE"
    echo "IP atual  : ${CURRENT_IP:-não detectado}"
    echo "Gateway   : ${CURRENT_GATEWAY:-não detectado}"

fi

echo

# ============================================================
# ATUALIZAR PACOTES
# ============================================================

echo "=============================================="
echo " ATUALIZANDO SISTEMA"
echo "=============================================="
echo

apt-get update

# ============================================================
# INSTALAR GIT
# ============================================================

echo "=============================================="
echo " INSTALANDO GIT"
echo "=============================================="
echo

apt-get install -y \
    git \
    curl \
    ca-certificates \
    gnupg

echo
echo "Git instalado:"
git --version
echo

# ============================================================
# INSTALAR DOCKER
# ============================================================

echo "=============================================="
echo " INSTALANDO DOCKER"
echo "=============================================="
echo

echo "==> Removendo pacotes Docker antigos/conflitantes..."

apt-get remove -y \
    docker.io \
    docker-doc \
    docker-compose \
    docker-compose-v2 \
    podman-docker \
    containerd \
    runc \
    2>/dev/null || true

echo
echo "==> Instalando dependências..."

apt-get install -y \
    ca-certificates \
    curl \
    gnupg

# ============================================================
# CHAVE DOCKER
# ============================================================

install -m 0755 -d /etc/apt/keyrings

echo "==> Adicionando chave oficial do Docker..."

curl -fsSL \
    https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

# ============================================================
# DETECTAR ARQUITETURA
# ============================================================

ARCH=$(dpkg --print-architecture)

CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

if [ -z "$CODENAME" ]; then

    CODENAME=$(lsb_release -cs 2>/dev/null || true)

fi

if [ -z "$CODENAME" ]; then

    echo
    echo "Erro: não foi possível detectar a versão do Debian."
    exit 1

fi

echo
echo "Arquitetura : $ARCH"
echo "Codename    : $CODENAME"
echo

# ============================================================
# REPOSITÓRIO DOCKER
# ============================================================

echo "==> Configurando repositório oficial do Docker..."

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable
EOF

apt-get update

# ============================================================
# INSTALAR DOCKER
# ============================================================

echo "==> Instalando Docker Engine..."

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin

echo
echo "Docker instalado:"
docker --version
echo

# ============================================================
# HABILITAR DOCKER
# ============================================================

echo "==> Habilitando Docker no boot..."

systemctl enable docker
systemctl enable containerd

systemctl start docker

echo
echo "Docker iniciado."
echo

# ============================================================
# ADICIONAR USUÁRIO AO GRUPO DOCKER
# ============================================================

if id "$REAL_USER" >/dev/null 2>&1; then

    echo "==> Adicionando usuário '$REAL_USER' ao grupo docker..."

    usermod -aG docker "$REAL_USER"

    echo "Usuário adicionado ao grupo docker."

else

    echo
    echo "Aviso: usuário '$REAL_USER' não encontrado."

fi

echo

# ============================================================
# TESTAR DOCKER
# ============================================================

echo "==> Testando Docker..."

if docker run --rm hello-world >/dev/null 2>&1; then

    echo "Docker funcionando corretamente."

else

    echo
    echo "Aviso: não foi possível executar o teste Docker."
    echo
    echo "Faça logout/login ou reinicie o Raspberry Pi."
    echo
    echo "Depois execute:"
    echo
    echo "docker run hello-world"

fi

echo

# ============================================================
# FIREWALL
# ============================================================

echo "=============================================="
echo " CONFIGURANDO FIREWALL"
echo "=============================================="
echo

# ============================================================
# INSTALAR UFW
# ============================================================

if command -v ufw >/dev/null 2>&1; then

    echo "UFW já está instalado."

else

    echo "UFW não instalado."
    echo "Instalando..."

    apt-get install -y ufw

fi

# ============================================================
# LIBERAR SSH
# ============================================================

echo
echo "==> Liberando SSH..."

ufw allow ssh

echo "SSH: permitido."

# ============================================================
# PORTAS DE APLICAÇÃO
# ============================================================

echo
echo "=============================================="
echo " PORTAS DE APLICAÇÃO"
echo "=============================================="
echo
echo "Deseja liberar alguma porta de aplicação?"
echo
echo "Você pode informar uma ou várias portas."
echo
echo "Exemplos:"
echo
echo "  8080"
echo "  8080 3000 5000"
echo "  8080,3000,5000"
echo
echo "Pressione ENTER para não liberar nenhuma."
echo

read -r -p "Portas de aplicação: " APPLICATION_PORTS </dev/tty

# ============================================================
# NORMALIZAR ENTRADA
# ============================================================

APPLICATION_PORTS=$(echo "$APPLICATION_PORTS" |
    tr ',' ' ' |
    xargs 2>/dev/null || true)

OPENED_PORTS=""

# ============================================================
# VALIDAR E LIBERAR PORTAS
# ============================================================

if [ -n "$APPLICATION_PORTS" ]; then

    for PORT in $APPLICATION_PORTS; do

        # ----------------------------------------------------
        # Validar número
        # ----------------------------------------------------

        if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then

            echo
            echo "ERRO: porta inválida: $PORT"
            echo
            echo "Informe somente números entre 1 e 65535."

            exit 1

        fi

        # ----------------------------------------------------
        # Validar intervalo
        # ----------------------------------------------------

        if (( PORT < 1 || PORT > 65535 )); then

            echo
            echo "ERRO: porta fora do intervalo: $PORT"
            echo
            echo "O intervalo permitido é 1 até 65535."

            exit 1

        fi

    done

    # --------------------------------------------------------
    # Mostrar portas antes de aplicar
    # --------------------------------------------------------

    echo
    echo "Portas selecionadas:"
    echo

    for PORT in $APPLICATION_PORTS; do
        echo "  TCP/$PORT"
    done

    echo

    read -r -p \
        "Confirmar liberação dessas portas? [s/N]: " \
        CONFIRM_PORTS </dev/tty

    if [[ "$CONFIRM_PORTS" =~ ^[Ss]$ ]]; then

        for PORT in $APPLICATION_PORTS; do

            echo
            echo "==> Liberando TCP/$PORT..."

            # Evitar regra duplicada
            if ufw status | grep -qE \
                "^${PORT}/tcp[[:space:]]+ALLOW"; then

                echo "TCP/$PORT já está liberada."

            else

                ufw allow "$PORT/tcp"

                echo "TCP/$PORT liberada."

            fi

            if [ -z "$OPENED_PORTS" ]; then

                OPENED_PORTS="$PORT"

            else

                OPENED_PORTS="$OPENED_PORTS $PORT"

            fi

        done

    else

        echo
        echo "Nenhuma porta de aplicação foi liberada."

    fi

else

    echo
    echo "Nenhuma porta de aplicação será liberada."

fi

# ============================================================
# RESUMO DO FIREWALL
# ============================================================

echo
echo "=============================================="
echo " REGRAS DE FIREWALL"
echo "=============================================="
echo

echo "SSH:"
echo "  permitido"

if [ -n "$OPENED_PORTS" ]; then

    echo
    echo "Portas de aplicação:"

    for PORT in $OPENED_PORTS; do
        echo "  TCP/$PORT : permitido"
    done

else

    echo
    echo "Portas de aplicação:"
    echo "  nenhuma"

fi

echo
echo "UFW NÃO será ativado automaticamente."
echo
echo "Para ativar:"
echo
echo "  sudo ufw enable"
echo

# ============================================================
# STATUS DOCKER
# ============================================================

echo "=============================================="
echo " STATUS DOCKER"
echo "=============================================="
echo

systemctl --no-pager status docker | head -n 10

echo

# ============================================================
# RESULTADO FINAL
# ============================================================

echo
echo "=============================================="
echo " CONFIGURAÇÃO CONCLUÍDA"
echo "=============================================="
echo

echo "REDE"
echo "----------------------------------------------"

if [ -n "$INTERFACE" ]; then

    echo "Interface : $INTERFACE"
    echo "IP        : ${CURRENT_IP:-não detectado}"
    echo "Gateway   : ${CURRENT_GATEWAY:-não detectado}"

fi

echo

echo "SOFTWARE"
echo "----------------------------------------------"
echo "Git       : $(git --version)"
echo "Docker    : $(docker --version)"
echo "Buildx    : $(docker buildx version 2>/dev/null || echo 'não disponível')"
echo

echo "DOCKER COMPOSE"
echo "----------------------------------------------"
echo "NÃO instalado."
echo

echo "FIREWALL"
echo "----------------------------------------------"
echo "SSH       : permitido"

if [ -n "$OPENED_PORTS" ]; then

    for PORT in $OPENED_PORTS; do
        echo "TCP/$PORT  : permitido"
    done

else

    echo "Aplicação: nenhuma porta liberada."

fi

echo
echo "UFW       : não ativado automaticamente"
echo

echo "USUÁRIO DOCKER"
echo "----------------------------------------------"
echo "$REAL_USER foi adicionado ao grupo docker."
echo

echo "IMPORTANTE:"
echo "Faça logout/login ou reinicie o Raspberry Pi"
echo "para que a permissão do grupo docker tenha efeito."
echo

echo "TESTAR DOCKER"
echo "----------------------------------------------"
echo
echo "docker run hello-world"
echo

echo "=============================================="
echo " FIM"
echo "=============================================="
echo
