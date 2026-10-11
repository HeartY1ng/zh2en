-- sentence_tap.lua：记录"这句话打到哪了"，写进 zh2en/live.json 给浮窗小程序看（zh2en 第 2 步）
--
-- 它是一个 processor（按键处理器），排在处理器列表最前面，但所有按键一律返回 kNoop（"我不管"），
-- 所以绝不会吞掉、改变你的任何按键，只是先看一眼。它做三件事：
--   1. commit_notifier：看到"上屏了什么字"，累加成当前这句话
--   2. update_notifier：看到"正在打、还没上屏的部分"
--   3. 不在输入状态时的按键：退格删字、回车结束一句、Esc/光标移动/快捷键作废这一句
-- 一句话结束（上屏的字以 。！？ 结尾，或者按了回车）就标记 done，浮窗收到后去要地道版。

local kNoop = 2
local IDLE_RESET = 60   -- 秒：这么久没动静，下次打字就算新的一句
local ENDS = { ["。"] = true, ["！"] = true, ["？"] = true, ["!"] = true, ["?"] = true, ["…"] = true }

local path, tmp            -- live.json 和临时文件
local seq, counter = 0, 0  -- 写文件次数、句子计数（所有会话共用）
local last_key = nil       -- 上次写出的内容，没变就不重复写

local function json_str(s)
  return '"' .. (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end)) .. '"'
end

local function last_char(s)   -- 最后一个 UTF-8 字符
  return s:match("[%z\1-\127\194-\244][\128-\191]*$") or ""
end

local function write(env)
  local key = env.sid .. "\0" .. env.buf .. "\0" .. env.composing .. "\0" .. tostring(env.done)
  if key == last_key then return end
  last_key = key
  seq = seq + 1
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(string.format('{"seq":%d,"sid":%d,"committed":%s,"composing":%s,"done":%s}',
    seq, env.sid, json_str(env.buf), json_str(env.composing), env.done and "true" or "false"))
  f:close()
  os.rename(tmp, path)   -- 先写临时文件再改名：浮窗永远读不到写了一半的文件
end

local function new_sentence(env)
  counter = counter + 1
  env.sid = os.time() * 100 + counter % 100
  env.buf, env.composing, env.done = "", "", false
end

local function touch(env)   -- 有新内容进来：上一句已结束、或太久没动，就开始新的一句
  local now = os.time()
  if env.done or now - env.last > IDLE_RESET then new_sentence(env) end
  env.last = now
end

local function on_update(env, ctx)
  local comp = ""
  if ctx:is_composing() then
    touch(env)
    comp = ctx:get_commit_text()
    if not comp:find("[\128-\255]") then
      comp = ""                        -- 还全是拼音字母，没有汉字
    else
      comp = comp:gsub("[%a']+$", "")  -- 去掉末尾还没转换的拼音
    end
  end
  env.composing = comp
  write(env)
end

local function on_commit(env, ctx)
  touch(env)
  env.buf = env.buf .. ctx:get_commit_text()
  env.composing = ""
  if ENDS[last_char(env.buf)] then env.done = true end
  write(env)
end

local function init(env)
  -- 放在系统临时目录：不进 Time Machine 备份，重启就清空；浮窗消失时浮窗程序会把它删掉
  local dir = (os.getenv("TMPDIR") or "/tmp/"):gsub("/?$", "/") .. "zh2en"
  path = dir .. "/live.json"
  tmp = path .. ".tmp"
  local probe = io.open(dir .. "/.keep", "a")
  if probe then probe:close() else os.execute('mkdir -p "' .. dir .. '"') end
  env.last = 0
  new_sentence(env)
  local ctx = env.engine.context
  env.update_conn = ctx.update_notifier:connect(function(c) on_update(env, c) end)
  env.commit_conn = ctx.commit_notifier:connect(function(c) on_commit(env, c) end)
end

local function fini(env)
  env.update_conn:disconnect()
  env.commit_conn:disconnect()
end

local function func(key, env)
  if key:release() then return kNoop end
  local ctx = env.engine.context
  if ctx:is_composing() then return kNoop end   -- 正在打拼音时的按键交给雾凇，不归我们管
  local r = key:repr()
  if r == "BackSpace" then
    if env.buf ~= "" and not env.done then
      env.buf = env.buf:sub(1, #env.buf - #last_char(env.buf))
      env.last = os.time()
      write(env)
    end
  elseif r == "Return" or r == "KP_Enter" then
    if env.buf:find("[\228-\233]") then env.done = true; write(env) end   -- 含汉字（UTF-8 首字节 E4–E9）才算一句
  elseif r == "Escape" then
    new_sentence(env); write(env)
  elseif r:find("Control+", 1, true) or r:find("Super+", 1, true)
      or r == "Left" or r == "Right" or r == "Up" or r == "Down" or r == "Home" or r == "End" then
    -- 光标移动或快捷键（粘贴、撤销、全选…）：已经跟踪不到真实文本，这一句作废
    if env.buf ~= "" then new_sentence(env); write(env) end
  else
    -- 中文模式下原样上屏的数字和空格算进这句话（"明天3点"）。
    -- 英文模式下打的任何字一律不记：那可能是密码、命令、验证码。
    if not ctx:get_option("ascii_mode") and env.buf ~= "" then
      local ch = (r == "space") and " " or ((#r == 1 and r:match("%d")) and r or nil)
      if ch then env.buf = env.buf .. ch; env.last = os.time(); write(env) end
    end
  end
  return kNoop
end

return { init = init, func = func, fini = fini }
