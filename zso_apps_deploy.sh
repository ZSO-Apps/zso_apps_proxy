#!/bin/bash

# Abbrechen bei Fehlern
#set -e

# 1. Zentrale .env Konfiguration laden
if [ -f ".env" ]; then
    echo "Lade Konfiguration aus .env Datei..."
    set -a
    source .env
    set +a
else
    echo "Fehler: Zentrale .env Datei im aktuellen Verzeichnis nicht gefunden!"
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# ==============================================================================
# ENGINE DETECTION & INSTALLATION (Docker mit Fallback auf Podman)
# ==============================================================================
echo "Prüfe Container-Engine Verfügbarkeit..."

USE_PODMAN=false

if command -v dnf &> /dev/null; then
    IS_RHEL=true
    
    echo "Versuche Docker über DNF zu installieren..."
    if dnf install -y docker docker-compose-plugin 2>/dev/null; then
        echo "Docker erfolgreich installiert."
    else
        echo "Docker-Repository nicht verfügbar. Weiche auf natives Podman aus..."
        USE_PODMAN=true
        # podman-docker stellt das 'docker'-Kommando bereit
        # podman-plugins wird für erweiterte Netzwerke benötigt
        dnf install -y podman podman-docker python3-pip
		# podman-compose global via pip installieren
		pip3 install --upgrade pip
		pip3 install podman-compose

		# Einen Symlink setzen, damit das System "docker-compose" und "podman-compose" im PATH findet
		ln -sf /usr/local/bin/podman-compose /usr/bin/podman-compose
		ln -sf /usr/local/bin/podman-compose /usr/bin/docker-compose
		touch /etc/containers/nodocker
    fi
elif command -v apt-get &> /dev/null; then
    IS_RHEL=false
    apt-get update
    apt-get install -y git docker.io docker-compose-v2
else
    echo "Fehler: Nicht unterstützte Distribution!"
    exit 1
fi

# Dienste starten & konfigurieren
if [ "$USE_PODMAN" = true ]; then
    echo "Konfiguriere Podman-Dienst und Docker-API-Emulation..."
    systemctl enable --now podman.socket
    
	mkdir -p /etc/containers
    cat <<EOF > /etc/containers/registries.conf
# Global generische Registry-Konfiguration für automatische Deployments
unqualified-search-registries = ['docker.io']

# Verhindert, dass Podman bei nicht auffindbaren Images interaktiv nachfragt
short-name-mode = "enforcing"
EOF
	
    # Podman benötigt diesen Symlink, damit Compose den Socket unter /var/run findet
    if [ ! -S "/var/run/docker.sock" ]; then
        ln -sf /run/podman/podman.sock /var/run/docker.sock
    fi
else
    echo "Konfiguriere Docker-Dienst..."
    systemctl start docker
    systemctl enable docker
fi

# SELinux Berechtigungen (Nur für RHEL-Systeme relevant)
if [ "$IS_RHEL" = true ]; then
    echo "Konfiguriere SELinux-Booleans..."
    setsebool -P container_manage_cgroup on || true
    
    if [ "$USE_PODMAN" = true ]; then
        # Podman benötigt spezifische Rechte, um den emulierten Socket freizugeben
        setsebool -P container_run_labels on || true
    else
        dnf install -y policycoreutils-python-utils
        semanage fcontext -a -t container_runtime_tmp_t "/run/docker.sock" 2>/dev/null || true
        restorecon -v /run/docker.sock || true
    fi
fi

# Let's Encrypt Ordner und Rechte vorbereiten
mkdir -p ./letsencrypt
touch ./letsencrypt/acme.json
chmod 600 ./letsencrypt/acme.json
chown -R 65532:65532 ./letsencrypt



# ==============================================================================
# CENTRAL TRAEFIK PROXY
# ==============================================================================
if [ "$SETUP_TRAEFIK" = "true" ]; then
    echo "========================================================"
    echo "Richte zentralen Traefik Proxy ein..."
    echo "========================================================"
    PROXY_APP_PATH=$SCRIPT_DIR
	
	# Gemeinsames Docker-Netzwerk anlegen
	if ! docker network inspect proxy-network >/dev/null 2>&1; then
		docker network create proxy-network
	fi
		
	# GID direkt vom Socket lesen (Verhindert leere Variablen durch Timing/NSS-Bugs)
    if [ -S "/run/docker.sock" ]; then
        CURRENT_DOCKER_GID=$(stat -c '%g' /run/docker.sock)
    elif [ -S "/var/run/docker.sock" ]; then
        CURRENT_DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    else
        CURRENT_DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "993")
    fi
    
    echo "Nutze Docker Gruppen-ID (GID): $CURRENT_DOCKER_GID"
    
    # Direkt für Docker Compose exportieren (Arbeitsspeicher)
    export DOCKER_GID=$CURRENT_DOCKER_GID
    
    # In die lokale .env schreiben/aktualisieren
    if grep -q "^DOCKER_GID=" .env; then
        sed -i "s|^DOCKER_GID=.*|DOCKER_GID=${CURRENT_DOCKER_GID}|" .env
    else
        echo "DOCKER_GID=${CURRENT_DOCKER_GID}" >> .env
    fi
	
    docker compose up -d
    cd - > /dev/null
