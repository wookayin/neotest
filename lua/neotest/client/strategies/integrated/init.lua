local async = require("neotest.async")
local lib = require("neotest.lib")

---@class integratedStrategyConfig
---@field height integer
---@field width integer

---@async
---@param spec neotest.RunSpec
---@return neotest.Process
return function(spec)
  local env, cwd = spec.env, spec.cwd

  local finish_cond = async.control.Condvar.new()
  local result_code = nil
  local command = spec.command

  local unread_data = ""
  local attach_win, attach_buf, attach_chan
  local output_path = async.fn.tempname()
  -- TODO: Resolve permissions issues with opening file with luv
  local output_file = assert(io.open(output_path, "w"))
  local success, job = pcall(async.fn.jobstart, command, {
    cwd = cwd,
    env = env,
    pty = true,
    height = spec.strategy.height,
    width = spec.strategy.width,
    on_stdout = function(_, data)
      data = table.concat(data, "\n")
      unread_data = unread_data .. data
      output_file:write(data)
      if attach_chan then
        async.api.nvim_chan_send(attach_chan, unread_data)
        unread_data = ""
      end
    end,
    on_exit = function(_, code)
      result_code = code
      finish_cond:notify_all()
    end,
  })
  if not success then
    output_file:write(job)
    result_code = 1
    finish_cond:notify_all()
  end
  return {
    is_complete = function()
      return result_code ~= nil
    end,
    output = function()
      return output_path
    end,
    stop = function()
      async.fn.jobstop(job)
    end,
    attach = function()
      attach_buf = attach_buf or vim.api.nvim_create_buf(false, true)
      attach_chan = attach_chan
        or vim.api.nvim_open_term(attach_buf, {
          on_input = function(_, _, _, data)
            pcall(async.api.nvim_chan_send, job, data)
          end,
        })
      attach_win = lib.ui.float.open({
        height = spec.strategy.height,
        width = spec.strategy.width,
        buffer = attach_buf,
      })
      async.api.nvim_buf_set_keymap(attach_buf, "n", "q", "", {
        noremap = true,
        silent = true,
        callback = function()
          pcall(vim.api.nvim_win_close, attach_win.win_id, true)
        end,
      })
      attach_win:jump_to()

      if unread_data ~= "" then
        async.api.nvim_chan_send(attach_chan, unread_data)
        unread_data = ""
      end
    end,
    result = function()
      if result_code == nil then
        finish_cond:wait()
      end
      output_file:close()
      pcall(async.fn.chanclose, job)
      if attach_win then
        attach_win:listen("close", function()
          pcall(vim.api.nvim_buf_delete, attach_buf, { force = true })
          pcall(vim.fn.chanclose, attach_chan)
        end)
      end
      return result_code
    end,
  }
end
