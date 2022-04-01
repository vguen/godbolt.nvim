local api = vim.api
local cmd = vim.cmd
local fun = vim.fn
local fmt = string.format
local wo_set = api.nvim_win_set_option
local term_escapes = "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]"
local map = nil
local nsid = nil
local ns_hi_id = nil

local godbolt_src_buffers = {}
local godbolt_asm_buffers = {}

local function prepare_buf(text, name, reuse_3f, source_buf)
  local buf
  if (reuse_3f and (type(map[source_buf]) == "table")) then
    -- TODO: the reuse option only seems to reuse the last created buffer
    buf = table.maxn(map[source_buf])
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_option(buf, "readonly", false)
  else
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "bufhidden", "delete")
    api.nvim_buf_set_option(buf, "swapfile", false)
  end
  api.nvim_buf_set_option(buf, "filetype", "asm")
  api.nvim_buf_set_lines(buf, 0, -1, true, vim.split(text, "\n", {trimempty = true}))
  api.nvim_buf_set_name(buf, name)
  return buf
end
local function setup_aucmd(source_buf, asm_buf)
  cmd("augroup Godbolt")
  cmd(fmt("autocmd CursorMoved <buffer=%s> lua require('godbolt.assembly')['update-hl'](%s, %s)", source_buf, source_buf, asm_buf))
  cmd(fmt("autocmd CursorMoved <buffer=%s> lua require('godbolt.assembly')['update-hl'](%s, %s)", asm_buf, source_buf, asm_buf))
  -- TODO: reenable it but handle both asm_buf and source_buf
  cmd(fmt("autocmd BufLeave <buffer=%s> lua require('godbolt.assembly').clear(%s)", source_buf, source_buf))
  cmd(fmt("autocmd BufLeave <buffer=%s> lua require('godbolt.assembly').clear(%s)", asm_buf, asm_buf))
  return cmd("augroup END")
end
local function make_qflist(err, bufnr)
  if next(err) then
    local tbl_15_auto = {}
    local i_16_auto = #tbl_15_auto
    for k, v in ipairs(err) do
      local val_17_auto
      do
        local entry = {text = string.gsub(v.text, term_escapes, ""), bufnr = bufnr}
        if v.tag then
          entry["col"] = v.tag.column
          entry["lnum"] = v.tag.line
        else
        end
        val_17_auto = entry
      end
      if (nil ~= val_17_auto) then
        i_16_auto = (i_16_auto + 1)
        do end (tbl_15_auto)[i_16_auto] = val_17_auto
      else
      end
    end
    return tbl_15_auto
  else
    return nil
  end
end
local function clear(buf)
  -- Is buf a source buf ?
  local is_source_buf = false
  for source_buf, _ in pairs(map) do
    if buf == source_buf then
      is_source_buf = true
    end
  end
  if is_source_buf then
    for asm_buf, _ in pairs(map[buf]) do
      api.nvim_buf_clear_namespace(asm_buf, nsid, 0, -1)
    end
    return nil
  end

  for source_buf, _ in pairs(map) do
    for asm_buf, _ in pairs(map[source_buf]) do
      if buf == asm_buf then
        api.nvim_buf_clear_namespace(source_buf, nsid, 0, -1)
      end
    end
  end
  return nil
end

local function old_asm_hl(entry, source_buf)
  local linenum = fun.line('.')
  local line = fun.getline(linenum)
  local asm_table = entry.asm
  for _, v in pairs(asm_table) do
    if (type(v.source) == "table") and (line == v.text) then
      vim.highlight.range(source_buf, nsid, "Visual", {v.source.line - 1, 0}, {v.source.line - 1, 100}, "linewise", true)
    end
  end
end

