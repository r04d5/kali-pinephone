#!/bin/bash -e
# Este script é o ponto de entrada principal para a geração de imagens Kali Linux para dispositivos móveis.
# Ele configura variáveis de ambiente, processa argumentos de linha de comando e orquestra todo o processo de build.

# Importa funções auxiliares do arquivo funcs.sh
. ./funcs.sh

# Configurações padrão para a criação da imagem
device="pinephone"          # Dispositivo alvo padrão
environment="phosh"         # Ambiente de desktop padrão (Phosh é uma interface móvel baseada em GNOME)
hostname="fossfrog"         # Nome do host padrão
username="kali"             # Nome de usuário padrão
password="8888"             # Senha padrão
mobian_suite="trixie"       # Versão do Mobian a ser utilizada
IMGSIZE=5                   # Tamanho da imagem em GB

# Processamento de argumentos da linha de comando usando getopts
# Permite personalizar vários aspectos da imagem a ser criada
while getopts "cbt:e:h:u:p:s:m:M:" opt
do
    case "$opt" in
        t ) device="$OPTARG" ;;         # Tipo de dispositivo
        e ) environment="$OPTARG" ;;    # Ambiente de desktop
        h ) hostname="$OPTARG" ;;       # Nome do host
        u ) username="$OPTARG" ;;       # Nome de usuário
        p ) password="$OPTARG" ;;       # Senha
        s ) custom_script="$OPTARG" ;;  # Script personalizado a ser executado
        m ) mobian_suite="$OPTARG" ;;   # Versão do Mobian
        M ) MIRROR="$OPTARG" ;;         # Espelho de repositório alternativo
        c ) compress=1 ;;               # Comprimir a imagem final
        b ) blockmap=1 ;;               # Criar um mapa de blocos para a imagem
    esac
done

# Configuração específica para cada família de dispositivos
# Define arquitetura, família, serviços necessários e pacotes específicos
case "$device" in
  # Dispositivos baseados em SoC Allwinner (PinePhone original, PineTab)
  "pinephone"|"pinetab"|"sunxi" )
    arch="arm64"                # Arquitetura ARM de 64 bits
    family="sunxi"              # Família Allwinner (sunxi)
    SERVICES="eg25-manager"     # Serviço para gerenciar o modem Quectel EG25
    ;;
  # Dispositivos baseados em SoC Rockchip (PinePhone Pro, PineTab 2)
  "pinephonepro"|"pinetab2"|"rockchip" )
    arch="arm64"
    family="rockchip"
    SERVICES="eg25-manager"
    ;;
  # Dispositivos baseados em Qualcomm Snapdragon 845
  "pocof1"|"oneplus6"|"oneplus6t"|"sdm845" )
    arch="arm64"
    family="qcom"
    # Serviços necessários para dispositivos Qualcomm
    SERVICES="qrtr-ns rmtfs pd-mapper tqftpserv qcom-modem-setup droid-juicer"
    PACKAGES="pulseaudio yq qbootctl"
    PARTITIONS=1                # Usa apenas uma partição em vez de separar /boot
    SPARSE=1                    # Cria uma imagem esparsa (formato Android)
    ;;
  # Dispositivos baseados em Qualcomm Snapdragon 7325
  "nothingphone1"|"sm7325" )
    arch="arm64"
    family="sm7325"
    SERVICES="qrtr-ns rmtfs pd-mapper tqftpserv qcom-modem-setup droid-juicer"
    PACKAGES="pulseaudio yq qbootctl"
    PARTITIONS=1
    SPARSE=1
    ;;
  # Dispositivo não suportado
  * )
    echo "Unsupported device ${device}"
    exit 1
    ;;
esac

# Adiciona pacotes básicos necessários para todos os dispositivos
PACKAGES="${PACKAGES} kali-linux-core wget curl rsync systemd-timesyncd systemd-repart"
# Adiciona pacote de suporte específico para a família do dispositivo
DPACKAGES="${family}-support"

