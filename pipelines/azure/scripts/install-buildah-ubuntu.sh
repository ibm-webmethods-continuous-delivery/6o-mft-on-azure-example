#!/bin/sh

# May optimize - move this in an image building prerequisite pipeline

echo "Updating existing OS packages..."
sudo apt-get -qy update

echo "Upgrading existing OS packages..."
sudo apt-get -qy upgrade

echo "Installing buildah prerequisites ..."
sudo apt-get -qy install \
	ca-certificates \
	curl \
	fuse-overlayfs \
	gnupg2

. /etc/os-release
echo "Installing buildah for OS release ${VERSION_ID}..."
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -fsL "https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_${VERSION_ID}/Release.key" | sudo apt-key add - &&
sudo apt-get -qq -y update

sudo apt-get -qq -y install buildah

if [ ! "$(buildah version)" ] ; then
  echo "FATAL: Buildah is not available! Cannot continue"
  exit 3
fi
