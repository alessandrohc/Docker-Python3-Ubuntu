FROM ubuntu:26.04

LABEL maintainer="Alessandro Hecht <alessandro@fabricadigital.com.br>"

ARG PYTHON_VERSION_TAG=3.10.20
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
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
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
