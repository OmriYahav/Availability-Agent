# Availability Agent (Bash + InfluxDB + Grafana)

Availability Agent periodically pings a list of hosts, stores reachability and latency metrics in InfluxDB, and visualizes them in Grafana.

## Stack

- **Agent**: Bash script (`AvailabilityAgent.sh`)
- **Metrics DB**: InfluxDB 1.8
- **Visualization**: Grafana (provisioned datasource + dashboard)
- **Orchestration**: Docker Compose

## Quick Start

### 1) Clone

```bash
git clone https://github.com/OmriYahav/Availability-Agent.git
cd Availability-Agent
```

### 2) Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set secure values for:

- `INFLUX_PASS`
- `GRAFANA_ADMIN_PASSWORD`

### 3) Configure hosts

Edit `hosts` with **one host per line**:

```text
# comments are allowed
1.1.1.1
google.com
```

### 4) Start services

```bash
docker compose up -d
```

### 5) Open Grafana

- URL: `http://localhost:${GRAFANA_PORT}` (default `http://localhost:3003`)
- Default credentials: from `.env` (`GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`)

The datasource and dashboard are provisioned automatically:

- Datasource: `InfluxDB`
- Dashboard: **Availability Agent Overview**

## How metrics are stored

InfluxDB measurement defaults to `availability_test` and includes:

- `status` (integer): `1` for up, `0` for down
- `latency_ms` (float/integer): ping latency in milliseconds (`0` when down)
- tag `host`

> Note: Ping output `time=` is already in milliseconds. The agent stores this value directly.

## Configuration

All runtime settings are env-driven. See `.env.example`.

Common settings:

- `INTERVAL_SECONDS` (default `5`)
- `PING_COUNT` (default `1`)
- `PING_TIMEOUT_SECONDS` (default `2`)
- `PING_RETRIES` (default `3`)
- `INFLUX_URL` (default in compose network: `http://influxdb:8086`)
- `INFLUX_DB`, `INFLUX_USER`, `INFLUX_PASS`, `INFLUX_MEASUREMENT`

## Persistence

Docker volumes are used so data survives restarts:

- `influxdb-data`
- `grafana-data`

## Troubleshooting

### InfluxDB not ready / agent not writing

- Check health:
  ```bash
  docker compose ps
  docker compose logs influxdb
  docker compose logs agent
  ```
- The agent waits for InfluxDB readiness (`/ping`) before sending writes.

### Permission issues on mounted files

- Ensure the repository files are readable by Docker.
- On Linux, if using restrictive umask/ACLs, relax permissions for `hosts` and provisioning files.

### Ping failures inside container

- Some environments restrict ICMP. If all hosts appear down, test with:
  ```bash
  docker compose exec agent ping -c 1 1.1.1.1
  ```
- Corporate/CI networks may block outbound ICMP.

### Grafana dashboard missing

- Verify provisioning files are mounted:
  ```bash
  docker compose logs grafana
  ```
- Restart Grafana after provisioning changes:
  ```bash
  docker compose restart grafana
  ```

## Development quality checks

GitHub Actions runs:

- `shellcheck` for shell scripts
- `shfmt -d` format check

## License

MIT License. See [LICENSE](LICENSE).