local function update_hl(source_buf, asm_buf)
  local curr_buf = fun.bufnr()

  if curr_buf == source_buf then
    api.nvim_buf_clear_namespace(asm_buf, nsid, 0, -1)
    local entry = map[source_buf][asm_buf]
    local offset = entry.offset
    local asm_table = entry.asm
    local linenum = ((fun.getcurpos()[2] - offset) + 1)
    for k, v in pairs(asm_table) do
      if type(v.source) == "table"
      and linenum == v.source.line then
        vim.highlight.range(asm_buf, nsid, "Visual", {(k - 1), 0}, {(k - 1), 100}, "linewise", true)
      end
    end
  elseif curr_buf == asm_buf then
    api.nvim_buf_clear_namespace(source_buf, nsid, 0, -1)
    -- old_asm_hl(map[source_buf][asm_buf], source_buf)
    local linenum = fun.getcurpos()[2]
    local toto = godbolt_asm_buffers[asm_buf][source_buf]
    local source_line = toto[1][2]
    for _, v in ipairs(toto) do
      source_line = v[2]
      if v[1] > linenum then
        break
      end
    end
    if source_line ~= -1 then
      -- Contrary to lua, vim index lines from 0 whereas lua index from 1
      local vim_source_line = source_line - 1
      vim.highlight.range(source_buf, nsid, "Visual", {vim_source_line, 0}, {vim_source_line, 100}, "linewise", true)
    end
  end
  return nil
end

local function extract_asm(asm_table)
  local str = ""
  for _, v in pairs(asm_table) do
    -- TODO: remove to many things (ie: the main lable) should it be handle here or should it be in asm-parser ?
    -- if type(v.source) == "table" and v.text then
    if v.text then
      str = (str .. "\n" .. v.text)
    end
  end
  return str
end

local function create_godbolt_src(asm_table, source_buf, asm_buf)
  if not godbolt_src_buffers[source_buf] then
    godbolt_src_buffers[source_buf] = {}
  end
  local source_lines = godbolt_src_buffers[source_buf]

  for i, v in pairs(asm_table) do
    if type(v.source) == "table" and v.source.line
    and v.text then
      local src_linenum = v.source.line
      if not source_lines[src_linenum] then
        source_lines[src_linenum] = {}
        source_lines[src_linenum][asm_buf] = {}
      end
      local generated_asm_lines = source_lines[src_linenum][asm_buf]
      if not generated_asm_lines[1] then
        generated_asm_lines[1] = i
      else
        generated_asm_lines[2] = i
      end
    end
  end
end

local function create_godbolt_asm(asm_table, asm_buf, src_buf)
  if not godbolt_asm_buffers[asm_buf] then
    godbolt_asm_buffers[asm_buf] = {}
    godbolt_asm_buffers[asm_buf][src_buf] = {}
  end
  local asm_lines = godbolt_asm_buffers[asm_buf][src_buf]

  local i, v = next(asm_table, nil)
  while i do
    -- if type(v.source) == "table" and v.source.line
    if v.text then
      local src_linenum = (type(v.source) == "table" or type(v.source) ~= "userdata") and v.source.line or -1
      i, v = next(asm_table, i)
      if src_linenum == -1 then
        while i
        and type(v.source) ~= "table"
        or type(v.source) == "userdata"
        do
          i, v = next(asm_table, i)
        end
      else
        while i
          and type(v.source) ~= "userdata"
          and src_linenum == v.source.line do
          i, v = next(asm_table, i)
        end
      end
      if i == nil then
        i = #asm_table
      end
      table.insert(asm_lines, {i, src_linenum})
    end
    i, v = next(asm_table, i)
  end
end

-- Set the background color based on the colormap config
local function set_hl_background(source_buf, asm_buf)
  local config = require("godbolt.init").config
  local colorscheme = config.colorscheme
  local colormap = config.colormap[colorscheme]

  for src_line, v in ipairs(godbolt_src_buffers[source_buf]) do
    vim.highlight.range(source_buf, ns_hi_id, "Visual", {src_line, 0}, {src_line, 100}, "linewise", true)
    local asm_lines = v[asm_buf]
    local asm_lines_start = asm_lines[1]
    local asm_lines_end = asm_lines[2] or asm_lines[1]
    vim.highlight.range(asm_buf, ns_hi_id, "Visual", {asm_lines_start, 0}, {asm_lines_end, 100}, "linewise", true)
  end