# Configuração específica para cada ambiente de desktop
case "${environment}" in
    phosh)
        # Phosh é uma interface móvel baseada em GNOME Shell
        PACKAGES="${PACKAGES} phosh-phone phog portfolio-filemanager"
        SERVICES="${SERVICES} greetd"  # Serviço de login gráfico
        ;;
    plasma-mobile)
        # KDE Plasma Mobile
        PACKAGES="${PACKAGES} plasma-mobile qmlkonsole"
        SERVICES="${SERVICES} plasma-mobile"
        ;;
    # Ambientes de desktop tradicionais
    xfce|lxde|gnome|kde)
        PACKAGES="${PACKAGES} kali-desktop-${environment}"
        ;;
esac

# Define nomes de arquivos para a imagem final e arquivos temporários
# Inclui data no formato AAAAMMDD para identificação
IMG="kali_${environment}_${device}_`date +%Y%m%d`.img"        # Nome do arquivo de imagem final
ROOTFS_TAR="kali_${environment}_${device}_`date +%Y%m%d`.tgz" # Nome do arquivo tar temporário
ROOTFS="kali_rootfs_tmp"                                      # Diretório temporário para o sistema de arquivos

### INÍCIO DO PROCESSO DE BUILD ###
banner  # Exibe o banner do projeto (função definida em funcs.sh)
echo '____________________BUILD_INFO____________________'
# Exibe informações sobre a configuração atual
echo "Device: $device"
echo "Environment: $environment"
echo "Hostname: $hostname"
echo "Username: $username"
echo "Password: $password"
echo "Mobian Suite: $mobian_suite"
echo "Family: $family"
echo "Custom Script: $custom_script"
echo -e '--------------------------------------------------\n\n'
echo '[*]Build will start in 5 seconds...'; sleep 5  # Pausa para o usuário verificar as configurações

# Se existir um arquivo base.tgz, usa-o como base para o sistema de arquivos
# Isso pode acelerar o processo de build usando um sistema pré-construído
[ -e "base.tgz" ] && mkdir ${ROOTFS} && tar --strip-components=1 -xpf base.tgz -C ${ROOTFS}

echo '[+]Stage 1: Debootstrap'
# Debootstrap é a ferramenta que cria um sistema Debian básico
# --foreign prepara o primeiro estágio do debootstrap sem executar scripts
# Verifica se o debootstrap já foi executado anteriormente
[ -e ${ROOTFS}/etc ] && echo -e "[*]Debootstrap already done.\nSkipping Debootstrap..." || debootstrap --foreign --arch $arch kali-rolling ${ROOTFS} ${MIRROR}

echo '[+]Stage 2: Debootstrap second stage and adding Mobian apt repo'
# Executa o segundo estágio do debootstrap se ainda não foi feito
[ -e ${ROOTFS}/etc/passwd ] && echo '[*]Second Stage already done' || nspawn-exec /debootstrap/debootstrap --second-stage
# Cria diretórios necessários para configuração do APT
mkdir -p ${ROOTFS}/etc/apt/sources.list.d ${ROOTFS}/etc/apt/trusted.gpg.d
# Adiciona componentes non-free ao sources.list do Kali
sed -i 's/main/main contrib non-free non-free-firmware/g' ${ROOTFS}/etc/apt/sources.list
# Adiciona o repositório Mobian (contém pacotes específicos para dispositivos móveis)
echo "deb http://repo.mobian.org/ ${mobian_suite} main non-free-firmware" > ${ROOTFS}/etc/apt/sources.list.d/mobian.list
# Baixa e configura a chave GPG do repositório Mobian
curl -L http://repo.mobian.org/mobian.gpg -o ${ROOTFS}/etc/apt/trusted.gpg.d/mobian.gpg
chmod 644 ${ROOTFS}/etc/apt/trusted.gpg.d/mobian.gpg

# Configura a prioridade do repositório Mobian
# Isso garante que os pacotes do Mobian tenham prioridade sobre os do Kali quando existirem em ambos
cat << EOF > ${ROOTFS}/etc/apt/preferences.d/00-mobian-priority
Package: *
Pin: release o=Mobian
Pin-Priority: 700
EOF

# Gera UUIDs únicos para as partições root e boot
ROOT_UUID=`python3 -c 'from uuid import uuid4; print(uuid4())'`
BOOT_UUID=`python3 -c 'from uuid import uuid4; print(uuid4())'`

