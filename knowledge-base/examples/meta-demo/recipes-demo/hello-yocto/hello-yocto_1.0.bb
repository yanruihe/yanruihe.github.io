SUMMARY = "A small Yocto demo service"
DESCRIPTION = "Installs a shell program and a systemd service"
LICENSE = "CLOSED"

SRC_URI = "file://hello-yocto.sh \
           file://hello-yocto.service"

S = "${UNPACKDIR}"

inherit allarch systemd

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/hello-yocto.sh ${D}${bindir}/hello-yocto.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/hello-yocto.service \
        ${D}${systemd_system_unitdir}/hello-yocto.service
}

RDEPENDS:${PN} = "busybox"
SYSTEMD_SERVICE:${PN} = "hello-yocto.service"
SYSTEMD_AUTO_ENABLE = "enable"
