# ARR Stack with Gluetun VPN

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
