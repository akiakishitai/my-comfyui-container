# my-comfyui-container

個人用のComfyUIコンテナイメージ。

## ビルドイメージ

```bash
podman run --rm -it \
  --name=buildah_cnt \
  --hostname=buildah \
  --cap-add=sys_admin,mknod \
  --device=/dev/fuse \
  --security-opt label=disable \
  --mount type=tmpfs,tmpfs-size=32M,dst=/home/build/.local/share/containers \
  --mount type=bind,src="${HOME}/.local/share/podman-in-podman",dst=/var/lib/containers \
  --mount type=volume,src=buildah-cache,dst=/var/tmp \
  --mount type=bind,src="${PWD}",dst=/workspace \
  --workdir=/workspace \
  quay.io/buildah/stable:v1.40.1 \
  buildah build --tag=my-comfyui-container --build-arg TARGETARCH="$(uname --machine)" .
```

## 開発

1. ビルド用コンテナ (_podman in podman_) を起動

    ```bash
    podman run -it \
      --name=buildah_cnt \
      --hostname=buildah \
      --cap-add=sys_admin,mknod \
      --device=/dev/fuse \
      --security-opt label=disable \
      --mount type=tmpfs,tmpfs-size=32M,dst=/home/build/.local/share/containers \
      --mount type=bind,src="${HOME}/.local/share/podman-in-podman",dst=/var/lib/containers \
      --mount type=volume,src=buildah-cache,dst=/var/tmp \
      --mount type=bind,src="${PWD}",dst=/workspace \
      --workdir=/workspace \
      --env BUILDAH_LAYERS=true \
      quay.io/buildah/stable:v1.40.1
    ```

1. ビルド実行

    ```bash
    STAGE_NAME=s6
    buildah build \
      --target="${STAGE_NAME}" \
      --layers=true \
      --tag="comfyui-build/${STAGE_NAME}" \
      --build-arg TARGETARCH="$(uname --machine)" \
      .
    ```

1. ホスト側で作成したイメージからコンテナ起動

    イメージ確認。

    ```bash
    podman run \
      --root="${HOME}/.local/share/podman-in-podman/storage" \
      --rm -it \
      "localhost/comfyui-build/${STAGE_NAME}" /bin/bash
    ```
