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
ARG COMFYUI_VERSION=0.3.40
ARG COMFYUI_MANAGER_VERSION=3.33
ARG COMFYUI_PATH=${UV_PROJECT}/comfyui
ARG COMFYUI_EXTRA_DIR=/storage/comfyui-extra
ARG CLOUD_DIR=/storage/cloud

# ------------------------------
# ref: https://hub.docker.com/_/busybox/
# ref: https://github.com/just-containers/s6-overlay
FROM docker.io/library/busybox:1.37 AS s6
ARG S6_OVERLAY_VERSION
ARG S6_ROOTFS
ARG TARGETARCH
ARG DOWNLOAD_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"

WORKDIR ${S6_ROOTFS}
# hadolint ignore=SC2034
RUN <<EOS sh
  ARCH="\$(uname -m)"
  case "${TARGETARCH:-__EMPTY__}" in
    "amd64")
      ARCH="x86_64" ;;
    "arm64")
      ARCH="aarch64" ;;
    *)
      echo "WARN: Unsupported architecture: ${TARGETARCH}" ;;
  esac

  DOWNLOAD_DIR="\$(mktemp -d)"
  wget --no-check-certificate -q -T 20 -P "\${DOWNLOAD_DIR}" \
    "${DOWNLOAD_URL}/s6-overlay-noarch.tar.xz" \
    "${DOWNLOAD_URL}/s6-overlay-\${ARCH}.tar.xz"
  tar -C ./ -xJf "\${DOWNLOAD_DIR}/s6-overlay-noarch.tar.xz"
  tar -C ./ -xJf "\${DOWNLOAD_DIR}/s6-overlay-\${ARCH}.tar.xz"

  rm -rf "\${DOWNLOAD_DIR}"
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

# ------------------------------
FROM base AS comfyui
ARG COMFYUI_PATH
ARG COMFYUI_VERSION
ARG COMFYUI_MANAGER_VERSION
ARG CLOUD_DIR

ENV COMFYUI_PATH=${COMFYUI_PATH} \
  COMFYUI_INPUT_DIR=${CLOUD_DIR}/input \
  COMFYUI_OUTPUT_DIR=${CLOUD_DIR}/output \
  COMFYUI_USER_DIR=${CLOUD_DIR}/userdata

# -- Pre-Install --
# クラウドストレージと連携する ComfyUI のディレクトリを作成
RUN mkdir -p ${COMFYUI_INPUT_DIR} ${COMFYUI_OUTPUT_DIR} ${COMFYUI_USER_DIR}

# -- Install ComfyUI and ComfyUI-Manager --
# ref: https://comfyui-wiki.com/ja/install/install-comfyui/install-comfyui-on-linux
# ref: https://github.com/Comfy-Org/ComfyUI-Manager
WORKDIR ${COMFYUI_PATH}
# Clone
RUN <<EOS bash
  git clone \
    --filter=blob:none \
    --branch v${COMFYUI_VERSION} \
    --single-branch \
    https://github.com/comfyanonymous/ComfyUI.git .

  git clone \
    --filter=blob:none \
    --branch ${COMFYUI_MANAGER_VERSION} \
    https://github.com/Comfy-Org/ComfyUI-Manager.git custom_nodes/comfyui-manager
EOS

# Install python packages
#COPY data/pyproject.toml ${UV_PROJECT}/pyproject.toml
RUN --mount=type=cache,dst=/root/.cache/uv,sharing=locked,id=comfy-cache \
  --mount=type=bind,src=data/pyproject.toml,dst=/app/pyproject.toml,rw \
  <<EOS bash
  uv add --no-sync -r requirements.txt
  uv add --no-sync -r custom_nodes/comfyui-manager/requirements.txt
  uv sync
EOS

# ------------------------------
FROM comfyui AS final
ARG S6_ROOTFS
ARG COMFYUI_EXTRA_DIR

ENV COMFYUI_PORT=8188 COMFYUI_EXTRA_DIR=${COMFYUI_EXTRA_DIR}

# アプリなどのコピー
COPY --from=s6 ${S6_ROOTFS}/ /
COPY data/comfyui/ ${COMFYUI_PATH}/
COPY data/s6-overlay/ /etc/s6-overlay/

EXPOSE ${COMFYUI_PORT}
WORKDIR ${UV_PROJECT}
ENTRYPOINT [ "/init" ]