# Para dispositivos sunxi e rockchip, configura uma partição de boot separada
if [[ "$family" == "sunxi" || "$family" == "rockchip" ]]
then
    BOOTPART="UUID=${BOOT_UUID}	/boot	ext4	defaults,x-systemd.growfs	0	2"
fi

# Salva os UUIDs em um arquivo para uso posterior
cat << EOF > partuuid
ROOT_UUID=${ROOT_UUID}
BOOT_UUID=${BOOT_UUID}
EOF

# Cria o arquivo fstab para configurar as partições no sistema
cat << EOF > ${ROOTFS}/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${ROOT_UUID}	/	ext4	defaults,x-systemd.growfs	0	1
${BOOTPART}
EOF

echo '[+]Stage 3: Installing device specific and environment packages'
# Atualiza os repositórios de pacotes
nspawn-exec apt update
# Instala os pacotes básicos e específicos do ambiente
nspawn-exec apt install -y ${PACKAGES}

# Adiciona o repositório FossFrog (contém pacotes adicionais)
nspawn-exec sh -c "$(curl -fsSL https://repo.fossfrog.in/setup.sh)"

# Atualiza novamente os repositórios e instala pacotes de suporte específicos para a família do dispositivo
nspawn-exec apt update
nspawn-exec apt install -y ${DPACKAGES}

echo '[+]Stage 4: Adding some extra tweaks'
# Verifica se as configurações já foram aplicadas anteriormente
if [ ! -e "${ROOTFS}/etc/repart.d/50-root.conf" ]
then
    # Desativa o aviso de instalação mínima do Kali
    mkdir -p ${ROOTFS}/etc/kali-motd
    touch ${ROOTFS}/etc/kali-motd/disable-minimal-warning
    # Configura o teclado virtual Squeekboard para dispositivos móveis
    mkdir -p ${ROOTFS}/etc/skel/.local/share/squeekboard/keyboards/terminal
    curl https://raw.githubusercontent.com/Shubhamvis98/PinePhone_Tweaks/main/layouts/us.yaml > ${ROOTFS}/etc/skel/.local/share/squeekboard/keyboards/us.yaml
    ln -srf ${ROOTFS}/etc/skel/.local/share/squeekboard/keyboards/{us.yaml,terminal/}
    # Ajusta o tema Plymouth (tela de inicialização)
    sed -i 's/-0.07/0/;s/-0.13/0/' ${ROOTFS}/usr/share/plymouth/themes/kali/kali.script
    # Configura systemd-repart para redimensionar a partição root
    mkdir -p ${ROOTFS}/etc/repart.d
    cat << 'EOF' > ${ROOTFS}/etc/repart.d/50-root.conf
[Partition]
Type=root
Weight=1000
EOF
else
    echo '[*]This has been already done'
fi

echo '[+]Stage 5: Adding user and changing default shell to zsh'
# Verifica se o usuário já existe
if [ ! `grep ${username} ${ROOTFS}/etc/passwd` ]
then
    # Cria um novo usuário sem senha
    nspawn-exec adduser --disabled-password --gecos "" ${username}
    # Define a senha para o usuário
    sed -i "s#${username}:\!:#${username}:`echo ${password} | openssl passwd -1 -stdin`:#" ${ROOTFS}/etc/shadow
    # Muda o shell padrão para zsh
    sed -i 's/bash/zsh/' ${ROOTFS}/etc/passwd
    # Adiciona o usuário a vários grupos importantes para funcionalidade em dispositivos móveis
    for i in dialout sudo audio video plugdev input render bluetooth feedbackd netdev; do
        nspawn-exec usermod -aG ${i} ${username} || true
    done
else
    echo '[*]User already present'
fi

echo '[*]Enabling kali plymouth theme'
# Configura o tema Plymouth do Kali
nspawn-exec plymouth-set-default-theme -R kali
# Configura o papel de parede do desktop
#sed -i "/picture-uri/cpicture-uri='file:\/\/\/usr\/share\/backgrounds\/kali\/kali-red-sticker-16x9.jpg'" ${ROOTFS}/usr/share/glib-2.0/schemas/11_mobile.gschema.override
sed -i "/picture-uri/cpicture-uri='file:\/\/\/usr\/share\/backgrounds\/kali\/kali-metal-dark-16x9.jpg'" ${ROOTFS}/usr/share/glib-2.0/schemas/10_desktop-base.gschema.override
# Compila os esquemas GLib para aplicar as alterações
nspawn-exec glib-compile-schemas /usr/share/glib-2.0/schemas

