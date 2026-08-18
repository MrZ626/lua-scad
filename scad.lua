local next, type = next, type
local format = string.format
local ins, rem, concat = table.insert, table.remove, table.concat

---@alias SCAD.Vec2 { [1]: number, [2]: number }
---@alias SCAD.Vec3 { [1]: number, [2]: number, [3]: number }
---@alias SCAD.FragOptions { fa?: number, fs?: number, fn?: number }

---@alias SCAD.enum.Shape 'cube' | 'square' | 'cylinder' | 'sphere' | 'circle' | 'text' | 'polygon' | 'polyhedron' | 'import' | 'surface'
---@alias SCAD.enum.MultiNodeOp 'union' | 'difference' | 'intersection' | 'hull' | 'minkowski' | 'fill' | 'render'
---@alias SCAD.enum.Transform.Basic 'translate' | 'scale' | 'rotate' | 'mirror' | 'resize' | 'multmatrix'
---@alias SCAD.enum.Transform.Special 'color' | 'linear_extrude' | 'rotate_extrude' | 'offset' | 'projection'
---@alias SCAD.enum.Transform.Extra 'array' | 'rotate_array'
---@alias SCAD.enum.Transform.Debug 'debug' | 'background' | 'root' | 'disable'
---@alias SCAD.enum.Transform SCAD.enum.Transform.Basic | SCAD.enum.Transform.Special | SCAD.enum.Transform.Extra | SCAD.enum.Transform.Debug
---@alias SCAD.enum.Op SCAD.enum.Shape | SCAD.enum.MultiNodeOp | SCAD.enum.Transform

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
    return type(n) == 'string' and ("field '" .. n .. "'") or ("arg_" .. n)
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
local function c_nonneg(v, n, f)
    assert(type(v) == 'number' and v >= 0,
        format("%s: %s must be a non-negative number, got %s", f, what(n), tostring(v)))
end
local function c_pint(v, n, f)
    assert(type(v) == 'number' and v > 0 and v % 1 == 0,
        format("%s: %s must be a positive integer, got %s", f, what(n), tostring(v)))
end
local function c_num_color(v, n, f)
    assert(type(v) == 'number' and v >= 0 and v <= 1,
        format("%s: %s must be a number in [0,1], got %s", f, what(n), tostring(v)))
