--!nonstrict
-- Part construction helpers shared by all builders. Keeps materials/colours on the palette and
-- keeps every generated part anchored, smooth, and named so the world is readable in Explorer.
local Palette = require(game:GetService("ReplicatedStorage").Shared.Palette)

local Builder = {}

export type Props = {
	name: string?,
	material: Enum.Material?,
	color: Color3?,
	transparency: number?,
	canCollide: boolean?,
	castShadow: boolean?,
	reflectance: number?,
	shape: Enum.PartType?,
}

function Builder.part(parent: Instance, cf: CFrame, size: Vector3, props: Props?): Part
	local p = props or {}
	local part = Instance.new("Part")
	part.Name = p.name or "Part"
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Material = p.material or Enum.Material.Concrete
	part.Color = p.color or Palette.PaleStone
	part.Transparency = p.transparency or 0
	part.CanCollide = if p.canCollide == nil then true else p.canCollide
	part.CastShadow = if p.castShadow == nil then true else p.castShadow
	part.Reflectance = p.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if p.shape then
		part.Shape = p.shape
	end
	part.Parent = parent
	return part
end

-- Axis-aligned box from centre (x, z), bottom y, size w (x) d (z) h (y).
function Builder.box(parent: Instance, x: number, bottomY: number, z: number, w: number, h: number, d: number, props: Props?): Part
	return Builder.part(parent, CFrame.new(x, bottomY + h / 2, z), Vector3.new(w, h, d), props)
end

function Builder.wedge(parent: Instance, cf: CFrame, size: Vector3, props: Props?): WedgePart
	local p = props or {}
	local part = Instance.new("WedgePart")
	part.Name = p.name or "Wedge"
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Material = p.material or Enum.Material.Concrete
	part.Color = p.color or Palette.PaleStone
	part.CanCollide = if p.canCollide == nil then true else p.canCollide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function Builder.truss(parent: Instance, cf: CFrame, height: number, name: string?): TrussPart
	local t = Instance.new("TrussPart")
	t.Name = name or "Ladder"
	t.Anchored = true
	t.Size = Vector3.new(2, height, 2)
	t.CFrame = cf
	t.Color = Palette.Industrial
	t.Material = Enum.Material.Metal
	t.Parent = parent
	return t
end

function Builder.pointLight(part: BasePart, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = part
	return l
end

function Builder.spotLight(part: BasePart, color: Color3, brightness: number, range: number, angle: number, face: Enum.NormalId): SpotLight
	local l = Instance.new("SpotLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Face = face
	l.Shadows = false
	l.Parent = part
	return l
end

-- Text on a face of a part (signs, labels). No asset ids required.
function Builder.label(part: BasePart, text: string, face: Enum.NormalId, color: Color3?, textSize: number?, bg: Color3?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	frame.BackgroundTransparency = if bg then 0 else 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(0.94, 0.9)
	tl.Position = UDim2.fromScale(0.03, 0.05)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color or Palette.PaleStone
	tl.TextScaled = textSize == nil
	tl.TextSize = textSize or 24
	tl.Font = Enum.Font.GothamBold
	tl.TextWrapped = true
	tl.Parent = frame
	gui.Parent = part
	return gui
end

-- Battery emergency lamp: dark until the grid goes down (BlackoutService switches it on).
function Builder.emergencyLight(parent: Instance, x: number, y: number, z: number): Part
	local p = Builder.box(parent, x, y, z, 1.4, 0.6, 1.4, { name = "EmergencyLight", material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(70, 48, 20), canCollide = false, castShadow = false })
	local l = Builder.pointLight(p, Palette.SecurityAmber, 0, 34)
	l.Enabled = false
	return p
end

function Builder.neonSign(parent: Instance, cf: CFrame, size: Vector3, text: string, color: Color3, face: Enum.NormalId?): Part
	local p = Builder.part(parent, cf, size, { name = "NeonSign", material = Enum.Material.Neon, color = color, canCollide = false })
	Builder.label(p, text, face or Enum.NormalId.Front, Palette.Night)
	Builder.pointLight(p, color, 2, 30)
	return p
end

function Builder.prompt(part: BasePart, actionText: string, objectText: string, holdSeconds: number, tag: string, attrs: { [string]: any }?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = holdSeconds
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Style = Enum.ProximityPromptStyle.Default
	pp:SetAttribute("Tag", tag)
	if attrs then
		for k, v in pairs(attrs) do
			pp:SetAttribute(k, v)
		end
	end
	pp.Parent = part
	return pp
end

function Builder.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Builder.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Deterministic pseudo-random for cosmetic variation (same world every build).
function Builder.rng(seed: number): Random
	return Random.new(seed)
end

return Builder
