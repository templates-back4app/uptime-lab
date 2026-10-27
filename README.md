# uptime-lab

[![Deploy on Back4app](https://img.shields.io/badge/Deploy%20on-Back4app-1568B8?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJMMiA3djEwbDEwIDUgMTAtNVY3eiIvPjwvc3ZnPg==)](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab)

**Four ways for an app to be down, run in a real container, probed by four monitors.** Three of them report `healthy`.

Measured on 27 October 2026 with Docker 29.4.3: the container status, the port check and the health check all pass while every user request returns **500**. Only the crashed process is caught — the one failure you would have found out about anyway.

> **Read the article:** [Your App Is Down and Nothing Told You. How to Keep It Alive on Back4app](https://www.back4app.com/blog/your-app-is-down-and-nothing-told-you?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab)

## Run it

```bash
./probe.sh
```

Docker is the only requirement. The script builds the image, runs it in each failure mode, probes it, and removes the container afterwards.

## What it finds

```
  WITH THE HEALTH CHECK ALMOST EVERY GENERATED APP SHIPS WITH  (GET /health)

  state of the app           container   port        docker health GET /health GET /orders
  -------------------------- ----------- ----------- ------------- ----------- -----------
  working normally           UP          UP          healthy       200         200
  database unreachable       UP          UP          healthy       200         500
  one endpoint hangs         UP          UP          healthy       200         000
  process exited             DOWN        DOWN        none          000         000

  WITH A HEALTH CHECK THAT ASKS WHETHER THE APP CAN DO ITS JOB  (GET /healthz)

  state of the app           container   port        docker health GET /healthz GET /orders
  -------------------------- ----------- ----------- ------------- ----------- -----------
  working normally           UP          UP          healthy       200         200
  database unreachable       UP          UP          unhealthy     503         500
```

Stable across two consecutive runs.

## The findings

**1. The ordinary health check proves one thing: this process can answer.** It is a constant:

```js
if (req.url === '/health') return send(200, { status: 'ok' });
```

Nothing in it touches the database, the queue, or anything else the app cannot work without — so a dependency going away is invisible to it.

**2. A check that touches the dependency flips the same broken app to failing.** Same image, same breakage, 503 and `unhealthy` instead of 200 and `healthy`:

```js
const up = await dependencyUp();            // opens a real connection
return send(up ? 200 : 503, { status: up ? 'ok' : 'dependency unreachable' });
```

**3. A hang cannot be caught by a health check at all.** The cheap path answers while the expensive one never returns. The only thing that catches it is requesting a real endpoint on a timeout, from outside.

**4. Errors survive only if they went to stdout.** The failing request's line was still retrievable with `docker logs` afterwards. A log file written inside the container is discarded whenever that container is replaced — which is every deploy.

## Files

- `app.js` — one app, three failure modes (`ok`, `dep-down`, `blocked`), two health endpoints.
- `Dockerfile` — `node:22-alpine`, no dependencies.
- `probe.sh` — builds, runs each mode, probes with `docker inspect`, `nc` and `curl`, prints the matrix.

## Deploy your own

1. **Create a free account.** Sign up at [https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab).
2. **Let the platform own the maintenance** — server updates, database patches and infrastructure — so the slow version of this failure never starts.
3. **Keep your own health check honest.** No platform can write it: only your code knows what your app cannot work without.

Documentation: [https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab](https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=uptime-lab).

## License

MIT.
