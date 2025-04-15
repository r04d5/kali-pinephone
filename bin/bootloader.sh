#!/bin/sh
# Este script é responsável por criar imagens de boot para dispositivos baseados em Qualcomm
# Ele utiliza configurações específicas para cada dispositivo, definidas em arquivos TOML
# e gera imagens de boot compatíveis com o bootloader Android

# Obtém o caminho do script e o tipo de dispositivo dos argumentos
SCRIPT="$0"
DEVICE="$1"

# Determina o caminho para o arquivo de configuração específico do dispositivo
CONFIG="$(dirname ${SCRIPT})/configs/${DEVICE}.toml"
# Verifica se o arquivo de configuração existe
if ! [ -f "${CONFIG}" ]; then
    echo "ERROR: No configuration for device type '${DEVICE}'!"
    exit 1
fi

# Função para extrair os offsets da imagem de boot a partir da configuração
# Esta função processa os dados JSON da configuração e formata os argumentos para o mkbootimg
bootimg_offsets() {
    local BOOTIMG="$1"

    # Extrai os valores de configuração do bootimg usando jq
    local VERSION="$(echo "${BOOTIMG}" | jq -r 'if .version then .version else 0 end' -)"
    local KERNEL="$(echo "${BOOTIMG}" | jq -r '.kernel + .base' -)"
    local RAMDISK="$(echo "${BOOTIMG}" | jq -r '.ramdisk + .base' -)"
    local SECOND="$(echo "${BOOTIMG}" | jq -r '.second + .base' -)"
    local TAGS="$(echo "${BOOTIMG}" | jq -r '.tags + .base' -)"
    local PAGE_SIZE="$(echo "${BOOTIMG}" | jq -r '.pagesize' -)"
    local DTB="$(echo "${BOOTIMG}" | jq -r 'if .dtb then .dtb + .base else "" end' -)"

    # Constrói a string de argumentos para o mkbootimg
    local ARGS="--kernel_offset ${KERNEL} --ramdisk_offset ${RAMDISK}"
    ARGS="${ARGS} --second_offset ${SECOND} --tags_offset ${TAGS}"
    ARGS="${ARGS} --pagesize ${PAGE_SIZE}"

    # Adiciona a versão do cabeçalho se não for zero
    if [ "${VERSION}" != "0" ]; then
        ARGS="${ARGS} --header_version ${VERSION}"
    fi

    # Adiciona o offset do DTB se estiver definido
    if [ "${DTB}" ]; then
        ARGS="${ARGS} --dtb_offset ${DTB}"
    fi

    echo "${ARGS}"
}

# Determina a partição root a partir do fstab
# Isso é necessário para configurar corretamente os parâmetros de boot
ROOTPART=$(grep -P '^UUID.*[ \t]/[ \t]' /etc/fstab | awk '{print $1}')

# Verifica se estamos usando uma partição root criptografada
if [ "${ROOTPART}" = "UUID=" ]; then
    # Se a UUID estiver vazia, estamos usando criptografia
    ROOTPART="/dev/mapper/root"
fi
# Obtém a versão mais recente do kernel instalado
KERNEL_VERSION=$(linux-version list | tail -1)

# Extrai parâmetros genéricos para o SoC atual da configuração
SOC=$(tomlq -r "if .chipset then .chipset else \"${DEVICE}\" end" ${CONFIG})
MKBOOTIMG_ARGS="$(bootimg_offsets "$(tomlq -r '.bootimg' ${CONFIG})")"

# Itera sobre todos os dispositivos definidos na configuração
for i in $(seq 0 $(tomlq -r '.device | length - 1' ${CONFIG})); do
    # Extrai parâmetros específicos do dispositivo
    VENDOR=$(tomlq -r ".device[$i].vendor" ${CONFIG})
    MODEL=$(tomlq -r ".device[$i].model" ${CONFIG})
    VARIANT=$(tomlq -r "if .device[$i].variant then .device[$i].variant else \"\" end" ${CONFIG})
    DEVICE_SOC=$(tomlq -r "if .device[$i].chipset then .device[$i].chipset else \"${SOC}\" end" ${CONFIG})
    APPEND=$(tomlq -r "if .device[$i].append then .device[$i].append else \"\" end" ${CONFIG})
    # Extrai parâmetros específicos do bootimg em formato JSON para processamento pela função bootimg_offsets
    DEVICE_BOOTIMG=$(tomlq -r "if .device[$i].bootimg then .device[$i].bootimg else \"\" end" ${CONFIG})

    # Constrói a linha de comando base com informações do dispositivo
    CMDLINE="mobile.qcomsoc=qcom/${DEVICE_SOC} mobile.vendor=${VENDOR} mobile.model=${MODEL}"
    if [ "${VARIANT}" ]; then
        # Adiciona a variante se estiver definida
        CMDLINE="${CMDLINE} mobile.variant=${VARIANT}"
        FULLMODEL="${MODEL}-${VARIANT}"
    else
        FULLMODEL="${MODEL}"
    fi
    # Define o caminho para o arquivo DTB específico do dispositivo
    DTB_FILE="/usr/lib/linux-image-${KERNEL_VERSION}/qcom/${DEVICE_SOC}-${VENDOR}-${FULLMODEL}.dtb"

    # Define o nível de log padrão como "quiet" (silencioso)
    LOGLEVEL="quiet"
    # Inclui argumentos adicionais da linha de comando se especificados
    if [ "${APPEND}" ]; then
        CMDLINE="${CMDLINE} ${APPEND}"
        # Se houver uma console definida, usa um nível de log mais detalhado
        if echo "${APPEND}" | grep -q "console="; then
            LOGLEVEL="loglevel=7"
        fi
    fi

    # Usa os parâmetros de bootimg específicos do dispositivo se disponíveis, caso contrário usa os genéricos
    if [ "${DEVICE_BOOTIMG}" ]; then
        BOOTIMG_ARGS="$(bootimg_offsets "${DEVICE_BOOTIMG}")"
    else
        BOOTIMG_ARGS="${MKBOOTIMG_ARGS}"
    fi

    # Adiciona o DTB aos argumentos se o offset do DTB estiver definido
    if echo "${BOOTIMG_ARGS}" | grep -q "dtb_offset"; then
        BOOTIMG_ARGS="${BOOTIMG_ARGS} --dtb ${DTB_FILE}"
    fi

    echo "Creating boot image for ${FULLMODEL}..."
    # Concatena o kernel e o DTB em um único arquivo
    cat /boot/vmlinuz-${KERNEL_VERSION} ${DTB_FILE} > /tmp/kernel-dtb

    # Cria a imagem de boot no formato reconhecido pelo bootloader Android
    mkbootimg -o /boot_${FULLMODEL}_`date +%Y%m%d`.img ${BOOTIMG_ARGS} \
        --kernel /tmp/kernel-dtb --ramdisk /boot/initrd.img-${KERNEL_VERSION} \
        --cmdline "mobile.root=${ROOTPART} ${CMDLINE} init=/sbin/init ro ${LOGLEVEL} splash"
done
