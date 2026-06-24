#!/usr/bin/env bash

CMD=$1
APPNAME=PWA
SCRIPTDIR=$(pwd)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)


if [ -f ".env" ]; then
    echo "Lade Konfiguration aus .env Datei..."
    set -a
    source .env
    set +a
else
    echo "Error: Zentrale .env Datei im aktuellen Verzeichnis nicht gefunden!"
    exit 1
fi

# Precheck
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker läuft aktuell nicht!" >&2
    exit 1
fi

if [ "$CMD" = "init" ]; then
    echo "Initialize ${APPNAME}..."
	
	if [ ! -d "$PWA_APP_PATH" ]; then
        git clone $PWA_GIT $PWA_APP_PATH
    fi
	
	docker compose -f $PWA_APP_PATH/docker-compose.yml -f $SCRIPTDIR/docker-compose-pwa.yml --env-file $SCRIPTDIR/.env build --no-cache

    echo "${APPNAME} initialized."

elif [ "$CMD" = "start" ]; then
    echo "Starting ${APPNAME}..."
	docker compose -f $PWA_APP_PATH/docker-compose.yml -f $SCRIPTDIR/docker-compose-pwa.yml --env-file $SCRIPTDIR/.env up -d
	
    echo "${APPNAME} started."

elif [ "$CMD" = "stop" ]; then
    echo "Stopping ${APPNAME}..."
	docker compose -f $PWA_APP_PATH/docker-compose.yml -f $SCRIPTDIR/docker-compose-pwa.yml --env-file $SCRIPTDIR/.env stop

    echo "${APPNAME} stopped."
elif [ "$CMD" = "config" ]; then
    echo "Load config of ${APPNAME}..."
	
	echo "----------------------------------------"
	docker compose -f $PWA_APP_PATH/docker-compose.yml -f $SCRIPTDIR/docker-compose-pwa.yml --env-file $SCRIPTDIR/.env config
	echo "----------------------------------------"
else
    echo "Usage: ./zso_pwa_app.sh {start|stop|config}"
    exit 1
fi