else
    echo "Traefik Proxy Setup ist deaktiviert. Überspringe..."
fi


# ==============================================================================
# WEB APP 1: PWA APP
# ==============================================================================
if [ "$SETUP_PWA" = "true" ]; then
    echo "========================================================"
    echo "Richte PWA ein..."
    echo "========================================================"

    if [ ! -d "$PWA_APP_PATH" ]; then
        git clone $PWA_GIT $PWA_APP_PATH
    fi

    cd $PWA_APP_PATH

    touch .env

    if grep -q "^APP_DOMAIN=" .env; then
        sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=${PWA_DOMAIN}|" .env
    else
        echo "APP_DOMAIN=${PWA_DOMAIN}" >> .env
    fi
    echo "PWA APP_DOMAIN auf '${PWA_DOMAIN}' konfiguriert."

    mkdir -p data
    chmod 777 data

    docker compose build
    docker compose run --rm pwa-app npm run seed-users

    docker compose up -d
    cd - > /dev/null
else
    echo "PWA App Setup ist deaktiviert. Überspringe..."
fi


# ==============================================================================
# WEB APP 2: Incident Manager
# ==============================================================================
if [ "$SETUP_INCIDENT_MANAGER" = "true" ]; then
    echo "========================================================"
    echo "Richte Incident Manager ein..."
    echo "========================================================"

    if [ ! -d "$IM_APP_PATH" ]; then
        git clone $IM_GIT $IM_APP_PATH
    fi

    cd $IM_APP_PATH
	chmod +x $IM_APP_PATH/backend/gradlew

    if [ ! -f .env ]; then
        echo "Erstelle .env aus .env.dist..."
        cp .env.dist .env
    fi

    if grep -q "^APP_DOMAIN=" .env; then
        sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=${IM_DOMAIN}|" .env
    else
        echo "APP_DOMAIN=${IM_DOMAIN}" >> .env
    fi
	
	if [ "$OVERWRITE_DOCKER_COMPOSE" = "true" ]; then
        if [ -f "$SCRIPT_DIR/docker-compose-im.yml" ]; then
            echo "Überschreibe docker-compose.yml im Incident Manager mit docker-compose-im.yml..."
            cp "$SCRIPT_DIR/docker-compose-im.yml" "$IM_APP_PATH/docker-compose.yml"
        else
            echo "Warnung: '$SCRIPT_DIR/docker-compose-im.yml' nicht gefunden! Standard-Datei wird verwendet."
        fi
    fi

    if ! grep -q "^RFO_JWT_SECRET=" .env || [ -z "$(grep "^RFO_JWT_SECRET=" .env | cut -d'=' -f2)" ]; then
        JWT_SECRET=$(openssl rand -hex 32)
        if grep -q "^RFO_JWT_SECRET=" .env; then
            sed -i "s|^RFO_JWT_SECRET=.*|RFO_JWT_SECRET=${JWT_SECRET}|" .env
        else
            echo "RFO_JWT_SECRET=${JWT_SECRET}" >> .env
        fi
        echo "JWT Secret wurde generiert."
    fi

    echo "Installiere Frontend-Abhängigkeiten über Docker..."
    docker compose run --rm --no-deps frontend sh -c "npm install"

    echo "Starte IM Backend (pre-import)"
    docker compose up -d backend

    echo "Warte 10 Sekunden, bis die Datenbank hochgefahren ist..."
    sleep 10

    case "$IM_DB_DATA_CHOICE" in
        minimal)
            echo "Lade minimale Daten (Admin & Agent)..."
            docker compose exec -T database sh -c 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < /data-minimal.sql'
            ;;
        sample)
            echo "Lade vollständige Sample-Daten..."
            docker compose exec -T database sh -c 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < /data-sample.sql'
            ;;
        *)
            echo "Überspringe das Laden von Demodaten."
            ;;
    esac

    echo "Starte Incident Manager Container..."
    docker compose up -d

    echo "Setup für Incident Manager erfolgreich abgeschlossen!"
    cd - > /dev/null
else
    echo "Incident Manager Setup ist deaktiviert. Überspringe..."
fi

echo "========================================================"
echo " Gesamtes Setup abgeschlossen!"
echo "========================================================"