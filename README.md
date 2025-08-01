# DNS Benchmark & Auto-Configuration

**Originally made by Matthew Deiter**

---

## Description

A bash script that benchmarks multiple DNS servers for speed, reliability, and DNSSEC support, logs results, applies custom filters, saves full stats to a CSV, and can automatically update your system’s DNS settings (resolv.conf, NetworkManager, or systemd-resolved).

---

## Features

- Benchmarks popular DNS servers for speed, DNSSEC, and reliability
- Custom filtering (max latency, provider, DNSSEC, reliability)
- Full stats saved to CSV for analysis or graphing
- Detailed logging (optional)
- Automatically applies the top 2 DNSSEC-supporting servers to your system:
  - Supports `/etc/resolv.conf`, NetworkManager, and systemd-resolved
- Safe: always prompts before changing settings and backs up resolv.conf

---

## Usage

1. **Download the script** and make it executable:
    ```bash
    chmod +x dns_benchmark.sh
    ```

2. **Run the script:**
    ```bash
    ./dns_benchmark.sh
    ```

3. **Follow the prompts** to enable logging and confirm DNS changes.

4. **Review results:**
    - Full stats are saved in a CSV file (path printed at the end).
    - Detailed logs (if enabled) are saved in `/tmp`.

---

## Customization

Edit the variables at the top of the script to:
- Change which DNS servers are tested
- Adjust latency or provider filters
- Choose how DNS settings are applied

---

## Requirements

- `bash`, `dig`, `awk`, `sudo`
- For auto-configuration: `systemd-resolved`, `NetworkManager`, or root access for `/etc/resolv.conf`

---

## License

MIT License

---

## Credits

**Originally made by Matthew Deiter**
