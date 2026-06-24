#!/bin/bash

echo "========================================================"
echo " WARNUNG: Alle Docker-Container & Images werden geloescht!"
echo "========================================================"
echo ""
read -p "Bist du dir absolut sicher? Alles wird unwiderruflich geloescht! [y/N]: " CONFIRM

# Ueberpruefen, ob die Antwort 'y' oder 'Y' ist. Falls nicht, Abbruch.
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Abgebrochen. Nichts wurde geloescht."
    exit 0
fi

echo ""
echo "Starte Bereinigung..."
echo "========================================================"

# 1. Alle laufenden Container stoppen
if [ "$(docker ps -q)" ]; then
    echo "-> Stoppe alle laufenden Container..."
    docker stop $(docker ps -q)
else
    echo "-> Keine laufenden Container gefunden."
fi

# 2. Alle Container loeschen (laufende und gestoppte)
if [ "$(docker ps -a -q)" ]; then
    echo "-> Loesche alle Container..."
    docker rm -f $(docker ps -a -q)
fi

# 3. Alle Docker-Images loeschen
if [ "$(docker images -q)" ]; then
    echo "-> Loesche alle Docker-Images..."
    docker rmi -f $(docker images -q)
fi

# 4. Radikaler System-Prune fuer Netzwerke und Volumes
echo "-> Bereinige restliche Fragmente (Volumes & Netzwerke)..."
docker system prune -a --volumes -f

echo "========================================================"
echo " Docker ist komplett leer geraeumt!"
echo "========================================================"