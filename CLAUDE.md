# samba4-server

## What this project does

Lokaler Samba 4 Active Directory Domain Controller als Docker-Setup mit interaktivem Setup-Script.
Dient als Entwicklungs- und Test-Umgebung fuer Applikationen, die LDAP/AD-Authentifizierung benoetigen.

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
  - `samba-ad` — Samba 4 AD DC (Ports: LDAP 389, LDAPS 636)
  - `phpldapadmin` — Web GUI (Port: 8090)
  - `ldap-seed` — Einmaliger Seed-Container fuer Testdaten
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
