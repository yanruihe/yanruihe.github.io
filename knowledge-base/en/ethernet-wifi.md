# Linux Ethernet PHY and Wi-Fi Debugging

This topic focuses on board-level network bring-up: start with the device-tree and MAC/PHY topology, then verify link, protocol, and userspace layers in order. RGMII and SGMII describe interfaces between a MAC and a PHY/PCS; they are not the cable-side Ethernet medium. Timing, clocks, reset, and the peer configuration must be checked together.

## 1. Separate the data paths

A wired path is broadly:

```text
SoC MAC ↔ MAC-PHY interface (RGMII / SGMII, etc.) ↔ PHY ↔ magnetics/connector/cable ↔ peer
                                  MDIO management bus ─┘
```

The MAC handles frame transmission, DMA, and the network interface. The PHY handles the physical layer and link negotiation; MDIO accesses its management registers. Linux phylib/phylink connects PHY state to the MAC driver. Wi-Fi devices commonly attach over PCIe, SDIO, USB, or a platform bus, and Linux drivers work with userspace connection managers through cfg80211/nl80211.

## 2. RGMII and SGMII: verify both ends

| Item | RGMII | SGMII |
| --- | --- | --- |
| Connection | Parallel data lines with a source-synchronous clock | Single-lane serial SerDes link |
| Board-level concerns | Routing, sampling window, TX/RX clock delay | SerDes/PCS setup, reference clock, polarity, negotiation mode |
| Software checks | Interface mode and delay ownership at MAC and PHY | Both ends configured for SGMII and consistent PCS state |

RGMII modes such as `rgmii`, `rgmii-id`, `rgmii-rxid`, and `rgmii-txid` describe which side supplies receive/transmit clock delay from the PHY's perspective. Do not switch to an `*-id` mode just because a link is unstable. Check the schematic, data sheets, PCB routing, and PHY driver so delay is neither duplicated nor omitted. SGMII and 1000BASE-X should not be treated as interchangeable just because their line rates match; mismatched control-word/PCS semantics can leave a link apparently up while duplex or speed information is wrong.

## 3. Board bring-up sequence

Capture boot logs, the device tree, and interface state before making changes. Work from the lower layers upward:

```sh
dmesg | grep -Ei 'eth|mdio|phy|link|firmware'
ip -details link show
ethtool eth0
ethtool -S eth0
readlink /sys/class/net/eth0/phydev 2>/dev/null
```

1. Hardware: power, reset timing, reference clock, strap pins, and MDIO/MDC levels. Confirm with instruments; a successful driver probe alone is not enough.
2. Enumeration: verify device-tree `compatible`, `reg` (PHY address), `phy-mode`, clocks/reset GPIOs, and interrupt polarity against the schematic. Confirm MDIO returns the expected PHY ID.
3. MAC-PHY link: inspect interface mode, PCS/SerDes state, autonegotiation, and speed/duplex at both ends. For RGMII, validate timing margin across temperature and voltage conditions.
4. Network layer: only after link-up, check IP, ARP, routes, VLANs, firewall, and DHCP. Continuous ping and packet-loss/throughput tests help separate physical-link faults from network configuration.

Do not hide a negotiation problem by forcing the speed, and do not treat an `ethtool -s` override as a fix. Record register/driver logs, temperature, cable, peer port, and workload before and after a change.

## 4. Wi-Fi: from enumeration to connectivity

A common stack is bus and power/clock → chip driver and firmware → cfg80211 (common configuration API) → mac80211 (used only by SoftMAC devices) or a FullMAC driver → nl80211 → `iw`, wpa_supplicant/NetworkManager → DHCP/IP. Not every Wi-Fi device uses mac80211; FullMAC firmware usually handles more 802.11 MAC work. The regulatory domain also constrains channels and transmission behavior.

```sh
dmesg | grep -Ei 'wlan|wifi|firmware|cfg80211|mac80211'
rfkill list
iw phy
iw dev
iw dev wlan0 link
iw dev wlan0 scan
ip link show wlan0
```

- No wireless interface: check SDIO/PCIe/USB enumeration, power/reset, kernel configuration, module dependencies, and firmware-load errors.
- Scanning works but association fails: check band/channel, regulatory domain, cipher suite, AP logs, authentication flow, and signal quality.
- Associated but offline: separate DHCP, gateway/DNS, routing, and firewall issues; `iw ... link` does not prove that an IP address was configured.
- Intermittent disconnects or poor throughput: collect RSSI, retries/loss, roaming, power-save, coexistence/interference, antenna, and RF-environment data with a fixed test location and peer.

## 5. Automotive Ethernet adds constraints to PHY bring-up

Automotive Ethernet is not complete just because a conventional Ethernet PHY is set to 100 Mbit/s or 1 Gbit/s. Identify the actual physical layer (for example 100BASE-T1 or 1000BASE-T1), PHY/switch, MAC/PCS, master/slave roles, harness/connector, and peer configuration. Follow the device data sheet and the applicable IEEE / OPEN Alliance specifications for link, interoperability, harness, and EMC validation. Linux-side concerns still include device tree, MDIO, phylib/phylink, PCS, time-synchronization needs, and observability; `ping` or a throughput test cannot replace conformance testing.

## 6. Bring-up record template

Record the board/schematic revision, SoC and PHY/Wi-Fi part numbers, kernel and device-tree commits, PHY address/interface mode, power/clock/reset, firmware version, peer configuration, reproduction conditions, logs, and test results. State what was observed, what was ruled out, what changed, and how to revert it; avoid a bare “network works” conclusion.

## Official references

- [Linux PHY Abstraction Layer](https://docs.kernel.org/networking/phy.html)
- [Linux PHY link topology](https://docs.kernel.org/networking/phy-link-topology.html)
- [cfg80211 subsystem](https://docs.kernel.org/driver-api/80211/cfg80211.html)
- [Linux Wireless: mac80211](https://wireless.docs.kernel.org/en/latest/en/developers/documentation/mac80211.html)
