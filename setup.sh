#!/bin/bash
# ============================================================================
# Samba 4 AD DC - Docker Setup Script
# Creates a local Samba Active Directory Domain Controller for development
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────────────

command -v docker >/dev/null 2>&1 || error "Docker is not installed."
docker info >/dev/null 2>&1     || error "Docker is not running. Please start Docker Desktop."

# ── Interactive configuration ────────────────────────────────────────────────

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Samba 4 AD DC - Setup${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

read -rp "Domain name (e.g. lab.dev): " DOMAIN_FQDN
[ -z "${DOMAIN_FQDN}" ] && error "Domain name is required."

# Validate domain has exactly two parts
IFS='.' read -ra DOMAIN_PARTS <<< "${DOMAIN_FQDN}"
[ "${#DOMAIN_PARTS[@]}" -ne 2 ] && error "Domain must have exactly two parts (e.g. lab.dev)"

DOMAIN_DC="DC=${DOMAIN_PARTS[0]},DC=${DOMAIN_PARTS[1]}"
REALM="${DOMAIN_FQDN^^}"

read -rp "NetBIOS domain name [${DOMAIN_PARTS[0]^^}]: " NETBIOS
NETBIOS="${NETBIOS:-${DOMAIN_PARTS[0]^^}}"
NETBIOS="${NETBIOS^^}"

while true; do
  read -rsp "Admin password (min 8 chars, upper+lower+number+special): " ADMIN_PASS
  echo ""
  if [ "${#ADMIN_PASS}" -lt 8 ]; then
    warn "Password must be at least 8 characters."
    continue
  fi
  read -rsp "Confirm password: " ADMIN_PASS_CONFIRM
  echo ""
  if [ "${ADMIN_PASS}" != "${ADMIN_PASS_CONFIRM}" ]; then
    warn "Passwords do not match."
    continue
  fi
  break
done

read -rp "Bind IP address [127.0.0.1]: " BIND_IP
BIND_IP="${BIND_IP:-127.0.0.1}"

read -rp "LDAP port [389]: " LDAP_PORT
LDAP_PORT="${LDAP_PORT:-389}"

read -rp "LDAPS port [636]: " LDAPS_PORT
LDAPS_PORT="${LDAPS_PORT:-636}"

read -rp "phpLDAPadmin port [8090]: " PLA_PORT
PLA_PORT="${PLA_PORT:-8090}"

read -rp "Docker subnet [172.20.0.0/24]: " SUBNET
SUBNET="${SUBNET:-172.20.0.0/24}"

# Derive the .10 address from the subnet
SUBNET_BASE="${SUBNET%.*}"
SAMBA_IP="${SUBNET_BASE}.10"

read -rp "Install test data (users, groups, nested groups)? [Y/n]: " INSTALL_SEED
INSTALL_SEED="${INSTALL_SEED:-Y}"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}── Configuration Summary ──────────────────${NC}"
echo "  Domain:          ${DOMAIN_FQDN}"
echo "  Realm:           ${REALM}"
echo "  NetBIOS:         ${NETBIOS}"
echo "  Base DN:         ${DOMAIN_DC}"
echo "  Bind IP:         ${BIND_IP}"
echo "  LDAP:            ${BIND_IP}:${LDAP_PORT}"
echo "  LDAPS:           ${BIND_IP}:${LDAPS_PORT}"
echo "  phpLDAPadmin:    http://${BIND_IP}:${PLA_PORT}"
echo "  Docker subnet:   ${SUBNET}"
echo "  Samba IP:        ${SAMBA_IP}"
echo "  Test data:       ${INSTALL_SEED}"
echo ""

read -rp "Proceed? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Generate files ───────────────────────────────────────────────────────────

DEPLOY_DIR="${SCRIPT_DIR}/deploy"
mkdir -p "${DEPLOY_DIR}/ldif"

