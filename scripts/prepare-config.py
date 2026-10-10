#!/usr/bin/env python3
"""Turns your own mihomo/Clash config into the one the F50 runs (build/config.yaml).

    prepare-config.py YOUR.yaml --secret PANEL_SECRET [--manual GROUP]... [--first GROUP=NODE]...

Proxies, groups and rules stay as they are. Changed for the F50:
  * the panel (external-controller) on 0.0.0.0:19090 with the secret; port 9090 is taken by a ZTE service
  * external-ui: ui (the bundled metacubexd)
  * only private source addresses may use the proxy ports (lan-allowed-ips), and they need no password;
    the device has a public IPv6 address on mobile data, so anyone else would need PROXY_USER/PROXY_PASS
  * redir-port / tproxy-port / tun are removed: they need root
  * GeoIP from the bundled Country.mmdb, no download at start
  * --manual GROUP turns a url-test/fallback group into a select group (choice kept across reboots)
  * --first GROUP=NODE puts NODE first in GROUP (the default choice of a select group)
"""
import argparse
import secrets
import string
import yaml

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("--secret", required=True)
ap.add_argument("--out", default="build/config.yaml")
ap.add_argument("--manual", action="append", default=[])
ap.add_argument("--first", action="append", default=[])
a = ap.parse_args()

d = yaml.safe_load(open(a.src, encoding="utf-8"))
for k in ("redir-port", "tproxy-port", "tun", "external-ui-url", "external-ui-name"):
    d.pop(k, None)
alnum = string.ascii_letters + string.digits
d.update({
    "allow-lan": True,
    "bind-address": "*",
    "external-controller": "0.0.0.0:19090",
    "secret": a.secret,
    "external-ui": "ui",
    "authentication": ["f50:" + "".join(secrets.choice(alnum) for _ in range(20))],
    "skip-auth-prefixes": ["127.0.0.1/8", "192.168.0.0/16"],
    "lan-allowed-ips": ["127.0.0.0/8", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"],
    "geodata-mode": False,
    "geo-auto-update": False,
})
d.setdefault("profile", {})["store-selected"] = True
groups = {g["name"]: g for g in d.get("proxy-groups") or []}
direct_like = {n for n, g in groups.items() if g.get("type") == "select" and g.get("proxies") == ["DIRECT"]} | {"DIRECT"}
for g in groups.values():
    if g.get("type") in ("url-test", "fallback", "load-balance"):
        g["proxies"] = [p for p in g.get("proxies") or [] if p not in direct_like]
for name in a.manual:
    g = groups[name]
    for k in ("url", "interval", "tolerance", "lazy", "timeout", "strategy"):
        g.pop(k, None)
    g["type"] = "select"
for spec in a.first:
    name, node = spec.split("=", 1)
    g = groups[name]
    g["proxies"] = [node] + [p for p in g["proxies"] if p != node]
yaml.safe_dump(d, open(a.out, "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
print("wrote", a.out)
