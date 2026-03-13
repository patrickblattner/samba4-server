# samba4-server

## What this project does

Vollstaendiger Samba 4 Active Directory Domain Controller als Docker-Setup mit interaktivem Setup-Script.
Lab-DC fuer Entwicklung und Tests — NICHT fuer Produktion.
Ersetzt einen Windows Server DC fuer Szenarien wie LDAP, Kerberos, SMB, DNS und AD-Authentifizierung.

## Key references

- `BACKLOG.md` — Kanban board with all open tasks, features, and bugs
- `AGENTS.md` — coding rules, conventions, build commands

## Project management — dual tracking rule

Tasks are tracked in **two places simultaneously** — always keep both in sync:

1. **`BACKLOG.md`** (local) — Kanban columns: Backlog / Todo / In Progress / Done
2. **GitHub Issues + Project Board**

Use `/task setup` to configure GitHub integration for this project.

## Architecture

- **Docker Image:** `diegogslomp/samba-ad-dc:latest` (Docker Hub)
- **Services:**
  - `samba-ad` — Vollstaendiger AD DC (DNS 53, Kerberos 88/464, RPC 135, NetBIOS 137-139, LDAP 389, SMB 445, LDAPS 636, Global Catalog 3268/3269)
  - `phpldapadmin` — Web GUI (Port: 8090)
  - `ldap-seed` — Einmaliger Seed-Container fuer Testdaten
- **Binding:** Konfigurierbar — `127.0.0.1` (intern) oder `0.0.0.0` (extern/Netzwerk)
- **Env-Vars des Images:** `DOMAIN`, `REALM` (uppercase!), `ADMIN_PASS`, `DNS_FORWARDER`, `BIND_NETWORK_INTERFACES`
- `BIND_NETWORK_INTERFACES` muss auf `"false"` stehen, sonst bindet Samba LDAP nur auf 127.0.0.1 im Container
- Healthcheck: `samba-tool domain info 127.0.0.1` (nicht die Container-IP)
- Provisioning dauert ~60-90 Sekunden beim ersten Start
- Seed benutzt `samba-tool` fuer User (wegen Passwort-Handling) und `ldapadd` fuer OUs/Gruppen
- `samba-tool` erstellt User mit `CN="Vorname Nachname"`, NICHT `CN=sAMAccountName`

### Dateistruktur

```
samba4-server/
  setup.sh          — Interaktives Setup-Script (Haupteinstiegspunkt)
  teardown.sh       — Alles herunterfahren und aufraeumen
  deploy/           — Wird von setup.sh generiert (nicht im Repo)
    docker-compose.yml
    .env
    ldif/
      structure.ldif
      groups.ldif
      run-seed.sh
```

### OU-Struktur (Testdaten)

```
DC=<domain>
  OU=Dev
    OU=Users          — patrick.blattner, angela.mueller, max.tester
    OU=Groups         — Engineers, Managers, QA, AllStaff, AppAccess
    OU=ServiceAccounts — svc.app
```

## Build & Development Commands

```bash
# Erstmaliges Setup (interaktiv)
./setup.sh

# Alles herunterfahren und aufraeumen
./teardown.sh

# User auflisten
docker exec samba-ad samba-tool user list

# Gruppen auflisten
docker exec samba-ad samba-tool group list

# Gruppenmitglieder anzeigen
docker exec samba-ad samba-tool group listmembers Engineers

# Logs pruefen
docker logs samba-ad
docker logs ldap-seed
```
