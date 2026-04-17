# Unseen

Route your internet traffic anonymously through the Tor network, directly from your terminal.

```
  _    _ _   _  _____ ______ ______ _   _
 | |  | | \ | |/ ____|  ____|  ____| \ | |
 | |  | |  \| | (___ | |__  | |__  |  \| |
 | |  | | . ` |\___ \|  __| |  __| | . ` |
 | |__| | |\  |____) | |____| |____| |\  |
  \____/|_| \_|_____/|______|______|_| \_|

```

> Unseen is not a traditional VPN — it is a Tor-based anonymizer that routes your traffic through the onion network.

## What it does

- Starts a Tor process on your machine
- Optionally rotates your IP automatically at a chosen interval
- Optionally enables a Kill Switch to block all traffic if Tor drops unexpectedly
- Lets you choose a fixed exit node country, or let Tor pick automatically (only when rotation is disabled)
- Detects if Tor ignores the exit node constraint and lets you retry or switch
- Routes all network traffic through the Tor SOCKS5 proxy (`127.0.0.1:9050`)
- **DNS leak protection** — forces every DNS query through Tor's `DNSPort` so your ISP cannot see what you're resolving
- **Transparent proxy** (Linux) — redirects all TCP traffic through Tor via `iptables` NAT, so every application is routed through Tor even if it ignores system proxy settings
- **Split tunneling** — list domains or IPs in `domains.txt` to bypass Tor for specific destinations (useful for streaming, banking, or sites that block Tor)
- Shows your anonymous IP, country, region and city once connected
- On exit (`CTRL+C`), automatically stops Tor and resets all proxy, DNS and firewall settings

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/vladkotov92/unseen.git
cd unseen
bash install.sh
```

## Usage

```bash
bash unseen.sh
```

On virtual machines (VMs), configure the browser's Network Settings to use Manual proxy configuration. Set the SOCKS Host to 127.0.0.1 and the Port to 9050.

On every run you will be asked a series of questions before connecting:

**1. IP rotation**

```
[?] Enable IP rotation? [y/n]:
```

**If you choose `y`**, you will be asked how often to rotate (in seconds):

```
[?] Rotate every how many seconds? (min 10):
```

Tor will start with a random exit node and automatically change identity at the specified interval, refreshing your IP and location info each time.

**2. Kill Switch**

```
[?] Enable Kill Switch? (blocks all traffic if Tor drops) [y/n]:
```

If enabled, all outbound traffic is blocked the moment Tor drops unexpectedly — your real IP is never exposed. On **Linux** this is enforced via `iptables`; on **macOS** via a background monitor that triggers an immediate disconnect.

**3. Exit node country** *(only when rotation is disabled)*

```
[+] Exit node country (e.g. US, DE, NL, FR, IT)
    Press ENTER to let Tor choose automatically:
```

Type a country code (e.g. `DE`, `NL`, `US`) or press `ENTER` to let Tor choose automatically.

Once connected you will see:

```
Connection active
──────────────────────
IP:      192.42.116.100
Country: The Netherlands
Region:  North Holland
City:    Amsterdam
──────────────────────

Press CTRL+C to disconnect  |  CTRL+R to restart
```

If the requested exit country is unavailable, the script will detect it and ask:

```
[!] Tor ignored StrictNodes: got DE instead of RU

[?] What do you want to do?
    1) Choose a different country
    2) Let Tor choose automatically
    Choice [1/2]:
```

Press `CTRL+C` at any time to disconnect. The script will automatically stop Tor and restore your original network settings.

Press `CTRL+R` at any time to do a full restart — cleans up Tor, the Kill Switch, the transparent proxy and the DNS overrides, then re-runs the script from the beginning so you can choose new settings.

## DNS leak protection

DNS leak protection is **always enabled** — no prompt, no opt-out.

Tor is configured with `DNSPort 9053` and `AutomapHostsOnResolve 1`, so it acts as a local DNS resolver that routes queries through the onion network.

- On **Linux**, `/etc/resolv.conf` is locked (`chattr +i`) to `nameserver 127.0.0.1` and an `iptables` NAT rule redirects all port 53 traffic (UDP/TCP) to `127.0.0.1:9053`. Your ISP never sees a single DNS query.
- On **macOS**, every active network service has its DNS servers overridden to `127.0.0.1` via `networksetup -setdnsservers`, with the original values backed up and restored on exit.

## Transparent proxy (Linux)

On Linux, Unseen adds a transparent proxy layer so that **every application** — including browsers that ignore system proxy settings — goes through Tor.

It works by:
- Adding `TransPort 9040` and `VirtualAddrNetworkIPv4 10.192.0.0/10` to Tor's config
- Creating an `iptables` NAT chain (`UNSEEN_TP`) that redirects all outgoing TCP traffic to `127.0.0.1:9040`, while:
  - Leaving Tor's own traffic untouched (matched by its system user, e.g. `debian-tor`)
  - Skipping loopback and private LAN ranges
  - Redirecting Tor's virtual address range (`10.192.0.0/10`) back to the TransPort

Requires a dedicated Tor system user (`debian-tor`, `tor`, or `_tor`) to avoid traffic loops. The installer ensures Tor is installed from your distro's package manager, which creates this user automatically.

On macOS the transparent proxy is not needed — `networksetup -setsocksfirewallproxy` applies system-wide and browsers honor it.

## Split tunneling

Unseen supports split tunneling via a plain-text file at the repo root: `domains.txt`.

Any destination listed there **bypasses Tor** and uses your real connection. Useful for:
- Streaming services that block Tor exits (Netflix, banking portals)
- Local servers, NAS, internal corporate resources
- Any site that flat-out refuses Tor traffic

### Format

One entry per line. Comments start with `#`. Three formats are accepted:

