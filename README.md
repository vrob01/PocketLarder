# PocketLarder

PocketLarder is a self-hosted, open-source shopping list app for one household. It does one job, shopping lists, and leaves everything else to other tools, in the spirit of "one job, one tool".

The server API is described in [server/API.md](server/API.md).

## Self-hosting

Run all commands from the repo root.

1. Create your settings file and the data directory. In `server/deploy/.env`, set `POCKETLARDER_PUBLIC_URL` to your own `https://` address, the same host as the Caddy site below, and `POCKETLARDER_HOST_DATA_DIR` to the host directory that holds the database (the example uses `/srv/pocketlarder`; keep it outside the repo), and `POCKETLARDER_PROXY_NETWORK` to the Docker network that PocketLarder shares with the reverse proxy. Settings that depend on your deployment live in `.env`, which git ignores, so `git pull` upgrades never conflict with `compose.yaml`. That directory is bind-mounted at `/data` and must belong to the container user (65532:65532):

   ```bash
   cp server/deploy/.env.example server/deploy/.env   # then edit it
   sudo mkdir -m 700 /srv/pocketlarder
   sudo chown 65532:65532 /srv/pocketlarder
   ```

2. Create the proxy network (with the name from `.env`), build the image from this clone and start the server:

   ```bash
   docker network create pocketlarder
   docker compose -f server/deploy/compose.yaml up -d --build
   ```

3. Put a reverse proxy in front. PocketLarder publishes no port; only containers on the proxy network reach it, so other services can stay on networks of their own. Run Caddy in a container and attach it to that network in Caddy's compose file:

   ```yaml
   services:
     caddy:
       networks: [pocketlarder]
   networks:
     pocketlarder:
       external: true
   ```

   Then use this block, as in `server/deploy/Caddyfile`, with `lists.example.com` replaced by your domain:

   ```
   lists.example.com {
   	encode zstd gzip
   	reverse_proxy pocketlarder:8080
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
- `POCKETLARDER_LISTEN` defaults to `:8080`, which serves plain HTTP on every interface. On a bare host behind a reverse proxy, set `POCKETLARDER_LISTEN=127.0.0.1:<port>`. The compose container is reachable only from the proxy network.
- The iOS app refuses every HTTP redirect, so its token can never follow one to another host. Serve PocketLarder directly at `POCKETLARDER_PUBLIC_URL`, the address in your invites. If the proxy redirects that address, for example from the bare domain to `www` or to an SSO login page, every request from the app fails. Forwarding with `reverse_proxy`, as above, isn't a redirect and works.
- `backup <path>` writes a 0600 file but refuses any path that already exists. Back up into a private directory such as `/data`, and use a fresh name for each run, for example one with the date in it. A second backup on the same day needs a different name.
- Run `invite` with `docker compose exec` (as above). It is the only way that keeps invite URLs out of every log. `docker compose run` sends the output to the container's logging driver, with or without `--rm`; if you use it anyway, write `docker compose -f server/deploy/compose.yaml run --rm pocketlarder invite <name>` (the entrypoint already is `pocketlarder`).
- Invite URLs are secrets, and `invite` prints them to stdout. With `exec` the output goes only to your terminal. With `docker compose run` it goes to the logging driver. With the default `json-file` or `local` driver it is in `docker logs` and on disk under `/var/lib/docker/containers/`; `--rm` removes that copy, without `--rm` you must `docker rm` the stopped container. With `journald` or `syslog` it is also in the host journal or syslog files, and with a remote driver (for example `fluentd`, `gelf` or `awslogs`) on the remote log server, and `--rm` does not remove those. Treat an invite that was logged as exposed and revoke it: `docker compose -f server/deploy/compose.yaml exec pocketlarder pocketlarder invite --revoke <name>`. An admin who already has a paired device can instead use `POST /v1/invites/revoke` (see [server/API.md](server/API.md)). Otherwise the invite expires after 24 hours. **Warning:** anyone who can read the logs while an invite is outstanding and redeems it first can impersonate that member, in the worst case the first admin.
- The data directory is owned by uid 65532 on the host, so any host account with that uid can read the database.

## The iOS app

The iPhone app lives in `ios/`. It needs a PocketLarder server (see Self-hosting), an iPhone with iOS 27, and a Mac with Xcode 27 to install it.

1. Copy `ios/Config/Local.xcconfig.example` to `ios/Config/Local.xcconfig`. Set your Apple developer team and a bundle ID of your own.
2. Open `ios/PocketLarder.xcodeproj` in Xcode, pick your iPhone and run the `PocketLarder` scheme.
3. Create an invite on the server with `pocketlarder invite <name>`, then open the link on the iPhone or paste it into "Enter invite".

With a free Apple ID, the app stops opening after 7 days: install it again from Xcode.

To use PocketLarder in another language than your iPhone's, open Settings > Apps > PocketLarder > Language.

## License

The server (`server/`) is AGPL-3.0. The iOS app (`ios/`) is MPL-2.0. See the root `LICENSE`.
