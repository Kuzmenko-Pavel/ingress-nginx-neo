#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Load test of the dev environment (`make dev-env-up`). Deploys the backends of
# test/k6/workload.yaml, runs test/k6/load.js with k6 in a container on this
# machine against the kind node, samples memory and CPU of the controller pod
# during the run and prints a summary. Called by `make test-load`.
#
# Results in OUT_DIR: <run>.json (k6 summary), <run>-resources.csv (samples),
# <run>-resources.txt (resource summary).

set -euo pipefail

: "${KIND:?}" "${KUBECTL:?}" "${KIND_CLUSTER_NAME:?}" "${NAMESPACE:?}" "${RELEASE_NAME:?}"
: "${ECHO_IMAGE:?}" "${HTTPBUN_IMAGE:?}" "${K6_IMAGE:?}" "${OUT_DIR:?}"
: "${LOAD_SCENARIO:?}" "${PROTOCOL:?}" "${RATE:?}" "${DURATION:?}"
BODY_SIZE="${BODY_SIZE:-0}"
REUSE="${REUSE:-true}"
P95_MS="${P95_MS:-500}"
P99_MS="${P99_MS:-1500}"
MAX_VUS="${MAX_VUS:-2000}"
CHURN_INTERVAL="${CHURN_INTERVAL:-10}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-10}"
WARMUP="${WARMUP:-60}"
MEM_GROWTH_MAX_PCT="${MEM_GROWTH_MAX_PCT:-}"

root="$(git rev-parse --show-toplevel)"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind-config-${KIND_CLUSTER_NAME}}"
kubectl() { "$KUBECTL" --context "kind-${KIND_CLUSTER_NAME}" "$@"; }
load_ns=ingress-nginx-neo-load

controller="$(kubectl -n "$NAMESPACE" get pods 2>/dev/null \
  -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=controller" \
  -o jsonpath='{.items[0].metadata.name}' || true)"
if [[ -z "$controller" ]]; then
  echo "Error: no controller pod of release ${RELEASE_NAME} in namespace ${NAMESPACE}" >&2
  echo "Please run: make dev-env-up" >&2
  exit 1
fi
if [[ "$LOAD_SCENARIO" == default-backend ]] &&
  ! kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=default-backend" \
    -o name | grep -q .; then
  echo "Error: the release ${RELEASE_NAME} has no default backend" >&2
  echo "Please run: make dev-env-up" >&2
  exit 1
fi

echo "deploying the backends"
for image in "$ECHO_IMAGE" "$HTTPBUN_IMAGE"; do
  "$KIND" load docker-image --name "${KIND_CLUSTER_NAME}" "$image"
done
sed -e "s#ECHO_IMAGE#${ECHO_IMAGE}#" -e "s#HTTPBUN_IMAGE#${HTTPBUN_IMAGE}#" "${root}/test/k6/workload.yaml" |
  kubectl apply -f -
kubectl -n "$load_ns" scale deployment echo --replicas=2
kubectl -n "$load_ns" rollout status deployment/echo deployment/httpbun --timeout=3m

echo "waiting for the controller to serve the backends"
for _ in $(seq 60); do
  conf="$(kubectl -n "$NAMESPACE" exec "$controller" -c controller -- /dbg conf 2>/dev/null || true)"
  backends="$(kubectl -n "$NAMESPACE" exec "$controller" -c controller -- /dbg backends list 2>/dev/null || true)"
  if grep -q 'server_name load.local ' <<< "$conf" && grep -q 'server_name errors.load.local ' <<< "$conf" &&
    grep -qx "${load_ns}-echo-80" <<< "$backends" && grep -qx "${load_ns}-httpbun-80" <<< "$backends"; then
    break
  fi
  sleep 2
done

