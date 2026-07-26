# ARR Stack with Gluetun VPN

> **Status: not deployed anywhere.** Parked here as a candidate for a
> future media host (e.g. bare-metal NixOS on the HP mini PC — out of
> scope for now). The Linux paths `/mnt/tank` and `/mnt/storage` assume
> that future host, not `nixos-infra`.

## Services
- qBittorrent (through VPN)
- Sonarr 
- Prowlarr (through VPN)
- Gluetun (AirVPN Wireguard)

## Setup
1. Copy `.env.example` to `.env`
2. Add your AirVPN Wireguard keys to `.env`
3. Run `docker compose up -d`

## Verification
```bash
docker exec qbittorrent curl -s https://ipinfo.io/ip

Should return AirVPN IP, not your home IP.

**Check before committing:**
