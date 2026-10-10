#!/usr/bin/env python3
"""Talk to the ZTE F50 stock web UI (goform API) without a browser.

    zte-web.py status        firmware, network, ADB switch (read only)
    zte-web.py adb-on        turn on the hidden "USB port" switch (index.html#usb_port)
    zte-web.py adb-off       turn it off again
    zte-web.py reboot        reboot the device

Environment: ZTE_HOST (default 192.168.0.1), ZTE_PASSWORD (default admin).

Login follows the stock web UI (WEB_ATTR_IF_SUPPORT_SHA256 = 2):
    password = SHA256(SHA256(pw) + LD)               (hex, upper case)
    AD       = SHA256(SHA256(wa_inner_version + cr_version) + RD)   on every set command
"""
import hashlib
import http.cookiejar
import json
import os
import sys
import urllib.parse
import urllib.request

HOST = "http://" + os.environ.get("ZTE_HOST", "192.168.0.1")
PASSWORD = os.environ.get("ZTE_PASSWORD", "admin")
HEADERS = {"Referer": HOST + "/index.html", "X-Requested-With": "XMLHttpRequest"}

_opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
    urllib.request.ProxyHandler({}),
)


def sha(s):
    return hashlib.sha256(s.encode()).hexdigest().upper()


def get(**q):
    q.setdefault("isTest", "false")
    url = HOST + "/goform/goform_get_cmd_process?" + urllib.parse.urlencode(q)
    with _opener.open(urllib.request.Request(url, headers=HEADERS), timeout=10) as r:
        return json.loads(r.read() or b"{}")


def post(**d):
    d.setdefault("isTest", "false")
    req = urllib.request.Request(HOST + "/goform/goform_set_cmd_process",
                                 data=urllib.parse.urlencode(d).encode(), headers=HEADERS)
    with _opener.open(req, timeout=10) as r:
        return json.loads(r.read() or b"{}")


def login():
    r = post(goformId="LOGIN", password=sha(sha(PASSWORD) + get(cmd="LD")["LD"]))
    if str(r.get("result")) not in ("0", "4"):
        sys.exit("login failed: %s" % r)


def ad():
    v = get(cmd="wa_inner_version,cr_version", multi_data="1")
    return sha(sha(v["wa_inner_version"] + v["cr_version"]) + get(cmd="RD")["RD"])


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        login()
        print(json.dumps(get(cmd="cr_version,wa_inner_version,network_type,network_provider,ppp_status,"
                                 "sim_slot,dual_sim_support,usb_port_switch", multi_data="1"),
                         ensure_ascii=False, indent=1))
    elif cmd in ("adb-on", "adb-off"):
        login()
        r = post(goformId="USB_PORT_SETTING", usb_port_switch="1" if cmd == "adb-on" else "0", AD=ad())
        print("set:", r.get("result"), "now:", get(cmd="usb_port_switch").get("usb_port_switch"))
    elif cmd == "reboot":
        login()
        print("reboot:", post(goformId="REBOOT_DEVICE", AD=ad()).get("result"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