target_ip="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "${KIND_CLUSTER_NAME}-control-plane")"
run="${LOAD_SCENARIO}-${PROTOCOL}-$(git rev-parse --short HEAD)-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
csv="${OUT_DIR}/${run}-resources.csv"
restarts_before="$(kubectl -n "$NAMESPACE" get pod "$controller" -o jsonpath='{.status.containerStatuses[0].restartCount}')"

# One line per SAMPLE_INTERVAL: time, NGINX processes (resident memory, CPU
# seconds, count), controller process (resident memory, Go heap in use, CPU
# seconds, goroutines) from the metrics of the pod, and the controller
# container cgroup (memory, CPU microseconds). Missing values stay empty.
metric() { awk -v name="$1" '$1 == name || index($1, name "{") == 1 { printf "%.0f", $2; exit }' <<< "$2"; }
sample() {
  local metrics cgroup
  metrics="$(kubectl get --raw "/api/v1/namespaces/${NAMESPACE}/pods/${controller}:10254/proxy/metrics" 2>/dev/null || true)"
  cgroup="$(kubectl -n "$NAMESPACE" exec "$controller" -c controller -- \
    cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/cpu.stat 2>/dev/null || true)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s)" \
    "$(metric nginx_ingress_controller_nginx_process_resident_memory_bytes "$metrics")" \
    "$(metric nginx_ingress_controller_nginx_process_cpu_seconds_total "$metrics")" \
    "$(metric nginx_ingress_controller_nginx_process_num_procs "$metrics")" \
    "$(metric process_resident_memory_bytes "$metrics")" \
    "$(metric go_memstats_heap_inuse_bytes "$metrics")" \
    "$(metric process_cpu_seconds_total "$metrics")" \
    "$(metric go_goroutines "$metrics")" \
    "$(head -n1 <<< "$cgroup" | grep -E '^[0-9]+$' || true)" \
    "$(awk '$1 == "usage_usec" { print $2 }' <<< "$cgroup")"
}
echo "time,nginx_rss_bytes,nginx_cpu_seconds,nginx_procs,controller_rss_bytes,controller_heap_bytes,controller_cpu_seconds,controller_goroutines,container_memory_bytes,container_cpu_usec" > "$csv"
(while true; do sample >> "$csv"; sleep "$SAMPLE_INTERVAL"; done) &
sampler=$!

# Configuration changes during reload and soak: endpoints (scale 2 <-> 4,
# applied by Lua without a reload) and an annotation of the Ingress (a reload
# of NGINX).
churner=""
if [[ "$LOAD_SCENARIO" == reload || "$LOAD_SCENARIO" == soak ]]; then
  (
    i=0
    while true; do
      sleep "$CHURN_INTERVAL"
      i=$((i + 1))
      kubectl -n "$load_ns" scale deployment echo --replicas=$((i % 2 ? 4 : 2)) >/dev/null
      kubectl -n "$load_ns" annotate ingress echo --overwrite \
        "nginx.ingress.kubernetes.io/proxy-read-timeout=$((60 + i % 2))" >/dev/null
    done
  ) &
  churner=$!
fi

cleanup() {
  kill "$sampler" ${churner:+"$churner"} 2>/dev/null || true
  wait "$sampler" ${churner:+"$churner"} 2>/dev/null || true
}
trap cleanup EXIT

tty=()
[[ -t 0 && -t 1 ]] && tty=(--tty --interactive)
user=()
[[ "$(uname -s)" == Linux ]] && user=(--user "$(id -u):$(id -g)")

echo "running ${LOAD_SCENARIO} over ${PROTOCOL}: rate ${RATE}/s, duration ${DURATION}"
status=0
docker run --rm ${tty[@]+"${tty[@]}"} ${user[@]+"${user[@]}"} --network kind \
  --volume "${root}/test/k6:/scripts:ro" \
  --volume "$(cd "$OUT_DIR" && pwd):/out" \
  "$K6_IMAGE" run \
  --summary-export "/out/${run}.json" \
  -e "TARGET_IP=${target_ip}" -e "LOAD_SCENARIO=${LOAD_SCENARIO}" -e "PROTOCOL=${PROTOCOL}" \
  -e "RATE=${RATE}" -e "DURATION=${DURATION}" -e "BODY_SIZE=${BODY_SIZE}" -e "REUSE=${REUSE}" \
  -e "P95_MS=${P95_MS}" -e "P99_MS=${P99_MS}" -e "MAX_VUS=${MAX_VUS}" \
  /scripts/load.js || status=$?

