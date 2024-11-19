#!/usr/bin/env bash

# To run all tests:
# docker/run-tests.sh prove -r t/

# or with verbose output:
# docker/run-tests.sh prove -vr t/

# or only a single test:
# docker/run-tests.sh prove -r t/add.t

rootdir=$(dirname $(dirname "$(realpath "$0")"))

APP=tailscale-wakeonlan-test

docker stop $APP
docker rm --force $APP

docker build --target=test-image --tag $APP:test-image "$rootdir" && \
docker run \
  --name tailscale-wakeonlan-test \
  --network bridge \
  $APP:test-image "$@"
