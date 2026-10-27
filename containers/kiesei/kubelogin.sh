#!/bin/sh
# kubelogin, as kiesei runs it (installed as /usr/local/bin/kubelogin; the
# binary is /usr/local/libexec/kubelogin). On Docker Desktop, host networking
# forwards to the Mac only the ports a container binds on all interfaces, so
# kubelogin's callback on 127.0.0.1:8000 would never reach it from the
# browser (seen 2026-10-27). driver/kiesei.sh sets BRZL_HOST_OS; on a Mac,
# get-token listens on 0.0.0.0 inside the container, which is Docker
# Desktop's VM, not the Mac's interfaces. Elsewhere kubelogin runs as it is.
if [ "${BRZL_HOST_OS:-}" = Darwin ] && [ "${1:-}" = get-token ]; then
  exec /usr/local/libexec/kubelogin "$@" --listen-address=0.0.0.0:8000 --listen-address=0.0.0.0:18000
fi
exec /usr/local/libexec/kubelogin "$@"