echo '[+]Stage 6: Enable services'
# Habilita todos os serviços necessários para o dispositivo
for svc in `echo ${SERVICES} | tr ' ' '\n'`
do
	nspawn-exec systemctl enable $svc
done

echo '[*]Checking for custom script'
# Executa um script personalizado se fornecido
if [ -f "${custom_script}" ]
then
    # Cria um diretório temporário para o script
    mkdir -p ${ROOTFS}/ztmpz
    # Copia o script para o sistema de arquivos
    cp ${custom_script} ${ROOTFS}/ztmpz
    # Executa o script
    nspawn-exec bash /ztmpz/${custom_script}
    # Remove o diretório temporário
    [ -d "${ROOTFS}/ztmpz" ] && rm -rf ${ROOTFS}/ztmpz
fi

echo '[*]Tweaks and cleanup'
# Define o nome do host
echo ${hostname} > ${ROOTFS}/etc/hostname
# Adiciona o nome do host ao arquivo /etc/hosts se ainda não estiver presente
grep -q ${hostname} ${ROOTFS}/etc/hosts || \
	sed -i "1s/$/\n127.0.1.1\t${hostname}/" ${ROOTFS}/etc/hosts
# Limpa o cache de pacotes APT para reduzir o tamanho da imagem
nspawn-exec apt clean

# Configurações específicas para dispositivos que usam imagens esparsas (Android)
if [ ${SPARSE} ]
then
    # Desativa e mascara pipewire (servidor de áudio moderno) em favor do PulseAudio
    nspawn-exec sudo -u ${username} systemctl --user disable pipewire pipewire-pulse
    nspawn-exec sudo -u ${username} systemctl --user mask pipewire pipewire-pulse
    nspawn-exec sudo -u ${username} systemctl --user enable pulseaudio
    # Copia os scripts e configurações do bootloader
    cp -r bin/bootloader.sh bin/configs ${ROOTFS}
    chmod +x ${ROOTFS}/bootloader.sh
    # Executa o script do bootloader para criar imagens de boot específicas para o dispositivo
    nspawn-exec /bootloader.sh ${family}
    # Move as imagens de boot geradas para o diretório atual
    mv -v ${ROOTFS}/boot*img .
    # Remove os scripts do bootloader
    rm -rf ${ROOTFS}/bootloader.sh ${ROOTFS}/configs
fi

echo '[*]Deploy rootfs into EXT4 image'
# Compacta o sistema de arquivos em um arquivo tar
tar -cpzf ${ROOTFS_TAR} ${ROOTFS} && rm -rf ${ROOTFS}
# Cria a imagem do disco com o tamanho especificado
mkimg ${IMG} ${IMGSIZE} ${PARTITIONS}
# Extrai o sistema de arquivos para a imagem
tar -xpf ${ROOTFS_TAR}

# Configuração específica para dispositivos sunxi e rockchip
if [[ "$family" == "sunxi" || "$family" == "rockchip" ]]
then
    echo '[*]Update u-boot config...'
    # Atualiza a configuração do U-Boot para a versão mais recente do kernel
    nspawn-exec -r '/etc/kernel/postinst.d/zz-u-boot-menu $(linux-version list | tail -1)'
fi

echo '[*]Cleanup and unmount'
# Limpa e desmonta o sistema de arquivos (função definida em funcs.sh)
cleanup

echo "[+]Stage 7: Compressing ${IMG}..."
# Cria um mapa de blocos se solicitado
if [ "$blockmap" ]
then
    bmaptool create ${IMG} > ${IMG}.bmap
else
    echo '[*]Skipped blockmap creation'
fi

# Converte para imagem esparsa se necessário (formato Android)
if [ "$SPARSE" ]
then
    img2simg ${IMG} ${IMG}_SPARSE
    mv -v ${IMG}_SPARSE ${IMG}
fi

# Comprime a imagem final se solicitado
if [ "$compress" ]
then
    [ -f "${IMG}" ] && xz "${IMG}"
else
    echo '[*]Skipped compression'
fi
echo '[+]Image Generated.'
