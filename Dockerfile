FROM ubuntu:24.04

LABEL maintainer="Alessandro Hecht <alessandro@fabricadigital.com.br>"

USER root
WORKDIR /root

SHELL [ "/bin/bash", "-c" ]

ARG PYTHON_VERSION_TAG=3.10.15
ARG LINK_PYTHON_TO_PYTHON3=0

# Instalação de pacotes essenciais e dependências, remoção de pacotes desnecessários e arquivos de cache
RUN set -ex \
    && apt-get -qq -y update --fix-missing \
    && DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
        build-essential \
        gdb \
        lcov \
        pkg-config \
        libbz2-dev \
        libffi-dev \
        libgdbm-dev \
        libgdbm-compat-dev \
        liblzma-dev \
        libncurses5-dev \
        libreadline6-dev \
        libsqlite3-dev \
        libssl-dev \
        lzma \
        lzma-dev \
        tk-dev \
        uuid-dev \
        zlib1g-dev \
        unzip \
        libcairo2-dev \
        chromium-browser \
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
        qemu-user-static \
        binfmt-support \
    && mv /usr/bin/lsb_release /usr/bin/lsb_release.bak \
    && apt-get -y autoclean \
    && apt-get -y autoremove \
    && rm -rf /var/lib/apt/lists/*

# Configuração do binfmt_misc para suportar execução de binários x86-64
RUN update-binfmts --enable qemu-x86_64

# Instalação do Python usando script customizado
COPY install_python.sh install_python.sh
RUN bash install_python.sh ${PYTHON_VERSION_TAG} ${LINK_PYTHON_TO_PYTHON3} \
    && rm -rf install_python.sh Python-${PYTHON_VERSION_TAG}

# Habilita o bash completion
RUN export SED_RANGE="$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+1)),$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+7))" \
    && sed -i -e "${SED_RANGE}"' s/^#//' /etc/bash.bashrc \
    && unset SED_RANGE

# Cria o usuário "docker" com permissões sudo
RUN useradd -m docker \
    && usermod -aG sudo docker \
    && echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
    && cp /root/.bashrc /home/docker/ \
    && mkdir /home/docker/data \
    && chown -R docker:docker /home/docker

# Configurações de locale
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# Configurações finais e preparação do ambiente do usuário "docker"
WORKDIR /home/docker/data
ENV HOME=/home/docker
ENV USER=docker
USER docker
ENV PATH /home/docker/.local/bin:$PATH

# Evita o aviso de primeiro uso do sudo
RUN touch $HOME/.sudo_as_admin_successful

CMD [ "/bin/bash" ]
