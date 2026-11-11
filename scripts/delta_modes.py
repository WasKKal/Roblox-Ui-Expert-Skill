#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Delta 执行器环境模式清单（Python 侧单一数据源）。

与 scripts/delta_env.lua 的 DeltaEnv.MODES 一一对应，改动需两处同步。
语义见 references/runtime-notes.md 的「Delta 执行器环境特征」章节。
"""

DELTA_MODES = (
    "getfenv_real",    # 默认：getgenv/getfenv 都返回独立 REAL_ENV
    "getfenv_empty",   # getfenv 返回空 _G
    "getfenv_err",     # getfenv 抛错
    "no_getfenv",      # getfenv 缺失
    "no_getgenv",      # getgenv 缺失，getfenv 返回空 _G
    "getrenv_real",    # getrenv 返回 REAL_ENV
    "getrenv_empty",   # getrenv 返回空 _G
    "getrenv_nil",     # getrenv 返回 nil
    "G_nil",           # _G = nil
)

DEFAULT_DELTA_MODE = "getfenv_real"

DELTA_ENV_SCRIPT = "delta_env.lua"