info "Generating docker-compose.yml..."
cat > "${DEPLOY_DIR}/docker-compose.yml" <<YAML
services:

  # -----------------------------------------------
  # Samba 4 - Active Directory Domain Controller
  # -----------------------------------------------
  samba-ad:
    image: diegogslomp/samba-ad-dc:latest
    container_name: samba-ad
    hostname: dc1
    privileged: true
    environment:
      DOMAIN:          ${NETBIOS}
      REALM:           ${REALM}
      ADMIN_PASS:      ${ADMIN_PASS}
      DNS_FORWARDER:   8.8.8.8
      BIND_NETWORK_INTERFACES: "false"
    volumes:
      - samba-data:/var/lib/samba
    ports:
      - "${BIND_IP}:${LDAP_PORT}:389"
      - "${BIND_IP}:${LDAPS_PORT}:636"
    networks:
      ldap-net:
        ipv4_address: ${SAMBA_IP}
    dns:
      - ${SAMBA_IP}
      - 8.8.8.8
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "samba-tool", "domain", "info", "127.0.0.1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # -----------------------------------------------
  # phpLDAPadmin - Web GUI
  # -----------------------------------------------
  phpldapadmin:
    image: osixia/phpldapadmin:latest
    container_name: phpldapadmin
    environment:
      PHPLDAPADMIN_LDAP_HOSTS:        samba-ad
      PHPLDAPADMIN_HTTPS:             "false"
      PHPLDAPADMIN_LDAP_CLIENT_TLS:   "false"
    ports:
      - "${BIND_IP}:${PLA_PORT}:80"
    depends_on:
      samba-ad:
        condition: service_healthy
    networks:
      - ldap-net
    restart: unless-stopped

  # -----------------------------------------------
  # Seed - befuellt AD mit Testdaten (einmalig)
  # Nutzt das gleiche Samba-Image fuer samba-tool
  # -----------------------------------------------
  ldap-seed:
    image: diegogslomp/samba-ad-dc:latest
    container_name: ldap-seed
    entrypoint: ["/bin/bash", "/seed/run-seed.sh"]
    volumes:
      - ./ldif:/seed
    environment:
      LDAP_HOST:           ${SAMBA_IP}
      LDAP_ADMIN_PASSWORD: ${ADMIN_PASS}
    depends_on:
      samba-ad:
        condition: service_healthy
    networks:
      - ldap-net
    restart: "no"
    profiles:
      - seed

volumes:
  samba-data:

networks:
  ldap-net:
    driver: bridge
    ipam:
      config:
        - subnet: ${SUBNET}
YAML

info "Generating LDIF and seed files..."

# ── structure.ldif ───────────────────────────────────────────────────────────

cat > "${DEPLOY_DIR}/ldif/structure.ldif" <<LDIF
# structure.ldif – Organisational Units

dn: OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: organizationalUnit
ou: Dev
description: Development Department

dn: OU=Users,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: organizationalUnit
ou: Users
description: Dev Users

dn: OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: organizationalUnit
ou: Groups
description: Dev Groups

dn: OU=ServiceAccounts,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: organizationalUnit
ou: ServiceAccounts
description: Service Accounts fuer Applikationen
LDIF

# ── groups.ldif ──────────────────────────────────────────────────────────────

cat > "${DEPLOY_DIR}/ldif/groups.ldif" <<LDIF
# groups.ldif – Gruppen inkl. Nested Groups
# CN entspricht dem von samba-tool generierten "Vorname Nachname"

# -- Basis-Gruppen -------------------------------------------------------

dn: CN=Engineers,OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: group
cn: Engineers
sAMAccountName: Engineers
description: Alle Engineers
groupType: -2147483646
member: CN=Patrick Blattner,OU=Users,OU=Dev,${DOMAIN_DC}
member: CN=Max Tester,OU=Users,OU=Dev,${DOMAIN_DC}

dn: CN=Managers,OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: group
cn: Managers
sAMAccountName: Managers
description: Alle Manager
groupType: -2147483646
member: CN=Angela Mueller,OU=Users,OU=Dev,${DOMAIN_DC}

