local M = {}

M.running = false
local colors = require("true-zen.utils.colors")
local cmd = vim.cmd
local data = require("true-zen.utils.data")
local cnf = require("true-zen.config").options
local fn = vim.fn
local o = vim.o
local wo = vim.wo
local w = vim.w
local api = vim.api
local padding = cnf.modes.ataraxis.padding
local minimum_writing_area = cnf.modes.ataraxis.minimum_writing_area
local CARDINAL_POINTS = { left = "width", right = "width", top = "height", bottom = "height" }

local base = colors.get_hl("Normal")["background"] or "NONE"

if base ~= "NONE" and cnf.modes.ataraxis.backdrop ~= 0 then
	if cnf.modes.ataraxis.shade == "dark" then
		base = colors.darken("#000000", cnf.modes.ataraxis.backdrop, base)
	else
		base = colors.lighten("#ffffff", cnf.modes.ataraxis.backdrop, base)
	end

	colors.highlight("TZBackground", { fg = base, bg = base }, true)
end

api.nvim_create_augroup("TrueZenAtaraxis", {
	clear = true,
})

local original_opts = {}
local win = {}
local opts = {
	bo = {
		buftype = "nofile",
		bufhidden = "hide",
		modifiable = false,
		buflisted = false,
		swapfile = false,
	},
	wo = {
		cursorline = false,
		cursorcolumn = false,
		number = false,
		relativenumber = false,
		foldenable = false,
		list = false,
		winbar = "",
	},
}

local function save_opts()
	original_opts.fillchars = o.fillchars
	original_opts.highlights = {
		just_bg = {
			MsgArea = colors.get_hl("MsgArea"),
		},
		FoldColumn = colors.get_hl("FoldColumn"),
		ColorColumn = colors.get_hl("ColorColumn"),
		VertSplit = colors.get_hl("VertSplit"),
		SignColumn = colors.get_hl("SignColumn"),
		WinBar = colors.get_hl("WinBar"),
	}
end

local function pad_win(new, props, move)
	cmd(new)

	local win_id = api.nvim_get_current_win()

	if props.width ~= nil then
		api.nvim_win_set_width(0, props.width)
	else
		api.nvim_win_set_height(0, props.height)
	end

	wo.winhighlight = "Normal:TZBackground"

	for opt_type, _ in pairs(opts) do
		for opt, val in pairs(opts[opt_type]) do
			vim[opt_type][opt] = val
		end
	end

	w.tz_pad_win = true

	cmd(move)
	return win_id
end

local function fix_padding(orientation, dimension, mod)
	mod = mod or 0
	local window_dimension = (api.nvim_list_uis()[1][dimension] - mod) -- width or height
	local mwa = minimum_writing_area[dimension]

	if mwa >= window_dimension then
		return 1
	else
		local wanted_available_size = (
			dimension == "width" and padding.left + padding.right + mwa or padding.top + padding.bottom + mwa
		)
		if wanted_available_size > window_dimension then
			local available_space = window_dimension - mwa -- available space for padding on each side (e.g. left and right)
			return (available_space % 2 > 0 and ((available_space - 1) / 2) or available_space / 2)
		else
			return padding[orientation]
		end
	end
end

local function layout(action)
	if action == "generate" then
		local splitbelow, splitright = o.splitbelow, o.splitright
		o.splitbelow, o.splitright = true, true

		local left_padding = fix_padding("left", "width")
		local right_padding = fix_padding("right", "width")
		local top_padding = fix_padding("top", "height")
		local bottom_padding = fix_padding("bottom", "height")

		win.main = api.nvim_get_current_win()

		win.left = pad_win("leftabove vnew", { width = left_padding }, "wincmd l") -- left buffer
		win.right = pad_win("vnew", { width = right_padding }, "wincmd h") -- right buffer
		win.top = pad_win("leftabove new", { height = top_padding }, "wincmd j") -- top buffer
		win.bottom = pad_win("rightbelow new", { height = bottom_padding }, "wincmd k") -- bottom buffer

		o.splitbelow, o.splitright = splitbelow, splitright
	else -- resize
		local pad_sizes = {}
		pad_sizes.left = fix_padding("left", "width")
		pad_sizes.right = fix_padding("right", "width")
		pad_sizes.top = fix_padding("top", "height")
		pad_sizes.bottom = fix_padding("bottom", "height")

		for point, dimension in pairs(CARDINAL_POINTS) do
			if api.nvim_win_is_valid(win[point]) then
				if dimension == "width" then
					api.nvim_win_set_width(win[point], pad_sizes[point])
				else
					api.nvim_win_set_height(win[point], pad_sizes[point])
				end
			end
		end
	end
