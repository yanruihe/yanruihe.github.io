SUMMARY = "Yocto knowledge base demo image"
DESCRIPTION = "A small image containing the hello-yocto systemd service"
LICENSE = "MIT"

inherit core-image

IMAGE_INSTALL:append = " hello-yocto"
IMAGE_FEATURES += "ssh-server-dropbear"
IMAGE_FSTYPES = "ext4"
