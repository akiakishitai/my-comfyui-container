# syntax=docker/dockerfile:1.7

ARG S6_OVERLAY_VERSION=3.2.1.0
ARG S6_ROOTFS=/s6-root

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
