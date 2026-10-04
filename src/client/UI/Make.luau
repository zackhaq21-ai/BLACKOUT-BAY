--!nonstrict
-- Small UI constructors so every panel shares the same look and touch-friendly sizing.
local Theme = require(script.Parent.Theme)

local Make = {}

function Make.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Radius)
	c.Parent = parent
	return c
end

function Make.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Stroke
	s.Thickness = thickness or 1
	s.Transparency = 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Make.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function Make.list(parent: Instance, gap: number, horizontal: boolean?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap)
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function Make.frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or Theme.Panel
	f.BackgroundTransparency = transparency or 0.15
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function Make.panel(parent: Instance, name: string, size: UDim2, pos: UDim2): Frame
	local f = Make.frame(parent, name, size, pos)
	Make.corner(f)
	Make.stroke(f)
	Make.padding(f, 10)
	return f
end

function Make.label(parent: Instance, name: string, text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = text
	t.TextSize = size or Theme.Body
	t.TextColor3 = color or Theme.Text
	t.Font = if bold then Theme.FontBold else Theme.Font
	t.BackgroundTransparency = 1
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.RichText = true
	t.Size = UDim2.new(1, 0, 0, size or Theme.Body)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Parent = parent
	return t
end

function Make.button(parent: Instance, name: string, text: string, color: Color3?, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.TextSize = Theme.Body
	b.Font = Theme.FontBold
	b.TextColor3 = Theme.Panel
	b.BackgroundColor3 = color or Theme.Accent
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1, 0, 0, Theme.MinButton)
	b.TextWrapped = true
	b.Parent = parent
	Make.corner(b, 8)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Make.ghostButton(parent: Instance, name: string, text: string, onClick: (() -> ())?): TextButton
	local b = Make.button(parent, name, text, Theme.PanelAlt, onClick)
	b.TextColor3 = Theme.Text
	Make.stroke(b)
	return b
end

function Make.textbox(parent: Instance, name: string, placeholder: string): TextBox
	local t = Instance.new("TextBox")
	t.Name = name
	t.PlaceholderText = placeholder
	t.Text = ""
	t.TextSize = Theme.Body
	t.Font = Theme.Font
	t.TextColor3 = Theme.Text
	t.PlaceholderColor3 = Theme.Muted
	t.BackgroundColor3 = Theme.PanelAlt
	t.BorderSizePixel = 0
	t.ClearTextOnFocus = false
	t.Size = UDim2.new(1, 0, 0, Theme.MinButton)
	t.Parent = parent
	Make.corner(t, 8)
	Make.stroke(t)
	return t
end

function Make.bar(parent: Instance, name: string, color: Color3, height: number?): (Frame, Frame)
	local bg = Make.frame(parent, name, UDim2.new(1, 0, 0, height or 8), UDim2.new(0, 0, 0, 0), Theme.PanelAlt, 0)
	Make.corner(bg, 4)
	local fill = Make.frame(bg, "Fill", UDim2.new(0, 0, 1, 0), UDim2.new(0, 0, 0, 0), color, 0)
	Make.corner(fill, 4)
	return bg, fill
end

function Make.pill(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local f = Make.frame(parent, name, UDim2.new(0, 0, 0, 26), UDim2.new(0, 0, 0, 0), Theme.Panel, 0.1)
	f.AutomaticSize = Enum.AutomaticSize.X
	Make.corner(f, 13)
	Make.stroke(f, color, 1.5)
	Make.padding(f, 6)
	local t = Make.label(f, "Text", text, Theme.Small, color, true)
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.new(0, 0, 0, 14)
	t.TextWrapped = false
	return t
end

return Make
