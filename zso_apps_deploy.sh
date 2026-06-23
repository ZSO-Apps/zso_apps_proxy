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

if ! docker buildx version > /dev/null 2>&1; then
    echo "Buildx nicht gefunden. Lade es herunter..."
    mkdir -p ~/.docker/cli-plugins
    curl -L $BUILDX_URL -o ~/.docker/cli-plugins/docker-buildx
    chmod +x ~/.docker/cli-plugins/docker-buildx
fi

# 2. Builder erstellen/aktivieren
if ! docker buildx inspect $BUILDER_NAME > /dev/null 2>&1; then
    echo "Erstelle neuen Builder: $BUILDER_NAME"
    docker buildx create --name $BUILDER_NAME --use
else
    echo "Verwende bestehenden Builder: $BUILDER_NAME"
    docker buildx use $BUILDER_NAME
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



# ==============================================================================
# CENTRAL TRAEFIK PROXY
# ==============================================================================
echo "========================================================"
echo "Richte zentralen Traefik Proxy ein..."
echo "========================================================"

if [ "$SETUP_TRAEFIK" = "true" ]; then
    PROXY_APP_PATH=$SCRIPT_DIR
	
	# Gemeinsames Docker-Netzwerk anlegen
	if ! docker network inspect proxy-network >/dev/null 2>&1; then
		docker network create proxy-network
	fi   
   
    docker compose --env-file .env --ansi never up -d --quiet-pull
    cd - > /dev/null
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

    docker compose --env-file .env --ansi never up -d --quiet-pull
    cd - > /dev/null
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

    if [ ! -f .env ]; then
        echo "Erstelle .env aus .env.dist..."
        cp .env.dist .env
    fi

