# zso_apps_proxy
Setup Scripte für die Einrichtung des ZSO Apps Proxy (Traefik) und der Grundeinrichtung von ZSO Apps (ZSO App, Incident-Manager und Offlinekarte)

Starte mit:
git clone https://github.com/ZSO-Apps/zso_apps_proxy.git

cd zso_apps_proxy
cp .env.example .env


RedHat Based (dont use Podman!)
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin openssl

Debian based:
apt-get install -y git docker.io docker-compose-v2 openssl

Docker-Services müssen aktiviert sein:
	systemctl start docker
	systemctl enable docker



SELinux auf RHEL based:
setsebool -P container_manage_cgroup on || true

dnf install -y policycoreutils-python-utils
semanage fcontext -a -t container_runtime_tmp_t "/run/docker.sock" 2>/dev/null || true
restorecon -v /run/docker.sock || true
	