```text
# Domain name (resolved to its real IP at script startup)
github.com

# IPv4 address
1.1.1.1

# CIDR range (Linux only)
192.168.10.0/24
```

### How it works

- **Linux**: domains are resolved with `getent ahostsv4` *before* DNS is dirottato on Tor. The resolved IPs are written to `/etc/hosts` (so future lookups skip Tor) and added as `RETURN` rules in the `UNSEEN_TP` iptables NAT chain. If the Kill Switch is active, the same IPs are also added as `ACCEPT` rules in `UNSEEN_KS`.
- **macOS**: domains are resolved with `dscacheutil -q host` and written to `/etc/hosts`. All entries are also added to every network service's SOCKS proxy bypass list via `networksetup -setproxybypassdomains`.

Both platforms back up `/etc/hosts` (and the macOS bypass lists) before modifying them and restore them cleanly on exit.

### Caveats

- **IPs are resolved once at script startup.** If the domain's IPs change (common with large CDNs like Cloudflare), press `CTRL+R` to reload `domains.txt`.
- Browsers cache DNS — you may need to restart the browser (or flush its internal DNS cache) after enabling/disabling split tunneling for an already-open session.
- If the destination is in `domains.txt` but still appears to go through Tor, check `sudo iptables -t nat -L UNSEEN_TP -n` (Linux) or `networksetup -getproxybypassdomains <service>` (macOS).

## Testing for leaks

Once connected, verify that everything is actually routed through Tor:

1. **IP check** — https://check.torproject.org
   Should say *"Congratulations. This browser is configured to use Tor."*
2. **DNS leak test** — https://dnsleaktest.com → run the *Extended test*
   You should see **only** Tor exit-relay resolvers. No ISP, Google (`8.8.8.8`), or Cloudflare (`1.1.1.1`) resolvers.
3. **IPv6 / WebRTC** — https://ipleak.net
   The IP shown must match the Tor exit node, not your real address.
4. **Split tunnel check** — with a domain (e.g. `ifconfig.me`) listed in `domains.txt`:
   ```bash
   curl ifconfig.me                                   # → your real IP (bypassed Tor)
   curl --socks5 127.0.0.1:9050 https://icanhazip.com # → a Tor exit IP
   ```

## Exit node country codes

Some countries have many reliable exit nodes, others have few or none.

| Works well                   | Unreliable or unavailable               |
| ---------------------------- | --------------------------------------- |
| `NL`, `DE`, `FR`, `SE`, `CH` | `RU`, `CN`, `IR`, `BY`                  |
| `US`, `CA`, `FI`, `GB`, `AT` | (blocked or removed from Tor consensus) |

## How it works

1. Asks whether to enable IP rotation
2. Asks whether to enable the Kill Switch
3. If rotation is disabled, asks for an exit node country (optional); if enabled, exit node is picked randomly
4. Writes a `torrc` with `SocksPort 9050`, `DNSPort 9053`, and (on Linux) `TransPort 9040`
5. Stops any existing Tor instance to avoid conflicts
6. Starts Tor and waits for a full bootstrap (100%)
7. Enables the SOCKS5 proxy on all active network interfaces
8. Reads `domains.txt` (if present) — resolves any domains to real IPs while the original DNS is still active, writes `/etc/hosts` entries and records the IPs for firewall exceptions
9. Locks system DNS to `127.0.0.1` so all queries go through Tor's DNSPort
10. (Linux) Installs `iptables` NAT rules to transparently redirect all TCP + DNS traffic through Tor, with `RETURN` exceptions for the split tunnel IPs
11. If Kill Switch is enabled, enforces traffic blocking rules (Linux: `iptables` chain with `ACCEPT` for split tunnel IPs; macOS: background monitor)
12. Fetches your anonymous IP and location through the Tor circuit
13. Verifies the exit country matches the requested one (only when rotation is off) — if not, prompts to retry
14. If rotation is on, changes Tor identity and refreshes connection info at the chosen interval
15. On exit, tears down in reverse order: Kill Switch → transparent proxy → split tunnel (`/etc/hosts` + bypass list) → DNS overrides → SOCKS proxy → Tor process

## Notes

- Your exit node IP may differ between requests — this is normal Tor behavior
- `StrictNodes 1` tells Tor to only use the specified country, but some countries have no usable exit nodes and Tor may fall back to another country
- Some websites may block known Tor exit nodes

## Developer

**A Russian Boy**  
GitHub: [https://github.com/vladkotov92](https://github.com/vladkotov92)

## License

MIT — see [LICENSE](LICENSE)
