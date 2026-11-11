#!/usr/bin/env bash
# Docker Engine + Docker Desktop side by side, all bulky data on /home.
#   Engine data:   /home/docker (data-root) and /home/containerd (bind-mounted
#                  over /var/lib/containerd; Engine 29 stores images there).
#   Desktop VM:    ~/.docker/desktop/vms (already on /home).
# Switch: `docker context use default` (Engine) / `docker context use desktop-linux`.
# --desktop-settings   apply memory/CPU/swap/disk limits to Docker Desktop (run after
#                      Desktop has started once; it quits and restarts Desktop).
source "$(dirname "$0")/lib.sh"
owner_sudo "$@"
need_ubuntu_2604
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

if [[ " $* " == *" --desktop-settings "* ]]; then
  S="$HOME/.docker/desktop/settings-store.json"
  [[ -f "$S" ]] || die "start Docker Desktop once first ($S missing)"
  run systemctl --user stop docker-desktop
  run cp -a "$S" "$S.bak-$(date +%F)"
  # 10 GiB RAM, 12 of 16 CPUs (leave 4 for the desktop), 4 GiB swap, 128 GiB disk ceiling.
  run bash -c "jq '.MemoryMiB=10240 | .Cpus=12 | .SwapMiB=4096 | .DiskSizeMiB=131072' '$S' > '$S.tmp' && mv '$S.tmp' '$S'"
  run systemctl --user start docker-desktop
  jq '{MemoryMiB,Cpus,SwapMiB,DiskSizeMiB}' "$S"
  exit 0
fi

# 1. Storage on /home, set up BEFORE the first start of the Engine.
run sudo install -d -m 0710 /home/docker
run sudo install -d -m 0711 /home/containerd /var/lib/containerd
FSTAB_LINE="/home/containerd /var/lib/containerd none bind 0 0"
if ! grep -qF "$FSTAB_LINE" /etc/fstab; then
  if [[ -n "$(sudo ls -A /var/lib/containerd 2>/dev/null)" ]] && ! findmnt -rn /var/lib/containerd >/dev/null; then
    # Engine already ran once: move its data before the bind mount hides it.
    run sudo systemctl stop docker docker.socket containerd || true
    run sudo rsync -aHAX /var/lib/containerd/ /home/containerd/
    run sudo find /var/lib/containerd -mindepth 1 -delete
  fi
  run sudo bash -c "echo '$FSTAB_LINE' >> /etc/fstab"
  run sudo systemctl daemon-reload
fi
findmnt -rn /var/lib/containerd >/dev/null || run sudo mount /var/lib/containerd
sudo_write /etc/docker/daemon.json "$(cat "$REPO_DIR/config/docker-daemon.json")"

# 2. Engine from Docker's apt repo.
[[ -s /etc/apt/keyrings/docker.asc ]] || run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo_write /etc/apt/sources.list.d/docker.sources "Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $CODENAME
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc"

# 3. NVIDIA container toolkit repo.
NV_KEY=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
[[ -s "$NV_KEY" ]] || run bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor | sudo tee $NV_KEY >/dev/null"
[[ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]] ||
  run bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=$NV_KEY] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null"

run sudo apt-get update
run sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit
run sudo nvidia-ctk runtime configure --runtime=docker   # merges into daemon.json, keeps data-root
run sudo systemctl enable --now containerd docker
run sudo usermod -aG docker,kvm "$USER"

# 4. Docker Desktop (.deb; no apt repo, it updates itself from the app).
if ! dpkg -s docker-desktop >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  run curl -fL https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb -o "$tmp/docker-desktop-amd64.deb"
  run sudo apt-get install -y "$tmp/docker-desktop-amd64.deb"
  rm -rf "$tmp"
fi

# 5. Database images used by the projects (PostgreSQL runs only in containers).
run sudo docker pull postgres:16-alpine
run sudo docker pull redis:7-alpine

# Checks
rc=0
verify_rows docker containerd docker-compose nvidia-ctk docker-desktop || rc=1
[[ "$(sudo docker info -f '{{.DockerRootDir}}')" == /home/docker ]] || { warn "Engine data-root is not /home/docker"; rc=1; }
[[ "$(findmnt -rno SOURCE /var/lib/containerd)" == *"/home/containerd"* || "$(findmnt -rno SOURCE /var/lib/containerd)" == *"[/containerd]"* ]] ||
  { warn "/var/lib/containerd is not bind-mounted from /home/containerd"; rc=1; }
sudo docker run --rm --gpus all ubuntu nvidia-smi -L | grep -q 'RTX 3050' || { warn "GPU not visible in containers"; rc=1; }
cid="$(sudo docker run -d --rm -e POSTGRES_PASSWORD=verify postgres:16-alpine)"
for _ in $(seq 20); do sudo docker exec "$cid" pg_isready -q -U postgres 2>/dev/null && break; sleep 1; done
sudo docker exec "$cid" psql -U postgres -tAc 'select 1' | grep -q 1 || { warn "PostgreSQL test container failed"; rc=1; }
sudo docker stop "$cid" >/dev/null
((rc == 0)) || die "Docker checks failed"

cat <<'TXT'
Next steps for you:
  1. Log out and back in (docker and kvm groups).
  2. Start Docker Desktop once from the app menu, accept the terms, then run:
       scripts/40-docker.sh --desktop-settings
  3. Do not run Engine containers and Desktop containers on the same ports at once.
TXT
mark_done
log "Next: scripts/50-mise-tools.sh"
