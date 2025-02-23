local logger = require("neotest.logging")
local config = require("neotest.config")
---@param client neotest.Client
local function init(client)
  local Canvas = require("neotest.consumers.summary.canvas")
  local SummaryComponent = require("neotest.consumers.summary.component")
  local async = require("neotest.async")

  local buf_name = "Neotest Summary"
  local summary_buf

  local function create_buf()
    if summary_buf then
      return summary_buf
    end

    summary_buf = async.api.nvim_create_buf(false, true)
    local options = {
      modifiable = false,
      filetype = "neotest-summary",
    }
    for name, value in pairs(options) do
      async.api.nvim_buf_set_option(summary_buf, name, value)
    end
    async.api.nvim_buf_set_name(summary_buf, buf_name)
    return summary_buf
  end

  local function is_open()
    return summary_buf and async.fn.bufwinnr(summary_buf) ~= -1
  end

  local function open_window(buf)
    local cur_win = async.api.nvim_get_current_win()
    vim.cmd([[botright vsplit | vertical resize 50]])
    local win = async.api.nvim_get_current_win()
    local options = {
      relativenumber = false,
      number = false,
      winfixwidth = true,
    }
    for name, value in pairs(options) do
      async.api.nvim_win_set_option(win, name, value)
    end
    async.api.nvim_win_set_buf(win, buf)
    async.api.nvim_set_current_win(cur_win)
  end

  local components = {}

  local focused
  local render
  render = function(expanded)
    if not is_open() then
      return
    end
    local ready = client:has_started()
    if not ready then
      async.run(function()
        client:ensure_started()
        -- In case no tests are found, we re-render.
        -- Want to do async because otherwise the "No tests found" render will
        -- happen before the "Parsing tests" render
        vim.schedule(render)
      end)
    end
    local canvas = Canvas.new(config.summary)
    if not ready then
      canvas:write("Parsing tests")
    else
      local cwd = async.fn.getcwd()
      for _, adapter_id in ipairs(client:get_adapters()) do
        local tree = client:get_position(nil, { adapter = adapter_id })
        canvas:write(adapter_id .. "\n", { group = config.highlights.adapter_name })
        if tree:data().path ~= cwd then
          local root_dir = async.fn.fnamemodify(tree:data().path, ":.")
          canvas:write(root_dir .. "\n", { group = config.highlights.dir })
        end
        components[adapter_id] = components[adapter_id] or SummaryComponent(client, adapter_id)
        components[adapter_id]:render(canvas, tree, expanded or {}, focused)
        canvas:write("\n")
      end
      if canvas:length() > 1 then
        canvas:remove_line()
        canvas:remove_line()
      else
        canvas:write("No tests found")
      end
    end
    local rendered, err = canvas:render_buffer(summary_buf)
    if not rendered then
      logger.error("Couldn't render buffer", err)
    end
  end

  local listener = function()
    render()
  end
  client.listeners.discover_positions = listener
  client.listeners.run = listener
  client.listeners.results = function(adapter_id, results)
    if not config.summary.expand_errors then
      render()
    end
    local expanded = {}
    for pos_id, result in pairs(results) do
      if
        result.status == "failed"
        and client:get_position(pos_id, { refresh = false, adapter = adapter_id })
        and #client:get_position(pos_id, { adapter = adapter_id }):children() > 0
      then
        expanded[pos_id] = true
      end
    end
    render(expanded)
  end
  local function expand(pos_id, recursive, focus)
    local tree = client:get_position(pos_id)
    if not tree then
      return
    end
    local expanded = {}
    if recursive then
      for _, node in tree:iter_nodes() do
        if #node:children() > 0 then
          expanded[node:data().id] = true
        end
      end
    else
      expanded[pos_id] = true
    end
    for parent in tree:iter_parents() do
      expanded[parent:data().id] = true
    end
    if focus then
      focused = pos_id
    end
    render(expanded)
  end

  if config.summary.follow then
    client.listeners.test_file_focused = function(_, file_path)
      expand(file_path, true)
    end
    client.listeners.test_focused = function(_, pos_id)
      expand(pos_id, false, true)
    end
  end
  local function open()
    create_buf()
    open_window(summary_buf)
  end

  local function close()
    if is_open() then
      local win = async.fn.win_getid(async.fn.bufwinnr(summary_buf))
      async.api.nvim_win_close(win, true)
    end
  end

  return {
    render = render,
    open = function()
      if is_open() then
        return
      end
      open()
      render()
    end,
    close = function()
      close()
    end,
    toggle = function()
      async.run(function()
        if is_open() then
          close()
        else
          open()
          render()
        end
      end)
    end,
    expand = function(pos_id, recursive)
      async.run(function()
        expand(pos_id, recursive)
      end)
    end,
    focus = function() end,
  }
end

---@tag neotest.summary
---@brief [[
--- A consumer that displays the structure of the test suite, along with results and allows running tests.
---<pre>
---    See: ~
---        |neotest.Config.summary.mappings| for all mappings in the summary window
---</pre>
---@brief ]]
local neotest = {}
neotest.summary = {}

---Open the summary window
---<pre>
--->
---lua require("neotest").summary.open()
---</pre>
function neotest.summary.open() end

---Close the summary window
---<pre>
--->
---lua require("neotest").summary.close()
---</pre>
function neotest.summary.close() end

---Toggle the summary window
---<pre>
--->
---lua require("neotest").summary.toggle()
---</pre>
function neotest.summary.toggle() end

neotest.summary = setmetatable(neotest.summary, {
  __call = function(_, ...)
    return init(...)
  end,
})

return neotest.summary
