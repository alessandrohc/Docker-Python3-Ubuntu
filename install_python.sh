#!/usr/bin/env bash

set -e

# This is being run as root and so sudo is not needed

function download_cpython () {
    # 1: the version tag
    printf "\n### Downloading CPython source as Python-%s.tgz\n" "${1}"
    wget "https://www.python.org/ftp/python/${1}/Python-${1}.tgz" &> /dev/null

    # A extração usa o tarfile do Python, e NÃO o `tar`, por causa de um bug de
    # emulação: em amd64 sob Rosetta (Docker Desktop no Apple Silicon) o GNU tar
    # 1.35 não cria diretórios aninhados e falha com "Cannot mkdir / Cannot open:
    # Function not implemented" em milhares de arquivos.
    #   https://github.com/orbstack/orbstack/issues/2588
    # O mesmo tar em arm64 funciona, e o tarfile funciona nas duas. Sem isto, o
    # build multi-arch termina COM SUCESSO e publica uma imagem amd64 sem o
    # interpretador compilado — foi exatamente o que aconteceu na v8.
    # Não é bug do Docker por builder: a opção Rosetta é global do Docker Desktop,
    # e o builder `qemu` falha igual.
    if command -v python3 > /dev/null; then
        printf "### Extraindo com tarfile (contorna o bug do tar sob Rosetta)\n"
        python3 - "Python-${1}.tgz" <<'EXTRACT'
import sys, tarfile
with tarfile.open(sys.argv[1]) as arquivo:
    try:
        arquivo.extractall(".", filter="data")   # filter existe a partir do 3.12
    except TypeError:
        arquivo.extractall(".")
EXTRACT
    else
        printf "### python3 ausente; extraindo com tar (quebra em amd64 sob Rosetta)\n"
        tar -xzf "Python-${1}.tgz"
    fi
    rm "Python-${1}.tgz"
}

function set_num_processors {
    # Set the number of processors used for build
    # to be 1 less than are available
    if [[ -f "$(command -v nproc)" ]]; then
        NPROC="$(nproc)"
    else
        NPROC="$(grep -c '^processor' /proc/cpuinfo)"
    fi
    echo "$((NPROC - 1))"
}

function build_cpython () {
    # 1: the prefix to be passed to configure
    #    c.f. https://docs.python.org/3/using/unix.html#python-related-paths-and-files
    # 2: the Python version being built

    # https://docs.python.org/3/using/unix.html#building-python
    # https://github.com/python/cpython/blob/3.8/README.rst
    # https://github.com/python/cpython/blob/3.7/README.rst
    # https://github.com/python/cpython/blob/3.6/README.rst
    printf "\n### ./configure --help\n"
    ./configure --help
    printf "\n### ./configure\n"
    ./configure --prefix="${1}" \
        --exec_prefix="${1}" \
        --with-ensurepip \
        --enable-optimizations \
        --with-lto \
        --enable-loadable-sqlite-extensions \
        --enable-ipv6 \
        --enable-shared
    
    printf "\n### make -j%s\n" "${NPROC}"
    make -j"${NPROC}"
    printf "\n### make install\n"
    make install
}

function update_pip {
    # Update pip, setuptools, and wheel
    if [[ "$(id -u)" -eq 0 ]]; then
        # If root
        printf "\n### pip3 install --upgrade --no-cache-dir pip setuptools wheel virtualenv\n"
        pip3 install --upgrade --no-cache-dir pip setuptools wheel virtualenv
    else
        printf "\n### pip3 install --user --upgrade --no-cache-dir pip setuptools wheel virtualenv\n"
        pip3 install --user --upgrade --no-cache-dir pip setuptools wheel virtualenv
    fi
}

function symlink_python_to_python3 {
    local python_version
    python_version="$(python3 --version)"
    local which_python
    which_python="$(command -v python3)${python_version:8:-2}"
    local which_pip
    which_pip="$(command -v pip3)"

    # symlink python to python3
    printf "\n### ln -s -f %s %s\n" "${which_python}" "${which_python::-3}"
    ln -s -f "${which_python}" "${which_python::-3}"

    # symlink pip to pip3 if no pip exists or it is a different version than pip3
    if [[ -n "$(command -v pip)" ]]; then
        if [[ "$(pip --version)" = "$(pip3 --version)" ]]; then
            return 0
        fi
    fi
    printf "\n### ln -s -f %s %s\n" "${which_pip}" "${which_pip::-1}"
    ln -s -f "${which_pip}" "${which_pip::-1}"
    return 0
}

function main() {
    # 1: the Python version tag
    # 2: bool of if should symlink python and pip to python3 versions

    # Fallback só para invocação manual sem argumento. A fonte da verdade é o ARG
    # PYTHON_VERSION_TAG do Dockerfile, que sempre passa a versão — este valor
    # tinha ficado em 3.10.13 e envelheceu em silêncio por isso.
    PYTHON_VERSION_TAG=3.10.21
    LINK_PYTHON_TO_PYTHON3=0 # By default don't link so as to reserve python for Python 2
    if [[ $# -gt 0 ]]; then
        PYTHON_VERSION_TAG="${1}"

        if [[ $# -gt 1 ]]; then
            LINK_PYTHON_TO_PYTHON3="${2}"
        fi
    fi

    NPROC="$(set_num_processors)"
    download_cpython "${PYTHON_VERSION_TAG}"
    cd Python-"${PYTHON_VERSION_TAG}"
    build_cpython /usr "${PYTHON_VERSION_TAG}"
    update_pip

    if [[ "${LINK_PYTHON_TO_PYTHON3}" -eq 1 ]]; then
        symlink_python_to_python3
    fi

    verify_install "${PYTHON_VERSION_TAG}"
}

# Prova de que o interpretador pedido existe de verdade, em vez de confiar no
# encadeamento de comandos. Existe porque este script JÁ reportou sucesso com
# tudo falhando: o `tar` morreu sob emulação, o ./configure não existia, o make
# não tinha alvo, o pip3 não existia -- e o build seguiu, publicando uma imagem
# com o Python do sistema no lugar do compilado.
#
# Duas causas se somaram, e as duas estão corrigidas aqui:
#   1. `main "$@" || exit 1` DESLIGA o `set -e` dentro do main: num comando à
#      esquerda de `||`, o bash suprime o errexit, então nenhuma falha abortava.
#   2. Com LINK_PYTHON_TO_PYTHON3=0 (o default), a última instrução do main era
#      um `if` que não entra -- e um `if` com condição falsa retorna 0. O main
#      devolvia sucesso mesmo depois de tudo quebrar.
function verify_install () {
    local expected="${1}"
    local binary="/usr/bin/python${expected%.*}"

    if [[ ! -x "${binary}" ]]; then
        printf "\n### ERRO: %s nao existe -- a compilacao nao produziu o interpretador\n" "${binary}" >&2
        return 1
    fi

    local found
    found="$("${binary}" --version 2>&1 | awk '{print $2}')"
    if [[ "${found}" != "${expected}" ]]; then
        printf "\n### ERRO: esperado Python %s, encontrado %s em %s\n" \
            "${expected}" "${found}" "${binary}" >&2
        return 1
    fi

    printf "\n### OK: Python %s instalado em %s\n" "${found}" "${binary}"
}

# Sem `|| exit 1`: ele é justamente o que suprimia o errexit dentro do main.
main "$@"
