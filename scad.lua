local next, type = next, type
local format = string.format
local ins, rem, concat = table.insert, table.remove, table.concat

---@alias SCAD.Vec2 { [1]: number, [2]: number }
---@alias SCAD.Vec3 { [1]: number, [2]: number, [3]: number }
---@alias SCAD.FragOptions { fa?: number, fs?: number, fn?: number }

---@alias SCAD.enum.Shape 'cube' | 'square' | 'cylinder' | 'sphere' | 'circle' | 'text' | 'polygon' | 'polyhedron' | 'import' | 'surface'
---@alias SCAD.enum.Calculate 'union' | 'difference' | 'intersection' | 'hull' | 'minkowski'
---@alias SCAD.enum.Transform 'translate' | 'scale' | 'rotate' | 'mirror' | 'resize' | 'multmatrix' | 'color' | 'linear_extrude' | 'rotate_extrude' | 'offset' | 'projection'
---@alias SCAD.enum.Op SCAD.enum.Shape | SCAD.enum.Calculate | SCAD.enum.Transform

---@class SCAD.Transform
---@field op SCAD.enum.Transform
---@field [string] any

---@class SCAD.Node
---@field op SCAD.enum.Op
---@field params table
---@field transforms SCAD.Transform[]
---@field children SCAD.Node[] | nil
local Node = {}; Node.__index = Node

local SCAD = {}

local function what(n)
    return type(n) == 'string' and ("field '" .. n .. "'") or ("arg " .. n)
end
local function c_bool(v, n, f)
    assert(type(v) == 'boolean',
        format("%s: %s must be a boolean, got %s", f, what(n), type(v)))
end
local function c_num(v, n, f)
    assert(type(v) == 'number',
        format("%s: %s must be a number, got %s", f, what(n), type(v)))
end
local function c_size(v, n, f)
    assert(type(v) == 'number' and v > 0,
        format("%s: %s must be a positive number, got %s", f, what(n), tostring(v)))
end
local function c_color(v, n, f)
    assert(type(v) == 'number' and v >= 0 and v <= 1,
        format("%s: %s must be a number in [0,1], got %s", f, what(n), tostring(v)))
end
local function c_fn(v, n, f)
    assert(type(v) == 'number' and v >= 0 and v % 1 == 0,
        format("%s: %s must be a non-negative integer, got %s", f, what(n), tostring(v)))
end
local function c_frag(v, n, f)
    assert(type(v) == 'table', format("%s: %s must be a table, got %s", f, what(n), type(v)))
    if v.fa ~= nil then c_size(v.fa, 'fa', f) end
    if v.fs ~= nil then c_size(v.fs, 'fs', f) end
    if v.fn ~= nil then c_fn(v.fn, 'fn', f) end
end
local function c_str(v, n, f)
    assert(type(v) == 'string', format("%s: %s must be a string, got %s", f, what(n), type(v)))
end
local function c_node(v, n, f)
    assert(type(v) == 'table' and v.__index == Node,
        format("%s: %s must be a scad node, got %s", f, what(n), type(v)))
