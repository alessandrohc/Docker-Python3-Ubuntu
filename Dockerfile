# Base fixada por DIGEST (#6656). `ubuntu:26.04` é tag móvel: sem o digest, dois
# builds em datas diferentes produzem interpretadores compilados contra libs
# diferentes, sem que uma linha mude. Atualizar é manual. Para subir:
#   docker pull ubuntu:26.04 \
#     && docker image inspect ubuntu:26.04 --format '{{index .RepoDigests 0}}'
FROM ubuntu:26.04@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d

LABEL maintainer="Alessandro Hecht <alessandro@fabricadigital.com.br>"

# Última da série 3.10 (publicada em 12/08/2026). A série é requisito do produto;
# só o patch sobe.
ARG PYTHON_VERSION_TAG=3.10.21
ARG LINK_PYTHON_TO_PYTHON3=0
ARG TARGETPLATFORM

USER root
WORKDIR /root

SHELL [ "/bin/bash", "-c" ]

# Instalação de pacotes essenciais e dependências, remoção de pacotes desnecessários e arquivos de cache
RUN set -ex \
    && apt-get -qq -y update \
    && DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
        build-essential \
        gdb \
        lcov \
        yasm \
        pkg-config \
        libbz2-dev \
        libffi-dev \
        libgdbm-dev \
        libgdbm-compat-dev \
        liblzma-dev \
        libncurses5-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        lzma \
        tk-dev \
        uuid-dev \
        zlib1g-dev \
        unzip \
        libcairo2-dev \
        wget \
        curl \
        git \
        sudo \
        bash-completion \
        tree \
        vim \
        gdal-bin \
        default-libmysqlclient-dev \
        mysql-client \
        libmagic1 \
        # /etc/mime.types (#7463). Entrava por transitividade e o produto passou a
        # depender dele: o elFinder deriva as extensões aceitas de
        # mimetypes.guess_all_extensions(), que lê este arquivo. Sem o pacote, 43
        # extensões somem (.docx, .xlsx, .webp, .odt...) e a falha é MUDA — o
        # usuário só não consegue renomear, sem erro nenhum no log.
        media-types \
        libmediainfo-dev \
        jpegoptim \
        optipng \
        gettext \
        software-properties-common \
        ffmpeg \
    # Workaround: alguns pacotes (ex.: gdal) invocam lsb_release e quebram em ambientes minimos
    && mv /usr/bin/lsb_release /usr/bin/lsb_release.bak \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Chromium para Selenium via PPA xtradeb/apps (chromium real como .deb, sem snap).
# O download_webdriver.py usa ChromeType.CHROMIUM, entao o navegador precisa ser o Chromium real.
# Pinning garante que chromium* venha do PPA mesmo se o nome existir em outros repositorios.
RUN set -ex \
    && add-apt-repository -y ppa:xtradeb/apps \
    && printf "Package: chromium*\nPin: release o=LP-PPA-xtradeb-apps\nPin-Priority: 700\n" \
        > /etc/apt/preferences.d/xtradeb-chromium \
    && apt-get -qq -y update \
    && DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
        chromium \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# linux/arm64 - Adiciona arquitetura amd64, configura fontes e instala pacotes
#
# O `sed` é obrigatório e não é cosmético: a base arm64 traz ubuntu.sources
# apontando para ports.ubuntu.com SEM declarar `Architectures`. Depois do
# `dpkg --add-architecture amd64`, o apt passa a pedir índices amd64 para TODAS
# as fontes, inclusive a de ports — que só serve arquiteturas não-x86 e devolve
# 404, derrubando o build inteiro com exit 100. Declarar `arm64` naquela fonte
# faz cada arquitetura ser buscada onde ela existe.
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
      sed -i 's|^URIs: http://ports.ubuntu.com/ubuntu-ports/|&\nArchitectures: arm64|' \
          /etc/apt/sources.list.d/ubuntu.sources && \
      dpkg --add-architecture amd64 && \
      printf "Types: deb\n\
URIs: http://archive.ubuntu.com/ubuntu/\n\
Suites: resolute resolute-updates resolute-backports\n\
Components: main universe restricted multiverse\n\
Architectures: amd64\n\
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\n\
## Ubuntu security updates. Aside from URIs and Suites,\n\
## this should mirror your choices in the previous section.\n\
Types: deb\n\
URIs: http://archive.ubuntu.com/ubuntu/\n\
Suites: resolute-security\n\
Components: main universe restricted multiverse\n\
Architectures: amd64\n\
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n" \
      > /etc/apt/sources.list.d/ubuntu_amd64.sources && \
      apt-get -qq -y update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            libc6:amd64 \
            libstdc++6:amd64 \
            zlib1g:amd64 \
            libglib2.0-0:amd64 \
            libnss3:amd64 \
            libx11-6:amd64 && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Instalação do Python usando script customizado.
# ldconfig e necessario porque o CPython e compilado com --enable-shared (libpython3.x.so em /usr/lib).
COPY install_python.sh install_python.sh
RUN bash install_python.sh ${PYTHON_VERSION_TAG} ${LINK_PYTHON_TO_PYTHON3} \
    && ldconfig \
    && rm -rf install_python.sh Python-${PYTHON_VERSION_TAG}

# Habilita o bash completion e cria o usuario "docker" com permissoes sudo
RUN export SED_RANGE="$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+1)),$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+7))" \
    && sed -i -e "${SED_RANGE}"' s/^#//' /etc/bash.bashrc \
    && unset SED_RANGE \
    && useradd -m docker \
    && usermod -aG sudo docker \
    && echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
    && cp /root/.bashrc /home/docker/ \
    && mkdir /home/docker/data \
    && touch /home/docker/.sudo_as_admin_successful \
    && chown -R docker:docker /home/docker

# Configuracoes finais: locale, ambiente e usuario "docker"
ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    HOME=/home/docker \
    USER=docker \
    PATH=/home/docker/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /home/docker/data
USER docker

CMD [ "/bin/bash" ]
