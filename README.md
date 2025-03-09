# Proxmox Tool Suite

A Bash script designed to simplify common management tasks for Proxmox VE, focusing on LXC containers and system maintenance. This tool provides an interactive menu with options to delete, update, clean, trim, and configure bind mounts for LXC containers, as well as perform system-level updates and cleanup.

## Features

### LXC Management
- **Delete LXC Containers** (`🚫`): Remove selected LXC containers manually or automatically.
- **Update LXC Containers** (`🔄`): Update packages in LXC containers based on their OS (supports Alpine, Arch, Fedora, Ubuntu/Debian, OpenSUSE, etc.).
- **Clean LXC Containers** (`🧹`): Remove unused packages, clear cache, and refresh package lists in LXC containers (Debian/Ubuntu only).
- **Run fstrim on LXC Containers** (`💾`): Execute `fstrim` to reclaim unused space in LXC containers.
- **Configure Bind Mount on LXC Containers** (`🔗`): Add or update a bind mount (e.g., for shared storage) in selected LXC containers.

### System Maintenance
- **Update Package List** (`📥`): Run `apt update` on the Proxmox host.
- **Update Full System** (`⬆️`): Run `apt update && apt upgrade` on the Proxmox host.
- **Clean System** (`🗑️`): Run `apt autoremove` and `apt autoclean` to clean up the Proxmox host.
- **Clean Old Kernels** (`⚙️`): Remove unused Proxmox kernels and update GRUB.

## Requirements
- Proxmox VE installed.
- Root privileges (run with `sudo`).
- `whiptail` installed for interactive menus (usually included in Proxmox).

## Installation
1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/YOUR_USERNAME/proxmox-tool-suite/main/proxmox-tools.sh

# Proxmox Tool Suite

A Bash script for managing Proxmox VE LXC containers and system tasks.

## Installation

### Make it executable:

```
chmod +x proxmox-tools.sh
```

### (Optional) Create an alias for easier access:

```
echo "alias ptools='sudo /path/to/proxmox-tools.sh'" >> ~/.bashrc
source ~/.bashrc
```

## Usage

Run the script:

```
sudo ./proxmox-tools.sh
```

Or with the alias:

```
ptools
```

Select an option from the menu using numbers (0-9). Follow the prompts to complete each task. The script returns to the menu after each operation; use `0` to exit.

## Configuration Notes

### Bind Mount Configuration (`HOST_DIR`):

The `configure_bind_mount` function uses a default `HOST_DIR` set to `/mnt/multimedia`. This must match an existing directory on your Proxmox host where your storage is mounted (e.g., `/mnt/ssd/storage`, `/media/data`, etc.).

To find your mount point, run:

```
df -h
```

And adjust `HOST_DIR` in the script:

```
HOST_DIR="/your/mount/point"
```

Example: If your storage is at `/mnt/storage`, edit line ~300 in `proxmox-tools.sh` to:

```
HOST_DIR="/mnt/storage"
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues or pull requests to improve this tool!

## Acknowledgments

Inspired by various Proxmox community scripts and enhanced with additional functionality.