dn: CN=QA,OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: group
cn: QA
sAMAccountName: QA
description: QA Team
groupType: -2147483646
member: CN=Max Tester,OU=Users,OU=Dev,${DOMAIN_DC}

# -- Nested Group Beispiel ------------------------------------------------

dn: CN=AllStaff,OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: group
cn: AllStaff
sAMAccountName: AllStaff
description: Alle Mitarbeiter (nested: Engineers + Managers + QA)
groupType: -2147483646
member: CN=Engineers,OU=Groups,OU=Dev,${DOMAIN_DC}
member: CN=Managers,OU=Groups,OU=Dev,${DOMAIN_DC}
member: CN=QA,OU=Groups,OU=Dev,${DOMAIN_DC}

# -- App-Zugriff Gruppe ---------------------------------------------------

dn: CN=AppAccess,OU=Groups,OU=Dev,${DOMAIN_DC}
objectClass: top
objectClass: group
cn: AppAccess
sAMAccountName: AppAccess
description: Zugriff auf die Applikation
groupType: -2147483646
member: CN=Patrick Blattner,OU=Users,OU=Dev,${DOMAIN_DC}
member: CN=Angela Mueller,OU=Users,OU=Dev,${DOMAIN_DC}
LDIF

# ── run-seed.sh ──────────────────────────────────────────────────────────────

cat > "${DEPLOY_DIR}/ldif/run-seed.sh" <<'SEEDSCRIPT'
#!/bin/bash
# run-seed.sh – wartet auf Samba AD und importiert Testdaten
# Nutzt samba-tool fuer User (Passwort-Handling) und ldapadd fuer OUs/Gruppen

LDAP_URI="ldap://${LDAP_HOST}"
BIND_DN="CN=Administrator,CN=Users,__DOMAIN_DC__"
BIND_PW="${LDAP_ADMIN_PASSWORD}"
USER_PW="Test1234!"

echo "Warte auf Samba AD unter ${LDAP_HOST}..."
until ldapsearch -x -H "${LDAP_URI}" \
    -D "${BIND_DN}" -w "${BIND_PW}" \
    -b "__DOMAIN_DC__" "(objectClass=domain)" > /dev/null 2>&1; do
  echo "   ... noch nicht bereit, warte 10s"
  sleep 10
done

echo "Samba AD ist erreichbar - starte Seed"

# Bereits importiert? Pruefen ob OU=Dev schon existiert
EXISTING=$(ldapsearch -x -H "${LDAP_URI}" \
  -D "${BIND_DN}" -w "${BIND_PW}" \
  -b "__DOMAIN_DC__" "(ou=Dev)" dn 2>/dev/null | grep "dn:" | wc -l)

if [ "${EXISTING}" -gt "0" ]; then
  echo "Testdaten bereits vorhanden - Seed wird uebersprungen"
  exit 0
fi

echo "Importiere OUs..."
ldapadd -x -H "${LDAP_URI}" \
  -D "${BIND_DN}" -w "${BIND_PW}" \
  -f /seed/structure.ldif && echo "OUs importiert"

echo ""
echo "Erstelle User via samba-tool..."

# patrick.blattner
samba-tool user create patrick.blattner "${USER_PW}" \
  --given-name="Patrick" --surname="Blattner" \
  --mail-address="patrick.blattner@__REALM_LOWER__" \
  --userou="OU=Users,OU=Dev" \
  -H "${LDAP_URI}" -U Administrator --password="${BIND_PW}"
echo "  patrick.blattner erstellt"

ldapmodify -x -H "${LDAP_URI}" -D "${BIND_DN}" -w "${BIND_PW}" <<LDIF
dn: CN=Patrick Blattner,OU=Users,OU=Dev,__DOMAIN_DC__
changetype: modify
replace: displayName
displayName: Patrick Blattner
-
add: department
department: Engineering
-
add: title
title: Systems Engineer
-
add: telephoneNumber
telephoneNumber: +41 71 123 45 67
LDIF
echo "  patrick.blattner Attribute gesetzt"

