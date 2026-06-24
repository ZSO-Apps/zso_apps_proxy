#!/usr/bin/env bash
set -e

CMD=$1
APPNAME=offlinekarte

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
	mkdir -p $OFFLINEKARTE_PATH
	cd $OFFLINEKARTE_PATH
	git clone $OFFLINEKARTE_GIT -b $OFFLINEKARTE_BRANCH $OFFLINEKARTE_PATH
	git submodule update --init --recursive

	bash $OFFLINEKARTE_PATH/zskarte.sh init

	echo "Running init for zskarte submodule"
	
	if [ ! -f "$ZSKARTE_PATH/packages/server/.env" ]; then
		cp "$ZSKARTE_PATH/packages/server/.env.example" "$ZSKARTE_PATH/packages/server/.env"
	fi
		
	mkdir -p $ZSKARTE_PATH/data/postgresql
	sudo chown -R 1001:1001 $ZSKARTE_PATH/data/postgresql
	mkdir -p $ZSKARTE_PATH/data/pgadmin
	sudo chown -R 5050:5050 $ZSKARTE_PATH/data/pgadmin

	if [ -f "$ZSKARTE_ENV_TS" ]; then
		echo "Passe TypeScript Environments an..."
		
		# Protokoll dynamisch anhand der TLS-Variable bestimmen
		if [ "$ZSKARTE_ENABLE_TLS" = "true" ]; then
			PROTO="https"
			echo "TLS ist aktiviert -> Nutze https://"
		else
			PROTO="http"
			echo "TLS ist deaktiviert -> Nutze http://"
		fi

		sed -i "s|apiUrl:.*|apiUrl: '${PROTO}://${ZSKARTE_API_DOMAIN}${ZSKARTE_API_PATH}',|" "$ZSKARTE_ENV_TS"
		sed -i "s|tileUrl:.*|tileUrl: '${PROTO}://${OFFLINEKARTE_TILESERVER_DOMAIN}${OFFLINEKARTE_TILESERVER_PATH}',|" "$ZSKARTE_ENV_TS"
		sed -i "s|searchUrl:.*|searchUrl: '${PROTO}://${OFFLINEKARTE_SEARCHSERVER_DOMAIN}${OFFLINEKARTE_SEARCHSERVER_PATH}',|" "$ZSKARTE_ENV_TS"
		sed -i "s|searchLabel:.*|searchLabel: '${ZSKARTE_SEARCH_LABEL}',|" "$ZSKARTE_ENV_TS"
		
		echo "TypeScript Environments erfolgreich aktualisiert."
		echo "----------------------------------------"
		grep -E "apiUrl|tileUrl|searchUrl|searchLabel" "$ZSKARTE_ENV_TS"
		echo "----------------------------------------"
	else
		echo "Warnung: $ZSKARTE_ENV_TS nicht gefunden. ueberspringe Anpassung."
	fi
	echo "----------------------------------------"
	echo "offlinekarte Konfiguration (inkl. override)"
	echo "----------------------------------------"
	docker compose -f $OFFLINEKARTE_PATH/docker-compose.yml -f $(pwd)/docker-compose-offlinekarte.yml config
	echo "----------------------------------------"
	echo "zskarte Konfiguration (inkl. override)"
	echo "----------------------------------------"
	docker compose -f $ZSKARTE_PATH/docker-compose.yml -f $(pwd)/docker-compose-zskarte.yml config
	echo "----------------------------------------"
	
    echo "${APPNAME} complete."

elif [ "$CMD" = "start" ]; then
    echo "Starting ${APPNAME}..."

    docker compose up -d -f $OFFLINEKARTE_PATH/docker-compose.yml -f $(pwd)/docker-compose-offlinekarte.yml
	docker compose up -d -f $ZSKARTE_PATH/docker-compose.yml -f $(pwd)/docker-compose-zskarte.yml

    echo "${APPNAME} started."

elif [ "$CMD" = "start" ]; then
    echo "Updating ${APPNAME}..."

    # to be build

    echo "${APPNAME} updated."
else
    echo "Usage: ./offlinekarte.sh {init|update|start}"
    exit 1
fi