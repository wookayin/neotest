local async = require("neotest.async")
local lib = require("neotest.lib")

---@param client neotest.Client
local function init(client)
  local last_run
  local function get_tree_from_args(args, store)
    local tree, adapter = (function()
      if args[1] then
        local position_id = lib.files.exists(args[1]) and async.fn.fnamemodify(args[1], ":p")
          or args[1]
        return client:get_position(position_id, args)
      end
      local file_path = async.fn.expand("%:p")
      local row = async.fn.getpos(".")[2] - 1
      return client:get_nearest(file_path, row, args)
    end)()
    if tree and store then
      last_run = { tree:data().id, vim.tbl_extend("keep", args, { adapter = adapter }) }
    end
    return tree
  end

  return {
    run = function(args)
      args = args or {}
      if type(args) == "string" then
        args = { args }
      end
      async.run(function()
        local tree = get_tree_from_args(args, true)
        if not tree then
          lib.notify("No tests found")
          return
        end
        client:run_tree(tree, args)
      end)
    end,
    run_last = function(args)
      args = args or {}
      if not last_run then
        lib.notify("No tests run yet")
        return
      end
      async.run(function()
        local position_id, last_args = unpack(last_run)
        args = vim.tbl_extend("keep", args, last_args)
        local tree = client:get_position(position_id, args)
        if not tree then
          lib.notify("Last test run no longer exists")
          return
        end
        client:run_tree(tree, args)
      end)
    end,
    attach = function(args)
      args = args or {}
      if type(args) == "string" then
        args = { args }
      end
      async.run(function()
        local pos = get_tree_from_args(args)
        if not pos then
          lib.notify("No tests found in file", "warn")
          return
        end
        client:attach(pos, args)
      end)
    end,
    stop = function(args)
      args = args or {}
      if type(args) == "string" then
        args = { args }
      end
      async.run(function()
        local tree = get_tree_from_args(args)
        if not tree then
          lib.notify("No tests found", "warn")
          return
        end
        client:stop(tree, args)
      end)
    end,
  }
end

---@tag neotest.run
---@brief [[
--- A consumer providing a simple interface to run tests.
---@brief ]]
local neotest = {}
neotest.run = {}

---Run the given position or the nearest position if not given.
---All arguments are optional
---
---Run the current file
---<pre>
--->
---lua require("neotest").run.run(vim.fn.expand("%"))
---</pre>
---
---Run the nearest test
---<pre>
--->
---lua require("neotest").run.run()
---</pre>
---
---Debug the current file with nvim-dap
---<pre>
--->
---lua require("neotest").run.run({vim.fn.expand("%"), strategy = "dap"})
---</pre>
---@param args string | table: Position ID to run or args. If args then args[1] should be the position ID.
---@field adapter string: Adapter ID, if not given the first adapter found with chosen position is used.
---@field strategy string | neotest.Strategy: Strategy to run commands with
---@field extra_args string[]: Extra arguments for test command
---@field env table<string, string>: Extra environment variables to add to the environment of tests
function neotest.run.run(args) end

---Re-run the last position that was run.
---Arguments are optional
---
---Run the last position that was run with the same arguments and strategy
---<pre>
--->
---lua require("neotest").run.run_last()
---</pre>
---
---Run the last position that was run with the same arguments but debug with nvim-dap
---<pre>
--->
---lua require("neotest").run.run_last({ strategy = "dap" })
---</pre>
---@param args table: Arguments to run with
---@field adapter string: Adapter ID, if not given the same adapter as the last run is used.
---@field strategy string | neotest.Strategy: Strategy to run commands with
---@field extra_args string[]: Extra arguments for test command
---@field env table<string, string>: Extra environment variables to add to the environment of tests
function neotest.run.run_last(args) end

---Stop a running process
---@param args string | table: Position ID to stop or args. If args then args[1] should be the position ID.
---@field adapter string: Adapter ID, if not given the first adapter found with chosen position is used.
function neotest.run.stop(args) end

---Attach to a running process for the given position.
---@param args string | table: Position ID to attach to or args. If args then args[1] should be the position ID.
---@field adapter string: Adapter ID, if not given the first adapter found with chosen position is used.
function neotest.run.attach(args) end

neotest.run = setmetatable(neotest.run, {
  __call = function(_, ...)
    return init(...)
  end,
})

return neotest.run
