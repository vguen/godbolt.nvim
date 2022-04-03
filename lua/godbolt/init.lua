local M = {}

local fun = vim.fn
local api = vim.api
local fmt = string.format

M.config = {
  quickfix = {enable = false, auto_open = false},
  colorscheme = "rainbow",
  colormap = {
    rainbow = {
      "#d7f0eb",
      "#ffffe4",
      "#e8e7fe",
      "#fed3ce",
      "#d3e4f0",
      "#fee5c8",
      "#e4f4ca",
      "#feeef6",
      "#f2f2f2",
      "#e8d3e8",
      "#edf8eb",
      "#fff9cd",
    },
  },
  -- output {
  asm_syntax = "intel", -- at
  demangle_identifier = "",
  -- compile_binary? Do we want it ? or is it our default asm_parser backend ?
  -- execute_code? Do we want it ?
  -- },
  filters = {
    unused_labels     = true,
    library_functions = true,
    directives        = true,
    comments          = true,
    -- horizontal_whitespaces = false
  },
  backend = "",
  backends = {
    compiler_explorer = {
      instance_address = "https://godbolt.org",
      cpp   = { compiler = "g112",  options = {} },
      c     = { compiler = "cg112", options = {} },
      rust  = { compiler = "r1560", options = {} }
    },
    asm_parser = {
      objdump = "objdump",
      objdump_options = "-d -l -j .text -j .rodata",
      asm_parser = "/home/RATIONAL_LL/guennouv/Documents/asm-parser/build/bin/asm-parser",
      asm_parser_options = "-stdin -binary -libray_functions -plt -unused_labels -directives"
    }
  }
}

local function build_asm_parser_cmd(source_buf)
  -- TODO: example of objdump path to find
  -- /opt/rational-os/x86-64/2.2.0/toolchain/sysroots/x86_64-rationalsdk-linux/usr/bin/objdump
  -- TODO: need to find the current object file associated with buffer
  local makeprg = vim.api.nvim_get_option("makeprg")
  local obj_file = "/home/RATIONAL_LL/guennouv/test.o"
  local asm_parser = M.config.backends.asm_parser
  local objdump_opt_with_asm = asm_parser.objdump_options .. " -M " .. M.config.asm_syntax
  return string.format(("%s %s %s | %s %s"), asm_parser.objdump, objdump_opt_with_asm, obj_file, asm_parser.asm_parser, asm_parser.asm_parser_options)
end

M.build_cmd = function(compiler, text, options, exec_asm_3f)
  local json = vim.json.encode({source = text, options = options})
  local file = io.open(string.format("godbolt_request_%s.json", exec_asm_3f), "w")
  file:write(json)
  io.close(file)
  return string.format(("curl " .. "%s/api/compiler/'%s'/compile" .. " --data-binary @godbolt_request_%s.json" .. " --header 'Accept: application/json'" .. " --header 'Content-Type: application/json'" .. " --output godbolt_response_%s.json"), M.config.instance_address, compiler, exec_asm_3f, exec_asm_3f)
end

M.godbolt = function(begin, _end, backend, reuse_3f, compiler)
  local pre_display = (require("godbolt.assembly"))["pre-display"]
  local execute = (require("godbolt.execute")).execute
  local fuzzy = (require("godbolt.fuzzy")).fuzzy

  if backend == "compiler-explorer" then
    local ft = vim.bo.filetype
    if ft == "" then
      api.nvim_err_writeln("filetype is not set")
      return nil
    end
    local compiler_explorer = M.config.backends.compiler_explorer
    if compiler_explorer[ft] == nil then
      api.nvim_err_writeln("There is no config for filetype: " .. ft)
      return nil
    end

    local compiler0 = (compiler or compiler_explorer[ft].compiler)
    local options
    if compiler_explorer[ft] then
      options = vim.deepcopy(compiler_explorer[ft].options)
    else
      options = {}
    end
    local flags = vim.fn.input({prompt = "Flags: ", default = (options.userArguments or "")})
    do end (options)["userArguments"] = flags
    --
    -- local compilers = {"telescope", "fzf", "skim", "fzy"}
    local fuzzy_3f
    do
      for _, v in pairs({"telescope", "fzf", "skim", "fzy"}) do
        if (v == compiler0) then
          fuzzy_3f = v
        end
      end
    end
    if fuzzy_3f then
      return fuzzy(fuzzy_3f, M.config.instance_address, ft, begin, _end, options, (true == vim.b.godbolt_exec), reuse_3f)
    else
      pre_display(begin, _end, compiler0, options, reuse_3f)
      if vim.b.godbolt_exec then
        return execute(begin, _end, compiler0, options)
      else
        return nil
      end
    end
  elseif backend == "asm-parser" then
    -- TODO: merge fuzzy and "compiler-explorer" backend
    local time = os.date("*t")
    local hour = time.hour
    local min = time.min
    local sec = time.sec
    local bufname = fmt("%s %02d:%02d:%02d", compiler, hour, min, sec)
    local display = (require("godbolt.assembly")).display
    local output = {}
    local function _15_(_, data, _0)
      return vim.list_extend(output, data)
    end
    local function curryed_display(_0, _1, _2)
      s = table.concat(output, ", ")
      -- print(s)
      return display(vim.json.decode(s), begin, bufname, reuse_3f)
    end
    local source_buf = vim.fn.bufnr()
    local cmd = build_asm_parser_cmd(source_buf)
    -- print(cmd)
    fun.jobstart(cmd, {on_stdout = _15_, on_exit = curryed_display, stdout_buffered = true})
    -- TODO: execute asm-parser request
    -- check if there is a `main` symbol (how to handle if there is not ?)
    -- if vim.b.godbolt_exec then
    --   return execute(begin, _end, compiler0, options)
    -- else
    --   return nil
    -- end
  else
    api.nvim_err_writeln("backend `" .. backend .. "` not supported. Use either `compiler-explorer` or `asm-parser`")
    return nil
  end
end

M.setup = function(user_opts)
  require("godbolt.assembly").init()
  M.config = vim.tbl_deep_extend("force", M.config, user_opts or {})
  -- TODO: clear highlights when we change the config
  local highlights = ""
  local color_idx = M.config.colorscheme
  for i, color in pairs(M.config.colormap[color_idx]) do
    highlights = highlights .. "highlight Godbolt" .. color_idx .. i .. " guibg=" .. color .. " | "
  end
  highlights = string.sub(highlights, 0, -4)
  vim.cmd("augroup GodboltColors")
  vim.cmd("autocmd!")
  vim.cmd("autocmd ColorScheme * " .. highlights)
  vim.cmd("augroup END")
end

return M
