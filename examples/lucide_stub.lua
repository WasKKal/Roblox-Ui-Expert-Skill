-- ==========================================
-- lucide_stub.lua — Lucide 模块最小桩（仅供无头冒烟测试离线使用）
-- ==========================================
-- 真实库 DynamicCowUI.lua 的 loadLucide() 会按以下顺序尝试从 CDN 下载
-- lucide/init.lua，然后 loadstring(content)() 加载，并调用 module.GetAsset(name)：
--   1. https://gcore.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua
--   2. https://cdn.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua
--   3. https://raw.githubusercontent.com/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua
--
-- 无头 Skill 运行在隔离沙箱，CDN 不可达。本桩通过 run_ui.py --lib 把上述 3 个
-- URL 映射到本文件，使 loadLucide() 离线成功。图标像素对无头布局/结构验证无意义，
-- 桩仅返回确定性 rbxasset:// URL；真实库中 getcustomasset/getsynasset 亦在 mock 下
-- 返回确定性 URL，渲染器不会真正解码图像，因此不影响任何布局/层级/动画断言。
--
-- 必须包含的标记（否则库会判定为下载失败而取消 UI 加载）：
--   * 字节数 > 5000（库 loadLucide 校验 #content > 5000）
--   * 字面串 "lucide-icon-latest"（库本地缓存校验用）
-- 下方 padding 段落仅用于满足上述体积约束，无任何运行时作用。
--
-- 验证范围：本桩仅替换「图标资源下载」这一步，库的余下 7000+ 行逻辑
-- （CreateWindow / 全控件工厂 / 补间 / task 调度 / 入场状态机 / ShowNotify 等）
-- 全部为真实代码路径，未经任何裁剪。
-- ==========================================

-- PADDING-START lucide-icon-latest
-- The following block is inert filler that exists solely so this stub exceeds the
-- 5000-byte minimum that DynamicCowUI.loadLucide() enforces before it trusts a
-- downloaded module. It carries no executable behaviour. The marker string
-- "lucide-icon-latest" above is matched by the library's cache validation.
local PAD = {
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
  "lucide-icon-latest", "lucide-icon-latest", "lucide-icon-latest",
}
-- PADDING-END

local Lucide = {}

function Lucide.GetAsset(name)
    name = name or "unknown"
    return { Url = "rbxasset://lucide-stub/" .. tostring(name) }
end

function Lucide.GetAssetAsync(name)
    return Lucide.GetAsset(name)
end

return Lucide
