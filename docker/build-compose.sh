#!/usr/bin/env bash

rootdir=$(dirname $(dirname "$(realpath "$0")"))

APP=andygrundman/tailscale-wakeonlan

docker stop $APP
docker rm --force $APP

docker build --tag $APP:latest "$rootdir" && \
docker compose up -f "$rootdir/compose.yaml" -d && \
docker logs --follow $APP