# Sicherstellen, dass .env mit einer echten neuen Zeile endet (behebt das Aneinanderkleben)
    sed -i -e '$a\' .env

    # 1. APP_DOMAIN setzen / ersetzen
    if grep -q "^APP_DOMAIN=" .env; then
        sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=${IM_DOMAIN}|" .env
    else
        echo "APP_DOMAIN=${IM_DOMAIN}" >> .env
    fi

    # 2. RFO_JWT_SECRET generieren und IMMER sauber setzen
    JWT_SECRET=$(openssl rand -hex 32)
    if grep -q "^RFO_JWT_SECRET=" .env; then
        sed -i "s|^RFO_JWT_SECRET=.*|RFO_JWT_SECRET=${JWT_SECRET}|" .env
    else
        echo "RFO_JWT_SECRET=${JWT_SECRET}" >> .env
    fi
    echo "JWT Secret wurde neu gesetzt."
	
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
	echo "Konfiguriere ZS Karte / offlinekarte"
	
	mkdir -p $OFK_PATH
	cd $OFK_PATH
	git clone $OFK_GIT -b $OFK_BRANCH $OFK_PATH
	git submodule update --init --recursive #load also submodules
	
	if grep -q "^OFK_TILE_DOMAIN=" .env; then
        sed -i "s|^OFK_TILE_DOMAIN=.*|OFK_TILE_DOMAIN=${OFK_TILE_DOMAIN}|" .env
    else
        echo "OFK_TILE_DOMAIN=${OFK_TILE_DOMAIN}" >> .env
    fi

	if grep -q "^OFK_SEARCH_DOMAIN=" .env; then
        sed -i "s|^OFK_SEARCH_DOMAIN=.*|OFK_SEARCH_DOMAIN=${OFK_SEARCH_DOMAIN}|" .env
    else
        echo "OFK_SEARCH_DOMAIN=${OFK_SEARCH_DOMAIN}" >> .env
    fi		
	
	if grep -q "^TILESERVER_GL_ALLOWED_HOSTS=" .env; then
        sed -i "s|^TILESERVER_GL_ALLOWED_HOSTS=.*|TILESERVER_GL_ALLOWED_HOSTS=${OFK_TILE_DOMAIN}|" tileserver.env
    else
        echo "TILESERVER_GL_ALLOWED_HOSTS=${OFK_TILE_DOMAIN}" >> tileserver.env
    fi
	
	if [ "$OVERWRITE_DOCKER_COMPOSE" = "true" ]; then
        if [ -f "$SCRIPT_DIR/docker-compose-offlinekarte.yml" ]; then
            echo "ueberschreibe docker-compose.yml in ZS-Karte mit docker-compose-offlinekarte.yml..."
            cp "$SCRIPT_DIR/docker-compose-offlinekarte.yml" "$OFK_PATH/docker-compose.yml"
        else
            echo "Warnung: '$SCRIPT_DIR/docker-compose-offlinekarte.yml' nicht gefunden! Standard-Datei wird verwendet."
        fi
    fi
	
	# Starte offlinekarte (tileserver und searchserver)
	bash $OFK_PATH/zskarte.sh init
	bash $OFK_PATH/zskarte.sh start
	
	echo "init ZSKARTE"
	#### ZSKARTE
	
	if [ "$OVERWRITE_DOCKER_COMPOSE" = "true" ]; then
        if [ -f "$SCRIPT_DIR/docker-compose-zskarte.yml" ]; then
            echo "ueberschreibe docker-compose.yml in ZS-Karte mit docker-compose-zskarte.yml..."
            cp "$SCRIPT_DIR/docker-compose-zskarte.yml" "$ZSK_PATH/docker-compose.yml"
        else
            echo "Warnung: '$SCRIPT_DIR/docker-compose-zskarte.yml' nicht gefunden! Standard-Datei wird verwendet."
        fi
    fi
	
	# Create the data/postgresql folder
	cd $ZSK_PATH
	
	grep ZSK $SCRIPT_DIR/.env > $ZSK_PATH/.env
	
	cp $ZSK_PATH/packages/server/.env.example $ZSK_PATH/packages/server/.env
	
	mkdir -p $ZSK_PATH/data/postgresql
	# Add the UID 1001 (non-root user of postgresql) as the folder owner
	sudo chown -R 1001:1001 $ZSK_PATH/data/postgresql
	# Create the data/pgadmin folder
	mkdir -p $ZSK_PATH/data/pgadmin
	# Add the UID 5050 (non-root user of pgadmin) as the folder owner
	sudo chown -R 5050:5050 $ZSK_PATH/data/pgadmin
	
	#../zskarte/packages/app/src/environments/environment.prod.ts
	if [ -f "$ZSK_ENV_TS" ]; then
		echo "Passe TypeScript Environments an..."
		
		# Protokoll dynamisch anhand der TLS-Variable bestimmen
		if [ "$ZSK_ENABLE_TLS" = "true" ]; then
			PROTO="https"
			echo "TLS ist aktiviert -> Nutze https://"
		else
			PROTO="http"
			echo "TLS ist deaktiviert -> Nutze http://"
		fi

		sed -i "s|apiUrl:.*|apiUrl: '${PROTO}://${ZSK_API_DOMAIN}${ZSK_API_PATH}',|" "$ZSK_ENV_TS"
		sed -i "s|tileUrl:.*|tileUrl: '${PROTO}://${OFK_TILE_DOMAIN}${OFK_TILE_PATH}',|" "$ZSK_ENV_TS"
		sed -i "s|searchUrl:.*|searchUrl: '${PROTO}://${OFK_SEARCH_DOMAIN}${OFK_SEARCH_PATH}',|" "$ZSK_ENV_TS"
		sed -i "s|searchLabel:.*|searchLabel: '${ZSK_SEARCH_LABEL}',|" "$ZSK_ENV_TS"
		
		echo "TypeScript Environments erfolgreich aktualisiert."
		echo "----------------------------------------"
		grep -E "apiUrl|tileUrl|searchUrl|searchLabel" "$ZSK_ENV_TS"
		echo "----------------------------------------"
	else
		echo "Warnung: $ZSK_ENV_TS nicht gefunden. ueberspringe Anpassung."
	fi
	
	docker compose up -d --force-recreate

else
    echo "Zivilschutz Karte / Offlinekarte Setup ist deaktiviert. ueberspringe..."
fi
echo "========================================================"


echo "========================================================"
echo " Gesamtes Setup abgeschlossen!"
echo "========================================================"