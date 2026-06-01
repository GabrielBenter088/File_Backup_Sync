# File Backup & Sync

A Bash script that syncs one or more local directories to a **NAS** (via `rsync`) or a **cloud remote** (via `rclone`). It features configurable logging, lock-file protection, desktop/email notifications, and automatic log rotation.

---

## Project Layout

```
File_Backup_Sync/
├── sync.sh              # Main entry point
├── config/
│   └── config.conf      # Default configuration (edit or override)
├── lib/
│   ├── logger.sh        # Logging helper (stdout + log file)
│   └── utils.sh         # Utility functions (deps, lock, validation, …)
├── logs/                # Runtime log files (git-ignored)
└── .gitignore
```

---

## Quick Start

### 1. Clone the repository
```bash
git clone https://github.com/GabrielBenter088/File_Backup_Sync.git
cd File_Backup_Sync
```

### 2. Configure

Copy the default config and edit it:
```bash
cp config/config.conf config/config.local.conf
nano config/config.local.conf
```

Key settings in `config.local.conf`:

| Variable | Description |
|---|---|
| `SOURCE_DIRS` | Space-separated list of directories to back up |
| `DEST_TYPE` | `rsync` (NAS/SSH) or `rclone` (cloud) |
| `RSYNC_DEST` | Destination path/host for rsync |
| `RCLONE_DEST` | `remote:path` for rclone |
| `LOG_RETENTION` | How many monthly log files to keep |
| `NOTIFY_DESKTOP` | `true` to enable desktop notifications |
| `NOTIFY_EMAIL` | `true` to enable email reports |

### 3. Install dependencies

**For NAS / SFTP sync:**
```bash
# rsync is usually pre-installed; if not:
sudo apt install rsync      # Debian/Ubuntu
sudo dnf install rsync      # Fedora/RHEL
```

**For cloud sync (Google Drive, S3, Dropbox, …):**
```bash
# Install rclone: https://rclone.org/install/
curl https://rclone.org/install.sh | sudo bash
rclone config   # Set up your remote once
```

### 4. Make the script executable
```bash
chmod +x sync.sh
```

### 5. Run

```bash
# Normal sync
./sync.sh

# Preview only (no files transferred)
./sync.sh --dry-run

# Use a custom config file
./sync.sh -c /path/to/my.conf

# Verbose / debug output
./sync.sh --verbose

# Help
./sync.sh --help
```


---

## Automate with cron

Add a line to your crontab (`crontab -e`) to run automatically:

```cron
# Every day at 02:00
0 2 * * * /absolute/path/to/File_Backup_Sync/sync.sh >> /var/log/backup_cron.log 2>&1

# Every 6 hours
0 */6 * * * /absolute/path/to/File_Backup_Sync/sync.sh
```

---

## Logs

Logs are written to `logs/sync_YYYYMM.log` (one file per month). Old files are
removed automatically according to `LOG_RETENTION` (default: keep last 6 months).

---

## License

MIT