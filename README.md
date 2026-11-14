# disktwin

**The copy you need when you don't need RAID.**

disktwin keeps a second disk as a **live twin** of your data disk. Whatever you add, change or delete appears on the twin a few seconds later. It also **watches the health of your disks** with SMART and tells you when something looks wrong.

It needs no array, no reformatting and no `mdadm`: you get two ordinary disks with ordinary files, and one is always a copy of the other.

> 🇪🇸 [Leer en español](README.es.md)

> ⚠️ **Not production-ready.** disktwin is a set of well-behaved shell scripts for your home computer, your media box or your homelab. It is not meant for business-critical data. If losing a few seconds of changes, or having to swap disks by hand, would be a real problem for you, you need real RAID, plus real backups.

## Why

You have a disk full of photos, videos and documents, a spare disk, and the nagging feeling that you should "have a copy".

RAID 1 is the textbook answer, but for this job it is heavy:

- you have to wipe both disks and rebuild everything around an array;
- both disks should match in size and type;
- the copy can only be read with `mdadm` or ZFS;
- and it doesn't protect you from your own mistakes: `rm -rf` and ransomware are mirrored instantly too.

disktwin keeps the useful part, an up-to-date second copy, and drops the ceremony.

## disktwin vs. RAID 1

| | RAID 1 (mdadm / ZFS) | disktwin |
|---|---|---|
| Setup | Wipe both disks, build the array, configure mdadm/initramfs | Fill in one config file, run two scripts |
| Data you already have | Must be moved out and back in | Used as is |
| Mixed disks (size, type, USB, NVMe + HDD) | Wasteful or awkward | No problem |
| Reading the copy on another computer | Needs mdadm / ZFS | Plain files: plug it into Windows or macOS |
| **Accidental mass deletion** | **Mirrored to both disks instantly** | Blocked, and you get an alert |
| Disk health alerts | Configured separately | Built in (SMART → desktop + terminal) |
| A disk dies | Keeps running, no downtime ✅ | The copy is there; switching to it is manual |
| System / boot disk | ✅ | ❌ Data disks only |
| Delay before changes reach the copy | 0 | ~3 seconds |

## What it does

- **One-way mirror, source → twin.**
  - **Real time:** a user service watches the source with `inotifywait`. A few seconds after each batch of changes (`SETTLE_SECONDS`), it syncs **only what changed**:
    - a file created, changed or deleted → only its folder is checked, not its subfolders;
    - a new folder (created or moved in) → that folder is copied whole;
    - a deleted folder → it is deleted on the twin by checking only its parent.

    Each change takes a fraction of a second, even on disks with tens of thousands of files.
  - **Hourly:** a cron job runs a full sync, in case anything slipped through (for example, changes made while the service was stopped).
- **SMART monitoring** through `smartd`: failing health, reallocated, pending or uncorrectable sectors, growing error logs, failed self-tests and critical temperature. On SATA disks it runs a short self-test every day and a long one every week.
- **Alerts you can't miss:**
  - a critical desktop notification as soon as something happens;
  - a red banner in every new terminal until you acknowledge it;
  - a reminder notification at login while alerts are still pending.

### Safety rails

- Partitions are found **by UUID**, never by path. If the source is not mounted, **nothing is synced** (the twin is never emptied against an empty directory), and you get an alert.
- If the twin is not mounted exactly where expected, nothing is synced, and you get an alert.
- **Mass deletions are blocked:** if a sync would delete more than `MAX_DELETE` files, it stops and alerts you. If it was intended, run `disktwin-sync --force`.
- Only one `rsync` runs at a time (`flock`).

## Install

Tested on Linux Mint 22.3 (Ubuntu 24.04 base). Other systemd distributions with `apt` should work, but are untested. The source and the twin can use any filesystem Linux can write to (ext4, exFAT, NTFS…).

```bash
git clone https://github.com/<you>/disktwin && cd disktwin
cp config.example disktwin.conf
nano disktwin.conf        # UUIDs, twin mount point, SMART disks, user, language
sudo ./install.sh         # packages, commands, /etc/disktwin.conf, smartd
./install-user.sh         # watch service, cron job, terminal banner (no sudo)
```

To find the values for the config:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
ls -l /dev/disk/by-id/ | grep -v -- -part
```

The twin partition must be mounted automatically at boot (with an `/etc/fstab` entry) at `TARGET_MOUNT`. For an NTFS twin on Linux Mint, use the `ntfs-3g` type, because Mint blacklists the `ntfs3` driver:

```
/dev/disk/by-uuid/<UUID> /mnt/twin ntfs-3g nosuid,nodev,nofail,uid=1000,gid=1000,x-gvfs-show 0 0
```

> **The first copy takes a while.** For hundreds of GB, run it by hand before enabling the service, so you can watch its progress: `rsync -rt --info=progress2 SOURCE/ TWIN/`. Note that SMR hard drives (very common in cheap 2 TB+ disks) can drop to a few MB/s during long writes. That's normal; day-to-day syncs are tiny.

## Usage

| Command | What it does |
|---|---|
| `disktwin-sync` | Full sync now |
| `disktwin-sync --force` | Full sync without the deletion limit |
| `disktwin-sync --paths FILE` | Sync only the folders listed in FILE (used by the watcher) |
| `disktwin-alerts` | List pending alerts |
| `disktwin-alerts --ok` | Acknowledge all alerts |
| `systemctl --user status disktwin-watch` | Real-time mirror status |
| `journalctl --user -u disktwin-watch -f` | Watcher log |
| `less ~/.local/state/disktwin/sync.log` | Sync history |
| `journalctl -u smartmontools` | smartd log |
| `sudo smartctl -a /dev/sdX` | Full SMART report for a disk |

Messages and alerts follow `DISKTWIN_LANG` in the config: `auto` (from `LANG`), `es` or `en`.

## Files

```
bin/disktwin-sync           rsync mirror with the safety rails
bin/disktwin-watch          inotify watcher → disktwin-sync --paths (only what changed)
bin/disktwin-alert          records an alert and notifies it (used by smartd and the mirror)
bin/disktwin-alerts         shows and acknowledges pending alerts
systemd/disktwin-watch.service    user service
autostart/disktwin-alerts.desktop reminder at login
config.example              configuration template
install.sh                  root install
install-user.sh             user install
```

Where things end up:

| What | Where |
|---|---|
| Commands | `/usr/local/bin/` |
| Configuration | `/etc/disktwin.conf` |
| smartd configuration | `/etc/smartd.conf` (original saved as `/etc/smartd.conf.orig`) |
| Alerts | `/var/lib/disktwin/alerts/{pending,seen}` |
| Cron job | the user's crontab |

## What disktwin is NOT

- **Not RAID.** If the source disk dies, your data is safe on the twin, but nothing switches over automatically: you swap disks or paths yourself.
- **Not a backup.** It is a mirror: a file you delete or damage on the source is deleted or damaged on the twin seconds later (only mass deletions are stopped). Pair it with a versioned backup such as `restic`, `borg` or Timeshift, ideally to a third place: the 3-2-1 rule.
- **Not two-way.** Changes made directly on the twin are overwritten.
- **Not for the system disk.** It is meant for data disks.
- **Not network-aware.** `inotify` only sees changes made on this computer. If the source disk is changed from another computer, the hourly full sync picks those changes up.
- File permissions and owners are not copied (`rsync -rt`), because exFAT and NTFS don't store them the Linux way.

## License

[MIT](LICENSE)