# angela.mueller
samba-tool user create angela.mueller "${USER_PW}" \
  --given-name="Angela" --surname="Mueller" \
  --mail-address="angela.mueller@__REALM_LOWER__" \
  --userou="OU=Users,OU=Dev" \
  -H "${LDAP_URI}" -U Administrator --password="${BIND_PW}"
echo "  angela.mueller erstellt"

ldapmodify -x -H "${LDAP_URI}" -D "${BIND_DN}" -w "${BIND_PW}" <<LDIF
dn: CN=Angela Mueller,OU=Users,OU=Dev,__DOMAIN_DC__
changetype: modify
replace: displayName
displayName: Angela Mueller
-
add: department
department: Management
-
add: title
title: Project Manager
-
add: telephoneNumber
telephoneNumber: +41 71 123 45 68
LDIF
echo "  angela.mueller Attribute gesetzt"

# max.tester
samba-tool user create max.tester "${USER_PW}" \
  --given-name="Max" --surname="Tester" \
  --mail-address="max.tester@__REALM_LOWER__" \
  --userou="OU=Users,OU=Dev" \
  -H "${LDAP_URI}" -U Administrator --password="${BIND_PW}"
echo "  max.tester erstellt"

ldapmodify -x -H "${LDAP_URI}" -D "${BIND_DN}" -w "${BIND_PW}" <<LDIF
dn: CN=Max Tester,OU=Users,OU=Dev,__DOMAIN_DC__
changetype: modify
replace: displayName
displayName: Max Tester
-
add: department
department: QA
-
add: title
title: QA Engineer
LDIF
echo "  max.tester Attribute gesetzt"

# svc.app (Service Account)
samba-tool user create svc.app "${USER_PW}" \
  --given-name="Service" --surname="App" \
  --userou="OU=ServiceAccounts,OU=Dev" \
  -H "${LDAP_URI}" -U Administrator --password="${BIND_PW}"
echo "  svc.app erstellt"

ldapmodify -x -H "${LDAP_URI}" -D "${BIND_DN}" -w "${BIND_PW}" <<LDIF
dn: CN=Service App,OU=ServiceAccounts,OU=Dev,__DOMAIN_DC__
changetype: modify
replace: displayName
displayName: Service App Account
-
add: description
description: Service Account fuer LDAP-Binds der Applikation
LDIF
echo "  svc.app Attribute gesetzt"

echo ""
echo "Importiere Gruppen..."
ldapadd -x -H "${LDAP_URI}" \
  -D "${BIND_DN}" -w "${BIND_PW}" \
  -f /seed/groups.ldif && echo "Gruppen importiert"

echo ""
echo "Seed abgeschlossen!"
echo ""
echo "Bind DN:  ${BIND_DN}"
echo "Password: ${BIND_PW}"
echo "Base DN:  __DOMAIN_DC__"
SEEDSCRIPT

# Replace placeholders in run-seed.sh
REALM_LOWER="${REALM,,}"
sed -i '' "s|__DOMAIN_DC__|${DOMAIN_DC}|g" "${DEPLOY_DIR}/ldif/run-seed.sh"
sed -i '' "s|__REALM_LOWER__|${REALM_LOWER}|g" "${DEPLOY_DIR}/ldif/run-seed.sh"
chmod +x "${DEPLOY_DIR}/ldif/run-seed.sh"

# ── Save config for teardown/re-seed ────────────────────────────────────────

cat > "${DEPLOY_DIR}/.env" <<ENV
DOMAIN_FQDN=${DOMAIN_FQDN}
REALM=${REALM}
NETBIOS=${NETBIOS}
DOMAIN_DC=${DOMAIN_DC}
ADMIN_PASS=${ADMIN_PASS}
BIND_IP=${BIND_IP}
LDAP_PORT=${LDAP_PORT}
LDAPS_PORT=${LDAPS_PORT}
PLA_PORT=${PLA_PORT}
SUBNET=${SUBNET}
SAMBA_IP=${SAMBA_IP}
ENV

