#!/usr/bin/env bash

# Run the container built by the GitHub Action

NAME=tailscale-wakeonlan
AUTHKEY="${TAILSCALE_AUTHKEY:-your-tskey}"

docker stop $NAME
docker rm --force $NAME

docker volume create tailscale-wakeonlan-state && \
docker run -d \
  --name $NAME \
  --restart unless-stopped \
  --network bridge \
  -v tailscale-wakeonlan-state:/var/lib/tailscale \
  -e TAILSCALE_HOSTNAME=wakeonlan-testing \
  -e TAILSCALE_AUTHKEY="$AUTHKEY" \
  -e TAILSCALE_USE_SSH=true \
  -e WOL_NETWORK="192.168.2.0/24" \
  ghcr.io/andygrundman/tailscale-wakeonlan:latest && \
docker logs --follow $NAME
