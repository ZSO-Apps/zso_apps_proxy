#!/usr/bin/env bash

CMD=$1
APPNAME=zso_traefik
SCRIPTFOLDER=$(pwd)

if [ -f ".env" ]; then
    echo "Lade Konfiguration aus .env Datei..."
    set -a
    source .env
    set +a
else
    echo "Fehler: Zentrale .env Datei im aktuellen Verzeichnis nicht gefunden!"
    exit 1
fi

if [ "$CMD" = "init" ]; then
    echo "Running INIT workflow for ${APPNAME}..."

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
echo "Pruefe Container-Engine Verfuegbarkeit..."

	if command -v dnf &> /dev/null; then
		IS_RHEL=true
		echo "RHEL based system erkannt!"
	elif command -v apt-get &> /dev/null; then
		echo "Debian based system erkannt!"
	elif [ -f /etc/synoinfo.conf ]; then
		IS_RHEL=false
		echo "Synology NAS erkannt. Applikationen vermutlich nicht supportet..."
	else
		echo "Fehler: Vermutlich nicht unterstuetzte Distribution!"
		exit 1
	fi
	
	# Let's Encrypt Ordner und Rechte vorbereiten
	mkdir -p ./certs
	touch ./certs/acme.json
	chmod 600 ./certs/acme.json
	chown -R 65532:65532 ./certs


	if ! docker network inspect proxy-network >/dev/null 2>&1; then
		docker network create proxy-network
	fi   
   
	docker compose -f docker-compose-zsotraefik.yml --env-file .env --ansi never up -d --quiet-pull --build --force-recreate
	
    echo "${APPNAME} complete."

elif [ "$CMD" = "start" ]; then
    echo "Starting ${APPNAME}..."

	docker compose -f docker-compose-zsotraefik.yml --env-file .env --ansi never up -d --quiet-pull
	
    echo "${APPNAME} started."

elif [ "$CMD" = "update" ]; then
    echo "Updating ${APPNAME}..."

    # to be build

    echo "${APPNAME} updated."
elif [ "$CMD" = "config" ]; then
    echo "Load config of ${APPNAME}..."
	
	echo "----------------------------------------"
	docker compose -f docker-compose-zsotraefik.yml --env-file .env config
	echo "----------------------------------------"
else
    echo "Usage: ./zso_traefik.sh {init|update|start|config}"
    exit 1
fi