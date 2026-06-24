# ZSO Apps Setup & Proxy 
Setup Scripte für die Einrichtung des ZSO Apps Proxy (Traefik) und der Grundeinrichtung von ZSO Apps (ZSO App, Incident-Manager und Offlinekarte)

## 1. Vorbereitung
```
git clone https://github.com/ZSO-Apps/zso_apps_proxy.git
cd zso_apps_proxy
cp .env.example .env
```
Anschliessend die gewünschten Werte in der .env-Datei anpassen.

## 2. Docker Installation
Wichtig: podman Installationen können zu Problemen führen, falls möglich die Pakete direkt von Docker verwenden!
### RedHat based (Rocky, Fedora, RHEL ...)
```
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin openssl
```
### Debian based (Ubuntu, Debian ...)
```
apt-get install -y git docker.io docker-compose-v2 openssl
```
### Andere Systeme
Andere Systeme wie macOS, Suse, Synology, Windows etc. wurden nicht getestet. 

## 3. Systemeinstellungen

SELinux Konfiguration für RHEL-basierte Systeme:
```
setsebool -P container_manage_cgroup on || true
dnf install -y policycoreutils-python-utils
semanage fcontext -a -t container_runtime_tmp_t "/run/docker.sock" 2>/dev/null || true
restorecon -v /run/docker.sock || true
```
## 4. Docker Prozess starten & aktivieren
```
systemctl start docker
systemctl enable docker
```

## 5. Netzwerk und DNS Konfiguration
### Netzwerk
Falls die Apps von ausserhalb des ZS-Standortes genutzt werden sollen, so müssen hierfür Portweiterleitungen und/oder Firewall-Regeln erstellt werden.
Beim Einsatz von Traefik reicht es, wenn von Extern die Ports 80 und 443 auf die Ports von Traefik (Standardmässig 18080 und 18443) weitergeleitet werden.

### DNS
Traefik erstellt und verwaltet standardmässig auch Let's Encrypt Zertifikate. Beim Einsatz von statischen IP Adressen können die Einträge manuell der ZS-eigenen Domain eingerichtet werden. 
Dynamische IP-Adressen erfordern einen Zwischenschritt über einen DynDNS Anbieter. Die DynDNS-Adresse kann dann entweder direkt genutzt oder als CNAME bei der ZS-eigenen Domain eingerichtet werden. 
#### Beispiel statische Adresse:
app.zso.example.org A 1.2.3.4
#### Beispiel dynamische Adresse:
app.zso.example.org CNAME zso.dyndns-example.org


## 5. Apps initialisieren
Die ZSO Apps können grundsätzlich ohne Traefik (zso_traefik.sh) genutzt werden. Dies empfiehlt sich vor allem, bei Umgebungen mit vorhandenem Proxy oder wo keine HTTPS-Verbindung benötigt wird (z.B. KP intern).
Traefik wird in diesem Setup als Proxy vor die Docker Container gestellt.
Beispiel:
offlinekarte mit der Domain maps.zso.example.org 
incident-manager erhält die Domain im.zso.example.org
```
./zso_traefik.sh init
```


## X. Troubleshooting
### Portkonflikte
Bei Portkonflikten müssen die entsprechenden _PORT-Variabeln in der .env-Datei angepasst werden.
