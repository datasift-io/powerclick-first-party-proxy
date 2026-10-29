# PowerClick First-Party Proxy (server-side GTM client)

Serves the [PowerClick](https://powerclick.io) loader and its event posts from your server container's own domain (for example
`ss.example.com`), so browsers and ad blockers see a first-party request instead of PowerClick's domains.

## Setup

1. Server container: **Templates → Client Templates → Search Gallery → PowerClick First-Party Proxy**.
2. **Clients → New → PowerClick First-Party Proxy**. Enter your PowerClick **Account ID**; keep the default paths
   (`/c/l.js` for the script, `/c/e` for events) or choose your own neutral paths. Save and publish.
3. Check that `https://<your server container domain>/c/l.js` returns a script.
4. In the web container, point the PowerClick tag (or your PowerClick script tag) at that URL.

For visitor location, enable your hosting provider's geo headers (on Stape: the **Geo headers** power-up).

## What it does

- `GET <script path>`: fetches your account's loader from `js.powerclick.io`, caches it for 5 minutes and serves the
  last good copy if PowerClick's script host is unreachable.
- `POST <event path>`: forwards the body unchanged to `ingest.powerclick.io` for your account, with the visitor's
  user agent, IP and geo headers.
- Claims only those two paths; every other request is left to your other clients.

## Permissions

- **Reads request:** path, method, headers, body and remote address of the requests it claims.
- **Sends HTTP requests:** `https://js.powerclick.io/*`, `https://ingest.powerclick.io/*`.
- **Accesses template storage:** the cached loader script.
- **Returns response / writes response:** answers the two paths it claims.
