-- english_hint.lua：给鼠须管的每个候选词后面加上英文释义（zh2en 第 1 步）
--
-- 它在 Rime 流水线里的位置：
--   按键 → 拼音变候选（雾凇词库）→ 各种过滤器 → 【english_hint】→ 候选框
-- 过滤器拿到的是一串候选词，逐个查 zh2en/cedict.tsv，查到了就把英文追加到注释里，
-- 然后原样交出去（yield）。不改候选的顺序，也不增减候选。

local dict = nil   -- 词典只加载一次，所有输入会话共用

local function load_dict()
  if dict then return end
  dict = {}
  local path = rime_api.get_user_data_dir() .. "/zh2en/cedict.tsv"
  local f = io.open(path, "r")
  if not f then
    log.warning("english_hint: 找不到词典 " .. path)
    return
  end
  local n = 0
  for line in f:lines() do
    local tab = line:find("\t", 1, true)
    if tab then
      dict[line:sub(1, tab - 1)] = line:sub(tab + 1)
      n = n + 1
    end
  end
  f:close()
  log.info("english_hint: 词典已加载 " .. n .. " 条")
end

local function init(env)
  load_dict()
end

local function filter(input, env)
  for cand in input:iter() do
    local en = dict[cand.text]
    if en then
      local c = cand:get_genuine()
      -- 雾凇自己也可能写了注释（比如错音提示），保留它，英文接在后面
      if c.comment == "" then
        c.comment = en
      elseif not c.comment:find(en, 1, true) then   -- 同一个候选被过滤两次时不重复追加
        c.comment = c.comment .. "  " .. en
      end
    end
    yield(cand)
  end
end

return { init = init, func = filter }
