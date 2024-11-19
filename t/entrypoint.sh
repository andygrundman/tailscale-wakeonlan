#!/bin/sh

# entrypoint for running tests, we don't want to launch s6 /init or install Tailscale

exec "$@"
