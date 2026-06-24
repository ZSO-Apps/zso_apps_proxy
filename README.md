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



