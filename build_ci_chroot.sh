#!/usr/bin/env bash
set -eux

apt-get update && \
  apt-get install -y debootstrap tar zstd

mkdir /tmp/chroot

debootstrap --variant=minbase noble /tmp/chroot http://archive.ubuntu.com/ubuntu
