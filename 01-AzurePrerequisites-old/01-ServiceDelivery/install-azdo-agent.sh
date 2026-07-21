#!/bin/sh

apt-get -qy update
apt-get -qy upgrade

apt-get install -qy \
  curl \
  docker \
  git \
  jq \
  libicu70
