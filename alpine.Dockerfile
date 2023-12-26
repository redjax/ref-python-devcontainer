FROM alpine:latest AS base

## Install Python and pipx
RUN apk add --no-cache g++ make python3 py3-pip git bash
RUN python3 -m pip install --no-cache-dir pipx --break-system-packages

RUN python3 -m pipx ensurepath

## Install pdm
ARG PDM_VERSION=2.11.1
RUN pipx install pdm==${PDM_VERSION}

FROM base AS build

## Install Python VSCode extensions
RUN apk add --no-cache git \
    && apk add --no-cache --virtual .build-deps gcc musl-dev libffi-dev openssl-dev
RUN pipx install black \
    && pipx install ruff

FROM base AS run

WORKDIR /app

SHELL ["/bin/bash", "-c"]
