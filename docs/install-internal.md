# Dual boot beside Fedora

Googlebook on the internal NVMe, next to Fedora, booted from its own firmware entry. gbOS86 finds its partitions by label,
so the same files that boot from the external SSD boot from here (stage0's "nvme" mode).

## Layout on this laptop
WDC SN730 256 GB (238.5 GiB):

| Partition | Size | What |
|---|---|---|
| `nvme0n1p1` | 600 MiB | Fedora's EFI partition; also holds `EFI/gbos/BOOTX64.EFI` (the gbOS86 kernel) |
| `nvme0n1p2` | 2 GiB | Fedora `/boot` |
| `nvme0n1p3` | 163.9 GiB | Fedora btrfs (was 235.9 GiB; 89 GiB used) |
| `nvme0n1p4` | 8 GiB | `GBOSSYS` FAT32: `gbos/` (system image, scripts, modules, firmware, `gbos.cfg`, logs) |
| `nvme0n1p5` | 64 MiB | `GBOS_META` ext4 (`/metadata`) |
| `nvme0n1p6` | 63.9 GiB | `GBOS_DATA` ext4 with verity (`/data`) |

No separate EFI partition for gbOS86: its kernel sits in its own folder on Fedora's, which Fedora's updates never touch.

## `tools/install_internal.sh`
```sh
sh tools/install_internal.sh          # dry run: computes the layout from the disk, prints every command, changes nothing
sh tools/install_internal.sh --run    # does it, asking before each step: y continues, anything else stops (sudo for disk steps)
SIZE_GIB=72 ...                       # the space for gbOS86 (default 72)
```

| Step | What | Safety |
|---|---|---|
| — | Checks | `/` is btrfs on the disk's last partition; no GBOS partitions there yet; at least 20 GiB left free for Fedora; the external drive (the copy source) is plugged in; a backup is confirmed |
| 1 | Shrink Fedora's btrfs online (`btrfs filesystem resize`) to 1 GiB below its new partition size | btrfs moves its data off the end first |
| 2 | Shrink Fedora's partition (`sfdisk -N`, `partx -u`) | Only if btrfs is confirmed at or below the target size |
| 3 | Add GBOSSYS, GBOS_META, GBOS_DATA, 1 MiB aligned | |
| 4 | Make the filesystems, as gbOS86's own installer does (`GBOS_DATA` with `-m 0 -O verity`) | |
| 5 | Copy `gbos/` (without logs and backups) and `busybox` from the external drive | Every file compared afterwards; the external drive is only read |
| 6 | Copy the kernel to `EFI/gbos/BOOTX64.EFI` on Fedora's EFI partition | Compared afterwards |
| 7 | Add the "Googlebook (internal)" boot entry with the quiet options, after Fedora | Named apart from the SSD's "Googlebook"; `tools/grub/install_grub.sh` later removed the SSD's and renamed this one "Googlebook" |

**Resume:** if the three partitions already follow Fedora's in exactly this layout and are still unformatted (steps 1-3
done), a rerun skips to step 4. Any other existing GBOS partitions make it refuse.

What happened here: step 3's `partx -a` reported an error because the kernel had already picked the new partitions up; the
partitions were fine, and the resume was added for that. Step 6's check needed `sudo cmp` (Fedora's EFI partition is
root-only); the copy was verified by hand. Both are fixed in the script.

`/data` starts empty: the first boot runs Googlebook's setup, and fingerprints are enrolled again (a new install gets a new
install ID, so the SSD install's templates on the sensor are not offered).

## The external SSD now
The SSD and the internal install carry the **same labels**, and stage0 finds `GBOSSYS`, `GBOS_META` and `GBOS_DATA` by label
with `findfs`, which returns whichever it sees first. So:
- **Boot Googlebook (internal) with the SSD unplugged.**
- **Do not boot the SSD while the internal install exists**: stage0 could take the system from one disk and `/data` from
  the other.
- The SSD stays useful as a backup (it is a complete, working install) and as the VM's source
  (`tools/run_vm.sh` uses it when it is plugged in). To boot it again, the internal install's labels would have to change, or
  the internal install be removed.

## Updating
After rebuilding (or changing files in `usb/`), copy what changed to the internal GBOSSYS and the kernel to the EFI partition:

```sh
sudo mount -o uid=$(id -u) /dev/nvme0n1p4 /mnt
cp ~/Documents/gbos-x86/usb/hook.sh ~/Documents/gbos-x86/usb/gbos_fp /mnt/gbos/      # e.g. scripts and the HAL
cp ~/Documents/gbos-x86/usb/kmod/*.ko /mnt/gbos/kmod/
sync; sudo umount /mnt
sudo cp ~/Documents/gbos-x86/usb/out/BOOTX64.EFI /boot/efi/EFI/gbos/                  # only when the kernel changed
```

For a new upstream release (new `super.img`, modules, firmware): build the looper image, attach it read-only with
`udisksctl loop-setup -r -f dist/gbOS86-looper-*.img`, and copy its `gbos/` over the internal one the same way, keeping the
internal `gbos.cfg` and `logs/`.

## Removing it
Not needed so far, and not tested; written down so it is not improvised. In order:

```sh
sudo efibootmgr -b 0000 -B                                    # the "Googlebook (internal)" entry (check its number first)
sudo rm -r /boot/efi/EFI/gbos
sudo sfdisk --delete /dev/nvme0n1 4 5 6 && sudo partx -d -n 4:6 /dev/nvme0n1
echo ',+' | sudo sfdisk --no-reread --no-tell-kernel -N 3 /dev/nvme0n1 && sudo partx -u -n 3 /dev/nvme0n1   # p3 to the disk's end
sudo btrfs filesystem resize max /
```
Check with `lsblk` after each line. This deletes Googlebook's data on the internal disk.
