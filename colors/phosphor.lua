-- Phosphor: Dojo's own theme. A near-black screen with a faint green tint,
-- mint-white text, and one neon green used sparingly (cursor, keywords,
-- focus). Cool aqua and cyan carry structure; a single warm amber for
-- numbers and constants gives the eye somewhere to rest. No italics.

vim.cmd("highlight clear")
if vim.g.syntax_on then
  vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.o.termguicolors = true
vim.g.colors_name = "phosphor"

-- stylua: ignore
local c = {
  bg        = "#0b0f0d", -- the screen
  bg_dim    = "#080b0a", -- inactive windows
  panel     = "#0f1512", -- tree, floats, pickers
  raise     = "#141c18", -- cursor line, hovered rows
  line      = "#1a2520", -- separators, borders
  select    = "#1d3a2b", -- selection
  muted     = "#3b4d43", -- line numbers, guides
  comment   = "#67806f",
  dim       = "#8aa497", -- punctuation, secondary text
  fg        = "#d3e6da", -- text
  bright    = "#eef8f1",
  neon      = "#5ef2a0", -- the one bright green
  neon_soft = "#2f7d57", -- neon at rest (borders, matches)
  aqua      = "#86e3cf", -- functions
  cyan      = "#7cc9e6", -- types
  lime      = "#c5e59a", -- strings
  amber     = "#eec27d", -- numbers, constants
  red       = "#ff7b86",
  orange    = "#f3a46b",
}

