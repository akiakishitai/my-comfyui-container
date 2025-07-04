# syntax=docker/dockerfile:1.7

ARG S6_OVERLAY_VERSION=3.2.1.0
ARG S6_ROOTFS=/s6-root
ARG PYTHON_VERSION=3.12
ARG UV_COMPILE_BYTECODE=1
ARG UV_CACHE_DIR=/root/.cache/uv
ARG UV_PROJECT=/app
ARG UV_PROJECT_ENVIRONMENT=${UV_PROJECT}/venv
ARG VIRTUAL_ENV=${UV_PROJECT_ENVIRONMENT}
ARG TZ="Asia/Tokyo"

# ------------------------------
# ref: https://hub.docker.com/_/busybox/
# ref: https://github.com/just-containers/s6-overlay
FROM docker.io/library/busybox:1.37 AS s6
ARG S6_OVERLAY_VERSION
ARG S6_ROOTFS
ARG TARGETARCH
ARG DOWNLOAD_DIR=/tmp/s6
ARG DOWNLOAD_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"

WORKDIR ${S6_ROOTFS}
RUN --mount=type=tmpfs,dst=/tmp/s6,tmpfs-size=64M \
  <<EOS sh
  wget -P ${DOWNLOAD_DIR} \
    ${DOWNLOAD_URL}/s6-overlay-noarch.tar.xz \
    ${DOWNLOAD_URL}/s6-overlay-${TARGETARCH}.tar.xz
  tar -C ./ -xJf ${DOWNLOAD_DIR}/s6-overlay-noarch.tar.xz
  tar -C ./ -xJf ${DOWNLOAD_DIR}/s6-overlay-${TARGETARCH}.tar.xz
EOS

# ------------------------------
# ref: https://hub.docker.com/r/nvidia/cuda
FROM docker.io/nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04 AS base
ARG PYTHON_VERSION
ARG UV_CACHE_DIR
ARG UV_COMPILE_BYTECODE
ARG UV_PROJECT
ARG UV_PROJECT_ENVIRONMENT
ARG VIRTUAL_ENV
ARG TZ

ENV LANG=C.UTF-8 TZ=${TZ}
# Pythonソースをバイトコードに事前コンパイルすることで実行速度を高速化する
ENV UV_COMPILE_BYTECODE=${UV_COMPILE_BYTECODE} \
  UV_CACHE_DIR=${UV_CACHE_DIR} \
  UV_PROJECT_ENVIRONMENT=${UV_PROJECT_ENVIRONMENT} \
  UV_PROJECT=${UV_PROJECT} \
  VIRTUAL_ENV=${VIRTUAL_ENV}
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}

# Install packages
RUN --mount=type=cache,dst=/var/cache/apt,sharing=locked,id=apt-cache \
  --mount=type=cache,dst=/var/lib/apt/lists,sharing=locked,id=apt-list \
  --mount=type=bind,src=data/apt.conf.d/keep-cache.conf,dst=/etc/apt/apt.conf.d/keep-cache \
  <<EOS bash
  rm -f /etc/apt/apt.conf.d/docker-clean
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    python${PYTHON_VERSION} \
    python3-pip \
    libffi-dev \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    libsm6 \
    libxext6 \
    libxrender1

  # Pillow
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    libavif-dev \
    libjpeg8-dev \
    libpng-dev \
    liblcms2-dev \
    zlib1g-dev
EOS

# Install rclone; a command-line program to manage files on cloud storage
# doc: https://rclone.org/install/
COPY --from=docker.io/rclone/rclone:v1.70-stable /usr/local/bin/rclone /bin/

# Install uv; python package manager
# doc: https://docs.astral.sh/uv/
COPY --from=ghcr.io/astral-sh/uv:0.7.13 /uv /uvx /bin/
# Create python virtual environment
WORKDIR ${UV_PROJECT}
RUN uv venv --python ${PYTHON_VERSION} ${UV_PROJECT_ENVIRONMENT}
