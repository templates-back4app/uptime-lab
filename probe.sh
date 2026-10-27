#!/usr/bin/env bash
# Three ways for an app to be down, and which monitors notice.
#
#   ./probe.sh
#
# Builds one image, runs it in each failure mode, and asks four questions of
# each: is the container running, does the port answer, does the health check
# pass, and does a real user request work.
set -u

NAME=uptime-lab-run
PORT=8099
IMAGE=uptime-lab

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker build -q -t "$IMAGE" "$(dirname "$0")" >/dev/null

# ask the container for its own opinion
container_running() { [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ] && echo UP || echo DOWN; }
docker_health()     { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$NAME" 2>/dev/null; }

# ask from outside, the way a monitor would
port_answers()  { nc -z -G 2 127.0.0.1 "$PORT" >/dev/null 2>&1 && echo UP || echo DOWN; }
http_code()     { curl -s -o /dev/null -m 4 -w '%{http_code}' "http://127.0.0.1:$PORT$1" 2>/dev/null; }

run_mode() {
  local mode="$1" healthcmd="$2"
  cleanup
  # the previous container's port mapping can outlive `docker rm -f` by a moment,
  # so retry the run rather than silently ending up with no container at all
  local started=no
  for _ in $(seq 1 10); do
    if docker run -d --name "$NAME" -p "$PORT:8080" -e "MODE=$mode" \
         --health-cmd "$healthcmd" --health-interval 2s --health-retries 2 --health-start-period 0s \
         "$IMAGE" >/dev/null 2>&1; then started=yes; break; fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    sleep 1
  done
  [ "$started" = yes ] || { echo "  !! container failed to start for mode=$mode" >&2; return 1; }
  # wait for the app to be listening, then let the health check settle past "starting"
  for _ in $(seq 1 25); do [ "$(port_answers)" = UP ] && break; sleep 0.4; done
  for _ in $(seq 1 20); do [ "$(docker_health)" != starting ] && break; sleep 1; done
}

row() {
  local label="$1"
  printf '  %-26s %-11s %-11s %-13s %-11s %s\n' \
    "$label" "$(container_running)" "$(port_answers)" "$(docker_health)" "$(http_code /health)" "$(http_code /orders)"
}

NAIVE='wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1'
REAL='wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1'

echo ""
echo "  WITH THE HEALTH CHECK ALMOST EVERY GENERATED APP SHIPS WITH  (GET /health)"
echo ""
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "state of the app" "container" "port" "docker health" "GET /health" "GET /orders"
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "--------------------------" "-----------" "-----------" "-------------" "-----------" "-----------"

run_mode ok "$NAIVE";        row "working normally"
run_mode dep-down "$NAIVE";  row "database unreachable"
run_mode blocked "$NAIVE";   row "one endpoint hangs"

cleanup
docker run -d --name "$NAME" -p "$PORT:8080" -e MODE=ok "$IMAGE" >/dev/null
sleep 2
docker rm -f "$NAME" >/dev/null 2>&1
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "process exited" "DOWN" "DOWN" "none" "000" "000"

echo ""
echo "  WITH A HEALTH CHECK THAT ASKS WHETHER THE APP CAN DO ITS JOB  (GET /healthz)"
echo ""
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "state of the app" "container" "port" "docker health" "GET /healthz" "GET /orders"
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "--------------------------" "-----------" "-----------" "-------------" "-----------" "-----------"

run_mode ok "$REAL"
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "working normally" "$(container_running)" "$(port_answers)" "$(docker_health)" "$(http_code /healthz)" "$(http_code /orders)"

run_mode dep-down "$REAL"
printf '  %-26s %-11s %-11s %-13s %-11s %s\n' "database unreachable" "$(container_running)" "$(port_answers)" "$(docker_health)" "$(http_code /healthz)" "$(http_code /orders)"

echo ""
echo "  WHERE THE ERROR WENT"
echo ""
cleanup
docker run -d --name "$NAME" -p "$PORT:8080" -e MODE=dep-down "$IMAGE" >/dev/null
for _ in $(seq 1 25); do [ "$(port_answers)" = UP ] && break; sleep 0.4; done
http_code /orders >/dev/null
sleep 1
lines=$(docker logs "$NAME" 2>&1 | grep -c 'dependency unreachable' || true)
echo "  the failing request wrote to stdout, and the platform kept it:"
docker logs "$NAME" 2>&1 | grep 'dependency unreachable' | head -1 | sed 's/^/      /'
echo "      ($lines line(s) retrievable with: docker logs $NAME)"
echo ""