local hl = function(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

-- stylua: ignore start
-- Editor
hl("Normal",        { fg = c.fg, bg = c.bg })
hl("NormalNC",      { fg = c.fg, bg = c.bg_dim })
hl("NormalFloat",   { fg = c.fg, bg = c.panel })
hl("FloatBorder",   { fg = c.panel, bg = c.panel })
hl("FloatTitle",    { fg = c.dim, bg = c.panel })
hl("FloatFooter",   { fg = c.comment, bg = c.panel })
hl("Cursor",        { fg = c.bg, bg = c.neon })
hl("lCursor",       { link = "Cursor" })
hl("TermCursor",    { link = "Cursor" })
hl("CursorLine",    { bg = c.raise })
hl("CursorColumn",  { bg = c.raise })
hl("CursorLineNr",  { fg = c.neon })
hl("LineNr",        { fg = c.muted })
hl("SignColumn",    { bg = "NONE" })
hl("FoldColumn",    { fg = c.muted })
hl("Folded",        { fg = c.dim, bg = c.panel })
hl("ColorColumn",   { bg = c.panel })
hl("WinSeparator",  { fg = c.line })
hl("VertSplit",     { link = "WinSeparator" })
hl("EndOfBuffer",   { fg = c.bg })
hl("NonText",       { fg = c.muted })
hl("Whitespace",    { fg = c.line })
hl("SpecialKey",    { fg = c.muted })
hl("Visual",        { bg = c.select })
hl("VisualNOS",     { bg = c.select })
hl("Search",        { fg = c.bright, bg = "#24503a" })
hl("IncSearch",     { fg = c.bg, bg = c.neon })
hl("CurSearch",     { link = "IncSearch" })
hl("Substitute",    { fg = c.bg, bg = c.amber })
hl("MatchParen",    { fg = c.neon, bold = true })
hl("Pmenu",         { fg = c.fg, bg = c.panel })
hl("PmenuSel",      { fg = c.bright, bg = c.select })
hl("PmenuSbar",     { bg = c.panel })
hl("PmenuThumb",    { bg = c.line })
hl("PmenuKind",     { fg = c.dim, bg = c.panel })
hl("PmenuExtra",    { fg = c.comment, bg = c.panel })
hl("StatusLine",    { fg = c.comment, bg = c.bg })
hl("StatusLineNC",  { fg = c.muted, bg = c.bg })
hl("TabLine",       { fg = c.comment, bg = c.bg })
hl("TabLineFill",   { bg = c.bg })
hl("TabLineSel",    { fg = c.fg, bg = c.bg, bold = true })
hl("WinBar",        { fg = c.comment, bg = "NONE" })
hl("WinBarNC",      { fg = c.muted, bg = "NONE" })
hl("Title",         { fg = c.neon, bold = true })
hl("Directory",     { fg = c.aqua })
hl("Question",      { fg = c.neon })
hl("MoreMsg",       { fg = c.neon })
hl("ModeMsg",       { fg = c.dim })
hl("ErrorMsg",      { fg = c.red })
hl("WarningMsg",    { fg = c.amber })
hl("QuickFixLine",  { bg = c.raise })
hl("Conceal",       { fg = c.comment })
hl("SpellBad",      { sp = c.comment, undercurl = true })
hl("SpellCap",      {})
hl("SpellRare",     {})
hl("SpellLocal",    {})

-- Syntax
hl("Comment",       { fg = c.comment })
hl("Constant",      { fg = c.amber })
hl("String",        { fg = c.lime })
hl("Character",     { fg = c.lime })
hl("Number",        { fg = c.amber })
hl("Boolean",       { fg = c.amber })
hl("Float",         { fg = c.amber })
hl("Identifier",    { fg = c.fg })
hl("Function",      { fg = c.aqua })
hl("Statement",     { fg = c.neon })
hl("Conditional",   { fg = c.neon })
hl("Repeat",        { fg = c.neon })
hl("Label",         { fg = c.neon })
hl("Operator",      { fg = c.dim })
hl("Keyword",       { fg = c.neon })
hl("Exception",     { fg = c.neon })
hl("PreProc",       { fg = c.cyan })
hl("Include",       { fg = c.neon })
hl("Define",        { fg = c.neon })
hl("Macro",         { fg = c.cyan })
hl("Type",          { fg = c.cyan })
hl("StorageClass",  { fg = c.neon })
hl("Structure",     { fg = c.cyan })
hl("Typedef",       { fg = c.cyan })
hl("Special",       { fg = c.aqua })
hl("SpecialChar",   { fg = c.amber })
hl("Delimiter",     { fg = c.dim })
hl("SpecialComment",{ fg = c.comment })
hl("Tag",           { fg = c.neon })
hl("Underlined",    { underline = true })
hl("Error",         { fg = c.red })
hl("Todo",          { fg = c.bg, bg = c.amber })

-- Treesitter
hl("@variable",               { fg = c.fg })
hl("@variable.builtin",       { fg = c.cyan })
hl("@variable.parameter",     { fg = c.bright })
hl("@variable.member",        { fg = c.fg })
hl("@property",               { fg = c.fg })
hl("@constant",               { fg = c.amber })
hl("@constant.builtin",       { fg = c.amber })
hl("@module",                 { fg = c.cyan })
hl("@string",                 { link = "String" })
hl("@string.escape",          { fg = c.amber })
hl("@string.special",         { fg = c.amber })
hl("@string.documentation",   { fg = c.comment })
hl("@character",              { link = "String" })
hl("@number",                 { link = "Number" })
hl("@boolean",                { link = "Boolean" })
hl("@type",                   { link = "Type" })
hl("@type.builtin",           { fg = c.cyan })
hl("@attribute",              { fg = c.cyan })
hl("@function",               { link = "Function" })
hl("@function.builtin",       { fg = c.aqua })
hl("@function.call",          { fg = c.aqua })
hl("@function.method",        { fg = c.aqua })
hl("@function.method.call",   { fg = c.aqua })
hl("@constructor",            { fg = c.cyan })
hl("@operator",               { link = "Operator" })
hl("@keyword",                { link = "Keyword" })
hl("@keyword.function",       { fg = c.neon })
hl("@keyword.return",         { fg = c.neon })
hl("@keyword.import",         { fg = c.neon })
hl("@keyword.operator",       { fg = c.neon })
hl("@punctuation",            { fg = c.dim })
hl("@punctuation.bracket",    { fg = c.dim })
hl("@punctuation.delimiter",  { fg = c.dim })
hl("@punctuation.special",    { fg = c.aqua })
hl("@comment",                { link = "Comment" })
hl("@tag",                    { fg = c.neon })
hl("@tag.attribute",          { fg = c.cyan })
hl("@tag.delimiter",          { fg = c.dim })
hl("@markup.heading",         { fg = c.neon, bold = true })
hl("@markup.strong",          { bold = true })
hl("@markup.italic",          { italic = true })
hl("@markup.link",            { fg = c.cyan, underline = true })
hl("@markup.link.url",        { fg = c.cyan, underline = true })
hl("@markup.raw",             { fg = c.lime })
hl("@markup.list",            { fg = c.neon })
hl("@markup.quote",           { fg = c.dim })
hl("@lsp.type.parameter",     { fg = c.bright })
hl("@lsp.type.property",      { fg = c.fg })
hl("@lsp.type.namespace",     { fg = c.cyan })

-- Diagnostics and diffs
hl("DiagnosticError",           { fg = c.red })
hl("DiagnosticWarn",            { fg = c.amber })
hl("DiagnosticInfo",            { fg = c.cyan })
hl("DiagnosticHint",            { fg = c.neon_soft })
hl("DiagnosticOk",              { fg = c.neon })
hl("DiagnosticUnderlineError",  { sp = c.red, undercurl = true })
hl("DiagnosticUnderlineWarn",   { sp = c.amber, undercurl = true })
hl("DiagnosticUnderlineInfo",   { sp = c.cyan, undercurl = true })
hl("DiagnosticUnderlineHint",   { sp = c.neon_soft, undercurl = true })
hl("DiagnosticVirtualTextError",{ fg = c.red, bg = "#2a1518" })
hl("DiagnosticVirtualTextWarn", { fg = c.amber, bg = "#2a2416" })
hl("DiffAdd",       { bg = "#123322" })
hl("DiffChange",    { bg = "#15282a" })
hl("DiffDelete",    { fg = "#6b3a3f", bg = "#241416" })
hl("DiffText",      { bg = "#1d4a4e" })
hl("Added",         { fg = c.neon })
hl("Changed",       { fg = c.cyan })
hl("Removed",       { fg = c.red })
hl("LspReferenceText",  { bg = c.raise })
hl("LspReferenceRead",  { bg = c.raise })
hl("LspReferenceWrite", { bg = c.raise, underline = true, sp = c.neon_soft })
hl("LspInlayHint",      { fg = c.muted })

-- Plugins: pickers, tree, completion, dashboard, indent guides
hl("SnacksPickerTitle",       { fg = c.dim, bg = c.panel })
hl("SnacksPickerInputTitle",  { fg = c.dim, bg = c.panel })
hl("SnacksPickerListTitle",   { fg = c.dim, bg = c.panel })
hl("SnacksPickerPreviewTitle",{ fg = c.dim, bg = c.panel })
hl("SnacksPickerBoxTitle",    { fg = c.dim, bg = c.panel })
hl("SnacksPickerMatch",       { fg = c.neon, bold = true })
hl("SnacksPickerPrompt",      { fg = c.neon })
hl("SnacksPickerCursorLine",  { bg = c.raise })
hl("SnacksPickerListCursorLine", { bg = c.raise })
hl("SnacksPickerDir",         { fg = c.comment })
hl("SnacksPickerComment",     { fg = c.comment })
hl("SnacksPickerTree",        { fg = c.line })
hl("SnacksPickerGitStatusModified",  { fg = c.amber })
hl("SnacksPickerGitStatusUntracked", { fg = c.neon_soft })
hl("SnacksPickerGitStatusAdded",     { fg = c.neon })
hl("SnacksDashboardHeader",   { fg = c.neon })
hl("SnacksDashboardDesc",     { fg = c.fg })
hl("SnacksDashboardKey",      { fg = c.neon })
hl("SnacksDashboardIcon",     { fg = c.comment })
hl("SnacksDashboardTitle",    { fg = c.dim })
hl("SnacksDashboardFile",     { fg = c.fg })
hl("SnacksDashboardDir",      { fg = c.comment })
hl("SnacksDashboardFooter",   { fg = c.comment })
hl("SnacksIndent",            { fg = "#16201b" })
hl("SnacksIndentScope",       { fg = c.neon_soft })
hl("SnacksNotifierInfo",      { fg = c.fg, bg = c.panel })
hl("SnacksNotifierBorderInfo",{ fg = c.panel, bg = c.panel })
hl("BlinkCmpMenu",            { fg = c.fg, bg = c.panel })
hl("BlinkCmpMenuBorder",      { fg = c.panel, bg = c.panel })
hl("BlinkCmpMenuSelection",   { bg = c.select })
hl("BlinkCmpLabelMatch",      { fg = c.neon })
hl("BlinkCmpKind",            { fg = c.comment })
hl("BlinkCmpLabelDetail",     { fg = c.comment })
hl("BlinkCmpLabelDescription",{ fg = c.comment })
hl("BlinkCmpDoc",             { fg = c.fg, bg = c.panel })
hl("BlinkCmpDocBorder",       { fg = c.panel, bg = c.panel })
hl("BlinkCmpSignatureHelp",   { fg = c.fg, bg = c.panel })
hl("WhichKey",                { fg = c.neon })
hl("WhichKeyDesc",            { fg = c.fg })
hl("WhichKeyGroup",           { fg = c.aqua })
hl("WhichKeySeparator",       { fg = c.muted })
hl("WhichKeyNormal",          { bg = c.panel })
hl("NoiceCmdlinePopup",       { bg = c.panel })
hl("NoiceCmdlinePopupBorder", { fg = c.neon_soft, bg = c.panel })
hl("NoiceCmdlineIcon",        { fg = c.neon })
hl("TroubleNormal",           { bg = c.panel })
hl("TodoBgTODO",              { fg = c.bg, bg = c.cyan, bold = true })
hl("TodoFgTODO",              { fg = c.cyan })
hl("DojoKeyText",             { fg = c.neon })
hl("DojoVimText",             { fg = c.lime })
-- stylua: ignore end

-- The built-in terminal (⌘J, ⌘R output) in the same palette.
-- stylua: ignore
local term = {
  c.panel, c.red, c.neon, c.amber, c.cyan, "#b7a4f0", c.aqua, c.fg,
  c.comment, "#ff9aa3", "#8af7bb", "#f5d49a", "#9fd9ee", "#cdbdf6", "#a6eedf", c.bright,
}
for i, color in ipairs(term) do
  vim.g["terminal_color_" .. (i - 1)] = color
end
