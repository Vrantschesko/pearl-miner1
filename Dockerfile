# Small image for Pearl mining on clore.ai
#   Ubuntu 22.04 + SSH server + curl + OneZeroMiner, nothing else.
#
# - SSH server already installed, so clore has nothing to install before you can log in.
# - OneZeroMiner already inside (/opt/onezerominer/onezerominer), so the startup script
#   finds it instantly and starts mining with no download.
# - GPU drivers and nvidia-smi come from the host, exactly like with buildpack-deps,
#   so no multi-GB CUDA base image is needed.
# - Ubuntu 22.04 on purpose: it's what clore's SSH setup already handles on your rentals.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# SSH server + curl/certificates, without the extras (no systemd).
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server ca-certificates curl \
 && mkdir -p /run/sshd \
 && sed -i -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' \
           -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && rm -rf /var/lib/apt/lists/*

# No SSH host keys inside the image (the image is public, so baked-in keys would be
# public too). Instead, sshd is wrapped so each container makes its own keys the
# first time anything starts sshd. That takes about a second.
RUN rm -f /etc/ssh/ssh_host_* \
 && dpkg-divert --local --rename --add /usr/sbin/sshd \
 && printf '%s\n' '#!/bin/sh' \
      'ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A >/dev/null 2>&1' \
      'exec /usr/sbin/sshd.distrib "$@"' > /usr/sbin/sshd \
 && chmod 755 /usr/sbin/sshd

# OneZeroMiner: newest release at build time, or the known-good version if GitHub
# can't be reached.
ARG OZM_FALLBACK=https://github.com/OneZeroMiner/onezerominer/releases/download/v1.8.2/onezerominer-linux-1.8.2.tar.gz
RUN set -e; \
    url=$(curl -fsSL --max-time 30 https://api.github.com/repos/OneZeroMiner/onezerominer/releases/latest \
          | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
          | grep -iE 'linux.*\.tar\.gz$' | grep -viE 'hive|mmpos' | head -1) || true; \
    [ -n "$url" ] || url="$OZM_FALLBACK"; \
    echo "downloading $url"; \
    mkdir -p /tmp/ozm /opt/onezerominer; \
    curl -fsSL --retry 3 "$url" | tar -xz -C /tmp/ozm; \
    bin=$(find /tmp/ozm -type f -name onezerominer | head -1); \
    [ -n "$bin" ]; \
    cp -a "$(dirname "$bin")/." /opt/onezerominer/; \
    chmod +x /opt/onezerominer/onezerominer; \
    rm -rf /tmp/ozm

EXPOSE 22
CMD ["bash"]
