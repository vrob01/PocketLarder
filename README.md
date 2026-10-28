# PocketLarder

PocketLarder is a self-hosted, open-source shopping list app for one household. It does one job, shopping lists, and leaves everything else to other tools, in the spirit of "one job, one tool".

The server API is described in [server/API.md](server/API.md).

## Self-hosting

Run all commands from the repo root.

1. Create your settings file and the data directory. In `server/deploy/.env`, set `POCKETLARDER_PUBLIC_URL` to your own `https://` address, the same host as the Caddy site below, and `POCKETLARDER_HOST_DATA_DIR` to the host directory that holds the database (the example uses `/srv/pocketlarder`; keep it outside the repo). Settings that depend on your deployment live in `.env`, which git ignores, so `git pull` upgrades never conflict with `compose.yaml`. That directory is bind-mounted at `/data` and must belong to the container user (65532:65532):

   ```bash
   cp server/deploy/.env.example server/deploy/.env   # then edit it
   sudo mkdir -m 700 /srv/pocketlarder
   sudo chown 65532:65532 /srv/pocketlarder
   ```

2. Build the image from this clone and start the server:

   ```bash
   docker compose -f server/deploy/compose.yaml up -d --build
   ```

3. Put a reverse proxy in front. With Caddy on the same host (it reaches the port compose publishes on the host's loopback), use this block, as in `server/deploy/Caddyfile`, with `lists.example.com` replaced by your domain:

   ```
   lists.example.com {
   	encode zstd gzip
   	reverse_proxy 127.0.0.1:8080
   }
   ```

4. Create the first admin:

   ```bash
   docker compose -f server/deploy/compose.yaml exec pocketlarder pocketlarder invite --new-admin <name>
   ```

5. Back up the database:

   ```bash
   docker compose -f server/deploy/compose.yaml exec pocketlarder pocketlarder backup /data/backup-$(date +%F).db
   ```

   Scheduling backups, and copying them off the server, is the host's job.

### Hosting notes

- An existing data directory or database keeps its current file mode. `serve` creates them 0700/0600 only when they don't exist yet. If you bring existing data along, check that the data directory is 0700, the database files are 0600, and the owner is 65532:65532 in the container.
- `POCKETLARDER_LISTEN` defaults to `:8080`, which serves plain HTTP on every interface. On a bare host behind a reverse proxy, set `POCKETLARDER_LISTEN=127.0.0.1:<port>`. The compose file already publishes the port on 127.0.0.1 only.
- `backup <path>` writes a 0600 file but refuses any path that already exists. Back up into a private directory such as `/data`, and use a fresh name for each run, for example one with the date in it. A second backup on the same day needs a different name.
- Run `invite` with `docker compose exec` (as above) or `docker compose run --rm`, so invite URLs don't stay in container logs.
- Invite URLs are secrets, and `invite` prints them to stdout. With `exec` the output goes only to your terminal. With `docker compose run` without `--rm` it is captured by the container's logging driver and the stopped container stays around, so the URL remains in `docker logs` until you run `docker rm` on it. With the default `json-file` driver it is also on disk under `/var/lib/docker/containers/`. With `journald` or `syslog` it is also in the host journal or syslog files, and with a remote driver (for example `fluentd`, `gelf` or `awslogs`) on the remote log server. `docker rm` does not remove those copies, so clean them up there too, and treat an invite that was logged as exposed: revoke it with `POST /v1/invites/revoke` (see [server/API.md](server/API.md)) or let it expire after 24 hours.

## License

The server (`server/`) is AGPL-3.0. The iOS app (`ios/`) is MPL-2.0. See the root `LICENSE`.
