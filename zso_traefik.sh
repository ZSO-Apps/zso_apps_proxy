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
		echo "Versuche Docker ueber DNF zu installieren..."
		if dnf install -y docker docker-compose-plugin openssl 2>/dev/null; then
			echo "Docker erfolgreich installiert."
		else
			echo "Docker-Repository nicht verfuegbar. Weiche auf Docker Repo aus"
			sudo dnf -y install dnf-plugins-core
			sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
			sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin openssl
		fi
	elif command -v apt-get &> /dev/null; then
		IS_RHEL=false
		echo "Debian based system erkannt!"
		apt-get update
		apt-get install -y git docker.io docker-compose-v2 openssl
	elif [ -f /etc/synoinfo.conf ]; then
		IS_RHEL=false
		echo "Synology NAS erkannt. ueberpruefe installierte Pakete..."
		
		# Git und OpenSSL koennen via SynoCommunity (opkg) oder oft direkt genutzt werden.
		# Docker/Docker-Compose sollte ueber das DSM Paketzentrum installiert sein.
		if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
			echo "Fehler: Docker oder docker compose ist nicht auf der Synology installiert!"
			echo "Bitte installiere das 'Container Manager' (DSM 7.2+) oder 'Docker' Paket ueber das DSM Paketzentrum."
			exit 1
		fi
		#fallback fuer synology NAS ohne seccomp
		echo "Docker und docker compose sind auf der Synology bereit."
	else
		echo "Fehler: Nicht unterstuetzte Distribution!"
		exit 1
	fi

	echo "Konfiguriere Docker-Dienst..."
	systemctl start docker
	systemctl enable docker

	# SELinux Berechtigungen (Nur fuer RHEL-Systeme relevant)
	if [ "$IS_RHEL" = true ]; then
		echo "Konfiguriere SELinux-Booleans..."
		setsebool -P container_manage_cgroup on || true
		
		dnf install -y policycoreutils-python-utils
		semanage fcontext -a -t container_runtime_tmp_t "/run/docker.sock" 2>/dev/null || true
		restorecon -v /run/docker.sock || true
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