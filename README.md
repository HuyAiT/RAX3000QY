# RAX3000QY U-Boot Flash Tool

One-click script to flash custom U-Boot on the **China Mobile RAX3000Q(Y)** router from stock firmware — no SSH, no Telnet, no serial cable required.

## How It Works

The script exploits a command injection vulnerability in the stock firmware's log management API to gain root access, transfer U-Boot files, and flash them — all automated through a single command.

**Flow:** Login via web API → RCE via log endpoint → remove root password → upload files via HTTP → flash & verify MTD partitions.

## Requirements

### System

- **Linux** (tested on Fedora 44, should work on any distro)
- PC connected to the router via **Ethernet**
- Router running **stock China Mobile firmware**

### Dependencies

| Tool | Required for | Install (Fedora) | Install (Ubuntu/Debian) |
|------|-------------|-------------------|------------------------|
| `curl` | API requests | `sudo dnf install curl` | `sudo apt install curl` |
| `python3` | JSON parsing & HTTP server | `sudo dnf install python3` | `sudo apt install python3` |
| `sha256sum` | Password hashing | included in `coreutils` | included in `coreutils` |
| `ping` | Connectivity check | included in `iputils` | included in `iputils-ping` |
| `ip` | Local IP detection | included in `iproute2` | included in `iproute2` |
| `grep` | Output parsing | included in `grep` | included in `grep` |

Most of these come pre-installed on any Linux system. You likely don't need to install anything.

## Usage

```bash
# Option 1: provide uboot folder as argument
./flash_uboot.sh ./uboot

# Option 2: interactive mode (will prompt for path)
./flash_uboot.sh

# Option 3: pass credentials via environment variables (non-interactive)
ROUTER_IP=192.168.10.1 ROUTER_USER=user ROUTER_PASS=yourpassword ./flash_uboot.sh ./uboot
```

### What the script will ask

| Prompt | Default | Description |
|--------|---------|-------------|
| Router IP | `192.168.10.1` | Your router's admin IP |
| Username | `user` | Web admin username (on router label) |
| Password | *(none)* | Web admin password (on router label) |
| Uboot folder | *(none)* | Path to folder containing `.mbn` and `.bin` files |

### Example output

```
╔══════════════════════════════════════════════╗
║   RAX3000QY U-Boot Flash Tool               ║
║   For China Mobile stock firmware            ║
╚══════════════════════════════════════════════╝

Router IP [192.168.10.1]:
Username [user]:
Password: ********
Path to uboot folder: ./uboot
[✓] Found uboot files
[✓] Router is reachable
[✓] Login successful (session: 3ad224ff...)
[✓] RCE working (uid=0 root)
[✓] Root password removed
[✓] HTTP server running at http://192.168.10.101:18888
[✓] nwrt_rax3000qy_uboot.mbn: 516590 bytes
[✓] nwrt_rax3000qy_mibib.bin: 262144 bytes
[!] ABOUT TO WRITE U-BOOT TO FLASH. THIS CANNOT BE UNDONE!
  mtd11 (APPSBL) <- nwrt_rax3000qy_uboot.mbn
  mtd1  (MIBIB)  <- nwrt_rax3000qy_mibib.bin
Continue flashing? (y/N): y
[✓] mtd11 verified OK
[✓] mtd1 verified OK

╔══════════════════════════════════════════════╗
║   U-BOOT FLASHED SUCCESSFULLY!              ║
╚══════════════════════════════════════════════╝
```

## After Flashing U-Boot

Once U-Boot is flashed, you need to install OpenWrt/ImmortalWrt firmware:

1. **Unplug** the router power
2. Set your PC to a **static IP**: `192.168.1.2`, subnet `255.255.255.0`
3. **Hold the reset button**, plug in power, keep holding for **10 seconds**, then release
4. Open **http://192.168.1.1** in your browser — the U-Boot web interface will appear
5. Upload the firmware `.ubi` file and click **Update firmware**
6. Wait 2-3 minutes for the router to reboot

Default credentials: `root` / `password`

## Downloads

### U-Boot

U-Boot files are included in the `uboot/` folder of this repo. Originally from [sfxfs/rax3000qy-OpenWrt](https://github.com/sfxfs/rax3000qy-OpenWrt).

### ImmortalWrt Firmware

Latest firmware builds for RAX3000Q:

**[kkstone/Actions-OpenWrt-RAX3000Q](https://github.com/kkstone/Actions-OpenWrt-RAX3000Q/releases/latest)**

Download the file named `immortalwrt-ipq50xx-arm-cmcc_rax3000q-squashfs-nand-factory.ubi` for flashing via U-Boot.

## Credits

- [hugo.utermux.dev](https://hugo.utermux.dev/default/rax3000q-latest/) — vulnerability research on stock firmware RCE
- [kkstone](https://github.com/kkstone/Actions-OpenWrt-RAX3000Q) — ImmortalWrt automated firmware builds
- [sfxfs/rax3000qy-OpenWrt](https://github.com/sfxfs/rax3000qy-OpenWrt) — original flashing guide

## Disclaimer

**Back up your original firmware before proceeding.** Flashing U-Boot is irreversible — a bad flash can brick your router. You are solely responsible for any risks or damages.

## License

MIT
