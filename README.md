# rasp-project

Scripts de setup para Raspberry Pi (Debian/Raspberry Pi OS).

## Instalação rápida

```bash
curl -fsSL https://raw.githubusercontent.com/weto/rasp-project/main/setup-base-raspberry.sh | sudo bash
```

## Scripts

### `setup-base-raspberry.sh`

Configuração base do sistema:

- Configura teclado Português Brasil ABNT2
- Habilita SSH
- Configura IP estático (interface, IP, gateway e DNS)
- Detecta automaticamente NetworkManager ou dhcpcd
- Faz backup da configuração de rede antes de alterar
- Valida a configuração gravada

Execução:

```bash
sudo bash setup-base-raspberry.sh
```

### `setup_raspberry.sh`

Configuração de ambiente de desenvolvimento/aplicação:

- Instala Git
- Instala Docker Engine e Docker Buildx (sem Docker Compose)
- Adiciona o usuário ao grupo `docker`
- Instala UFW e libera a porta SSH
- Pergunta quais portas de aplicação devem ser liberadas
- Não ativa o UFW automaticamente (é preciso rodar `sudo ufw enable` depois)

#### Guia de instalação

**1. Pré-requisitos**

- Já ter rodado o [`setup-base-raspberry.sh`](#setup-base-raspberrysh) (rede/SSH configurados), ou já ter rede funcionando por outro meio
- Acesso root (`sudo`)
- Terminal interativo — o script pergunta as portas de aplicação durante a execução

**2. Baixar e executar**

Direto do repositório, via `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/weto/rasp-project/main/setup_raspberry.sh | sudo bash
```

Ou clonando o repositório:

```bash
git clone https://github.com/weto/rasp-project.git
cd rasp-project
sudo bash setup_raspberry.sh
```

> Se for rodar via `curl | sudo bash`, o script ainda consegue ler respostas do terminal (`/dev/tty`), então as perguntas interativas funcionam normalmente.

**3. O que o script vai perguntar**

Durante a execução, será solicitado:

```
Portas de aplicação:
```

- Pressione **ENTER** para não liberar nenhuma porta agora
- Ou informe uma ou mais portas TCP, separadas por espaço ou vírgula:

```
8080
8080 3000 5000
8080,3000,5000
```

Em seguida o script mostra as portas escolhidas e pede confirmação (`s/N`) antes de aplicar as regras no UFW.

**4. Pós-instalação**

Depois que o script terminar:

```bash
# Ativar o firewall (não é feito automaticamente)
sudo ufw enable

# Fazer logout/login (ou reiniciar) para que a permissão do
# grupo "docker" tenha efeito no usuário atual
sudo reboot

# Testar o Docker
docker run hello-world
```

## Requisitos

- Debian ou Raspberry Pi OS
- Acesso root (`sudo`)
- Terminal interativo (os scripts fazem perguntas durante a execução)
