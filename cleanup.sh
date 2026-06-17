#!/bin/bash

echo "========================================================"
echo " WARNUNG: Alle Docker-Container werden gestoppt & gelöt!"
echo "========================================================"

# 1. Alle laufenden Container stoppen
if [ "$(docker ps -q)" ]; then
    echo "-> Stoppe alle laufenden Container..."
    docker stop $(docker ps -q)
else
    echo "-> Keine laufenden Container gefunden."
fi

# 2. Alle Container löen (laufende und gestoppte)
if [ "$(docker ps -a -q)" ]; then
    echo "-> Löe alle Container..."
    docker rm -f $(docker ps -a -q)
fi

# 3. Alle Docker-Images löen
if [ "$(docker images -q)" ]; then
    echo "-> Löe alle Docker-Images..."
    docker rmi -f $(docker images -q)
fi

# 4. Radikaler System-Prune füzwerke und Volumes
echo "-> Bereinige restliche Fragmente (Volumes & Netzwerke)..."
docker system prune -a --volumes -f

echo "========================================================"
echo " Docker ist komplett leer gerät!"
echo "========================================================"