ok "All files generated in ${DEPLOY_DIR}/"

# ── Start the stack ──────────────────────────────────────────────────────────

info "Starting Samba AD DC..."
cd "${DEPLOY_DIR}"
docker compose up -d samba-ad

info "Waiting for Samba AD to become healthy (this takes ~60-90s on first run)..."
RETRIES=0
MAX_RETRIES=30
until [ "$(docker inspect samba-ad --format '{{.State.Health.Status}}' 2>/dev/null)" = "healthy" ]; do
  RETRIES=$((RETRIES + 1))
  if [ "${RETRIES}" -ge "${MAX_RETRIES}" ]; then
    error "Samba AD did not become healthy after ${MAX_RETRIES} attempts. Check: docker logs samba-ad"
  fi
  sleep 5
done
ok "Samba AD is healthy"

info "Starting phpLDAPadmin..."
docker compose up -d phpldapadmin
ok "phpLDAPadmin started"

if [[ "${INSTALL_SEED}" =~ ^[Yy]$ ]]; then
  info "Running seed (creating test users and groups)..."
  docker compose --profile seed up -d ldap-seed

  # Wait for seed to complete
  RETRIES=0
  until [ "$(docker inspect ldap-seed --format '{{.State.Status}}' 2>/dev/null)" = "exited" ]; do
    RETRIES=$((RETRIES + 1))
    if [ "${RETRIES}" -ge 60 ]; then
      warn "Seed container is still running after 60 attempts."
      break
    fi
    sleep 3
  done

  SEED_EXIT=$(docker inspect ldap-seed --format '{{.State.ExitCode}}' 2>/dev/null)
  if [ "${SEED_EXIT}" = "0" ]; then
    ok "Seed completed successfully"
  else
    warn "Seed exited with code ${SEED_EXIT}. Check: docker logs ldap-seed"
  fi
fi

# ── Verify ───────────────────────────────────────────────────────────────────

info "Verifying LDAP connectivity..."
if docker exec samba-ad samba-tool user list >/dev/null 2>&1; then
  ok "LDAP is working"
else
  warn "Could not verify LDAP. Check: docker logs samba-ad"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  LDAP URL:        ldap://${BIND_IP}:${LDAP_PORT}"
echo "  LDAPS URL:       ldaps://${BIND_IP}:${LDAPS_PORT}"
echo "  phpLDAPadmin:    http://${BIND_IP}:${PLA_PORT}"
echo ""
echo "  Bind DN:         CN=Administrator,CN=Users,${DOMAIN_DC}"
echo "  Admin Password:  (as configured)"
echo "  Base DN:         ${DOMAIN_DC}"
echo ""

if [[ "${INSTALL_SEED}" =~ ^[Yy]$ ]]; then
  echo "  Test users (password: Test1234!):"
  echo "    - patrick.blattner  (Engineering)"
  echo "    - angela.mueller    (Management)"
  echo "    - max.tester        (QA)"
  echo "    - svc.app           (Service Account)"
  echo ""
  echo "  Groups:"
  echo "    - Engineers       (patrick.blattner, max.tester)"
  echo "    - Managers        (angela.mueller)"
  echo "    - QA              (max.tester)"
  echo "    - AllStaff        (nested: Engineers + Managers + QA)"
  echo "    - AppAccess       (patrick.blattner, angela.mueller)"
  echo ""
fi

echo "  Useful commands:"
echo "    docker exec samba-ad samba-tool user list"
echo "    docker exec samba-ad samba-tool group list"
echo "    docker exec samba-ad samba-tool group listmembers Engineers"
echo ""
echo "  Teardown:"
echo "    ./teardown.sh"
echo ""