end
local function c_mat4(m, n, f)
    assert(type(m) == 'table' and #m == 4, format("%s: %s must be a 4x4 matrix", f, what(n)))
    for i = 1, 4 do
        local row = m[i]
        assert(type(row) == 'table' and #row >= 4,
            format("%s: %s row %d must be vector with at least 4 elements", f, what(n), i))
        for j = 1, 4 do
            c_num(row[j], format('[%d][%d]', i, j), f)
        end
    end
end

local function fmt(v)
    return format('%.6g', v)
end
local function fmt_vec(v)
    local parts = {}
    for i = 1, #v do parts[i] = fmt(v[i]) end
    return "[" .. concat(parts, ",") .. "]"
end
local function fmt_mat(m)
    local rows = {}
    for i = 1, #m do rows[i] = fmt_vec(m[i]) end
    return "[" .. concat(rows, ",") .. "]"
end

--------------------------------------------------------------
---Primitive 2D

---@overload fun(size: number, center?: true): SCAD.Node
---@param w number width
---@param l number length or true (center)
---@param c? true center
---@return SCAD.Node
function SCAD.square(w, l, c)
    c_size(w, 1, 'square')
    if type(l) == 'number' then
        c_size(l, 2, 'square')
        if c ~= nil then c_bool(c, 3, 'square') end
    else
        if l ~= nil then c_bool(l, 2, 'square') end
    end

    return Node.new('square',
        type(l) == 'number' and
        { size = { w, l }, center = c == true } or
        { size = w, center = l == true }
    )
end

---@param r number radius
---@param frag? SCAD.FragOptions
---@return SCAD.Node
function SCAD.circle(r, frag)
    c_size(r, 1, 'circle')
    if frag ~= nil then c_frag(frag, 2, 'circle') end

    return Node.new('circle', { r = r, frag = frag })
end

---@param p { points: SCAD.Vec2[], paths?: number[][], convexity?: number }
---@return SCAD.Node
function SCAD.polygon(p)
    assert(type(p) == 'table', "polygon: expected a table parameter")
    local pts = p.points
    assert(type(pts) == 'table' and #pts >= 3, "polygon: field 'points' must be an array of at least 3 points")
    for i, pt in next, pts do
        assert(type(pt) == 'table' and type(pt[1]) == 'number' and type(pt[2]) == 'number',
            format("polygon: points[%d] must be {x, y}", i))
    end
    if p.convexity ~= nil then c_num(p.convexity, 'convexity', 'polygon') end

    return Node.new('polygon', {
        points    = pts,
        paths     = p.paths,
        convexity = p.convexity,
    })
end

---@overload fun(str: string): SCAD.Node
---@overload fun(str: string, size: number): SCAD.Node
---@param str string text to render
---@param size? number font size
---@param font? string font name
---@param halign? 'left' | 'center' | 'right'
---@param valign? 'top' | 'center' | 'baseline' | 'bottom'
---@param spacing? number character spacing
---@param direction? 'ltr' | 'rtl' | 'ttb' | 'btt'
---@param language? string
---@param script? string
---@return SCAD.Node
function SCAD.text(str, size, font, halign, valign, spacing, direction, language, script)
    c_str(str, 1, 'text')
    if size ~= nil then c_size(size, 2, 'text') end
    if font ~= nil then c_str(font, 3, 'text') end
    if halign ~= nil then c_str(halign, 4, 'text') end
    if valign ~= nil then c_str(valign, 5, 'text') end
    if spacing ~= nil then c_num(spacing, 6, 'text') end
    if direction ~= nil then c_str(direction, 7, 'text') end
    if language ~= nil then c_str(language, 8, 'text') end
    if script ~= nil then c_str(script, 9, 'text') end

    return Node.new('text', {
        text      = str,
        size      = size,
        font      = font,
        halign    = halign,
        valign    = valign,
        spacing   = spacing,
        direction = direction,
        language  = language,
        script    = script,
    })
end

--------------------------------------------------------------
---Primitive 3D

---@overload fun(size: number, center?: true): SCAD.Node
---@param w number width
---@param l? number length or true (center)
---@param h? number height
---@param c? true center
---@return SCAD.Node
function SCAD.cube(w, l, h, c)
    c_size(w, 1, 'cube')
    if h ~= nil then
        c_size(l, 2, 'cube')
        c_size(h, 3, 'cube')
        if c ~= nil then c_bool(c, 4, 'cube') end
    else
        if l ~= nil then c_bool(l, 2, 'cube') end
    end

    return Node.new('cube',
        h and
        { size = { w, l, h }, center = c == true } or
        { size = w, center = l == true }
    )
end

---@param r number radius
---@param frag? SCAD.FragOptions
---@return SCAD.Node
function SCAD.sphere(r, frag)
    c_size(r, 1, 'sphere')
    if frag ~= nil then c_frag(frag, 2, 'sphere') end

    return Node.new('sphere', { r = r, frag = frag })
end

---@overload fun(h: number, r: number, center?: true, frag?: SCAD.FragOptions): SCAD.Node
---@param h number height
---@param r1 number bottom radius
---@param r2? number top radius
---@param c? true center
---@param frag? SCAD.FragOptions
---@return SCAD.Node
function SCAD.cylinder(h, r1, r2, c, frag)
    c_size(h, 1, 'cylinder')
    if type(r2) == 'number' then
        c_size(r1, 2, 'cylinder')
        c_size(r2, 3, 'cylinder')
        if c ~= nil then c_bool(c, 4, 'cylinder') end
        if frag ~= nil then c_frag(frag, 5, 'cylinder') end
    else
        -- one radius mode (no r2): center = r2==true, frag = c
        if r2 ~= nil and r2 ~= true then
            error("cylinder: expected cylinder(h, r[, true][, frag]) or cylinder(h, r1, r2[, true][, frag])", 3)
        end
        c_size(r1, 2, 'cylinder')
        if c ~= nil then c_frag(c, 4, 'cylinder') end
    end

    return Node.new('cylinder',
        type(r2) == 'number' and {
            h      = h,
            r1     = r1,
            r2     = r2,
            center = c == true,
            frag   = frag,
        } or {
            h      = h,
            r      = r1,
            center = r2 == true,
            frag   = c and c ~= true and c or nil,
        }
    )
end

---@param p { points: SCAD.Vec3[], faces: SCAD.Vec3[], convexity?: number }
---@return SCAD.Node
function SCAD.polyhedron(p)
    assert(type(p) == 'table', "polyhedron: expected a table parameter")
    local pts = p.points
    assert(type(pts) == 'table' and #pts >= 4, "polyhedron: field 'points' must be an array of at least 4 points")
    for i, pt in next, pts do
        assert(type(pt) == 'table' and type(pt[1]) == 'number' and type(pt[2]) == 'number' and type(pt[3]) == 'number',
            format("polyhedron: points[%d] must be {x, y, z}", i))
    end
    assert(type(p.faces) == 'table' and #p.faces > 0, "polyhedron: field 'faces' must be a non-empty array")
    for i, face in next, p.faces do
        assert(type(face) == 'table' and #face >= 3,
            format("polyhedron: faces[%d] must be an array of at least 3 vertex indices", i))
    end
    if p.convexity ~= nil then c_num(p.convexity, 'convexity', 'polyhedron') end

    return Node.new('polyhedron', {
        points    = pts,
        faces     = p.faces,
        convexity = p.convexity,
    })
end

---@param file string heightmap data file path
---@param center? true
---@param convexity? number
---@return SCAD.Node
function SCAD.surface(file, center, convexity)
    c_str(file, 1, 'surface')
    if center ~= nil then c_bool(center, 2, 'surface') end
    if convexity ~= nil then c_num(convexity, 3, 'surface') end

    return Node.new('surface', { file = file, center = center == true, convexity = convexity })
end

--------------------------------------------------------------
---Primitive Utils

---@param path string file path to import (.stl / .3mf / .dxf / ...)
---@param convexity? number
---@return SCAD.Node
function SCAD.import(path, convexity)
    c_str(path, 1, 'import')
    if convexity ~= nil then c_num(convexity, 2, 'import') end

    return Node.new('import', { path = path, convexity = convexity })
end

--------------------------------------------------------------
---Boolean / hull / minkowski (wrap child node arrays)

---@alias SCAD.multiNodeOp fun(children: SCAD.Node[]): SCAD.Node

SCAD.union        = nil ---@type SCAD.multiNodeOp
SCAD.difference   = nil ---@type SCAD.multiNodeOp
SCAD.intersection = nil ---@type SCAD.multiNodeOp
SCAD.hull         = nil ---@type SCAD.multiNodeOp
SCAD.minkowski    = nil ---@type SCAD.multiNodeOp

for _, kind in next, { 'union', 'difference', 'intersection', 'hull', 'minkowski' } do
    SCAD[kind] = function(children)
        assert(type(children) == 'table' and #children > 0, kind .. " needs at least one child")
        for i, child in next, children do c_node(child, i, kind) end

        return Node.new(kind, nil, children)
    end
end

--------------------------------------------------------------
---Node

---@param op SCAD.enum.Op
---@param params? table
---@param children? SCAD.Node[]
---@return SCAD.Node
function Node.new(op, params, children)
    return setmetatable({
        op         = op,
        params     = params or {},
        transforms = {},
        children   = children,
    }, Node)
end

local function copy_table(t)
    local out = {}
    for k, v in next, t do out[k] = type(v) == 'table' and copy_table(v) or v end
    return out
end

--------------------------------------------------------------
---Node operations

---@param x number
---@param y? number
---@param z? number
---@return SCAD.Node
function Node:translate(x, y, z)
    c_num(x, 1, 'translate')
    if y ~= nil then
        c_num(y, 2, 'translate')
        if z ~= nil then c_num(z, 3, 'translate') end
    end

    ins(self.transforms, { op = 'translate', v = { x or 0, y or 0, z or 0 } })
    return self
end

---@overload fun(factor: number): SCAD.Node
---@param x number x scale factor
---@param y? number y scale factor
---@param z? number z scale factor
---@return SCAD.Node
function Node:scale(x, y, z)
    c_num(x, 1, 'scale')
    if y ~= nil then
        c_num(y, 2, 'scale')
        c_num(z, 3, 'scale')
    end

    ins(self.transforms, { op = 'scale', v = y and { x, y, z } or x })
    return self
end

---@overload fun(z: number): SCAD.Node
---@param a number
---@param x? number
---@param y? number
---@param z? number
---@return SCAD.Node
function Node:rotate(a, x, y, z)
    c_num(a, 1, 'rotate')
    if x ~= nil then
        c_num(x, 2, 'rotate')
        c_num(y, 3, 'rotate')
        if z ~= nil then c_num(z, 4, 'rotate') end
    end

    ins(self.transforms, { op = 'rotate', v = { a, x, y, z } })
    return self
end

---@param x number normal x
---@param y? number normal y
---@param z? number normal z
---@return SCAD.Node
function Node:mirror(x, y, z)
    c_num(x, 1, 'mirror')
    if y ~= nil then
        c_num(y, 2, 'mirror')
        if z ~= nil then c_num(z, 3, 'mirror') end
    end

    ins(self.transforms, { op = 'mirror', v = { x or 0, y or 0, z or 0 } })
    return self
end

---@overload fun(x: number, y: number, z: number): SCAD.Node
---@param w number target width
---@param l number target length
---@param h number target height
---@param auto? boolean | SCAD.Vec3 auto-scale (boolean or per-axis)
---@param convexity? number
---@return SCAD.Node
function Node:resize(w, l, h, auto, convexity)
    c_num(w, 1, 'resize')
    c_num(l, 2, 'resize')
    c_num(h, 3, 'resize')
    if auto ~= nil then c_bool(auto, 4, 'resize') end
    if convexity ~= nil then c_num(convexity, 5, 'resize') end

    ins(self.transforms, { op = 'resize', v = { w, l, h }, auto = auto, convexity = convexity })
    return self
end

---@param m number[][] 4x4 transformation matrix
---@return SCAD.Node
function Node:multmatrix(m)
    c_mat4(m, 1, 'multmatrix')

    ins(self.transforms, { op = 'multmatrix', m = m })
    return self
end

---@param r number red (0-1)
---@param g? number green (0-1), default r
---@param b? number blue (0-1), default r
---@param a? number alpha (0-1), default 1
---@return SCAD.Node
function Node:color(r, g, b, a)
    c_color(r, 1, 'color')
    if g ~= nil then
        c_color(g, 2, 'color')
        c_color(b, 3, 'color')
        if a ~= nil then c_color(a, 4, 'color') end
    end

    ins(self.transforms, { op = 'color', v = { r, g or r, b or r, a } })
    return self
end

---@param params { h: number, center?: true, twist?: number, convexity?: number }
---@return SCAD.Node
function Node:linear_extrude(params)
    params = params or {}
    c_size(params.h, 'h', 'linear_extrude')
    if params.center ~= nil then c_bool(params.center, 'center', 'linear_extrude') end
    if params.twist ~= nil then c_num(params.twist, 'twist', 'linear_extrude') end
    if params.convexity ~= nil then c_num(params.convexity, 'convexity', 'linear_extrude') end

    ins(self.transforms, {
        op = 'linear_extrude',
        h = params.h,
        center = params.center,
        twist = params.twist,
        convexity = params.convexity
    })
    return self
end

---@param angle? number
---@param convexity? number
---@return SCAD.Node
function Node:rotate_extrude(angle, convexity)
    if angle ~= nil then c_num(angle, 1, 'rotate_extrude') end
    if convexity ~= nil then c_num(convexity, 2, 'rotate_extrude') end

    ins(self.transforms, { op = 'rotate_extrude', angle = angle, convexity = convexity })
    return self
end

---r-branch of offset
---@param r number offset radius
---@return SCAD.Node
function Node:offsetR(r)
    c_num(r, 1, 'offsetR')

    ins(self.transforms, { op = 'offset', r = r })
    return self
end

---delta-branch of offset
---@param delta number offset distance
---@param chamfer? true enable chamfer
---@return SCAD.Node
function Node:offsetD(delta, chamfer)
    c_num(delta, 1, 'offsetD')
    if chamfer ~= nil then c_bool(chamfer, 2, 'offsetD') end

    ins(self.transforms, { op = 'offset', delta = delta, chamfer = chamfer })
    return self
end

---@param cut? true
---@return SCAD.Node
function Node:projection(cut)
    if cut ~= nil then c_bool(cut, 1, 'projection') end

    ins(self.transforms, { op = 'projection', cut = cut })
    return self
end

--------------------------------------------------------------
---Node operations EXTRA

---[Extra] Deep clone a node to create duplicate copies
---@return SCAD.Node
function Node:clone()
    local n = Node.new(self.op, copy_table(self.params))
    n.transforms = copy_table(self.transforms)
    if self.children then
        n.children = {}
        for i = 1, #self.children do
            n.children[i] = self.children[i]:clone()
        end
    end
    return n
end

---[Extra] Shortcut of Projection (cut mode), with optional height specification
---@param h? number height
---@return SCAD.Node
function Node:cut(h)
    if h ~= nil then c_num(h, 1, 'cut') end

    if h ~= nil then self:translate(0, 0, -(h or 0)) end
    return self:projection(true)
end

---[Extra] Duplicate a node with specific spatial step
---@param count number count (including the original)
---@param dx number x step
---@param dy? number y step
---@param dz? number z step
---@return SCAD.Node
function Node:array(count, dx, dy, dz)
    c_size(count, 1, 'array')
    c_num(dx, 2, 'array')
    if dy ~= nil then
        c_num(dy, 3, 'array')
        if dz ~= nil then c_num(dz, 4, 'array') end
    end

    ins(self.transforms, { op = 'array', count = count, step = { dx or 0, dy or 0, dz or 0 } })
    return self
end

---[Extra] [2D] Lossless rounding via double offset
---@param r number corner radius
---@return SCAD.Node
function Node:round(r)
    c_num(r, 1, 'round')

    return self:offsetD(-r):offsetR(r)
end

---[Extra] [2D] Lossless chamfer via double offset
---@param d number chamfer size
---@return SCAD.Node
function Node:chamfer(d)
    c_num(d, 1, 'chamfer')

    return self:offsetD(-d):offsetD(d, true)
end

--------------------------------------------------------------
---Rendering

---Return `pr(p1, p2, ...);`
local function buildP(list)
    for i = #list, 1, -1 do if list[i] == false then rem(list, i) end end
    return rem(list, 1) .. "(" .. concat(list, ", ") .. ");"
end
local primitive_templates = {
    cube = function(p)
        return buildP {
            "cube",
            type(p.size) == 'number' and fmt(p.size) or fmt_vec(p.size),
            p.center and 'center=true' or false,
        }
    end,
    square = function(p)
        return buildP {
            "square",
            type(p.size) == 'number' and fmt(p.size) or fmt_vec(p.size),
            p.center and 'center=true' or false,
        }
    end,
    cylinder = function(p)
        return buildP {
            "cylinder",
            "h=" .. fmt(p.h),
            p.r and "r=" .. fmt(p.r) or false,
            p.r1 and "r1=" .. fmt(p.r1) or false,
            p.r2 and "r2=" .. fmt(p.r2) or false,
            p.center and "center=true" or false,
            p.frag and p.frag.fa and "$fa=" .. fmt(p.frag.fa) or false,
            p.frag and p.frag.fs and "$fs=" .. fmt(p.frag.fs) or false,
            p.frag and p.frag.fn and "$fn=" .. p.frag.fn or false,
        }
    end,
    sphere = function(p)
        return buildP {
            "sphere",
            "r=" .. fmt(p.r),
            p.frag and p.frag.fa and "$fa=" .. fmt(p.frag.fa) or false,
            p.frag and p.frag.fs and "$fs=" .. fmt(p.frag.fs) or false,
            p.frag and p.frag.fn and "$fn=" .. p.frag.fn or false,
        }
    end,
    circle = function(p)
        return buildP {
            "circle",
            "r=" .. fmt(p.r),
            p.frag and p.frag.fa and "$fa=" .. fmt(p.frag.fa) or false,
            p.frag and p.frag.fs and "$fs=" .. fmt(p.frag.fs) or false,
            p.frag and p.frag.fn and "$fn=" .. p.frag.fn or false,
        }
    end,
    text = function(p)
        return buildP {
            "text",
            format('"%s"', p.text),
            p.size and "size=" .. fmt(p.size) or false,
            p.font and format('font="%s"', p.font) or false,
            p.halign and format('halign="%s"', p.halign) or false,
            p.valign and format('valign="%s"', p.valign) or false,
            p.spacing and "spacing=" .. fmt(p.spacing) or false,
            p.direction and format('direction="%s"', p.direction) or false,
            p.language and format('language="%s"', p.language) or false,
            p.script and format('script="%s"', p.script) or false,
        }
    end,
    polygon = function(p)
        return buildP {
            "polygon",
            "points=" .. fmt_mat(p.points),
            p.paths and "paths=" .. fmt_mat(p.paths) or false,
            p.convexity and "convexity=" .. p.convexity or false,
        }
    end,
    polyhedron = function(p)
        return buildP {
            "polyhedron",
            "points=" .. fmt_mat(p.points),
            "faces=" .. fmt_mat(p.faces),
            p.convexity and "convexity=" .. p.convexity or false,
        }
    end,
    import = function(p)
        return buildP {
            "import",
            format('"%s"', p.path),
            p.convexity and "convexity=" .. p.convexity or false,
        }
    end,
    surface = function(p)
        return buildP {
            "surface",
            format('file="%s"', p.file),
            p.center and "center=true" or false,
            p.convexity and "convexity=" .. p.convexity or false,
        }
    end,
}
---Return `tr(p1, p2, ...)`
local function buildT(list)
    for i = #list, 1, -1 do if list[i] == false then rem(list, i) end end
    return rem(list, 1) .. "(" .. concat(list, ", ") .. ")"
end
local transform_templates = {
    translate = function(tr)
        return buildT {
            "translate",
            fmt_vec(tr.v),
        }
    end,
    scale = function(tr)
        return buildT {
            "scale",
            type(tr.v) == 'number' and fmt(tr.v) or fmt_vec(tr.v),
        }
    end,
    rotate = function(tr)
        return buildT {
            "rotate",
            #tr.v == 3 and fmt_vec(tr.v) or fmt(tr.v[1]),
            #tr.v == 4 and fmt_vec({ tr.v[2], tr.v[3], tr.v[4] }) or false,
        }
    end,
    mirror = function(tr)
        return buildT {
            "mirror",
            fmt_vec(tr.v),
        }
    end,
    resize = function(tr)
        return buildT {
            "resize",
            fmt_vec(tr.v),
            tr.auto ~= nil and "auto=" .. tostring(tr.auto) or false,
            tr.convexity ~= nil and "convexity=" .. fmt(tr.convexity) or false,
        }
    end,
    multmatrix = function(tr)
        return buildT {
            "multmatrix",
            "m=" .. fmt_mat(tr.m),
        }
    end,
    color = function(tr)
        return buildT {
            "color",
            fmt_vec(tr.v),
        }
    end,
    linear_extrude = function(tr)
        return buildT {
            "linear_extrude",
            fmt(tr.h),
            tr.center and "center=true" or false,
            tr.twist and "twist=" .. fmt(tr.twist) or false,
            tr.convexity and "convexity=" .. tr.convexity or false,
        }
    end,
    rotate_extrude = function(tr)
        return buildT {
            "rotate_extrude",
            tr.angle and "angle=" .. fmt(tr.angle) or false,
            tr.convexity and "convexity=" .. tr.convexity or false,
        }
    end,
    offset = function(tr)
        return buildT {
            "offset",
            tr.r and "r=" .. fmt(tr.r) or false,
            tr.delta and "delta=" .. fmt(tr.delta) or false,
            tr.chamfer and "chamfer=true" or false,
        }
    end,
    projection = function(tr)
        return buildT {
            "projection",
            tr.cut and "cut=true" or false,
        }
    end,
    array = function(tr)
        return "for (i = [0:" .. (tr.count - 1) .. "]) translate(" .. fmt_vec(tr.step) .. " * i)"
    end,
}

local render_node

local function render_boolean(n)
    local parts = {}
    for i, child in next, n.children do
        parts[i] = render_node(child)
    end
    return n.op .. "() {\n" .. concat(parts, "\n") .. "\n}"
end

local function wrap_transforms(n, code)
    for _, tr in next, n.transforms do
        code = transform_templates[tr.op](tr) .. " {\n" .. code .. "\n}"
    end
    return code
end

function render_node(n)
    if n.children then return wrap_transforms(n, render_boolean(n)) end
    return wrap_transforms(n, (primitive_templates[n.op] or error("unknown primitive type: " .. n.op))(n.params))
end

---@overload fun(...: (SCAD.Node | string)): string
---@overload fun(...: (SCAD.Node | string), path: string)
---@overload fun(...: (SCAD.Node | string), preview: true)
function SCAD.export(...)
    local n = select('#', ...)

    local mode
    local lastParam = select(n, ...)
    if lastParam == true then
        mode = 'preview'
    elseif type(lastParam) == 'string' and lastParam:match('%.scad$') then
        mode = 'scad'
    elseif type(lastParam) == 'string' and lastParam:match('%.stl$') then
        mode = 'stl'
    else
        mode = 'raw'
    end

    local buffer = { ... }

    if mode ~= 'raw' then
        buffer[n] = nil
        n = n - 1
    end

    for i = 1, n do
        if type(buffer[i]) == 'table' and buffer[i].__index == Node then
            buffer[i] = render_node(buffer[i])
        elseif type(buffer[i]) ~= 'string' then
            error("export: expected SCAD.Node object or scad script string, got " .. type(buffer[i]))
        end
    end

    local code = concat(buffer, "\n\n")

    if mode == 'raw' then
        -- Raw string
        return code
    elseif mode == 'preview' then
        -- Preview in openscad
        io.open('_preview.scad', 'w'):write(code):close()
        os.execute('"openscad" "_preview.scad"')
    elseif mode == 'scad' then
        -- Write to .scad file
        io.open(lastParam, 'w'):write(code):close()
    elseif mode == 'stl' then
        -- Render & write to .stl file with openscad
        local tmp = os.tmpname() .. '.stl'
        local p = io.popen(format('"openscad" - -o "%s" 2>/dev/null', tmp), 'w')
        p:write(code)
        local ok = p:close()
        if ok then
            local src = assert(io.open(tmp, 'rb'))
            local data = src:read('a')
            src:close()
            io.open(lastParam, 'wb'):write(data):close()
        end
        os.remove(tmp)
        assert(ok, "openscad render failed")
    else
        error("?")
    end
end

--------------------------------------------------------------
---Utils

---Release all APIs to _ENV, so you can call them directly without SCAD prefix
function SCAD.install()
    for k, v in next, SCAD do
        if type(k) == 'string' and not k:find('^_') then
            _G[k] = v
        end
    end
    return SCAD
end

return SCAD
