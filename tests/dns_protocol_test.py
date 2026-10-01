#!/usr/bin/env python3
"""Real AdGuard Home queries against a deterministic loopback upstream."""
import base64
import ipaddress
import json
import os
from pathlib import Path
import socket
import struct
import threading
import time
import urllib.request


def values(path):
    return dict(line.split("=", 1) for line in Path(path).read_text().splitlines() if "=" in line)


ports = values(Path(os.environ["AGH_STATE_DIR"]) / "ports.conf")
creds = values(Path(os.environ["AGH_STATE_DIR"]) / "credentials.conf")
api_base = "http://127.0.0.1:" + ports["web_port"]
credential = base64.b64encode((creds["username"] + ":" + creds["password"]).encode()).decode()


def api(path, payload=None):
    headers = {"Authorization": "Basic " + credential, "Content-Type": "application/json"}
    request = urllib.request.Request(api_base + path, headers=headers,
                                     data=None if payload is None else json.dumps(payload).encode())
    with urllib.request.urlopen(request, timeout=5) as response:
        body = response.read()
    return json.loads(body) if body.strip().startswith((b"{", b"[")) else {}


upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
upstream.bind(("127.0.0.1", 0))
upstream.settimeout(0.2)
stop = threading.Event()
seen = []


def serve():
    while not stop.is_set():
        try:
            query, peer = upstream.recvfrom(4096)
        except socket.timeout:
            continue
        end = 12
        labels = []
        while query[end]:
            length = query[end]
            labels.append(query[end + 1:end + 1 + length].decode())
            end += length + 1
        end += 1
        qtype = struct.unpack("!H", query[end:end + 2])[0]
        seen.append(".".join(labels))
        address = ipaddress.ip_address("192.0.2.23" if qtype == 1 else "2001:db8::23").packed
        answer = b"\xc0\x0c" + struct.pack("!HHIH", qtype, 1, 10, len(address)) + address
        packet = query[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0) + query[12:end + 4] + answer
        upstream.sendto(packet, peer)


thread = threading.Thread(target=serve, daemon=True)
thread.start()


def exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        assert chunk, "short TCP DNS response"
        data += chunk
    return data


def query_dns(name, family, stream=False, qtype=1):
    packet = struct.pack("!HHHHHH", 0x5151, 0x0100, 1, 0, 0, 0)
    packet += b"".join(bytes([len(label)]) + label.encode() for label in name.split("."))
    packet += b"\0" + struct.pack("!HH", qtype, 1)
    host = "127.0.0.1" if family == socket.AF_INET else "::1"
    with socket.socket(family, socket.SOCK_STREAM if stream else socket.SOCK_DGRAM) as sock:
        sock.settimeout(5)
        sock.connect((host, int(ports["dns_port"])))
        if stream:
            sock.sendall(struct.pack("!H", len(packet)) + packet)
            response = exact(sock, struct.unpack("!H", exact(sock, 2))[0])
        else:
            sock.send(packet)
            response = sock.recv(4096)
    assert response[:2] == packet[:2]
    return response


try:
    for attempt in range(50):
        state = api("/control/filtering/status")
        if any(item["id"] == 10001 and item.get("rules_count", 0) > 1000 for item in state["filters"]):
            break
        time.sleep(0.2)
    else:
        raise AssertionError("bundled anti-AD was not loaded")
    api("/control/dns_config", {"upstream_dns": ["127.0.0.1:" + str(upstream.getsockname()[1])],
                               "fallback_dns": [], "bootstrap_dns": [], "ratelimit": 0})
    api("/control/cache_clear", {})
    for family in (socket.AF_INET, socket.AF_INET6):
        for stream in (False, True):
            for qtype in (1, 28):
                response = query_dns("gdt.qq.com", family, stream, qtype)
                assert response[3] & 15 in (0, 3), "blocked response failed"
                assert "gdt.qq.com" not in seen, "ad query leaked to upstream"
                # Never block the whole WeChat domain to claim ad removal.
                response = query_dns("weixin.qq.com", family, stream, qtype)
                address = ipaddress.ip_address("192.0.2.23" if qtype == 1 else "2001:db8::23").packed
                assert response[3] & 15 == 0 and address in response, "normal DNS did not resolve"
    for index in range(40):
        response = query_dns("burst" + str(index) + ".example.test", socket.AF_INET)
        assert ipaddress.ip_address("192.0.2.23").packed in response, "loopback burst rate limited"
    print("real DNS passed: offline filtering, IPv4/IPv6 UDP/TCP, A/AAAA, normal domains, burst")
finally:
    stop.set()
    thread.join(timeout=1)
    upstream.close()