end

function M.on()
	data.do_callback("ataraxis", "open", "pre")

	local cursor_pos = fn.getpos(".")
	if cnf.modes.ataraxis.quit_untoggles == true then
		api.nvim_create_autocmd({ "QuitPre" }, {
			callback = function()
				M.off()
			end,
			group = "TrueZenAtaraxis",
		})
	end

	require("true-zen.minimalist").on()
	save_opts()

	if fn.filereadable(fn.expand("%:p")) == 1 then
		cmd("tabe %")
	end

	layout("generate")

	o.fillchars = "stl: ,stlnc: ,vert: ,diff: ,msgsep: ,eob: "

	for hi_group, _ in pairs(original_opts["highlights"]) do
		if hi_group == "just_bg" then
			for bg_hi_group, _ in pairs(original_opts["highlights"]["just_bg"]) do
				colors.highlight(bg_hi_group, { bg = base })
			end
		else
			colors.highlight(hi_group, { bg = base, fg = base })
		end
	end

	for integration, val in pairs(cnf.integrations) do
		if (type(val) == "table" and val.enabled or val) == true and integration ~= "tmux" then
			require("true-zen.integrations." .. integration).on()
		end
	end

	api.nvim_create_autocmd({ "VimResized" }, { -- sorta works
		callback = function()
			layout("resize")
		end,
		group = "TrueZenAtaraxis",
		desc = "Resize TrueZen pad windows after nvim has been resized",
	})

	api.nvim_create_autocmd({ "WinEnter", "WinClosed" }, {
		callback = function()
			vim.schedule(function()
				if api.nvim_win_get_config(0).relative == "" then -- not a floating win
					if w.tz_pad_win == nil and api.nvim_get_current_win() ~= win.main then
						local pad_sizes = {}
						pad_sizes.left = fix_padding("left", "width", api.nvim_win_get_width(0))
						pad_sizes.right = fix_padding("right", "width", api.nvim_win_get_width(0))
						pad_sizes.top = fix_padding("top", "height", api.nvim_win_get_height(0))
						pad_sizes.bottom = fix_padding("bottom", "height", api.nvim_win_get_height(0))

						if next(win) ~= nil then
							for point, dimension in pairs(CARDINAL_POINTS) do
								if api.nvim_win_is_valid(win[point]) then
									if dimension == "width" then
										api.nvim_win_set_width(win[point], pad_sizes[point])
									else
										api.nvim_win_set_height(win[point], pad_sizes[point])
									end
								end
							end
						end
					else
						-- in tz win
						layout("resize")
					end
				end
			end)
		end,
		group = "TrueZenAtaraxis",
		desc = "Asser whether to resize TrueZen pad windows or not",
	})

	fn.setpos('.', cursor_pos)
	M.running = true
	data.do_callback("ataraxis", "open", "pos")
end

function M.off()
	data.do_callback("ataraxis", "close", "pre")
	local cursor_pos
	if pcall(function() api.nvim_win_is_valid(win.main) end) and  api.nvim_win_is_valid(win.main) then
		if win.main ~= api.nvim_get_current_win() then
			fn.win_gotoid(win.main)
		end
		cursor_pos = fn.getpos(".")
	else
		data.do_callback("ataraxis", "close", "pos")
		return 1 -- already off
	end
	cmd("only")
	if fn.filereadable(fn.expand("%:p")) == 1 then
		pcall(function () pcall(cmd("q")) end)
	end

	require("true-zen.minimalist").off()

    for k, v in pairs(original_opts) do
		if k ~= "highlights" then
			o[k] = v
		end
	end

	for hi_group, props in pairs(original_opts["highlights"]) do
		if hi_group == "just_bg" then
			for bg_hi_group, bg_props in pairs(original_opts["highlights"]["just_bg"]) do
				colors.highlight(bg_hi_group, { bg = bg_props.background })
			end
		else
			colors.highlight(hi_group, { fg = props.foreground, bg = props.background }, true)
		end
	end

	api.nvim_create_augroup("TrueZenAtaraxis", {
		clear = true,
	})

	for integration, val in pairs(cnf.integrations) do
		if (type(val) == "table" and val.enabled or val) == true and integration ~= "tmux" then
			require("true-zen.integrations." .. integration).off()
		end
	end

	if cursor_pos ~= nil then
		fn.setpos('.', cursor_pos)
	end

	win = {}
	M.running = false
	data.do_callback("ataraxis", "close", "pos")
end

function M.toggle()
	if M.running then
		M.off()
	else
		M.on()
	end
end

return M
