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


# Precheck
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker läuft aktuell nicht!" >&2
    exit 1
fi

# Let's Encrypt Ordner und Rechte vorbereiten
mkdir -p ./certs
touch ./certs/acme.json
chmod 600 ./certs/acme.json
chown -R 65532:65532 ./certs

# ==============================================================================
# CENTRAL TRAEFIK PROXY
# ==============================================================================
echo "========================================================"
echo "Richte zentralen Traefik Proxy ein..."
echo "========================================================"

if [ "$SETUP_TRAEFIK" = "true" ]; then
    bash $SCRIPT_DIR/zso_traefik.sh init
else
    echo "Traefik Proxy Setup ist deaktiviert. ueberspringe..."
fi

echo "========================================================"

# ==============================================================================
# WEB APP 1: PWA APP
# ==============================================================================

echo "========================================================"
echo "Richte PWA ein..."
echo "========================================================"

if [ "$SETUP_PWA" = "true" ]; then
	bash $SCRIPT_DIR/zso_pwa_app.sh init
else
    echo "PWA App Setup ist deaktiviert. ueberspringe..."
fi
echo "========================================================"

# ==============================================================================
# WEB APP 2: Incident Manager
# ==============================================================================
echo "========================================================"
echo "Richte Incident Manager ein..."
echo "========================================================"
	
if [ "$SETUP_INCIDENT_MANAGER" = "true" ]; then
    if [ ! -d "$IM_APP_PATH" ]; then
        git clone $IM_GIT $IM_APP_PATH
    fi

    cd $IM_APP_PATH
	chmod +x $IM_APP_PATH/backend/gradlew

	# 1. .env kopieren, falls nicht vorhanden
	if [ ! -f .env ]; then
		echo "Erstelle .env aus .env.dist..."
		cp .env.dist .env
	fi

	# Sicherstellen, dass .env mit einer echten neuen Zeile endet (POSIX-konform & portabel)
	[ -n "$(tail -c1 .env)" ] && echo "" >> .env

	# 2. APP_DOMAIN setzen / ersetzen
	if grep -q "^APP_DOMAIN[[:space:]]*=" .env; then
		# Nutzt , statt | als Trenner, falls in der Domain ein | vorkommen sollte
		sed -i.bak "s,^APP_DOMAIN[[:space:]]*=.*,APP_DOMAIN=${IM_DOMAIN}," .env && rm .env.bak
	else
		echo "APP_DOMAIN=${IM_DOMAIN}" >> .env
	fi

	# Sucht nach RFO_JWT_SECRET und schaut, ob der Wert "secret-key" enthält oder leer ist
	if grep -q "^RFO_JWT_SECRET[[:space:]]*=" .env && ! grep -q "secret-key" .env; then
		echo "Ein echtes RFO_JWT_SECRET ist bereits gesetzt. Überspringe."
	else
		echo "Generiere echtes JWT Secret..."
		JWT_SECRET=$(openssl rand -hex 32)
		
		if grep -q "^RFO_JWT_SECRET[[:space:]]*=" .env; then
			# Ersetzt die KOMPLETTE Zeile, um den Dummy-Wert und den Kommentar zu löschen
			sed -i.bak "s,^RFO_JWT_SECRET[[:space:]]*=.*,RFO_JWT_SECRET=${JWT_SECRET}," .env && rm .env.bak
		else
			echo "RFO_JWT_SECRET=${JWT_SECRET}" >> .env
		fi
		echo "RFO_JWT_SECRET wurde sauber neu gesetzt."
	fi
	
	if [ "$OVERWRITE_DOCKER_COMPOSE" = "true" ]; then
        if [ -f "$SCRIPT_DIR/docker-compose-im.yml" ]; then
            echo "ueberschreibe docker-compose.yml im Incident Manager mit docker-compose-im.yml..."
            cp "$SCRIPT_DIR/docker-compose-im.yml" "$IM_APP_PATH/docker-compose.yml"
        else
            echo "Warnung: '$SCRIPT_DIR/docker-compose-im.yml' nicht gefunden! Standard-Datei wird verwendet."
        fi
    fi

    echo "Installiere Frontend-Abhaengigkeiten ueber Docker..."
    docker compose run --rm --no-deps frontend sh -c "npm install"

    echo "Starte IM Backend (pre-import)"
    docker compose --env-file .env --ansi never up backend -d --quiet-pull

    echo "Warte 10 Sekunden, bis die Datenbank hochgefahren ist..."
    sleep 10

    case "$IM_DB_DATA_CHOICE" in
        minimal)
            echo "Lade minimale Daten (Admin & Agent)..."
           docker compose exec -T database sh -c 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < /data-minimal.sql'
            ;;
        sample)
            echo "Lade vollstaendige Sample-Daten..."
           docker compose exec -T database sh -c 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < /data-sample.sql'
            ;;
        *)
            echo "ueberspringe das Laden von Demodaten."
            ;;
    esac

    echo "Starte Incident Manager Container..."
    docker compose --env-file .env --ansi never up -d --quiet-pull
	
    echo "Setup fuer Incident Manager erfolgreich abgeschlossen!"
    cd - > /dev/null
else
    echo "Incident Manager Setup ist deaktiviert. ueberspringe..."
fi

echo "========================================================"

# ==============================================================================
# WEB APP 3: ZS Karte / offlinekarte
# ==============================================================================
if [ "$SETUP_ZSK" = "true" ]; then
	bash $SCRIPT_DIR/offlinekarte.sh init
else
    echo "Zivilschutz Karte / Offlinekarte Setup ist deaktiviert. ueberspringe..."
fi
echo "========================================================"

echo "========================================================"
echo " Gesamtes Setup abgeschlossen!"
echo "========================================================"