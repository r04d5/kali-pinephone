#!/bin/bash
# Este arquivo contém funções auxiliares utilizadas pelo script principal build.sh
# Ele define variáveis globais e implementa funções para manipulação do sistema de arquivos,
# execução de comandos no ambiente chroot e outras operações necessárias para o processo de build.

# Variáveis globais para configuração do ambiente
ARCH='arm64'                                # Arquitetura alvo (ARM de 64 bits)
qemu_bin='/usr/bin/qemu-aarch64-static'     # Caminho para o binário QEMU para emulação ARM64
machine='debian'                            # Nome da máquina para o container systemd-nspawn
ENV='-E RUNLEVEL=1 -E LANG=C -E DEBIAN_FRONTEND=noninteractive -E DEBCONF_NOWARNINGS=yes'  # Variáveis de ambiente para o chroot
LOOP=`losetup -f`                           # Dispositivo loop disponível para montar a imagem
BOOT_P=${LOOP}p1                            # Partição de boot no dispositivo loop
ROOT_P=${LOOP}p2                            # Partição root no dispositivo loop
WORK_DIR=`dirname $0`                       # Diretório de trabalho (onde o script está sendo executado)
ROOTFS=${WORK_DIR}/kali_rootfs_tmp          # Diretório temporário para o sistema de arquivos root

# Função para exibir o banner do projeto
# Esta função é chamada no início do processo de build para identificar visualmente o projeto
banner()
{
cat <<'EOF'
-----------------------------------------
 _____     _   _____         _
|   | |___| |_|  |  |_ _ ___| |_ ___ ___
| | | | -_|  _|     | | |   |  _| -_|  _|
|_|___|___|_| |__|__|___|_|_|_| |___|_|
 _____
|  _  |___ ___
|   __|  _| . | Image Generator
|__|  |_| |___| by Shubham Vishwakarma

twitter/git: shubhamvis98
-----------------------------------------
EOF
}

# Função para executar comandos dentro do ambiente chroot usando systemd-nspawn
# Esta função permite executar comandos no sistema de arquivos montado como se estivesse
# rodando no dispositivo alvo, com suporte a emulação de arquitetura via QEMU
nspawn-exec() {
    case "$1" in
        # Modo especial para executar comandos a partir de um script temporário
        '-r')
            echo "$2" > ${ROOTFS}/__tmp.sh
            nspawn-exec bash /__tmp.sh
            rm ${ROOTFS}/__tmp.sh
            ;;
        # Modo normal para executar comandos diretamente
        *)
            systemd-nspawn --bind-ro $qemu_bin -M $machine --capability=cap_setfcap $ENV -D ${ROOTFS} "$@"
            ;;
    esac
}

# Função para criar uma imagem de disco e configurar as partições
# Parâmetros:
# $1 - Nome do arquivo de imagem
# $2 - Tamanho da imagem em GB
# $3 - Número de partições (1 para apenas root, ou 2 para boot+root)
mkimg() {
    set -e
    # Verifica se os parâmetros são válidos
    [[ -z $2 || $2 -lt 3 ]] && echo -e "Usage:\n\tmkimg {filename} {size_in_GB}\n\nNote: Size must be more than 3GB" && return
    IMG=$1
    SIZE=$2
    PARTS=$3
    # Verifica se a imagem já existe
    [ -e ${IMG} ] && echo -e '[*]$IMG already exists. So, skipping mkimg' && return

    echo "[*]Creating blank Image: ${IMG} of size ${SIZE}GB..."
    # Cria uma imagem em branco com o tamanho especificado
    dd if=/dev/zero of=${IMG} bs=1M count=$((1024*$SIZE)) status=progress

    # Carrega os UUIDs das partições gerados anteriormente
    source ./partuuid

    # Configuração para imagem com apenas uma partição (root)
    if [ $PARTS -eq 1 ]
    then
        # Monta a imagem como um dispositivo loop
        losetup ${LOOP} ${IMG}
        # Formata a partição root como ext4
        mkfs.ext4 -L ROOT -U ${ROOT_UUID} ${LOOP}
        # Cria o diretório de montagem e monta a partição
        mkdir -pv ${ROOTFS}
        mount -v ${LOOP} ${ROOTFS}
    else
        # Configuração para imagem com duas partições (boot + root)
        echo '[*]Partitioning Image: 512MB BOOT and rest ROOTFS...'
        sleep 1
        # Cria a tabela de partições GPT
        cat << 'EOF' | sfdisk ${IMG}
        label: gpt
        device: test.img
        unit: sectors
        first-lba: 2048
        sector-size: 512
        1 : start=2048, size=1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
        2 : start=1050624, type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
EOF
        echo '[*]Formatting Partitions...'
        # Monta a imagem como um dispositivo loop com suporte a partições
        losetup ${LOOP} -P ${IMG}
        # Formata as partições boot e root como ext4
        [ -e ${BOOT_P} ] && mkfs.ext4 -L BOOT -U ${BOOT_UUID} ${BOOT_P}
        [ -e ${ROOT_P} ] && mkfs.ext4 -L ROOT -U ${ROOT_UUID} ${ROOT_P}

        echo '[*]Mounting Partitions...'
        # Cria o diretório de montagem e monta as partições
        mkdir -pv ${ROOTFS}
        mount -v ${ROOT_P} ${ROOTFS}
        mkdir -pv ${ROOTFS}/boot
        mount -v ${BOOT_P} ${ROOTFS}/boot
    fi
}

# Função para limpar e desmontar o sistema de arquivos
# Esta função é chamada no final do processo de build para garantir que
# todos os recursos sejam liberados corretamente
cleanup() {
    set -x
    echo '[*]Unounting Partitions...'
    # Desmonta as partições se estiverem montadas
    mountpoint -q ${ROOTFS}/boot && umount ${ROOTFS}/boot
    mountpoint -q ${ROOTFS} && umount ${ROOTFS}
    # Remove o diretório temporário e o arquivo de UUIDs
    rm -rf ${ROOTFS} ./partuuid
    # Libera o dispositivo loop
    losetup -d ${LOOP}
}

# Configura um handler para o sinal SIGINT (Ctrl+C)
# Isso garante que o script possa ser interrompido de forma segura
trap ctrl_c INT
ctrl_c() {
    exit 1
}