end
local function c_hex_color(v, n, f)
    assert(#v == 4 or #v == 5 or #v == 7 or #v == 9,
        format("%s: %s must be a hex color string (#RGB #RGBA #RRGGBB #RRGGBBAA), got %s", f, what(n), tostring(v)))
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
local function c_vec2(m, n, f)
    assert(type(m) == 'table' and #m == 2, format("%s: %s must be a vector with 2 elements", f, what(n)))
    for i = 1, 2 do c_num(m[i], format('[%d]', i), f) end
end
local function c_vec3(m, n, f)
    assert(type(m) == 'table' and #m == 3, format("%s: %s must be a vector with 3 elements", f, what(n)))
    for i = 1, 3 do c_num(m[i], format('[%d]', i), f) end
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

---@overload fun(size: number, center?: boolean): SCAD.Node
---@param w number width
---@param l number length (or center)
---@param c? boolean center
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

---@param points SCAD.Vec2[]
---@param paths? number[][]
---@param convexity? number
---@return SCAD.Node
function SCAD.polygon(points, paths, convexity)
    assert(type(points) == 'table' and #points >= 3, "polygon: 'arg_1' must be an array of at least 3 points")
    for i, pt in next, points do c_vec2(pt, format('arg_1[%d]', i), 'polygon') end
    if paths ~= nil then
        assert(type(paths) == 'table', "polygon: 'arg_2' must be a table")
        for i, path in next, paths do
            assert(type(path) == 'table', format("polygon: arg_2[%d] must be an array", i))
            for j = 1, #path do
                assert(type(path[j]) == 'number' and path[j] % 1 == 0 and path[j] >= 0,
                    format("polygon: arg_2[%d][%d] must be a non-negative integer index", i, j))
                assert(path[j] < #points,
                    format("polygon: arg_2[%d][%d] index %d out of range (max %d)", i, j, path[j], #points - 1))
            end
        end
    end
    if convexity ~= nil then c_num(convexity, 3, 'polygon') end

    return Node.new('polygon', {
        points    = points,
        paths     = paths,
        convexity = convexity,
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

---@overload fun(size: number, center?: boolean): SCAD.Node
---@param w number width
---@param l? number length (or center)
---@param h? number height
---@param c? boolean center
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

---@overload fun(h: number, r: number, center?: boolean, frag?: SCAD.FragOptions): SCAD.Node
---@param h number height
---@param r1 number bottom radius
---@param r2? number top radius
---@param c? boolean center
---@param frag? SCAD.FragOptions
---@return SCAD.Node
function SCAD.cylinder(h, r1, r2, c, frag)
    c_size(h, 1, 'cylinder')
    c_nonneg(r1, 2, 'cylinder')
    if type(r2) == 'number' then
        c_nonneg(r2, 3, 'cylinder')
        if c ~= nil then c_bool(c, 4, 'cylinder') end
        if frag ~= nil then c_frag(frag, 5, 'cylinder') end
    else
        -- one radius mode (no r2): center = r2==true, frag = c
        if r2 ~= nil then c_bool(r2, 3, 'cylinder') end
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

---@param points SCAD.Vec3[]
---@param faces number[][]
---@param convexity? number
---@return SCAD.Node
function SCAD.polyhedron(points, faces, convexity)
    assert(type(points) == 'table' and #points >= 4, "polyhedron: 'arg_1' must be an array of at least 4 points")
    for i, pt in next, points do c_vec3(pt, format('arg_1[%d]', i), 'polyhedron') end
    assert(type(faces) == 'table' and #faces > 0, "polyhedron: 'arg_2' must be a non-empty array")
    for i, face in next, faces do
        assert(type(face) == 'table' and #face >= 3,
            format("polyhedron: arg_2[%d] must be an array of at least 3 vertex indices", i))
        for j = 1, #face do
            assert(type(face[j]) == 'number' and face[j] % 1 == 0 and face[j] >= 0,
                format("polyhedron: arg_2[%d][%d] must be a non-negative integer index", i, j))
            assert(face[j] < #points,
                format("polyhedron: arg_2[%d][%d] index %d out of range (max %d)", i, j, face[j], #points - 1))
        end
    end
    if convexity ~= nil then c_num(convexity, 3, 'polyhedron') end

    return Node.new('polyhedron', {
        points    = points,
        faces     = faces,
        convexity = convexity,
    })
end

---@param file string heightmap data file path
---@param center? boolean
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
---Multinode Operations (union / hull / ...)

---@alias SCAD.multiNodeOp fun(children: SCAD.Node[]): SCAD.Node

local function makeMultinodeOp(name)
    return function(children)
        assert(type(children) == 'table' and #children > 0, name .. " needs at least one child")
        for i, child in next, children do c_node(child, i, name) end

        return Node.new(name, nil, children)
    end
end

SCAD.union        = makeMultinodeOp('union') ---@type SCAD.multiNodeOp
SCAD.difference   = makeMultinodeOp('difference') ---@type SCAD.multiNodeOp
SCAD.intersection = makeMultinodeOp('intersection') ---@type SCAD.multiNodeOp
SCAD.hull         = makeMultinodeOp('hull') ---@type SCAD.multiNodeOp
SCAD.minkowski    = makeMultinodeOp('minkowski') ---@type SCAD.multiNodeOp
SCAD.fill         = makeMultinodeOp('fill') ---@type SCAD.multiNodeOp
SCAD.render       = makeMultinodeOp('render') ---@type SCAD.multiNodeOp

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

---@private
---@param tr SCAD.Transform
---@return SCAD.Node
function Node:addTransform(tr)
    ins(self.transforms, tr)
    return self
end

---@return string `pr(p1, p2, ...);`
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
            format('"%s"', string.gsub(p.text, [["]], [[\"]])),
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
---@return string `tr(p1, p2, ...)`
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
            tr.v and fmt_vec(tr.v) or false,
            tr.hex and format('"%s"', tr.hex) or false,
            tr.alpha and "alpha=" .. fmt(tr.alpha) or false,
        }
    end,
    linear_extrude = function(tr)
        return buildT {
            "linear_extrude",
            fmt(tr.h),
            tr.center and "center=true" or false,
            tr.twist and "twist=" .. fmt(tr.twist) or false,
            tr.slices and "slices=" .. tr.slices or false,
            tr.scale and ("scale=" .. (type(tr.scale) == 'table' and fmt_vec(tr.scale) or fmt(tr.scale))) or false,
            tr.convexity and "convexity=" .. tr.convexity or false,
            tr.frag and tr.frag.fa and "$fa=" .. fmt(tr.frag.fa) or false,
            tr.frag and tr.frag.fs and "$fs=" .. fmt(tr.frag.fs) or false,
            tr.frag and tr.frag.fn and "$fn=" .. tr.frag.fn or false,
        }
    end,
    rotate_extrude = function(tr)
        return buildT {
            "rotate_extrude",
            tr.angle and "angle=" .. fmt(tr.angle) or false,
            tr.convexity and "convexity=" .. tr.convexity or false,
            tr.frag and tr.frag.fa and "$fa=" .. fmt(tr.frag.fa) or false,
            tr.frag and tr.frag.fs and "$fs=" .. fmt(tr.frag.fs) or false,
            tr.frag and tr.frag.fn and "$fn=" .. tr.frag.fn or false,
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
        return "for (i = [0:" .. (tr.count - 1) .. "]) " ..
            buildT {
                "translate",
                fmt_vec(tr.step) .. " * i"
            }
    end,
    rotate_array = function(tr)
        return "for (i = [0:" .. (tr.count - 1) .. "]) " ..
            buildT {
                "rotate",
                fmt(tr.angle) .. " * i",
                tr.axis and fmt_vec(tr.axis) or false,
            }
    end,
}
local function export_expand_children(n)
    local parts = {}
    for i, child in next, n.children do
        parts[i] = child:export()
    end
    return n.op .. "() {\n" .. concat(parts, "\n") .. "\n}"
end
local modifier_prefix = {
    debug      = '#',
    background = '%',
    root       = '!',
    disable    = '*',
}
local function wrap_transforms(n, code)
    for _, tr in next, n.transforms do
        local prefix = modifier_prefix[tr.op]
        if prefix then
            code = prefix .. ' ' .. code
        else
            code = transform_templates[tr.op](tr) .. " {\n" .. code .. "\n}"
        end
    end
    return code
end
---@private
---@return string scadScript
function Node:export()
    if self.children then return wrap_transforms(self, export_expand_children(self)) end
    assert(primitive_templates[self.op], "export: unknown primitive type: " .. self.op)
    return wrap_transforms(self, primitive_templates[self.op](self.params))
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

    self:addTransform { op = 'translate', v = { x or 0, y or 0, z or 0 } }
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

    self:addTransform { op = 'scale', v = y and { x, y, z } or x }
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

    self:addTransform { op = 'rotate', v = { a, x, y, z } }
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

    self:addTransform { op = 'mirror', v = { x or 0, y or 0, z or 0 } }
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

    self:addTransform { op = 'resize', v = { w, l, h }, auto = auto, convexity = convexity }
    return self
end

---@param m number[][] 4x4 transformation matrix
---@return SCAD.Node
function Node:multmatrix(m)
    c_mat4(m, 1, 'multmatrix')

    self:addTransform { op = 'multmatrix', m = m }
    return self
end

---@overload fun(hex: string, alpha?: number): SCAD.Node
---@overload fun(color: string, alpha?: number): SCAD.Node
---@param r number red (0-1)
---@param g? number green (0-1), default r
---@param b? number blue (0-1), default r
---@param a? number alpha (0-1), default 1
---@return SCAD.Node
function Node:color(r, g, b, a)
    if type(r) == 'string' then
        if r:match("^#?%x+$") then
            if r:sub(1, 1) ~= '#' then r = '#' .. r end
            c_hex_color(r, 1, 'color')
        else
            if g ~= nil then c_num_color(g, 2, 'color') end
        end
    else
        c_num_color(r, 1, 'color')
        if g ~= nil then
            c_num_color(g, 2, 'color')
            c_num_color(b, 3, 'color')
            if a ~= nil then c_num_color(a, 4, 'color') end
        end
    end

    if type(r) == 'number' then
        self:addTransform { op = 'color', v = { r, g or r, b or r, a } }
    else
        self:addTransform { op = 'color', hex = r, alpha = g }
    end
    return self
end

---@param params { h: number, center?: boolean, twist?: number, slices?: number, scale?: number | SCAD.Vec2, convexity?: number, frag?: SCAD.FragOptions }
---@return SCAD.Node
function Node:linear_extrude(params)
    params = params or {}
    c_size(params.h, 'h', 'linear_extrude')
    if params.center ~= nil then c_bool(params.center, 'center', 'linear_extrude') end
    if params.twist ~= nil then c_num(params.twist, 'twist', 'linear_extrude') end
    if params.slices ~= nil then c_fn(params.slices, 'slices', 'linear_extrude') end
    if params.scale ~= nil then
        if type(params.scale) == 'table' then
            c_vec2(params.scale, 'scale', 'linear_extrude')
        else
            c_num(params.scale, 'scale', 'linear_extrude')
        end
    end
    if params.convexity ~= nil then c_num(params.convexity, 'convexity', 'linear_extrude') end
    if params.frag ~= nil then c_frag(params.frag, 'frag', 'linear_extrude') end

    self:addTransform {
        op = 'linear_extrude',
        h = params.h,
        center = params.center,
        twist = params.twist,
        slices = params.slices,
        scale = params.scale,
        convexity = params.convexity,
        frag = params.frag,
    }
    return self
end

---@param angle? number
---@param convexity? number
---@param frag? SCAD.FragOptions
---@return SCAD.Node
function Node:rotate_extrude(angle, convexity, frag)
    if angle ~= nil then c_num(angle, 1, 'rotate_extrude') end
    if convexity ~= nil then c_num(convexity, 2, 'rotate_extrude') end
    if frag ~= nil then c_frag(frag, 3, 'rotate_extrude') end

    self:addTransform { op = 'rotate_extrude', angle = angle, convexity = convexity, frag = frag }
    return self
end

---r-branch of offset
---@param r number offset radius
---@return SCAD.Node
function Node:offsetR(r)
    c_num(r, 1, 'offsetR')

    self:addTransform { op = 'offset', r = r }
    return self
end

---delta-branch of offset
---@param delta number offset distance
---@param chamfer? boolean enable chamfer
---@return SCAD.Node
function Node:offsetD(delta, chamfer)
    c_num(delta, 1, 'offsetD')
    if chamfer ~= nil then c_bool(chamfer, 2, 'offsetD') end

    self:addTransform { op = 'offset', delta = delta, chamfer = chamfer }
    return self
end

---@param cut? boolean
---@return SCAD.Node
function Node:projection(cut)
    if cut ~= nil then c_bool(cut, 1, 'projection') end

    self:addTransform { op = 'projection', cut = cut }
    return self
end

---[Debug] Add OpenSCAD debug modifier `#` (highlight, excluded from CSG)
---@return SCAD.Node
function Node:debug()
    self:addTransform { op = 'debug' }
    return self
end

---[Debug] Add OpenSCAD background modifier `%` (grayed out, excluded from CSG)
---@return SCAD.Node
function Node:background()
    self:addTransform { op = 'background' }
    return self
end

---[Debug] Add OpenSCAD root modifier `!` (show this subtree only)
---@return SCAD.Node
function Node:root()
    self:addTransform { op = 'root' }
    return self
end

---[Debug] Add OpenSCAD disable modifier `*` (hide this subtree)
---@return SCAD.Node
function Node:disable()
    self:addTransform { op = 'disable' }
    return self
end

--------------------------------------------------------------
---Node operations EXTRA

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
    c_pint(count, 1, 'array')
    c_num(dx, 2, 'array')
    if dy ~= nil then
        c_num(dy, 3, 'array')
        if dz ~= nil then c_num(dz, 4, 'array') end
    end

    self:addTransform { op = 'array', count = count, step = { dx or 0, dy or 0, dz or 0 } }
    return self
end

---[Extra] Rotate a node around an axis to create a circular array
---@param count number copy count (including the original)
---@param angle number rotation step per copy (degrees)
---@param ax? number axis vector x
---@param ay? number axis vector y
---@param az? number axis vector z
---@return SCAD.Node
function Node:rotate_array(count, angle, ax, ay, az)
    c_pint(count, 1, 'rotate_array')
    c_num(angle, 2, 'rotate_array')
    if ax ~= nil then
        c_num(ax, 3, 'rotate_array')
        c_num(ay, 4, 'rotate_array')
        c_num(az, 5, 'rotate_array')
    end

    self:addTransform { op = 'rotate_array', count = count, angle = angle, axis = ax and { ax, ay, az } }
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

local function export_nodes(...)
    local buffer = { ... }

    for i = 1, #buffer do
        if type(buffer[i]) == 'table' and buffer[i].__index == Node then
            buffer[i] = buffer[i]:export()
        elseif type(buffer[i]) ~= 'string' then
            error("preview/export: expected SCAD.Node object or scad script string, got " .. type(buffer[i]))
        end
    end
    return buffer
end

---Preview in openscad
---@vararg SCAD.Node | string
function SCAD.preview(...)
    local code = concat(export_nodes(...), "\n\n")
    io.open('_preview.scad', 'w'):write(code):close()
    os.execute('"openscad" "_preview.scad"')
end

---Export to scad code string, or write to .scad file, or render to .stl file with openscad
---@overload fun(...: SCAD.Node | string): string
---@param path string *.scad or *.stl
---@vararg SCAD.Node | string
function SCAD.export(path, ...)
    if type(path) == 'table' then return concat(export_nodes(path, ...), "\n\n") end

    assert(type(path) == 'string', "export: expected string path, got " .. type(path))
    local code = concat(export_nodes(...), "\n\n")
    if path:match('%.scad$') then
        -- Write to .scad file
        io.open(path, 'w'):write(code):close()
    elseif path:match('%.stl$') then
        -- Render & write to .stl file with openscad
        local tmp = os.tmpname() .. '.stl'
        local p = io.popen(format('"openscad" - -o "%s" 2>/dev/null', tmp), 'w')
        assert(p, "export: failed to start process (openscad)")
        p:write(code)
        local ok = p:close()
        if ok then
            local src = assert(io.open(tmp, 'rb'))
            local data = src:read('a')
            src:close()
            io.open(path, 'wb'):write(data):close()
        end
        os.remove(tmp)
        assert(ok, "openscad render failed")
    else
        error("export: file extension must be .scad or .stl")
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

---Hint for IDE
if false then
    _G.union = SCAD.union
    _G.difference = SCAD.difference
    _G.intersection = SCAD.intersection
    _G.hull = SCAD.hull
    _G.minkowski = SCAD.minkowski
    _G.fill = SCAD.fill
    _G.render = SCAD.render

    _G.square = SCAD.square
    _G.circle = SCAD.circle
    _G.polygon = SCAD.polygon
    _G.text = SCAD.text
    _G.cube = SCAD.cube
    _G.sphere = SCAD.sphere
    _G.cylinder = SCAD.cylinder
    _G.polyhedron = SCAD.polyhedron
    _G.surface = SCAD.surface
    _G.import = SCAD.import

    _G.preview = SCAD.preview
    _G.export = SCAD.export
end

return SCAD
