#!/bin/sh
set -eu

mkdir -p /run/hello-yocto

while :; do
    date '+%Y-%m-%dT%H:%M:%S%z' > /run/hello-yocto/status
    sleep 10
done
