local Util = {}

-- Makes a table (and every table inside it) read-only.
function Util.DeepFreeze(tbl)
	if typeof(tbl) ~= "table" or table.isfrozen(tbl) then
		return tbl
	end
	for _, value in tbl do
		Util.DeepFreeze(value)
	end
	table.freeze(tbl)
	return tbl
end

-- 1234567 -> "$1,234,567"
function Util.FormatMoney(amount: number): string
	local rounded = math.floor(math.abs(amount) + 0.5)
	local digits = tostring(rounded)
	local withCommas = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	withCommas = withCommas:gsub("^,", "")
	local sign = if amount < 0 then "-" else ""
	return sign .. "$" .. withCommas
end

-- Returns a function(player) -> boolean. It returns false if the same player
-- calls again sooner than minInterval seconds. Entries vanish when players leave.
function Util.MakeRateLimiter(minInterval: number)
	local lastCall = setmetatable({}, { __mode = "k" })
	return function(player: Player): boolean
		local now = os.clock()
		local last = lastCall[player]
		if last and now - last < minInterval then
			return false
		end
		lastCall[player] = now
		return true
	end
end

-- 347 -> "$3.47", 123456 -> "$1,234.56"  (input is whole cents)
function Util.FormatCents(cents: number): string
	local total = math.floor(math.abs(cents) + 0.5)
	local dollars = total // 100
	local remainder = total % 100
	local sign = if cents < 0 then "-" else ""
	local dollarText = tostring(dollars):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return string.format("%s$%s.%02d", sign, dollarText, remainder)
end

-- Where does a ray hit an ellipsoid? Returns t (0..1 along `direction`) or nil.
-- halfSize = the ellipsoid's radius along each of its own X, Y, Z axes.
function Util.RayEllipsoid(origin: Vector3, direction: Vector3, cframe: CFrame, halfSize: Vector3): number?
	local o = cframe:PointToObjectSpace(origin)
	local d = cframe:VectorToObjectSpace(direction)
	o = Vector3.new(o.X / halfSize.X, o.Y / halfSize.Y, o.Z / halfSize.Z)
	d = Vector3.new(d.X / halfSize.X, d.Y / halfSize.Y, d.Z / halfSize.Z)

	local a = d:Dot(d)
	local b = 2 * o:Dot(d)
	local c = o:Dot(o) - 1
	local discriminant = b * b - 4 * a * c
	if a == 0 or discriminant < 0 then
		return nil
	end
	local t = (-b - math.sqrt(discriminant)) / (2 * a)
	if t < 0 or t > 1 then
		return nil
	end
	return t
end

-- Projects a point onto the ellipsoid's surface (straight out from its center).
-- Returns the surface point and the outward normal.
function Util.EllipsoidSurface(cframe: CFrame, halfSize: Vector3, point: Vector3): (Vector3, Vector3)
	local rel = cframe:PointToObjectSpace(point)
	local scaled = Vector3.new(rel.X / halfSize.X, rel.Y / halfSize.Y, rel.Z / halfSize.Z)
	local m = scaled.Magnitude
	if m < 1e-4 then
		return cframe.Position, cframe.UpVector
	end
	local p = rel / m
	local n = Vector3.new(p.X / (halfSize.X ^ 2), p.Y / (halfSize.Y ^ 2), p.Z / (halfSize.Z ^ 2)).Unit
	return cframe:PointToWorldSpace(p), cframe:VectorToWorldSpace(n)
end

return Util