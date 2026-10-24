# adb

## Over Wi-Fi (simplest)
Google's image sets `service.adb.tcp.port 5555` at boot (`/vendor/etc/init/init.common.rc`), so whenever **USB debugging** is
on in Developer options, adbd also listens on TCP port 5555:

```sh
adb connect <googlebook-ip>:5555      # then approve this computer on the Googlebook's screen
```
Port 5555 is then open on every network the Googlebook joins. Connecting still needs the on-screen approval, but on untrusted
networks turn USB debugging off.

## Over a Thunderbolt cable
A Thunderbolt/USB4 cable to another computer becomes a network link: `usb/kmod/thunderbolt_net.ko` (`CONFIG_USB4_NET`, left
out of gbOS86's kernel, [kernel-modules.md](kernel-modules.md)) plus `usb/tbnet.sh`, which gives `thunderbolt0` the address
10.42.0.2/24 and the routing rules Android leaves out. Loaded only when the laptop's Thunderbolt driver came up; `TB_NET=0`
turns it off, `TB_NET_IP` changes the address.

On the other computer (Linux):
```sh
nmcli con add type ethernet ifname thunderbolt0 ipv4.method manual ipv4.addresses 10.42.0.1/24
adb connect 10.42.0.2:5555
```
Status: the module loads at boot; the cable link itself is not checked yet.

## In the VM
`adb connect 127.0.0.1:5556` ([vm.md](vm.md)).

## Over a USB cable ("USB debugging")
Laptops have no USB device-mode controller, so a normal USB gadget is impossible. Google's Googlebook uses something else:
its `adb-usb-bridge` (started with adbd) turns on the USB controller's **xHCI Debug Capability (DbC)**, which lets a host port
act as a debug device when it is cabled **directly to another computer**, and bridges it to adbd's TCP port. It also supports
"USB host-to-host" bridge cables. The pieces are there on gbOS86: the kernel has `CONFIG_USB_XHCI_DBGCAP=y`, and Google's
ueventd rules give the bridge access to every xHCI controller's `dbc` attributes.

What it needs, and what does not work:
- The other end must be a **computer** running adb. A phone cannot be the host (both ends try to be).
- **USB-A to USB-A** only with a USB 3.0 **debug (crossover) cable** (no 5 V line, SuperSpeed lanes crossed); a normal A-to-A
  cable does not work and can harm a port.
- **USB-C to USB-C** between two Thunderbolt laptops tends to come up as a Thunderbolt link instead: use the Thunderbolt
  network above.

Tried so far: with an Android phone (C-C and C-A), which cannot work. Not yet tried with another computer. If it fails there,
`DEBUG_LOGS=1` for one boot records the bridge's messages ("Found XHCI PCI paths", "DbC device was created", "no DbC capability
found") in the full logcat.