sample >> "$csv"
cleanup
trap - EXIT
[[ -z "$churner" ]] || kubectl -n "$load_ns" scale deployment echo --replicas=2 >/dev/null

restarts_after="$(kubectl -n "$NAMESPACE" get pod "$controller" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")"

# Resource summary: the first sample after WARMUP seconds is the baseline;
# growth compares the last sample with it, CPU is the average number of cores
# used between them. With MEM_GROWTH_MAX_PCT, a larger growth of the NGINX or
# controller memory fails the run.
summary="${OUT_DIR}/${run}-resources.txt"
rc=0
awk -F, -v warmup="$WARMUP" -v max="$MEM_GROWTH_MAX_PCT" -v restarts="${restarts_before} -> ${restarts_after}" '
  NR == 1 { next }
  { n++; nf = NF; for (i = 1; i <= NF; i++) v[n, i] = $i }
  function mib(x) { return x == "" ? "n/a" : sprintf("%.1f MiB", x / 1048576) }
  function pct(i) { return (b[i] == "" || l[i] == "" || b[i] == 0) ? "n/a" : sprintf("%+.1f%%", (l[i] - b[i]) * 100 / b[i]) }
  function cores(i, scale) { return (b[i] == "" || l[i] == "" || l[1] == b[1]) ? "n/a" : sprintf("%.2f", (l[i] - b[i]) / scale / (l[1] - b[1])) }
  function row(name, i, fmt) {
    printf "%-22s %12s %12s %12s %8s\n", name, fmt ? mib(b[i]) : b[i], fmt ? mib(l[i]) : l[i], fmt ? mib(m[i]) : m[i], pct(i)
  }
  END {
    if (n == 0) { print "no resource samples"; exit }
    first = 1
    for (r = 1; r <= n; r++) if (v[r, 1] - v[1, 1] >= warmup) { first = r; break }
    for (i = 1; i <= nf; i++) {
      b[i] = v[first, i]; l[i] = v[n, i]; m[i] = ""
      for (r = first; r <= n; r++) if (v[r, i] != "" && (m[i] == "" || v[r, i] + 0 > m[i] + 0)) m[i] = v[r, i]
    }
    printf "%-22s %12s %12s %12s %8s\n", "", "baseline", "end", "max", "growth"
    row("nginx memory", 2, 1)
    row("controller memory", 5, 1)
    row("controller Go heap", 6, 1)
    row("container memory", 9, 1)
    row("controller goroutines", 8, 0)
    row("nginx processes", 4, 0)
    printf "CPU, cores: nginx %s, controller %s, container %s\n", cores(3, 1), cores(7, 1), cores(10, 1000000)
    printf "controller restarts: %s\n", restarts
    printf "baseline: %ss after the start (WARMUP %ss), %d samples\n", v[first, 1] - v[1, 1], warmup, n - first + 1
    if (max != "") {
      over = ""
      if (b[2] > 0 && (l[2] - b[2]) * 100 / b[2] > max) over = over " nginx"
      if (b[5] > 0 && (l[5] - b[5]) * 100 / b[5] > max) over = over " controller"
      if (over != "") { printf "memory growth above %s%%:%s\n", max, over; exit 3 }
    }
  }' "$csv" > "$summary" || rc=$?
cat "$summary"
echo "samples: ${csv}"
echo "k6 summary: ${OUT_DIR}/${run}.json"
if [[ $rc -ne 0 && $status -eq 0 ]]; then
  status=$rc
fi

exit "$status"
