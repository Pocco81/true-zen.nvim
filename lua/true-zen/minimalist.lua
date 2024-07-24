local M = {}

M.running = false
local colors = require("true-zen.utils.colors")
local data = require("true-zen.utils.data")
local cnf = require("true-zen.config").options
local o = vim.o
local cmd = vim.cmd
local fn = vim.fn
local w = vim.w
local api = vim.api
local IGNORED_BUF_TYPES = data.set_of(cnf.modes.minimalist.ignored_buf_types)

local original_opts = {}

api.nvim_create_augroup("TrueZenMinimalist", {
	clear = true,
})

-- reference: https://vim.fandom.com/wiki/Run_a_command_in_multiple_buffers
local function alldo(run)
	local tab = fn.tabpagenr()
	local winnr = fn.winnr()
	local buffer = fn.bufnr("%")

	for _, command in pairs(run) do
		-- tapped together solution, but works! :)
		cmd(
			[[windo if &modifiable == 1 && &buflisted == 1 && &bufhidden == "" | exe "let g:my_buf = bufnr(\"%\") | exe \"bufdo ]]
				.. command
				.. [[\" | exe \"buffer \" . g:my_buf" | endif]]
		)
	end

	w.tz_buffer = nil

	cmd("tabn " .. tab)
	cmd(winnr .. " wincmd w")
	cmd("buffer " .. buffer)
end

local function save_opts()
	-- check if current window's buffer type matches any of IGNORED_BUF_TYPES, if so look for one that doesn't
	local suitable_window = fn.winnr()
	local currtab = fn.tabpagenr()
	if IGNORED_BUF_TYPES[fn.gettabwinvar(currtab, suitable_window, "&buftype")] ~= nil then
		for i = 1, fn.winnr("$") do
			if IGNORED_BUF_TYPES[fn.gettabwinvar(currtab, i, "&buftype")] == nil then
				suitable_window = i
				goto continue
			end
		end
	end
	::continue::

	-- get the options from suitable_window
	for user_opt, val in pairs(cnf.modes.minimalist.options) do
		local opt = fn.gettabwinvar(currtab, suitable_window, "&" .. user_opt)
		if
			type(opt) == "string"
			or user_opt == "showtabline"
			or user_opt == "cmdheight"
			or user_opt == "laststatus"
			or user_opt == "numberwidth"
		then
			original_opts[user_opt] = opt
		else
			original_opts[user_opt] = opt == 1
		end
		o[user_opt] = val
	end

	original_opts.highlights = {
		StatusLine = colors.get_hl("StatusLine"),
		StatusLineNC = colors.get_hl("StatusLineNC"),
		TabLine = colors.get_hl("TabLine"),
		TabLineFill = colors.get_hl("TabLineFill"),
	}
end

function M.on()
	data.do_callback("minimalist", "open", "pre")

	save_opts()

	if cnf.modes.minimalist.options.number == false then
		alldo({ "set nonumber" })
	end

	if cnf.modes.minimalist.options.relativenumber == false then
		alldo({ "set norelativenumber" })
	end

	-- fully hide statusline and tabline
	local base = colors.get_hl("Normal")["background"] or "NONE"
	for hi_group, _ in pairs(original_opts["highlights"]) do
		colors.highlight(hi_group, { bg = base, fg = base }, true)
	end

	if cnf.integrations.tmux == true then
		require("true-zen.integrations.tmux").on()
	end

	M.running = true
	data.do_callback("minimalist", "open", "pos")
end

function M.off()
	data.do_callback("minimalist", "close", "pre")

	api.nvim_create_augroup("TrueZenMinimalist", {
		clear = true,
	})

	if original_opts.number == true then
		alldo({ "set number" })
	end

	if original_opts.relativenumber == true then
		alldo({ "set relativenumber" })
	end

	original_opts.number = nil
	original_opts.relativenumber = nil

	for k, v in pairs(original_opts) do
		if k ~= "highlights" then
			o[k] = v
		end
	end

	for hi_group, props in pairs(original_opts["highlights"]) do
		colors.highlight(hi_group, { fg = props.foreground, bg = props.background }, true)
	end

	if cnf.integrations.tmux == true then
		require("true-zen.integrations.tmux").off()
	end

	M.running = false
	data.do_callback("minimalist", "close", "pos")
end

function M.toggle()
	if M.running then
		M.off()
	else
		M.on()
	end
end

return M
