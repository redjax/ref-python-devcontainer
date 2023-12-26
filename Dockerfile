##############################################################################################
# | Python VSCode Dockerfile |                                                               #
#  --------------------------                                                                #
# Description:                                                                               #
#     This Dockerfile should be usable on its own, but it doesn't do much except setup       #
#     an environment for a VSCode devcontainer. Some extra features & settings in the        # 
#     .devcontainer/devcontainer.json file do some "magic," like installing docker-in-docker #
#     so this devcontainer can run docker containers within itself.                          #
##############################################################################################
FROM python:3.11-slim AS base

## Set DEBIAN_FRONTEND when using this container as a VSCode devcontainer.
#  From Microsoft's docs:
#    "The DEBIAN_FRONTEND export avoids warnings when you go on to work with your container"
ENV DEBIAN_FRONTEND=noninteractive

## Define args in the first build layer. Future layers can reference & use these args like:
#    ARG CONTAINER_USER  (note: no need to re-define the value)
ARG CONTAINER_USER=worker
ARG USER_UID=1000
ARG USER_GID=1000

## Set Python environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ## Pip
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100

## Define container user's username. After system setup is complete, all layers for Python
#  setup & container execution will have "USER ${USERNAME}" declared.
ENV CONTAINER_USER=worker
ENV CONTAINER_HOME=/home/${CONTAINER_USER}

## Add CONTAINER_USER's bin to PATH
ENV PATH="${PATH}:${CONTAINER_HOME}/.local/bin"

## Enable package manager caching. If you run into issues with build layers,
#  disable these env vars by commenting them out
ENV PDM_HTTP_CACHE=${CONTAINER_HOME}/.cache/pdm \
    PIP_CACHE_DIR=${CONTAINER_HOME}/.cache/pip \
    PYPI_CACHE_DIR=${CONTAINER_HOME}/.cache/pypi

## Create container user
RUN groupadd -g $USER_GID ${CONTAINER_USER} \
    && useradd -m -d /home/${CONTAINER_USER} -s /bin/bash ${CONTAINER_USER} -u ${USER_UID} -g $USER_GID

## Add container user to docker group, for docker-in-docker inside VSCode devcontainer
RUN groupadd docker \
    && usermod -aG docker ${CONTAINER_USER} \
    ## Activate new group
    && newgrp docker

FROM base AS build

## Import args from base layer
ARG CONTAINER_USER
ARG USER_UID
ARG USER_GID

RUN apt-get update -y
## Install system packages
RUN apt-get install --no-install-recommends -y \
    git \
    openssh-server \
    ## For docker-in-docker
    uidmap

## Uncomment next 3 RUN commands to add sudo support for the container user
RUN apt-get install --no-install-recommends -y sudo \
    && echo "$CONTAINER_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${CONTAINER_USER}
RUN chmod 0440 /etc/sudoers.d/${CONTAINER_USER}
RUN echo "${CONTAINER_USER}:x:${USER_UID}:$USER_GID:${CONTAINER_USER}:/home/${CONTAINER_USER}:/bin/bash" >> /etc/passwd

FROM build AS pyenv-base

RUN mkdir -pv ${CONTAINER_HOME}/.pyenv \
    && chown -R ${CONTAINER_USER}:${CONTAINER_USER} ${CONTAINER_HOME}/.pyenv

ENV PYENV_ROOT=/pyenv

## Import args from base layer
ARG CONTAINER_USER
ARG USER_UID
ARG USER_GID

## Install Pyenv
#  https://bnikolic.co.uk/blog/python/2023/03/23/pyenvdocker.html

RUN apt-get install --no-install-recommends -y \
    make \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    curl \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libffi-dev \
    liblzma-dev \
    git

USER ${CONTAINER_USER}

WORKDIR ${CONTAINER_HOME}
RUN git clone https://github.com/pyenv/pyenv.git .pyenv

## Add Pyenv to PATH
ENV PYENV_ROOT="${CONTAINER_HOME}/.pyenv"
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"

## -- END ROOT USER SESSION --

## Install/build Python dependencies
FROM pyenv-base AS python-build

ARG CONTAINER_USER
ARG USER_UID
ARG USER_GID

## Set this layer to run as the container user
USER ${CONTAINER_USER}

## Install Python versions with Pyenv
RUN pyenv install 3.11.4 \
    && pyenv install 3.12.0

## Set global pyenv version
RUN pyenv global 3.11.4 3.12.0

## Install pipx
#  Use a mounted .cache/pip dir so subsequent builds are faster.
#  To build without the cache, rebuild the Docker container itself with --no-cache
RUN python -m pip install --user pipx \
    && python -m pipx ensurepath

## Install dev dependencies
RUN python3 -m pipx install black \
    && python -m pipx install ruff \
    && python -m pipx install pdm \
    && python -m pipx install tox \
    && python -m pipx install nox

## Build layer for VSCode
FROM python-build AS devcontainer

ARG CONTAINER_USER
ARG USER_UID
ARG USER_GID

## Unset Python package manager caches for running in VSCode devcontainer
ENV PDM_HTTP_CACHE= \
    PIP_CACHE_DIR= \
    PYPI_CACHE_DIR=

## Set this layer to run as the container user
USER ${CONTAINER_USER}
