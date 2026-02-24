import collections
import math
import os
import socket
import subprocess
import time
import urllib.parse
import urllib.request


def env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def load_hosts(path: str) -> list[str]:
    hosts = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            hosts.append(line)
    return hosts


def escape_tag(value: str) -> str:
    return value.replace("\\", "\\\\").replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\=")


def write_influx(influx_url: str, db: str, line: str, timeout_s: int = 3) -> None:
    encoded_db = urllib.parse.quote(db, safe="")
    url = f"{influx_url.rstrip('/')}/write?db={encoded_db}"
    req = urllib.request.Request(url=url, data=line.encode("utf-8"), method="POST")
    with urllib.request.urlopen(req, timeout=timeout_s):
        return


def ping_latency_ms(host: str, timeout_s: int) -> float | None:
    cmd = ["ping", "-c", "1", "-W", str(timeout_s), host]
    try:
        completed = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except Exception:
        return None

    if completed.returncode != 0:
        return None

    output = completed.stdout
    marker = "time="
    idx = output.find(marker)
    if idx == -1:
        return None
    rest = output[idx + len(marker):]
    number = []
    for ch in rest:
        if ch.isdigit() or ch in {".", "-"}:
            number.append(ch)
        else:
            break
    try:
        return float("".join(number))
    except Exception:
        return None


def stdev(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    var = sum((v - mean) ** 2 for v in values) / len(values)
    return math.sqrt(var)


def main() -> None:
    hosts_file = os.getenv("HOSTS_FILE", "/app/hosts")
    influx_url = os.getenv("INFLUX_URL", "http://influxdb:8086")
    influx_db = os.getenv("INFLUX_DB", "ping")
    interval_seconds = env_float("INTERVAL_SECONDS", 5.0)
    ping_timeout_seconds = env_int("PING_TIMEOUT_SECONDS", 2)
    agent_name = os.getenv("AGENT_NAME", socket.gethostname())

    while True:
        try:
            hosts = load_hosts(hosts_file)
            break
        except Exception as exc:
            print(f"failed reading hosts file: {exc}", flush=True)
            time.sleep(2)

    windows = {
        host: collections.deque(maxlen=max(1, int(math.ceil(60.0 / max(interval_seconds, 1.0)))))
        for host in hosts
    }

    while True:
        loop_start = time.time()
        for host in hosts:
            latency = ping_latency_ms(host, ping_timeout_seconds)
            success = 1 if latency is not None else 0
            latency_value = latency if latency is not None else 0.0

            if host not in windows:
                windows[host] = collections.deque(maxlen=max(1, int(math.ceil(60.0 / max(interval_seconds, 1.0)))))

            windows[host].append((success, latency_value))
            samples = list(windows[host])
            total = len(samples)
            successful_latencies = [lat for s, lat in samples if s == 1]
            success_count = sum(s for s, _ in samples)
            packet_loss_percent = (1.0 - (success_count / total)) * 100.0 if total else 0.0
            jitter_ms = stdev(successful_latencies)

            line = (
                f"ping,host={escape_tag(host)},agent={escape_tag(agent_name)} "
                f"latency_ms={latency_value:.3f},"
                f"packet_loss_percent={packet_loss_percent:.3f},"
                f"jitter_ms={jitter_ms:.3f},"
                f"success={success}i"
            )

            try:
                write_influx(influx_url, influx_db, line)
                print(
                    f"host={host} success={success} latency_ms={latency_value:.3f} "
                    f"loss={packet_loss_percent:.2f} jitter={jitter_ms:.3f}",
                    flush=True,
                )
            except Exception as exc:
                print(f"write failed host={host}: {exc}", flush=True)

        elapsed = time.time() - loop_start
        sleep_for = interval_seconds - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)


if __name__ == "__main__":
    main()
