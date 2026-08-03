# lua-scad

纯Lua程序化建模方案（转译到`.scad`，Lua层不作逻辑处理）

## 依赖

- Lua
- OpenSCAD（可选，用于渲染 `.stl`）

## 快速开始

```lua
-- model.lua
local scad = require("scad")
scad.install() -- 解压 API 到全局，后续可直接裸名调用，否则就得用 scad.cube() 等较长的格式（不过IDE会不知道能裸名调用，看不到函数签名）

local base = cube(10, 10, 5, true) -- 10x10x5长方体
local hole = cylinder(6, 4, true) -- R4通孔
local part = difference({ base, hole }) -- 挖！

render(part, "./out.scad") -- 生成脚本
render(part, "./out.stl")  -- 渲染 STL（需要控制台有openscad命令）
```

运行：

```bash
lua model.lua
```

## API 概览

做了一些简单封装，绝大多数情况下直接没有带名参数，更符合 Lua 编程习惯

具体的调用格式写了LuaLS语法注释，会自动弹出函数签名（需要IDE支持）

### 原语样例

- 2D
    - `square(size, center?)` / `square(w, l, center?)`
    - `circle(r, fn?)`
    - `polygon{points={{x1,y1},{x2,y2},...}, paths?={{},...}, convexity?=10}`
    - `text(str, size?, font?, halign?, valign?, spacing?, direction?, language?, script?)`
- 3D
    - `cube(size, center?)` / `cube(w, l, h, center?)`
    - `cylinder(h, r, center?, fn?)` / `cylinder(h, r1, r2, center?, fn?)`
    - `sphere(r, fn?)`
    - `polyhedron{points={{x1,y1,z1},{x2,y2,z2},...}, faces={{i1,i2,i3,...},...}, convexity?=10}`
    - `surface(file, center?, convexity?)`

### 变换和运算样例

```lua
local flying_cube=cube(5)
    :translate(1, 2, 3)
    :scale(2)
    :rotate(45)
    :mirror(0, 1, 0)
    :color(1, 0.5, 0)

local twisted_cuboid=square(10):linear_extrude{ h=20, twist=30, center=true }

local diff_ab=difference{ a, b } -- 其他操作如 union 等同理
```

### 输出

| 调用                        | 行为                                        |
| --------------------------- | ------------------------------------------- |
| `render(obj)`               | 生成并返回脚本字符串                        |
| `render(obj, "./out.scad")` | 生成并写入`.scad`文件                       |
| `render(obj, "./out.stl")`  | 调用 openscad 渲染并写入`.stl`文件          |
| `render(obj, true)`         | 打开 openscad 预览（从stdin输入，不存文件） |

### 特殊变量

- 细分度 `$fn`
    - 全局默认 `scad._fn = 64`，作用于 cylinder/sphere/circle
    - 部分原语方法支持用尾参覆盖：`sphere(5, 128)`
- 其他暂未实现

### 参数校验

所有 API 调用时会进行格式/类型/值域检查，尽早抛出错误避免复杂debug
