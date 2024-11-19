#!/usr/bin/env bash

rootdir=$(dirname $(dirname "$(realpath "$0")"))

NAME=tailscale-wakeonlan
AUTHKEY="${TAILSCALE_AUTHKEY:-your-tskey}"

docker stop $NAME
docker rm --force $NAME

docker build --target=main-image --tag andygrundman/tailscale-wakeonlan:latest "$rootdir" && \
docker volume create tailscale-wakeonlan-state && \
docker run -d \
  --name $NAME \
  --restart unless-stopped \
  --network bridge \
  -v tailscale-wakeonlan-state:/var/lib/tailscale \
  -e TAILSCALE_HOSTNAME=wakeonlan \
  -e TAILSCALE_AUTHKEY="$AUTHKEY" \
  -e TAILSCALE_USE_SSH=true \
  andygrundman/tailscale-wakeonlan:latest && \
docker logs --follow $NAME
