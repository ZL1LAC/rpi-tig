#!/bin/bash

set -euo pipefail

# Choose docker compose command (prefer plugin)
compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

# Cross-platform sed -i helper (GNU/BSD)
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# Ensure the required env file exists before proceeding
if [ ! -f env.influxdb ]; then
  if [ -f env.influxdb.default ]; then
    echo "env.influxdb not found; creating from template env.influxdb.default"
    cp env.influxdb.default env.influxdb
  else
    echo "Error: env.influxdb not found and no env.influxdb.default template present." >&2
    echo "Please create env.influxdb before running this script." >&2
    exit 1
  fi
fi

# Ensure the required telegraf config exists before proceeding
if [ ! -f telegraf/telegraf.conf ]; then
  if [ -f telegraf/telegraf.conf.default ]; then
    echo "telegraf/telegraf.conf not found; creating from default template"
    cp telegraf/telegraf.conf.default telegraf/telegraf.conf
  else
    echo "Error: telegraf/telegraf.conf not found and no telegraf/telegraf.conf.default template present." >&2
    exit 1
  fi
fi

# Step one: ensure we have Token that is defined everywhere it is needed:
# - InfluxDB of course
# - Telegraf so that it can write to Influx
# - Grafana so that it can read from Influx
if grep -q "TOKEN_TO_CHANGE" env.influxdb; then
   echo "Default token detected for Influx database..."
   echo "Setting up a random token for this installation"
   if ! command -v openssl >/dev/null 2>&1
   then
      PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)
   else
      PASSWORD=$(openssl rand -hex 32)
   fi
   sed_inplace "s/TOKEN_TO_CHANGE/$PASSWORD/g" env.influxdb
   sed_inplace "s/TOKEN_TO_CHANGE/$PASSWORD/g" telegraf/telegraf.conf
   echo "Warning: this is not enough to consider this installation is secure"
   echo "         do NOT expose this to the Internet directly!"
fi

# Step two: also define an admin password for InfluxDB
if grep -q "ADMIN_TO_CHANGE" env.influxdb; then
   echo "Default password detected for InfluxDB administrator..."
   echo "Setting up a random password for this installation"
   if ! command -v openssl >/dev/null 2>&1
   then
      PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)
   else
      PASSWORD=$(openssl rand -hex 32)
   fi
   sed_inplace "s/ADMIN_TO_CHANGE/$PASSWORD/g" env.influxdb
   echo "... done"
   echo "Warning: again, the password is in the env.influxdb file now, be careful."
fi

echo "Changing ownership of grafana files to what the Docker image expects"
# Ensure data directories exist
mkdir -p grafana/data grafana/provisioning influxdb/data influxdb/config

# Attempt to set expected ownership for Grafana data (UID/GID 472)
if command -v sudo >/dev/null 2>&1; then
  sudo chown -R 472:472 grafana/data || true
elif [ "$(id -u)" -eq 0 ]; then
  chown -R 472:472 grafana/data || true
else
  echo "Note: Could not change grafana/data ownership automatically (no sudo)." >&2
  echo "      If Grafana fails to write to its data dir, run:" >&2
  echo "        sudo chown -R 472:472 grafana/data" >&2
fi

echo "Starting TIG stack in the background"
set +e
compose up -d
compose_exit=$?
set -e

# Detect common Docker manifest issues (e.g., wrong image tag or arch) and provide guidance
if [ $compose_exit -ne 0 ]; then
  echo "Error: Failed to start containers. Checking for manifest issues..." >&2
  # If docker is not present, we cannot probe manifests
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI not found; cannot probe image manifests. Please ensure Docker is installed." >&2
    exit $compose_exit
  fi

  if docker pull telegraf:${TELEGRAF_TAG:-1.30} 2>&1 | grep -qi "manifest unknown"; then
    echo "Detected unknown Telegraf image tag or unsupported architecture." >&2
    echo "Try setting a specific tag known to exist on your platform, e.g.:" >&2
    echo "  export TELEGRAF_TAG=1.30" >&2
    echo "  ./start.sh" >&2
    echo "You can list available tags at: https://hub.docker.com/_/telegraf/tags" >&2
  fi

  if docker pull grafana/grafana:${GRAFANA_TAG:-11.3.0} 2>&1 | grep -qi "manifest unknown"; then
    echo "Detected unknown Grafana image tag or unsupported architecture." >&2
    echo "Try setting a specific tag known to exist on your platform, e.g.:" >&2
    echo "  export GRAFANA_TAG=11.3.0" >&2
    echo "  ./start.sh" >&2
    echo "You can list available tags at: https://hub.docker.com/r/grafana/grafana/tags" >&2
  fi
  if docker pull influxdb:2 2>&1 | grep -qi "manifest unknown"; then
    echo "Detected unknown InfluxDB image tag or unsupported architecture." >&2
    echo "Try setting a specific 2.x tag known to exist on your platform, e.g.:" >&2
    echo "  docker pull influxdb:2.7" >&2
    echo "Available tags: https://hub.docker.com/_/influxdb/tags" >&2
  fi
  exit $compose_exit
fi

echo -n "Waiting for InfluxDB to come up..."
# Give InfluxDB some time to initialize the setup; health endpoint will be available once ready
for i in {1..30}; do
  if docker logs influxdb 2>&1 | grep -q "Listening"; then
    break
  fi
  sleep 2
  echo -n "."
done
echo " ready (continuing)"

#echo "Setting InfluxDB retention policy to one month to save Raspberry Pi resources"
# PASSWORD="$(grep DOCKER_INFLUXDB_INIT_PASSWORD env.influxdb | awk -F '=' '{print $2}')"
# docker exec -it influxdb influx -password $PASSWORD -username 'admin' -database 'telegraf' -execute 'CREATE RETENTION POLICY "one_month" ON "telegraf" DURATION 30d REPLICATION 1 DEFAULT'
# echo "... done"

echo "You should be able to access Grafana at http://localhost:3000/ in a few seconds"
echo "Obviously, use the hostname of your raspberry Pi if you are connecting remotely, not 'localhost'"
echo "Default username/password is admin/admin. Please change this"
echo "The stack will keep running and will restart on reboot unless you issue a 'docker compose stop'"
