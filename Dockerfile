FROM lscr.io/linuxserver/baseimage-alpine:3.20 AS build-image

# Deps for Mojo web app and proper replacements for some
# of the busybox networking tools
RUN apk add --no-cache \
    bash grep jq make \
    ipcalc iproute2 iputils-ping traceroute \
    perl perl-app-cpm libev perl-ev \
    && rm -rf /var/cache/apk/*

WORKDIR /mojo
ADD mojo/cpanfile .
RUN cpm install -g --show-build-log-on-failure --cpanfile /mojo/cpanfile && \
    rm -rf /root/.perl-cpm

## Test runner image

FROM build-image AS test-image

ADD t/cpanfile-tests t/

RUN apk add --no-cache alpine-sdk perl-dev && \
    rm -rf /var/cache/apk/*
RUN cpm install -g --show-build-log-on-failure --cpanfile /mojo/t/cpanfile-tests && \
    rm -rf /root/.perl-cpm

# Add code as late as possible for quicker rebuilds
ADD mojo .
ADD t t/

# lightweight entrypoint without s6 or Tailscale
ENTRYPOINT ["/mojo/t/entrypoint.sh"]
CMD ["prove", "-r", "/mojo/t"]

## Final image

FROM build-image AS main-image

LABEL org.opencontainers.image.description="Wake your LAN devices from any device on your tailnet"
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.source=https://github.com/andygrundman/tailscale-wakeonlan

# Debug logging
# ENV MOJO_LOG_LEVEL=debug

# Tailscale settings that shouldn't be changed
ENV DOCKER_MODS=ghcr.io/tailscale-dev/docker-mod:main
ENV TAILSCALE_STATE_DIR=/var/lib/tailscale
ENV TAILSCALE_SERVE_PORT=3000
ENV TAILSCALE_SERVE_MODE=https

# Defaults
ENV TAILSCALE_HOSTNAME=wakeonlan

# Add code as late as possible for quicker rebuilds
ADD mojo .

# starts s6 which will install docker-mod, tailscale, and start tailscale
ENTRYPOINT ["/init"]
# Mojo server runs via CMD giving it the power to stop the container if it should fail
CMD ["/mojo/start.sh"]
