# DevOps practical test

A small Python web service, containerized with Docker Compose, built and deployed by a GitLab CI/CD pipeline, monitored with Prometheus, Alertmanager and Grafana, and protected with iptables rules.

The project covers four areas: **containerization**, **CI/CD**, **monitoring and alerting**, and **network security with restart policies**. Each area has its own detailed guide in [`docs/`](docs/).

## Documentation

| Guide | What you will find |
|---|---|
| [Web application and containerization](docs/webapp.md) | The FastAPI service, tests, Dockerfile line by line, Compose file, health check, restart policy and the crash-recovery demonstration |
| [Monitoring and alerting](docs/monitoring.md) | Prometheus, Alertmanager and Grafana: every configuration file explained, the three alert rules, how to trigger and read an alert |
| [GitLab CI/CD pipeline](docs/gitlab.md) | The pipeline stage by stage, the runner setup, how to trigger it, failure recovery |
| [Network security with iptables](docs/iptables.md) | Why Docker needs `DOCKER-USER` rules, the rule set, the script, the before/after test and counter evidence |

## Requirements and where they are covered

| # | Requirement | Implementation | Guide | Evidence |
|---|---|---|---|---|
| 1 | Containerize the service with Docker Compose | `webapp/Dockerfile`, `webapp/compose.yml` | [webapp.md](docs/webapp.md) | [Service started via Compose](docs/screenshots/web-app.png) |
| 2 | GitLab CI/CD pipeline that builds, tests and deploys | `gitlab/.gitlab-ci.yml` (included by the root `.gitlab-ci.yml`) | [gitlab.md](docs/gitlab.md) | [Passing pipeline](docs/screenshots/full-green-pipline.png), [test report](docs/screenshots/test-pipline.png) |
| 3 | Prometheus monitoring and alerting | `monitoring/` (Prometheus, Alertmanager, Grafana configs) | [monitoring.md](docs/monitoring.md) | [Targets up](docs/screenshots/scraps.png), [rules](docs/screenshots/alerts.png), [alert firing](docs/screenshots/web-app-down.png), [Grafana dashboard](docs/screenshots/dashboard-webapp.png) |
| 4 | iptables rules restricting external access | `iptables/firewall.sh` | [iptables.md](docs/iptables.md) | [Test from a second machine](docs/screenshots/iptabels-afterrule.png), [rule counters](docs/screenshots/firewall-rule.png) |
| 5 | Restart policy and automatic restart after a kill | `restart: unless-stopped` in `webapp/compose.yml` | [webapp.md, section 7](docs/webapp.md#7-restart-policy-and-crash-recovery) | [Restart after kill](docs/screenshots/restart-proof.png) |

## Architecture

```
 Developer laptop                                        Home server
 +------------------------------+     git push      +-----------------------------------+
 | webapp + monitoring stack    | ----------------> | GitLab CE (behind Traefik, TLS)   |
 |  - webapp        :8000       |                   |        |                          |
 |  - Prometheus    :9090       |                   |        v                          |
 |  - Alertmanager  :9093       |                   | GitLab runner (Docker executor)   |
 |  - Grafana       :3000       |                   |   test -> build -> deploy         |
 | iptables firewall            |                   |        |                          |
 +------------------------------+                   |        v                          |
                                                    | webapp container  :8000           |
                                                    +-----------------------------------+
```

The webapp exposes `/metrics`; Prometheus collects them, evaluates the alert rules and passes firing alerts to Alertmanager, which sends them to a webhook receiver. Grafana draws the data. The pipeline tests the code, builds the image and deploys it, and only reports success when the container is healthy.

## Repository layout

```
.
├── README.md                    this file
├── .gitlab-ci.yml               includes gitlab/.gitlab-ci.yml
├── docs/                        the four guides and docs/screenshots/
├── webapp/                      FastAPI service, tests, Dockerfile, compose.yml
├── monitoring/                  compose.yml, prometheus/, alertmanager/, grafana/
├── gitlab/                      .gitlab-ci.yml, compose.yml of the GitLab stack, runner notes
└── iptables/                    firewall.sh
```

## Setup

**Requirements:** Docker with the Compose plugin, Linux. For the firewall: `iptables` and root access.

```bash
# 1. A network shared by the two stacks (once)
docker network create monitoring-net

# 2. The web service
cd webapp
docker compose up -d --build

# 3. Monitoring
cd ../monitoring
docker compose up -d
```

Check that everything is running:

```bash
docker ps
curl localhost:8000/health        # {"status":"ok"}
```

| Service | URL | Notes |
|---|---|---|
| Webapp | http://localhost:8000 | `/health`, `/metrics`, `/error` (returns 500 on purpose) |
| Prometheus | http://localhost:9090 | Status → Targets, Alerts |
| Alertmanager | http://localhost:9093 | |
| Grafana | http://localhost:3000 | User `admin`, password `admin` (set `GRAFANA_PASSWORD` to change); dashboard "Webapp Overview" |

Apply the firewall (optional, requires root; undo with `down`):

```bash
sudo ./iptables/firewall.sh up
sudo ./iptables/firewall.sh status
sudo ./iptables/firewall.sh down
```

Stop everything:

```bash
(cd monitoring && docker compose down)
(cd webapp && docker compose down)
```

## Trigger the pipeline

1. Push the repository to the GitLab project: `git push origin master`.
2. GitLab starts a pipeline automatically. Follow it under **Build → Pipelines**.
3. The stages are **test** (pytest), **build** (Docker image), an optional **publish** and **deploy** (default branch only). The deploy succeeds only when the container reports `healthy`.
4. To run it again without a new commit: **Build → Pipelines → Run pipeline**.

Details, the runner setup and the pipeline file are in [docs/gitlab.md](docs/gitlab.md).

## Failure recovery

| Situation | What to do |
|---|---|
| The webapp container crashed | Nothing: `restart: unless-stopped` restarts it automatically. Check with `docker ps` and `docker logs webapp` |
| The webapp was stopped by hand (`docker stop`) | Start it again: `docker start webapp` (or `docker compose up -d` in `webapp/`) |
| The container is `unhealthy` | `docker logs webapp`, fix the cause, then `docker compose up -d --build` |
| An alert is firing | Read it at http://localhost:9090/alerts and `docker logs alert-logger`; check the Grafana dashboard and `docker logs webapp` |
| Prometheus rules or config changed | Validate with `docker exec prometheus promtool check config /etc/prometheus/prometheus.yml`, then reload with `curl -X POST localhost:9090/-/reload` |
| A pipeline job is stuck "pending" | The runner is offline or not enabled for the project: `docker logs gitlab-runner` and the GitLab runners page |
| A deploy broke the service | Revert the commit and push; the pipeline redeploys the previous version |
| The firewall blocks something unexpected | `sudo ./iptables/firewall.sh down` removes all rules at once |

More specific tables are at the end of each guide.

## Notes

- The Compose files are named `compose.yml`, the current default name that Docker Compose looks for (`docker-compose.yml` also works).
- Screenshots in `docs/screenshots/` were taken during the actual runs described in the guides.
- This is a demonstration setup. Each guide ends with a short list of what would change in production (authentication, TLS, real alert receivers, isolated CI runners, IPv6 firewall rules, and so on).
