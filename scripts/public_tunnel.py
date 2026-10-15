#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
public_tunnel.py — 把本机预览服务映射到公网，并【断线自动重连】

免费公网隧道（localhost.run / serveo.net，均无需账号）给的是**临时随机子域**，
且空闲/网络抖动会被回收。本脚本负责：
  1. 建立 SSH 反向隧道（-R 80:localhost:<port>）
  2. 从输出里解析出公网地址
  3. **实测该地址可访问**（带令牌打 /api/health）后才发布，避免给出死链
  4. 把最新地址写入 --url-file（默认 /workspace/PUBLIC_URL.txt）
  5. 隧道断开后自动重连、自动更新地址

用法：
    python3 scripts/public_tunnel.py --port 8765 --token <token>
    # 稳定域名（可选）：先在 https://console.serveo.net/ssh/keys 用 GitHub/Google
    # 登录注册本机 SSH 公钥，然后：
    python3 scripts/public_tunnel.py --port 8765 --token <token> \
        --engine serveo --identity ~/.ssh/serveo_key --subdomain my-name
"""

import argparse
import os
import re
import subprocess
import sys
import time
import urllib.request

URL_RE = re.compile(
    r"https://([a-zA-Z0-9.\-]+\.(?:lhr\.life|serveo\.net|serveousercontent\.com|localtunnel\.me))")


def probe(url, token, timeout=12):
    """实测公网地址是否真的可访问"""
    u = url + "/api/health" + (("?k=" + token) if token else "")
    try:
        with urllib.request.urlopen(u, timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def publish(url, token, url_file):
    full = url + ("/?k=" + token if token else "/")
    try:
        d = os.path.dirname(os.path.abspath(url_file))
        if d:
            os.makedirs(d, exist_ok=True)
        with open(url_file, "w", encoding="utf-8") as f:
            f.write(full + "\n")
    except Exception as e:  # noqa: BLE001
        print("[tunnel] 写 url-file 失败: %s" % e, flush=True)
    print("[tunnel] ✅ 公网地址: %s" % full, flush=True)
    return full


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--token", default="")
    ap.add_argument("--engine", choices=["localhost.run", "serveo"], default="localhost.run")
    ap.add_argument("--identity", default="", help="serveo 固定子域需要已注册的私钥")
    ap.add_argument("--subdomain", default="", help="serveo 固定子域（需先注册 key）")
    ap.add_argument("--url-file", default="/workspace/PUBLIC_URL.txt")
    args = ap.parse_args()

    if args.engine == "serveo":
        target = "serveo.net"
        remote = ("%s:80:localhost:%d" % (args.subdomain, args.port)) if args.subdomain \
            else ("80:localhost:%d" % args.port)
    else:
        target = "nokey@localhost.run"
        remote = "80:localhost:%d" % args.port

    cmd = ["ssh",
           "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
           "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
           "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=15",
           "-T", "-R", remote, target]
    if args.identity:
        cmd = cmd[:1] + ["-i", os.path.expanduser(args.identity)] + cmd[1:]

    attempt = 0
    while True:
        attempt += 1
        print("[tunnel] (第 %d 次) 连接 %s …" % (attempt, target), flush=True)
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, bufsize=1)
        except Exception as e:  # noqa: BLE001
            print("[tunnel] 启动 ssh 失败: %s" % e, flush=True)
            time.sleep(5)
            continue

        url, published = None, False
        try:
            for line in p.stdout:
                line = line.rstrip("\n")
                if line.strip():
                    print("[tunnel] %s" % line, flush=True)
                if not url:
                    m = URL_RE.search(line)
                    if m:
                        url = "https://" + m.group(1)
                        # 实测可用后再发布
                        ok = False
                        for _ in range(6):
                            if probe(url, args.token):
                                ok = True
                                break
                            time.sleep(2)
                        if ok:
                            publish(url, args.token, args.url_file)
                            published = True
                        else:
                            print("[tunnel] 域名 %s 实测不可达，等待隧道就绪…" % url, flush=True)
                            for _ in range(10):
                                time.sleep(2)
                                if probe(url, args.token):
                                    publish(url, args.token, args.url_file)
                                    published = True
                                    break
                            if not published:
                                print("[tunnel] 放弃该域名，重连", flush=True)
                                break
        except Exception as e:  # noqa: BLE001
            print("[tunnel] 读取输出异常: %s" % e, flush=True)
        try:
            p.wait(timeout=5)
        except Exception:
            p.terminate()
        print("[tunnel] 连接结束(exit=%s)，3 秒后重连…" % p.returncode, flush=True)
        time.sleep(3)


if __name__ == "__main__":
    main()
