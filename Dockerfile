FROM ubuntu:noble

MAINTAINER Alessandro Hecht <alessandro@fabricadigital.com.br>

USER root
WORKDIR /root

SHELL [ "/bin/bash", "-c" ]

ARG PYTHON_VERSION_TAG=3.10.14
ARG LINK_PYTHON_TO_PYTHON3=0

# Existing lsb_release causes issues with modern installations of Python3
# https://github.com/pypa/pip/issues/4924#issuecomment-435825490
# Set (temporarily) DEBIAN_FRONTEND to avoid interacting with tzdata
RUN apt-get -qq -y update --fix-missing && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq -y install \
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
        software-properties-common && \
        mv /usr/bin/lsb_release /usr/bin/lsb_release.bak && \
        apt-get -y autoclean && \
        apt-get -y autoremove && \
        rm -rf /var/lib/apt-get/lists/*

COPY install_python.sh install_python.sh
RUN bash install_python.sh ${PYTHON_VERSION_TAG} ${LINK_PYTHON_TO_PYTHON3} && \
    rm -r install_python.sh Python-${PYTHON_VERSION_TAG}

# Enable tab completion by uncommenting it from /etc/bash.bashrc
# The relevant lines are those below the phrase "enable bash completion in interactive shells"
RUN export SED_RANGE="$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+1)),$(($(sed -n '\|enable bash completion in interactive shells|=' /etc/bash.bashrc)+7))" && \
    sed -i -e "${SED_RANGE}"' s/^#//' /etc/bash.bashrc && \
    unset SED_RANGE

# Create user "docker" with sudo powers
RUN useradd -m docker && \
    usermod -aG sudo docker && \
    echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && \
    cp /root/.bashrc /home/docker/ && \
    mkdir /home/docker/data && \
    chown -R --from=root docker /home/docker

# Use C.UTF-8 locale to avoid issues with ASCII encoding
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

WORKDIR /home/docker/data
ENV HOME /home/docker
ENV USER docker
USER docker
ENV PATH /home/docker/.local/bin:$PATH
# Avoid first use of sudo warning. c.f. https://askubuntu.com/a/22614/781671
RUN touch $HOME/.sudo_as_admin_successful

CMD [ "/bin/bash" ]
