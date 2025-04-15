# Kali Phosh para PinePhone e Dispositivos Qualcomm

```
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
```

## Visão Geral do Projeto

Este projeto permite gerar imagens do Kali Linux com interface Phosh (ou outras interfaces) para dispositivos móveis, incluindo PinePhone, PinePhone Pro e vários smartphones baseados em chipsets Qualcomm. O objetivo é criar um sistema Linux completo e funcional que possa ser instalado em dispositivos móveis, proporcionando um ambiente de segurança e penetração de redes portátil.

O sistema é baseado no Kali Linux, uma distribuição especializada em testes de segurança, combinado com componentes do projeto Mobian para suporte a hardware móvel. A interface padrão é o Phosh (Phone Shell), uma interface móvel baseada em GNOME, mas também há suporte para outras interfaces como Plasma Mobile e ambientes de desktop tradicionais.

Um agradecimento especial ao Projeto Mobian e aos patches de kernel do Megi.

## Instruções de Build

Para gerar uma imagem, execute o script build.sh com o parâmetro `-t` seguido do tipo de dispositivo:

```bash
# Para PinePhone
./build.sh -t pinephone

# Para PinePhone Pro
./build.sh -t pinephonepro

# Para dispositivos Qualcomm SDM845 (Poco F1, OnePlus 6/6T, etc.)
./build.sh -t sdm845
```

### Parâmetros Adicionais

O script aceita vários parâmetros para personalizar a imagem gerada:

- `-e <ambiente>`: Define o ambiente de desktop (phosh, plasma-mobile, xfce, lxde, gnome, kde)
- `-h <hostname>`: Define o nome do host
- `-u <username>`: Define o nome de usuário
- `-p <password>`: Define a senha do usuário
- `-s <script>`: Executa um script personalizado durante o build
- `-m <suite>`: Define a versão do Mobian a ser utilizada
- `-M <mirror>`: Define um espelho de repositório alternativo
- `-c`: Comprime a imagem final com xz
- `-b`: Cria um mapa de blocos para a imagem

## Pacotes Necessários

Para executar o script de build, você precisa ter os seguintes pacotes instalados no seu sistema:

- systemd-container
- rsync
- debootstrap
- qemu-user-static
- bmap-tools
- android-sdk-libsparse-utils

## Download Oficial

Você pode baixar as imagens oficiais do Kali Nethunter para PinePhone e PinePhone Pro na página de download do Kali: https://www.kali.org/get-kali/#kali-mobile

![](https://img.shields.io/github/downloads/Shubhamvis98/kali-pinephone/total?label=Downloads&style=plastic)

## Estrutura do Projeto

- `build.sh`: Script principal que orquestra todo o processo de build
- `funcs.sh`: Funções auxiliares utilizadas pelo script principal
- `bin/bootloader.sh`: Script para criar imagens de boot para dispositivos Qualcomm
- `bin/configs/`: Diretório contendo configurações específicas para diferentes famílias de dispositivos

## Dispositivos Suportados

### Família Allwinner (sunxi)
- PinePhone
- PineTab

### Família Rockchip
- PinePhone Pro
- PineTab 2

### Família Qualcomm (qcom/sdm845)
- Poco F1
- OnePlus 6/6T
- Xiaomi Mi MIX 2S
- SHIFT6mq

### Família Qualcomm SM7325
- Nothing Phone 1

## Processo de Build

O processo de build consiste em várias etapas:

1. Configuração do ambiente e processamento de parâmetros
2. Debootstrap para criar um sistema Debian básico
3. Adição de repositórios Mobian e configuração de APT
4. Instalação de pacotes específicos para o dispositivo e ambiente
5. Configuração do sistema (usuário, serviços, etc.)
6. Criação da imagem de disco e particionamento
7. Configuração do bootloader específico para o dispositivo
8. Compressão e finalização da imagem

O resultado é uma imagem pronta para ser gravada em um cartão SD ou eMMC do dispositivo alvo.