end

local function display(response, begin, name, reuse_3f)
  if (response.asm[1].text == "<Compilation failed>") then
    return vim.notify("godbolt.nvim: Compilation failed")
  end

  local source_buf = fun.bufnr()

  local qflist = nil
  if response.stderr then
    qflist = make_qflist(response.stderr, source_buf)
  end
  local quickfix_cfg = require("godbolt").config.quickfix
  local qf_winid = nil
  if (qflist and quickfix_cfg.enable) then
    fun.setqflist(qflist)
    if quickfix_cfg.auto_open then
      vim.cmd("copen")
      qf_winid = fun.win_getid()
    end

    api.nvim_set_current_win(qf_winid)

    return
  end

  local asm = extract_asm(response.asm)

  local source_winid = fun.win_getid()
  local asm_buf = prepare_buf(asm, name, reuse_3f, source_buf)

  create_godbolt_src(response.asm, source_buf, asm_buf)
  create_godbolt_asm(response.asm, asm_buf, source_buf)

  set_hl_background(source_buf, asm_buf)

  print("godbolt_src_buffers = " .. vim.inspect(godbolt_src_buffers))
  print("godbolt_asm_buffers = " .. vim.inspect(godbolt_asm_buffers))
  api.nvim_set_current_win(source_winid)
  local asm_winid
  if (reuse_3f and map[source_buf]) then
    asm_winid = map[source_buf][asm_buf].winid
  else
    cmd("vsplit")
    asm_winid = api.nvim_get_current_win()
  end
  api.nvim_set_current_win(asm_winid)
  api.nvim_win_set_buf(asm_winid, asm_buf)

  api.nvim_buf_set_option(asm_buf, "modifiable", false)
  api.nvim_buf_set_option(asm_buf, "readonly", true)

  wo_set(asm_winid, "number", false)
  wo_set(asm_winid, "relativenumber", false)
  wo_set(asm_winid, "spell", false)
  wo_set(asm_winid, "cursorline", false)

  api.nvim_set_current_win(source_winid)

  if not map[source_buf] then
    map[source_buf] = {}
  end

  map[source_buf][asm_buf] = {asm = response.asm, offset = begin, winid = asm_winid}
  update_hl(source_buf, asm_buf)

  return setup_aucmd(source_buf, asm_buf)
end

local function pre_display(begin, _end, compiler, options, reuse_3f)
  local lines = api.nvim_buf_get_lines(0, (begin - 1), _end, true)
  local text = fun.join(lines, "\n")
  local curl_cmd = (require("godbolt.init")).build_cmd(compiler, text, options, "asm")
  print(curl_cmd)
  local time = os.date("*t")
  local hour = time.hour
  local min = time.min
  local sec = time.sec
  local function _15_(_, _0, _1)
    -- TODO: print a pretty error when there is no response like when the instance cannot be reached by curl
    -- using vim.notify
    local file = io.open("godbolt_response_asm.json", "r")
    local response = file:read("*all")
    file:close()
    os.remove("godbolt_request_asm.json")
    os.remove("godbolt_response_asm.json")
    print(response)
    return display(vim.json.decode(response), begin, fmt("%s %02d:%02d:%02d", compiler, hour, min, sec), reuse_3f)
  end
  return fun.jobstart(curl_cmd, {on_exit = _15_})
end
local function init()
  map = {}
  nsid = api.nvim_create_namespace("godbolt")
  ns_hi_id = api.nvim_create_namespace("godbolt_highlight")
  return nil
end
return {init = init, map = map, nsid = nsid, ["pre-display"] = pre_display, ["update-hl"] = update_hl, display = display, clear = clear}
