#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""自动为无头渲染补齐常用库映射，避免「静默失败」。

真实 Roblox UI 库普遍通过 game:HttpGet 从 CDN 下载 lucide/init.lua，
再由 module.GetAsset(name) 拿到图标资源 URL。无头环境没有外网，
若调用方没有显式 --lib 注册这些 URL，loadLucide() 会拿到空串并静默失败，
结果是所有 ImageLabel.Image 为空、整屏图标全部不渲染，且没有任何报错提示——
这类问题极难排查。

本模块在解析 --lib 之前，把仓库自带的离线桩 examples/lucide_stub.lua
自动挂到这些已知 URL 上。调用方通过 --lib 显式注册的同名 URL 始终优先，
也可用 --no-builtin-libs 完全关闭此行为。
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILTIN_LUCIDE_STUB = os.path.join(ROOT, "examples", "lucide_stub.lua")

LUCIDE_URLS = (
    "https://gcore.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua",
    "https://cdn.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua",
    "https://raw.githubusercontent.com/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua",
)


def with_builtin_libs(specs, enabled=True):
    """返回补齐内置库映射后的 --lib spec 列表（不改变入参）。

    specs: 用户传入的 ["URL=PATH", ...] 列表
    enabled: False 时原样返回（用于 --no-builtin-libs）
    """
    out = list(specs)
    if not enabled or not os.path.exists(BUILTIN_LUCIDE_STUB):
        return out
    registered = set()
    for spec in out:
        registered.add(spec.partition("=")[0])
    for url in LUCIDE_URLS:
        if url not in registered:
            out.append(url + "=" + BUILTIN_LUCIDE_STUB)
    return out
