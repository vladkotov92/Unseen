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
- Lets you choose a fixed exit node country, or let Tor pick automatically (only when rotation is disabled)
- Detects if Tor ignores the exit node constraint and lets you retry or switch
- Routes all network traffic through the Tor SOCKS5 proxy (`127.0.0.1:9050`)
- Shows your anonymous IP, country, region and city once connected
- On exit (`CTRL+C`), automatically stops Tor and resets all proxy settings

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

On every run you will first be asked whether you want IP rotation:

```
[?] Enable IP rotation? [y/n]:
```

**If you choose `n`**, you will then be asked for an exit node country:

```
[+] Exit node country (e.g. US, DE, NL, FR, IT)
    Press ENTER to let Tor choose automatically:
```

Type a country code (e.g. `DE`, `NL`, `US`) or press `ENTER` to let Tor choose automatically.

**If you choose `y`**, you will be asked how often to rotate (in seconds):

```
[?] Rotate every how many seconds? (min 10):
```

Tor will start with a random exit node and automatically change identity at the specified interval, refreshing your IP and location info each time.

Once connected you will see:

```
Connection active
──────────────────────
IP:      192.42.116.100
Country: The Netherlands
Region:  North Holland
City:    Amsterdam
──────────────────────

Press CTRL+C to disconnect
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

## Exit node country codes

Some countries have many reliable exit nodes, others have few or none.

| Works well                   | Unreliable or unavailable               |
| ---------------------------- | --------------------------------------- |
| `NL`, `DE`, `FR`, `SE`, `CH` | `RU`, `CN`, `IR`, `BY`                  |
| `US`, `CA`, `FI`, `GB`, `AT` | (blocked or removed from Tor consensus) |

## How it works

1. Asks whether to enable IP rotation
2. If rotation is disabled, asks for an exit node country (optional); if enabled, any previous exit node config is cleared so Tor picks randomly
3. Stops any existing Tor instance to avoid conflicts
4. Starts Tor as the current user and waits for a full bootstrap (100%)
5. Enables the SOCKS5 proxy on all active network interfaces
6. Fetches your anonymous IP and location through the Tor circuit
7. Verifies the exit country matches the requested one (only when rotation is off) — if not, prompts to retry
8. If rotation is on, changes Tor identity and refreshes connection info at the chosen interval
9. On exit, disables the proxy and kills the Tor process

## Notes

- Your exit node IP may differ between requests — this is normal Tor behavior
- `StrictNodes 1` tells Tor to only use the specified country, but some countries have no usable exit nodes and Tor may fall back to another country
- Some websites may block known Tor exit nodes

## Developer

**A Russian Boy**  
GitHub: [https://github.com/vladkotov92](https://github.com/vladkotov92)

## License

MIT — see [LICENSE](LICENSE)
