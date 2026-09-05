local dkjson = require("dkjson")

local energese = {}

-- Node types whose PGF shape declares a `heat_sink` anchor. Sources and
-- interactions have one but carry no dissipation in Odum's convention; `text`,
-- `box` and `ground` are plain TikZ shapes and have no such anchor at all, so
-- asking for one is a hard TeX error.
energese.HAS_HEAT_SINK = {
    producer = true, consumer = true, storage = true, transaction = true,
    gain = true, loop_limited = true, switch = true,
}

local function report_error(msg)
    if luatexbase and luatexbase.module_error then
        luatexbase.module_error("energese", msg)
    else
        error("\n[energese error] " .. msg .. "\n")
    end
end

function energese.parse_json(json_string)
    local data, pos, err = dkjson.decode(json_string, 1, nil)
    if err then
        report_error("Invalid JSON syntax: " .. tostring(err))
    end
    return data
end

-- Resolve a JSON path relative to the current directory first, then fall back
-- to the TeX search path so a document compiles from any working directory.
local function resolve_path(filepath)
    if io.open(filepath, "r") then return filepath end
    if kpse and kpse.find_file then
        local found = kpse.find_file(filepath, "tex")
        if found then return found end
        local base = filepath:match("([^/\\]+)$")
        if base then
            found = kpse.find_file(base, "tex")
            if found then return found end
        end
    end
    return nil
end

function energese.parse_json_file(filepath)
    local resolved = resolve_path(filepath)
    local f = resolved and io.open(resolved, "r")
    if not f then
        report_error("File not found: " .. filepath)
    end
    local content = f:read("*all")
    f:close()
    return energese.parse_json(content)
end

-- Pathways that carry energy forward through the hierarchy. Used for
-- reachability, for balance where both kinds count, and for the chain the
-- derived transformity below is measured along.
local FORWARD_FLOW = { energy = true, material = true }

-- ---------------------------------------------------------------------------
-- GSSK models
--
-- GSSK is the simulation kernel this notation is drawn for, and the point of
-- reading its files directly is that one file both simulates and draws: a
-- published figure is generated from the model that produced the results
-- beside it, and the two cannot drift. See docs/gssk-interop.md for the design
-- this implements.
--
-- The two formats converged independently -- GSSK's node vocabulary *is*
-- Odum's symbol set -- so this is a normalisation and not a translation. It
-- runs ahead of validation and rewrites the model in place.
--
-- Every rule below fills in what is absent rather than overwriting what is
-- present, so a native energese model passes through untouched even if the
-- detection is wrong. The one exception is the coordinate transform, which
-- would wreck a native model, and it fires only on coordinates that came out
-- of a `visual` object.
-- ---------------------------------------------------------------------------

-- GSSK's names for the symbols, where they differ. The rest -- storage,
-- source, producer, consumer, interaction, gain, loop_limited, switch -- are
-- spelled the same in both.
local GSSK_TYPE = {
    exchange = "transaction",
    misc_box = "box",
    -- A fixed input from outside the system is what Odum's source *is*. GSSK
    -- distinguishes it from `source` because the kernel integrates them
    -- differently; nothing in the drawing does.
    constant = "source",
}

-- What a pathway is *drawn* as, given how the kernel computes it. These are
-- orthogonal questions -- `logic` says how a flow is calculated, `type` says
-- what kind of flow it is -- so this is only a default, and an explicit
-- `visual.type` always wins. Everything GSSK computes is a flow of energy or
-- material unless the model says otherwise; nothing in `logic` implies money
-- or information.
local DRAW_FROM_LOGIC = setmetatable({}, { __index = function() return "energy" end })

-- Pixels of GSSK canvas per diagram unit. GSSK-DIA lays out on a screen, where
-- a symbol is drawn at something like 60 pixels and the canvas runs to a few
-- hundred; energese works in centimetres, where a symbol is about 1.1. Fifty
-- is the ratio that makes a typical editor layout come out at the spacing the
-- grid would have chosen. Override with metadata.energese.pixels_per_unit.
local GSSK_PIXELS_PER_UNIT = 50

local function energese_settings(model)
    local meta = model.metadata
    return (meta and meta.energese) or {}
end

-- A model is GSSK's if it spells an edge's ends the way GSSK does. That is the
-- reliable tell: `metadata.schema_version`, which the design sketch proposed to
-- detect on, is absent from what the editor actually writes -- its files carry
-- `config` and `boundaries` and no metadata at all.
function energese.is_gssk(model)
    if not model then return false end
    if model.metadata and model.metadata.schema_version then return true end
    if model.config ~= nil then return true end
    for _, edge in ipairs(model.edges or {}) do
        if edge.origin ~= nil or edge.target ~= nil then return true end
    end
    for _, node in ipairs(model.nodes or {}) do
        if node.visual ~= nil then return true end
    end
    return false
end

-- Quality ordering, derived rather than measured.
--
-- Energese places columns by transformity and GSSK has no such field, so where
-- the model does not supply one it is derived: the longest chain of energy and
-- material pathways from a source to this node. That reproduces the ordering
-- Odum's convention expresses -- quality rises along the chain -- without
-- claiming a transformity the model does not contain, which is why the values
-- are 1, 2, 3 and not plausible-looking emergy figures. It orders the diagram.
-- It is not an emergy calculation.
local function derive_transformity(model)
    local depth, inflow = {}, {}
    for _, node in ipairs(model.nodes) do
        depth[node.id] = 1
        inflow[node.id] = {}
    end
    for _, edge in ipairs(model.edges) do
        local from, to = edge.from or edge.origin, edge.to or edge.target
        if FORWARD_FLOW[edge.type or "energy"] and inflow[to] and from then
            table.insert(inflow[to], from)
        end
    end
    -- Relax until settled. A feedback loop would otherwise spin, so the pass
    -- count is bounded by the number of nodes -- the length of the longest
    -- possible chain without one.
    for _ = 1, #model.nodes do
        local changed = false
        for _, node in ipairs(model.nodes) do
            for _, from in ipairs(inflow[node.id]) do
                if depth[from] and depth[from] + 1 > depth[node.id] then
                    depth[node.id] = depth[from] + 1
                    changed = true
                end
            end
        end
        if not changed then break end
    end
    return depth
end

function energese.normalise(model)
    if not (model and model.nodes and model.edges) then return model end
    if not energese.is_gssk(model) then return model end

    local settings = energese_settings(model)
    local scale = 1 / (settings.pixels_per_unit or GSSK_PIXELS_PER_UNIT)
    -- The author placed these nodes in an editor, so the placement is part of
    -- what was drawn and is honoured. `layout = "auto"` throws it away and lets
    -- the transformity grid place them instead.
    local keep_layout = settings.layout ~= "auto"

    -- Dissipation is stated twice over, once in each language. GSSK models the
    -- heat sink as a node with pathways into it; energese knows that a storage
    -- dissipates and draws the pathway and the ground itself. Carry both and
    -- the diagram grows a second ground and a duplicate dissipation pathway,
    -- so GSSK's spelling is dropped in favour of energese's.
    local is_sink = {}
    for _, node in ipairs(model.nodes) do
        if node.type == "sink" then is_sink[node.id] = true end
    end

    local nodes = {}
    for _, node in ipairs(model.nodes) do
        if not is_sink[node.id] then
            local visual = node.visual
            if type(visual) == "table" then
                for key, value in pairs(visual) do
                    -- Coordinates are converted below, not copied.
                    if key ~= "x" and key ~= "y" and node[key] == nil then
                        node[key] = value
                    end
                end
                if keep_layout and visual.x and visual.y then
                    node.gssk_x, node.gssk_y = visual.x, visual.y
                end
            end
            node.type = GSSK_TYPE[node.type] or node.type
            if node.label == nil then node.label = node.id end
            nodes[#nodes + 1] = node
        end
    end
    model.nodes = nodes

    local edges = {}
    for _, edge in ipairs(model.edges) do
        edge.from = edge.from or edge.origin
        edge.to = edge.to or edge.target
        local visual = edge.visual
        if type(visual) == "table" then
            if edge.waypoints == nil and visual.points and #visual.points > 0 then
                edge.waypoints = visual.points
            end
            if edge.volume == nil and visual.volume then edge.volume = visual.volume end
            for key, value in pairs(visual) do
                if edge[key] == nil and key ~= "points" then edge[key] = value end
            end
        end
        edge.type = edge.type or DRAW_FROM_LOGIC[edge.logic]
        -- A pathway into a sink said the same thing energese says by drawing a
        -- heat sink under the symbol, so it goes with the sink node.
        if not is_sink[edge.to] then edges[#edges + 1] = edge end
    end
    model.edges = edges

    local supplied = settings.transformity or {}
    local derived = derive_transformity(model)
    for _, node in ipairs(model.nodes) do
        if node.Tr == nil then node.Tr = supplied[node.id] or derived[node.id] end
    end

    -- Coordinates last, once the node list is settled: GSSK's canvas is in
    -- pixels with y increasing downwards, energese's diagram is in centimetres
    -- with y increasing upwards. Copied across unconverted, a three-node model
    -- comes out nearly four metres wide -- past the point where TeX abandons a
    -- dimension -- and upside down, with dissipation above the source it came
    -- from, which inverts the one convention the notation is most emphatic
    -- about.
    local top
    for _, node in ipairs(model.nodes) do
        if node.gssk_y and (not top or node.gssk_y < top) then top = node.gssk_y end
    end
    for _, node in ipairs(model.nodes) do
        if node.gssk_x and node.x == nil then node.x = node.gssk_x * scale end
        if node.gssk_y and node.y == nil then node.y = (top - node.gssk_y) * scale end
        node.gssk_x, node.gssk_y = nil, nil
    end

    return model
end

function energese.validate_node(node)
    if not node.id then return false, "Node missing required field 'id'" end
    if not node.type then return false, "Node '" .. node.id .. "' missing required field 'type'" end

    -- An exchange marker transforms nothing, so it has no transformity.
    if node.seller and node.buyer then return true end

    if node.type ~= "text" and node.type ~= "box" and node.type ~= "ground" then
        if not node.Tr then return false, "Node '" .. node.id .. "' missing required field 'Tr' (Transformity)" end
        if not node.label then return false, "Node '" .. node.id .. "' missing required field 'label'" end
    end

    local valid_types = {
        source = true, producer = true, consumer = true,
        storage = true, interaction = true, transaction = true,
        gain = true, loop_limited = true, switch = true,
        text = true, box = true, ground = true
    }
    if not valid_types[node.type] then
        return false, "Node '" .. node.id .. "' has invalid type '" .. node.type .. "'"
    end

    return true
end

function energese.validate_edge(edge, node_ids)
    if not edge.from then return false, "Edge missing 'from'" end
    if not edge.to then return false, "Edge missing 'to'" end
    if not edge.type then return false, "Edge missing 'type'" end

    if not node_ids[edge.from] then
        return false, "Edge references undefined node '" .. edge.from .. "'"
    end
    if not node_ids[edge.to] then
        return false, "Edge references undefined node '" .. edge.to .. "'"
    end

    local valid_types = {
        energy = true, money_feedback = true, information = true, material = true
    }
    if not valid_types[edge.type] then
        return false, "Edge has invalid type '" .. edge.type .. "'"
    end

    return true
end

function energese.validate_schema(data)
    if not data then return false, "No data provided" end
    if not data.nodes then return false, "Missing 'nodes' array" end
    if not data.edges then return false, "Missing 'edges' array" end

    local node_ids = {}
    for _, node in ipairs(data.nodes) do
        local ok, err = energese.validate_node(node)
        if not ok then return false, err end
        if node_ids[node.id] then
            return false, "Duplicate node ID: " .. node.id
        end
        node_ids[node.id] = true
    end

    for _, edge in ipairs(data.edges) do
        local ok, err = energese.validate_edge(edge, node_ids)
        if not ok then return false, err end
    end

    for _, node in ipairs(data.nodes) do
        if node.seller or node.buyer then
            if not (node.seller and node.buyer) then
                return false, "Exchange '" .. node.id
                    .. "' needs both 'seller' and 'buyer'"
            end
            for _, role in ipairs({ "seller", "buyer" }) do
                if not node_ids[node[role]] then
                    return false, "Exchange '" .. node.id .. "' names "
                        .. role .. " '" .. node[role] .. "', which is not a node"
                end
            end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Energetic checks
--
-- Odum's complaint was that scholars build mathematical models which are
-- energetically invalid, and the Energy Systems Language was meant to help
-- them avoid it. Drawing tools cannot: they render whatever is drawn. These
-- checks are what a renderer *can* say about a model without leaving the
-- diagram -- topological statements about quality, direction and connectivity.
--
-- Deliberately out of scope:
--   * Conservation of energy. Balancing inflow against outflow and dissipation
--     needs quantities, and `volume` is a line width, not a flux. That belongs
--     with the simulation kernel (docs/gssk-interop.md), not here.
--   * Anything to do with emergy. There is no agreed algorithm to validate
--     against, so a check would assert a standard that does not exist.
--
-- Findings are warnings by default: a diagram that breaks a convention is
-- usually still worth drawing, and the author is better placed to judge.
-- metadata.strict makes them errors.
-- ---------------------------------------------------------------------------


-- Quality must not fall along an `energy` pathway: that is the transformation
-- hierarchy. `material` is deliberately excluded -- degraded material moving to
-- a waste or decomposition store genuinely falls in transformity, and that is
-- what decomposition is. Feedback (money, information) runs downhill by design.
local QUALITY_RISES = { energy = true }

-- ---------------------------------------------------------------------------
-- Exchanges
--
-- Odum's exchange is a single transaction with two coupled sides: goods or
-- energy pass one way, money the other, and the diamond is where they meet.
-- Drawing the two as independent pathways that happen to pass near a diamond
-- looks similar and says something weaker -- that a payment and a delivery both
-- occurred, not that they are the same transaction.
--
-- A `transaction` node naming a `seller` and a `buyer` therefore expands into
-- the four half-pathways that make up the exchange. Because expansion happens
-- before layout, the legs are routed, validated and drawn like any other
-- pathway; nothing downstream needs to know they were synthesised.
--
--   seller --energy--> diamond --energy--> buyer
--   buyer  --money---> diamond --money---> seller
-- ---------------------------------------------------------------------------
function energese.expand_exchanges(data)
    local added = {}
    for _, node in ipairs(data.nodes) do
        if node.seller and node.buyer then
            -- The two sides of one transaction must read as a couple, so they
            -- run tightly parallel with the money just outside the goods.
            --
            -- The bend directions are not a typo. `bend left' is relative to
            -- direction of travel, and money runs opposite to goods, so
            -- matching `bend left' on both would bow them to opposite sides and
            -- open a lens between them. `bend right' on the return puts both
            -- bows on the same side; the larger angle sets the gap.
            local GOODS, MONEY = "bend left=8", "bend right=15"

            -- Goods run seller to buyer as ONE continuous pathway, and the
            -- diamond rides it as a marker at the midpoint, rotated to the
            -- flow. It is not a component the pathway enters: Odum draws the
            -- lines cutting straight through the glyph, which is exactly what
            -- every other symbol forbids. An exchange annotates a coupling, it
            -- does not transform anything -- so there is nothing to flow into,
            -- and nothing to give it a transformity of its own.
            added[#added + 1] = {
                from = node.seller, to = node.buyer, type = "energy",
                label = node.energy_label, options = GOODS, exchange_leg = true,
                marker = node.type or "transaction",
                marker_magnitude = node.magnitude or 0.62,
            }
            added[#added + 1] = {
                from = node.buyer, to = node.seller, type = "money_feedback",
                label = node.money_label, options = MONEY, exchange_leg = true,
            }
        end
    end
    for _, edge in ipairs(added) do
        data.edges[#data.edges + 1] = edge
    end
    return #added
end

function energese.check_energetics(data)
    local findings = {}
    local function report(fmt, ...)
        findings[#findings + 1] = string.format(fmt, ...)
    end

    local node_map = {}
    for _, node in ipairs(data.nodes) do node_map[node.id] = node end

    local out_degree, in_degree = {}, {}
    for _, edge in ipairs(data.edges) do
        if FORWARD_FLOW[edge.type] then
            out_degree[edge.from] = (out_degree[edge.from] or 0) + 1
            in_degree[edge.to] = (in_degree[edge.to] or 0) + 1
        end
    end

    for _, edge in ipairs(data.edges) do
        local from, to = node_map[edge.from], node_map[edge.to]
        if from and to then
            -- 1. Energy quality must not fall along a forward pathway.
            if QUALITY_RISES[edge.type] and from.Tr and to.Tr and to.Tr < from.Tr then
                report("pathway '%s' -> '%s' runs from transformity %s to %s: "
                    .. "energy quality falls along a forward pathway",
                    edge.from, edge.to, tostring(from.Tr), tostring(to.Tr))
            end
            -- 2. Direction rules for the two terminal types.
            if FORWARD_FLOW[edge.type] and to.type == "source" then
                report("pathway '%s' -> '%s' flows into a source; sources are "
                    .. "origins and take no energy inflow", edge.from, edge.to)
            end
            if from.type == "ground" then
                report("pathway '%s' -> '%s' leaves a ground; dissipated energy "
                    .. "does not return to the system", edge.from, edge.to)
            end
        end
    end

    -- 3. Every component should be reachable from a source.
    local reachable, frontier = {}, {}
    for _, node in ipairs(data.nodes) do
        if node.type == "source" then
            reachable[node.id] = true
            frontier[#frontier + 1] = node.id
        end
    end
    while #frontier > 0 do
        local id = table.remove(frontier)
        for _, edge in ipairs(data.edges) do
            if FORWARD_FLOW[edge.type] and edge.from == id and not reachable[edge.to] then
                reachable[edge.to] = true
                frontier[#frontier + 1] = edge.to
            end
        end
    end
    for _, node in ipairs(data.nodes) do
        local annotation = node.type == "text" or node.type == "box"
                           or node.type == "ground" or (node.seller and node.buyer)
        if not annotation and not reachable[node.id] then
            report("'%s' is not reachable from any source: it receives no "
                .. "energy", node.id)
        end
    end

    -- 4. Energy arriving somewhere must leave, as outflow or as dissipation.
    for _, node in ipairs(data.nodes) do
        if (in_degree[node.id] or 0) > 0 and (out_degree[node.id] or 0) == 0
            and not energese.HAS_HEAT_SINK[node.type]
            and node.type ~= "text" and node.type ~= "box"
            and node.type ~= "ground" and not (node.seller and node.buyer) then
            report("'%s' receives energy but neither passes it on nor "
                .. "dissipates it", node.id)
        end
    end

    return findings
end

-- ---------------------------------------------------------------------------
-- Estimated extents
--
-- How much room a symbol takes, in diagram units, without asking TeX. Lua does
-- not know what TeX will typeset, so these are estimates -- from
-- \energeseunit, the shape's own proportions and a per-character label width --
-- and an over-estimate is the safe direction in every use: it spaces symbols
-- further apart, routes pathways wider, and boxes labels more generously than
-- strictly needed. A node whose estimate is wrong overrides it with
-- `clearance_w` / `clearance_h`. Measuring exactly would mean round-tripping
-- the real dimensions through the .aux file, which is the obvious next step if
-- the estimate proves too coarse.
-- ---------------------------------------------------------------------------

-- Must track \energeseunit in energese.sty.
energese.UNIT_CM = 1.1

-- Half-extents of a bare symbol, in units of the grid cell.
local HALF_EXTENT = {
    source      = {0.508, 0.508}, storage      = {0.500, 0.500},
    producer    = {0.863, 0.500}, consumer     = {0.573, 0.653},
    transaction = {0.551, 0.250}, interaction  = {0.533, 0.283},
    gain        = {0.268, 0.291}, loop_limited = {0.436, 0.428},
    switch      = {0.468, 0.452}, box          = {0.450, 0.300},
    text        = {0.400, 0.200}, ground       = {0.200, 0.150},
}

-- Estimated height of a displaced label, in diagram units.
local LABEL_HEIGHT = 0.30

-- Rough width of a label character, in cm. Calibrated for \energeselabelfont
-- (\sffamily\footnotesize); change it with that font. Used to decide whether a
-- label fits its cell and to size the obstacle a displaced one presents, so an
-- over-estimate is the safe direction.
local CM_PER_CHAR = 0.14

-- What fraction of a symbol's width its label may occupy -- the `fx` each
-- shape declares to \energese@fit in energese-shapes.tex, and the reason a
-- labelled symbol is wider than its label. \energese@fit sets the outline
-- width to label-width / fx, so dividing here reproduces exactly what TeX will
-- do. Taking the label's own width as the symbol's, as this did, understated
-- a labelled exchange diamond by a factor of two, and the diamond attached to
-- a consumer overlapped it.
--
-- Source and storage do not go through \energese@fit: their outline is the
-- circle circumscribing the label box, so the width depends on the label's
-- height too. The figures below are the wide-label limit -- 1 for a circle,
-- 1/1.22 for the tank, whose peaked top adds 0.82 of the label's width.
local TEXT_FRACTION = {
    producer = 0.710, consumer = 1.0,   transaction  = 0.5,
    interaction = 0.708, gain = 0.45,   loop_limited = 0.740,
    switch = 0.715,   source = 1.0,     storage      = 0.82,
}

local function label_half_width(label)
    if not label or label == "" then return 0 end
    local longest = 0
    for line in tostring(label):gmatch("[^\\]+") do
        local n = #(line:gsub("%s+$", ""))
        if n > longest then longest = n end
    end
    return 0.5 * longest * CM_PER_CHAR
end

-- The half-width and half-height a node occupies, label included. One
-- definition, because a symbol that is one size to the router and another to
-- the layout would be routed around a box it does not fill.
function energese.half_extent(node)
    local half = HALF_EXTENT[node.type] or {0.4, 0.3}
    local mag = node.magnitude or 1.0
    local text = label_half_width(node.label) / (TEXT_FRACTION[node.type] or 1.0)
    local hw = node.clearance_w
        or math.max(half[1] * energese.UNIT_CM, text) * mag
    local hh = node.clearance_h or (half[2] * energese.UNIT_CM * mag)
    return hw, hh
end

-- ---------------------------------------------------------------------------
-- The system window
--
-- The frame declares what the model treats as inside the system, so what it
-- encloses is a claim and not a matter of taste. Two rules settle it.
--
-- What is inside: everything except the sources, which is Odum's convention --
-- a source is by definition an input from outside the system, and he draws the
-- circles beyond the frame. A node overrides that with `inside`, either way.
--
-- Where the frame falls: a fixed margin outside the *extents* of what is
-- inside, labels and attached modifiers included, not outside their centres.
-- Measuring centres and padding by half a column, as this did, made the margin
-- a function of the widest symbol in the diagram: the frame crowded a wide
-- producer and left a hand's width of dead space beside a small storage. The
-- margin scales with the grid, so a coarser \energeseunit gets a
-- proportionally wider one, and `boundary_margin` overrides it in diagram
-- units.
-- ---------------------------------------------------------------------------

energese.BOUNDARY_MARGIN = 0.45

function energese.inside_system(node)
    if node.inside ~= nil then return node.inside end
    if node.seller and node.buyer then return false end
    return node.type ~= "source"
end

-- `floor` is extra room below, for the dissipation bundle: the funnel converges
-- inside the window and only its trunk crosses the frame, so the frame has to
-- be far enough under the components for the tributaries to turn in. Fitted to
-- the symbols alone, the frame's underside cut straight across the funnel and
-- the tributaries sagged out of the window and back in.
--
-- Nil when nothing is inside: a frame around no components would be a claim
-- about a system the model does not describe.
function energese.system_bounds(nodes, boxes, margin, floor)
    local box_of = {}
    for _, box in ipairs(boxes) do box_of[box.id] = box end

    local x0, x1, y0, y1
    for _, node in ipairs(nodes) do
        local box = box_of[node.id]
        if box and energese.inside_system(node) then
            local nx0, nx1 = box.x - box.hw, box.x + box.hw
            local ny0, ny1 = box.y - box.hh, box.y + box.hh
            x0 = math.min(x0 or nx0, nx0)
            x1 = math.max(x1 or nx1, nx1)
            y0 = math.min(y0 or ny0, ny0)
            y1 = math.max(y1 or ny1, ny1)
        end
    end
    if not x0 then return nil end
    return { x_min = x0 - margin, x_max = x1 + margin,
             y_min = y0 - margin - (floor or 0), y_max = y1 + margin }
end

-- ---------------------------------------------------------------------------
-- Semantic grouping
--
-- An interaction is not an independent component. It is the place where two
-- flows combine on their way into the thing they drive, and Odum draws it
-- against that thing. A standalone transaction is the same kind of annotation
-- on a pair of parties. Laid out by transformity like every other node, both
-- take a column of their own and drift away from the component they modify,
-- and the reader loses which one that is.
--
-- They are therefore children in a compound graph: their coordinates are
-- locked to a parent's by a fixed offset, and they take no part in the column
-- or row algorithms -- neither claiming a column of their own nor pushing a
-- sibling out of a row.
--
-- The offset follows the flow. A child that feeds its parent sits upstream of
-- it, a child fed by its parent sits downstream, because a modifier drawn on
-- the wrong side reverses the direction its pathway reads in. Half a column is
-- the default gap: close enough to read as attached, wide enough that the two
-- outlines do not touch at any magnitude the grid allows.
--
-- The model has the last word: an explicit `x` or `y` is never overridden,
-- `parent` names the component to attach to, `parent_dx`/`parent_dy` set the
-- offset in diagram units, and `attach=false` opts out entirely.
-- ---------------------------------------------------------------------------

energese.MODIFIER_TYPES = { interaction = true, transaction = true }

-- Which component a modifier belongs against when it does not say. A consumer
-- first, because that is what Odum's interactions overwhelmingly drive; then
-- whatever else it exchanges energy with, sources last -- an interaction fed
-- by the sun belongs against what it drives, not against the sun.
-- Clear air between an attached modifier and its parent. Matches the gap the
-- router keeps when it steps a pathway around a symbol, so a flow can still
-- pass between the two if it has to.
local ATTACH_CLEARANCE = 0.34

local PARENT_RANK = {
    consumer = 5, producer = 4, storage = 3,
    loop_limited = 3, gain = 3, switch = 3, source = 1,
}

function energese.attach_modifiers(nodes, edges, col_spacing)
    local node_map, order = {}, {}
    for i, node in ipairs(nodes) do
        node_map[node.id] = node
        order[node.id] = i
    end

    local attached = {}
    for _, node in ipairs(nodes) do
        if energese.MODIFIER_TYPES[node.type]
            and not (node.seller and node.buyer)
            and node.attach ~= false
            and node.x == nil and node.y == nil then

            local best, best_rank, best_order, feeds_parent
            for _, edge in ipairs(edges) do
                if FORWARD_FLOW[edge.type] then
                    local other, feeds
                    if edge.from == node.id then
                        other, feeds = edge.to, true
                    elseif edge.to == node.id then
                        other, feeds = edge.from, false
                    end
                    local cand = other and node_map[other]
                    -- One modifier cannot anchor another: the pair would have
                    -- nothing to be positioned against.
                    if cand and not energese.MODIFIER_TYPES[cand.type] then
                        local rank = (node.parent == cand.id) and math.huge
                                     or (PARENT_RANK[cand.type] or 0)
                        if rank > (best_rank or -1)
                            or (rank == best_rank and order[cand.id] < best_order) then
                            best, best_rank, best_order = cand, rank, order[cand.id]
                            feeds_parent = feeds
                        end
                    end
                end
            end

            -- A named parent with no pathway between the two is still a
            -- parent: the model said so. An interaction with nothing to drive
            -- is drawn upstream, which is where one waiting for its outflow
            -- belongs.
            if not best and node.parent and node_map[node.parent] then
                best, feeds_parent = node_map[node.parent], true
            end

            if best then
                -- Half a column, but never less than the two symbols need to
                -- stand clear of each other: a labelled exchange diamond is
                -- wide, and a fixed fraction of the column buried its left
                -- vertex inside the consumer it was attached to.
                local child_hw = energese.half_extent(node)
                local parent_hw = energese.half_extent(best)
                local gap = math.max(0.55 * col_spacing,
                                     child_hw + parent_hw + ATTACH_CLEARANCE)
                attached[node.id] = {
                    parent = best.id,
                    dx = node.parent_dx or (feeds_parent and -gap or gap),
                    dy = node.parent_dy or 0,
                }
            end
        end
    end
    return attached
end

-- Resolve the locked coordinates, parents before children, so a modifier
-- attached to a component that is itself attached still lands. A cycle -- two
-- modifiers naming each other through `parent` -- stops rather than spins, and
-- leaves the nodes where the column algorithm put them.
function energese.place_attached(attached, x_coords, y_coords)
    local pending = {}
    for id in pairs(attached) do pending[#pending + 1] = id end
    table.sort(pending)
    for _ = 1, #pending do
        local moved = false
        for _, id in ipairs(pending) do
            local a = attached[id]
            if not a.placed and not (attached[a.parent] and not attached[a.parent].placed) then
                x_coords[id] = (x_coords[a.parent] or 0) + a.dx
                y_coords[id] = (y_coords[a.parent] or 0) + a.dy
                a.placed = true
                moved = true
            end
        end
        if not moved then break end
    end
end

-- Attached modifiers are skipped: a column exists because a transformity is
-- occupied, and a node locked to its parent occupies none.
function energese.calculate_transformity_columns(nodes, attached)
    local tr_values = {}
    for _, node in ipairs(nodes) do
        if not (attached and attached[node.id]) then
            table.insert(tr_values, node.Tr)
        end
    end

    table.sort(tr_values)
    local unique_tr = {}
    local last_tr = nil
    for _, tr in ipairs(tr_values) do
        if tr ~= last_tr then
            table.insert(unique_tr, tr)
            last_tr = tr
        end
    end

    local tr_map = {}
    for i, tr in ipairs(unique_tr) do
        tr_map[tr] = i
    end

    return tr_map
end

function energese.calculate_x_coordinates(nodes, tr_map, spacing)
    local x_coords = {}
    for _, node in ipairs(nodes) do
        if node.x then
            x_coords[node.id] = node.x
        else
            local col = tr_map[node.Tr] or 0
            x_coords[node.id] = col * spacing
        end
    end
    return x_coords
end

-- The spine is the *energy* transformation chain. Material pathways are
-- excluded: a flow of degraded material to a waste or decomposition store is a
-- side branch, and counting it let such a store capture the spine and sit on
-- the axis when it belongs below it.
function energese.build_directed_graph(nodes, edges, types)
    types = types or { energy = true }
    local adj = {}
    local node_map = {}
    for _, node in ipairs(nodes) do
        adj[node.id] = {}
        node_map[node.id] = node
    end
    for _, edge in ipairs(edges) do
        if types[edge.type] then
            if adj[edge.from] then
                table.insert(adj[edge.from], edge.to)
            end
        end
    end
    return adj, node_map
end

function energese.find_longest_path(nodes, edges, types)
    types = types or { energy = true }
    local adj, node_map = energese.build_directed_graph(nodes, edges, types)

    local is_target = {}
    for _, edge in ipairs(edges) do
        if types[edge.type] then
            is_target[edge.to] = true
        end
    end

    local start_nodes = {}
    for _, node in ipairs(nodes) do
        if not is_target[node.id] then
            table.insert(start_nodes, node.id)
        end
    end

    local best_path = {}
    local max_len = -1
    local max_tr_sum = -1

    local function dfs(u, path, current_tr_sum)
        local new_path = {}
        for i, v in ipairs(path) do new_path[i] = v end
        table.insert(new_path, u)
        current_tr_sum = current_tr_sum + (node_map[u].Tr or 0)

        local is_leaf = true
        if adj[u] then
            for _, v in ipairs(adj[u]) do
                local visited = false
                for _, p in ipairs(new_path) do if p == v then visited = true break end end
                if not visited then
                    is_leaf = false
                    dfs(v, new_path, current_tr_sum)
                end
            end
        end

        if is_leaf then
            if #new_path > max_len then
                max_len = #new_path
                max_tr_sum = current_tr_sum
                best_path = new_path
            elseif #new_path == max_len then
                if current_tr_sum > max_tr_sum then
                    max_tr_sum = current_tr_sum
                    best_path = new_path
                end
            end
        end
    end

    for _, start in ipairs(start_nodes) do
        dfs(start, {}, 0)
    end

    return best_path
end

-- Vertical placement.
--
-- The horizontal axis is ordered by transformity; nothing in Odum's language
-- assigns a magnitude to height, so the vertical axis carries no quantity.
-- It is not arbitrary either: Odum's own figures place things vertically by
-- their role relative to the main transformation chain, and that role can be
-- derived from the graph rather than fanned out by accident.
--
-- The rule is the horizontal ordering applied locally: vertical distance from
-- the chain tracks transformity relative to the chain, not any absolute
-- quantity. So the energy hierarchy runs bottom-left to top-right.
--
--   on the spine   the longest chain of forward pathways
--   above it       higher transformity than the chain node it connects to:
--                  a high-quality input, a controller, or a higher-quality
--                  product. This is why Fuels and Minerals enters Odum's
--                  aggregated economy from the top rather than the side, and
--                  the engine reproduces that placement unprompted.
--   below it       degraded output: it receives from the chain at equal or
--                  lower transformity. Dissipation, decomposition, waste.
--
-- Power is deliberately NOT the vertical variable. Along a transformation
-- chain empower is roughly conserved and available power falls as transformity
-- rises, so power is already determined by horizontal position; encoding it
-- again vertically would be redundant where the two agree and contradictory
-- where they do not.
--
-- `layer_hint` names the layer explicitly and wins over the derived one;
-- `y_gravity` nudges; an explicit `y` overrides the lot.
local function derive_layer(node, main_chain, edges, node_map)
    -- The chain node this one connects to, and which way the pathway runs.
    local neighbour, receives = nil, false
    for _, edge in ipairs(edges) do
        if FORWARD_FLOW[edge.type] then
            if edge.from == node.id and main_chain[edge.to] then
                neighbour = neighbour or node_map[edge.to]
            elseif edge.to == node.id and main_chain[edge.from] then
                neighbour = neighbour or node_map[edge.from]
                receives = true
            end
        end
    end
    if not neighbour or not node.Tr or not neighbour.Tr then return nil end

    -- The vertical axis is the same quality ordering as the horizontal, applied
    -- relative to the chain rather than absolutely. Higher quality than the
    -- chain sits above it -- a high-transformity input, a controller, or a
    -- higher-quality product. Degraded output sits below.
    if receives and node.Tr <= neighbour.Tr then return "below" end
    if node.Tr >= neighbour.Tr then return "above" end

    -- A lower-quality input is unattested in Odum's figures; make no claim.
    return nil
end

function energese.calculate_vertical_positions(nodes, edges, tr_map, row_spacing, attached)
    -- Energy first; fall back to counting material as well for a model that
    -- has no energy pathways at all, which would otherwise have no spine.
    local main_chain_list = energese.find_longest_path(nodes, edges)
    if #main_chain_list < 2 then
        main_chain_list = energese.find_longest_path(nodes, edges,
            { energy = true, material = true })
    end
    local main_chain = {}
    for _, id in ipairs(main_chain_list) do main_chain[id] = true end

    local node_map = {}
    for _, node in ipairs(nodes) do node_map[node.id] = node end

    local y_coords = {}

    local order = {}
    local cols = {}
    for index, node in ipairs(nodes) do
        order[node.id] = index
        -- An attached modifier is placed against its parent afterwards. It is
        -- still in the graph above -- the spine runs through interactions --
        -- but it must not take a row here, or it would push the sibling that
        -- belongs in that row out of it.
        if not (attached and attached[node.id]) then
            local c = tr_map[node.Tr] or 0
            cols[c] = cols[c] or {}
            table.insert(cols[c], node)
        end
    end

    for _, nodes_in_col in pairs(cols) do
        -- Declaration order, not alphabetical. Sorting by id made the layout
        -- depend on what nodes are called, so renaming one moved others.
        table.sort(nodes_in_col, function(a, b) return order[a.id] < order[b.id] end)

        local main_node, above, below, unplaced = nil, {}, {}, {}
        for _, node in ipairs(nodes_in_col) do
            -- An explicit hint wins outright, including over spine membership:
            -- a decomposition store can sit on the longest path and still
            -- belong below it.
            local hint = node.layer_hint
            if hint == "control" then
                above[#above + 1] = node
            elseif hint == "decomposition" then
                below[#below + 1] = node
            elseif main_chain[node.id] and not main_node then
                main_node = node
            else
                local layer = derive_layer(node, main_chain, edges, node_map)
                if layer == "above" then
                    above[#above + 1] = node
                elseif layer == "below" then
                    below[#below + 1] = node
                else
                    unplaced[#unplaced + 1] = node
                end
            end
        end

        if main_node then y_coords[main_node.id] = 0 end
        for i, node in ipairs(above) do
            y_coords[node.id] = i * row_spacing
        end
        for i, node in ipairs(below) do
            y_coords[node.id] = -i * row_spacing
        end
        -- Whatever the rules cannot classify fans around the spine, starting
        -- beyond the rows already taken so it never lands on a placed node.
        local free = math.max(#above, #below)
        for i, node in ipairs(unplaced) do
            local step = free + math.ceil(i / 2)
            local sign = (i % 2 == 1) and 1 or -1
            y_coords[node.id] = sign * step * row_spacing
        end
    end

    for _, node in ipairs(nodes) do
        if node.y then
            y_coords[node.id] = node.y
        elseif node.y_gravity then
            y_coords[node.id] = (y_coords[node.id] or 0) + node.y_gravity
        end
    end

    return y_coords
end

-- ---------------------------------------------------------------------------
-- Pathway routing
--
-- A pathway must go *around* an intervening symbol, not over or under it: in
-- ESL a line meeting a symbol means flow entering that symbol, so a pathway
-- drawn across one asserts a connection the model does not contain. Hiding the
-- crossing on a lower layer does not fix that -- it still reads as flow into
-- the symbol -- so the pathway itself has to move.
--
-- Priorities, in order: shortest path; no crossing of a symbol that is not this
-- edge's endpoint; and, where it costs nothing, no crossing of another pathway.
-- The third is best-effort, and some diagrams cannot satisfy all three.
--
-- Obstacle extents are estimated, not measured: see `energese.half_extent`.
-- ---------------------------------------------------------------------------

-- A label is allowed to grow its symbol, but only so far. Odum routinely writes
-- "Environmental Systems" inside a producer, so the limit cannot be the cell
-- itself; but a label several times the cell stops the symbol reading as the
-- cell it occupies, which is the inconsistency the grid exists to remove.
-- 1.6 cells is the point between those two, judged against Odum's own figures.
local GROWTH_ALLOWANCE = 1.6

function energese.label_fits(node)
    local half = HALF_EXTENT[node.type]
    if not half then return true end
    local cap = half[1] * energese.UNIT_CM * (node.magnitude or 1.0) * GROWTH_ALLOWANCE
    return label_half_width(node.label) <= cap
end

-- Odum names symbols as well as describing them: storages Q1, Q2, ...; sources
-- and flows X and J. Both belong in the model -- the short name is what the
-- equations refer to, the long one is what a reader needs -- so a node may
-- carry `label` (friendly) and `short_label` (Odum's nomenclature).
--
-- metadata.label_mode picks between them:
--   "long"  (default) friendly name inside, moved outside if it will not fit
--   "short"           Odum's name inside, nothing outside
--   "both"            Odum's name inside, friendly name outside
--
-- A node may force the issue with label_position = inside | above | below.
function energese.resolve_label(node, mode)
    local long = node.label or ""
    local short = node.short_label
    local pos = node.label_position

    if mode == "short" then
        return (short and short ~= "" and short) or long, nil, nil
    end

    local outside_where = (pos == "above") and "above" or "below"
    if mode == "both" then
        if short and short ~= "" then
            return short, (long ~= "" and long or nil), outside_where
        end
        return long, nil, nil
    end

    -- "long"
    if pos == "inside" or long == "" then return long, nil, nil end
    if pos == "above" or pos == "below" or not energese.label_fits(node) then
        return (short and short ~= "" and short) or "", long, outside_where
    end
    return long, nil, nil
end

function energese.obstacles(nodes, x_coords, y_coords, placement)
    local list = {}
    for _, node in ipairs(nodes) do
      -- An exchange marker sits on a pathway rather than beside one, so it is
      -- not an obstacle: routing around it would push the pathway off its own
      -- marker.
      if not (node.seller and node.buyer) then
        local hw, hh = energese.half_extent(node)
        local cy = y_coords[node.id]
        local place = placement and placement[node.id]
        if place and place.outside then
            -- The displaced label is part of the obstacle: a pathway crossing
            -- it is as wrong as one crossing the symbol.
            local lw = label_half_width(place.outside)
            local lh = LABEL_HEIGHT
            if lw > hw then hw = lw end
            hh = hh + lh
            cy = cy + ((place.where == "above") and lh or -lh)
        end
        list[#list + 1] = {
            id = node.id, x = x_coords[node.id], y = cy, hw = hw, hh = hh,
        }
      end
    end
    return list
end

-- Liang-Barsky: does the segment enter the box at all?
local function segment_hits_box(x1, y1, x2, y2, box, pad)
    local xmin, xmax = box.x - box.hw - pad, box.x + box.hw + pad
    local ymin, ymax = box.y - box.hh - pad, box.y + box.hh + pad
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0.0, 1.0
    local checks = {
        { -dx, x1 - xmin }, { dx, xmax - x1 },
        { -dy, y1 - ymin }, { dy, ymax - y1 },
    }
    for _, c in ipairs(checks) do
        local p, q = c[1], c[2]
        if p == 0 then
            if q < 0 then return false end
        else
            local r = q / p
            if p < 0 then
                if r > t1 then return false end
                if r > t0 then t0 = r end
            else
                if r < t0 then return false end
                if r < t1 then t1 = r end
            end
        end
    end
    return t1 > t0
end

-- How much a label placed at (cx, cy) would collide with: other symbols first,
-- then pathways. A displaced label crossed by a pathway is as unreadable as one
-- sitting on a symbol, and both are avoidable by choosing the other side.
function energese.label_conflicts(cx, cy, hw, hh, own_id, boxes, segments)
    local box = { x = cx, y = cy, hw = hw, hh = hh }
    local score = 0
    for _, other in ipairs(boxes) do
        if other.id ~= own_id then
            local dx = math.abs(other.x - cx) - (other.hw + hw)
            local dy = math.abs(other.y - cy) - (other.hh + hh)
            if dx < 0 and dy < 0 then score = score + 10 end
        end
    end
    -- Reject on bounding boxes first. A diagram's pathways come to a few
    -- thousand sampled segments and every candidate position is scored against
    -- all of them, so the cheap test is what keeps this off the compile time.
    local x0, x1 = cx - hw, cx + hw
    local y0, y1 = cy - hh, cy + hh
    for _, seg in ipairs(segments) do
        if not (math.max(seg[1], seg[3]) < x0 or math.min(seg[1], seg[3]) > x1
             or math.max(seg[2], seg[4]) < y0 or math.min(seg[2], seg[4]) > y1) then
            if segment_hits_box(seg[1], seg[2], seg[3], seg[4], box, 0) then
                score = score + 1
            end
        end
    end
    return score
end

-- Waypoints taking the pathway clear of every obstacle it would otherwise
-- cross, by shortest path through a visibility graph.
--
-- The vertices are the two endpoints and the corners of every obstacle,
-- inflated by the clearance a pathway is to keep. An edge joins two vertices
-- whose connecting segment cuts no obstacle, and Dijkstra over that graph
-- returns the shortest polyline avoiding them all -- which for rectangular
-- obstacles is *the* shortest such path, since a taut string around boxes
-- bends only at their corners.
--
-- What this replaces stepped over one offending symbol at a time, taking
-- whichever side deviated less, and re-tested. That is greedy in the ordinary
-- sense and wrong in the ordinary way: clearing the first obstacle by the
-- smaller deviation regularly pushed the pathway into a second, and a pathway
-- crossing a crowded middle came out as a staircase of local decisions with no
-- claim to being short. It also bounded its own recursion at depth 3 and then
-- gave up, drawing straight through a symbol -- which in ESL asserts a
-- connection the model does not contain.
--
-- Two details that are easy to get wrong:
--
--   * A box containing an endpoint is not an obstacle for that pathway. A
--     symbol whose neighbour's clearance overlaps its own would otherwise
--     leave every vertex invisible from the start, and the router would report
--     no path where the old one at least tried.
--   * Visibility is tested against boxes inflated slightly *less* than the
--     corners are, or a segment running from a corner along its own box's edge
--     grazes it and counts as blocked.
-- ---------------------------------------------------------------------------

-- Clear air a pathway keeps from a symbol it is not attached to, and so the
-- inflation of the corners it bends around.
local ROUTE_CLEAR = 0.34
local GRAZE = 1e-4

local function inside_box(x, y, box, pad)
    return math.abs(x - box.x) <= box.hw + pad
       and math.abs(y - box.y) <= box.hh + pad
end

local function visible(ax, ay, bx, by, blockers, block)
    for _, box in ipairs(blockers) do
        if segment_hits_box(ax, ay, bx, by, box, block) then return false end
    end
    return true
end

-- Dijkstra from vertex 1 to vertex #vertices. Ties break by index, which is
-- fixed by the order the corners are built in, so one model always routes the
-- same way.
local function shortest_path(vertices, blockers, block)
    local n = #vertices
    local dist, prev, done = {}, {}, {}
    for i = 1, n do dist[i] = math.huge end
    dist[1] = 0
    for _ = 1, n do
        local u, best = nil, math.huge
        for i = 1, n do
            if not done[i] and dist[i] < best then u, best = i, dist[i] end
        end
        if not u or u == n then break end
        done[u] = true
        local ax, ay = vertices[u][1], vertices[u][2]
        for v = 1, n do
            if not done[v] then
                local bx, by = vertices[v][1], vertices[v][2]
                local step = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
                if dist[u] + step < dist[v] - 1e-9
                    and visible(ax, ay, bx, by, blockers, block) then
                    dist[v] = dist[u] + step
                    prev[v] = u
                end
            end
        end
    end
    if dist[n] == math.huge then return nil end
    local path, at = {}, n
    while prev[at] do
        table.insert(path, 1, vertices[at])
        at = prev[at]
    end
    table.remove(path)          -- the goal is not a waypoint
    return path
end

local function route_once(x1, y1, x2, y2, boxes, pad, inflate)
    local blockers = {}
    for _, box in ipairs(boxes) do
        if not (inside_box(x1, y1, box, pad + inflate)
                or inside_box(x2, y2, box, pad + inflate)) then
            blockers[#blockers + 1] = box
        end
    end
    if #blockers == 0 then return {} end

    local vertices = { { x1, y1 } }
    for _, box in ipairs(blockers) do
        local hw, hh = box.hw + pad + inflate, box.hh + pad + inflate
        vertices[#vertices + 1] = { box.x - hw, box.y - hh }
        vertices[#vertices + 1] = { box.x - hw, box.y + hh }
        vertices[#vertices + 1] = { box.x + hw, box.y - hh }
        vertices[#vertices + 1] = { box.x + hw, box.y + hh }
    end
    vertices[#vertices + 1] = { x2, y2 }
    return shortest_path(vertices, blockers, pad + inflate - GRAZE)
end

function energese.route(x1, y1, x2, y2, boxes, pad)
    pad = pad or 0
    if visible(x1, y1, x2, y2, boxes, pad) then return {} end

    -- The polyline clears the obstacles; the curve drawn through it is what
    -- the reader sees, and it cuts the corners the polyline turns at. So the
    -- curve is what decides: a pathway whose curve still grazes a symbol is
    -- re-routed around wider corners rather than accepted.
    local fallback
    for attempt = 1, 3 do
        local pts = route_once(x1, y1, x2, y2, boxes, pad, ROUTE_CLEAR * attempt)
        if pts then
            fallback = fallback or pts
            if #pts == 0 then return pts end
            local curve = { { x1, y1 } }
            for _, w in ipairs(pts) do curve[#curve + 1] = w end
            curve[#curve + 1] = { x2, y2 }
            if energese.curve_is_clear(curve, boxes, pad) then return pts end
        end
    end
    return fallback or {}
end

-- ---------------------------------------------------------------------------
-- The dissipation bundle
--
-- Every dissipating component sends its used energy to one ground, and Odum
-- draws those pathways as a delta: each leaves its component downwards, sweeps
-- in, and the whole bundle merges into a single line at the terminator. Not a
-- horizontal floor line collecting them -- that would draw dissipation as flow
-- into a surface -- and not a spray of independent curves either.
--
-- Routing each one on its own gave the spray: pathways from components in
-- different rows arrived at the junction from all directions and crossed each
-- other on the way, which reads as pathways meeting where nothing joins.
--
-- Lanes fix the order. A tributary's lane is how far it drops before it turns
-- in, assigned by reach: the component nearest the trunk turns in highest, the
-- furthest lowest, so the further one runs below and outside the nearer one all
-- the way to the junction they share.
--
-- A lane is a depth, not a point to turn at. Expressed as a waypoint it put a
-- corner in the middle of the pathway, and the tangent at an interior waypoint
-- is the chord spanning its neighbours -- which at a near-right-angle turn
-- points back the way the pathway came, and bulged the curve out sideways
-- before it could turn.
--
-- The arrival tangent is the chord too, not vertical. Requiring every tributary
-- to arrive at the junction pointing straight down made the nearer ones dip
-- below the further ones to get there, and they crossed after all. Odum's
-- tributaries meet the junction at an angle and the trunk leaves it vertically,
-- which is what the chord gives.
-- ---------------------------------------------------------------------------
function energese.dissipation_lanes(sinks, x_coords, ground_x)
    local ranked = {}
    for i, id in ipairs(sinks) do
        ranked[#ranked + 1] = {
            id = id, seq = i,
            reach = math.abs((x_coords[id] or 0) - ground_x),
        }
    end
    table.sort(ranked, function(a, b)
        if math.abs(a.reach - b.reach) > 1e-9 then return a.reach < b.reach end
        return a.seq < b.seq
    end)
    local lane = {}
    for rank, entry in ipairs(ranked) do lane[entry.id] = rank end
    return lane, #ranked
end

-- Collision testing for an author-bent pathway.
--
-- An edge carrying `bend left=20` has been routed by its author, and the router
-- leaves it alone. But a bend that happens to cross a symbol still asserts a
-- connection the model does not contain, so it cannot simply be accepted. The
-- resolution keeps the author's intent -- the direction of curvature -- and
-- opens the angle until the pathway clears. Only if no angle clears does the
-- automatic router take over.
--
-- TikZ builds `to[bend left=a]` as a cubic whose control points lie a third of
-- the chord along the departure and arrival directions; this reproduces that
-- closely enough to test what the curve actually crosses.
-- One cubic, sampled: the curve TikZ draws for `to[out=<out>, in=<in>]`, whose
-- control points lie a third of the chord along the departure and arrival
-- directions. Every clearance test in this file goes through here, so what is
-- tested is what will be drawn.
local function cubic_samples(ax, ay, bx, by, out_a, in_a, steps)
    local d = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local o, i = math.rad(out_a), math.rad(in_a)
    local c1x, c1y = ax + d / 3 * math.cos(o), ay + d / 3 * math.sin(o)
    local c2x, c2y = bx + d / 3 * math.cos(i), by + d / 3 * math.sin(i)
    local pts = {}
    for k = 0, steps do
        local t = k / steps
        local m = 1 - t
        pts[#pts + 1] = {
            m*m*m*ax + 3*m*m*t*c1x + 3*m*t*t*c2x + t*t*t*bx,
            m*m*m*ay + 3*m*m*t*c1y + 3*m*t*t*c2y + t*t*t*by,
        }
    end
    return pts
end

local function bezier_samples(ax, ay, bx, by, alpha, steps)
    local base = math.deg(math.atan(by - ay, bx - ax))
    return cubic_samples(ax, ay, bx, by, base + alpha, base + 180 - alpha, steps)
end

local function path_is_clear(pts, boxes, pad)
    for i = 1, #pts - 1 do
        for _, box in ipairs(boxes) do
            if segment_hits_box(pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2],
                                box, pad) then
                return false
            end
        end
    end
    return true
end

-- Returns an options string whose bend clears every obstacle, or nil if none
-- does. Escalates in 8-degree steps, which is enough to clear a symbol without
-- turning a gentle arc into a loop.
function energese.clear_bend(options, ax, ay, bx, by, boxes, pad)
    local alpha = tonumber(options:match("bend%s+left%s*=%s*(%-?[%d.]+)"))
    local sign, key = 1, "bend left"
    if not alpha then
        alpha = tonumber(options:match("bend%s+right%s*=%s*(%-?[%d.]+)"))
        sign, key = -1, "bend right"
    end
    if not alpha then return nil end

    for step = 0, 6 do
        local try = alpha + step * 8
        if path_is_clear(bezier_samples(ax, ay, bx, by, sign * try, 24), boxes, pad) then
            if step == 0 then return options end
            return (options:gsub("bend%s+%a+%s*=%s*%-?[%d.]+",
                                 string.format("%s=%g", key, try), 1))
        end
    end
    return nil
end

-- Waypoints supplied by the model rather than computed.
--
-- A visual editor (see docs/gssk-interop.md) knows exactly where its user
-- dragged a pathway, and that geometry must survive into the rendered figure
-- unchanged -- otherwise what is published is not what was drawn. An edge
-- carrying `waypoints` is therefore routed by the model, and the automatic
-- router stands aside.
--
-- JSON supplies a list of pairs: "waypoints": [[3, 2], [5, 4]]
-- TeX supplies the same compactly:  waypoints={3,2; 5,4}
function energese.parse_waypoints(value)
    local points = {}
    if type(value) == "table" then
        for _, pair in ipairs(value) do
            if type(pair) == "table" and pair[1] and pair[2] then
                points[#points + 1] = { tonumber(pair[1]), tonumber(pair[2]) }
            end
        end
    elseif type(value) == "string" then
        for chunk in value:gmatch("[^;]+") do
            local x, y = chunk:match("^%s*(-?[%d.]+)%s*,%s*(-?[%d.]+)%s*$")
            if x and y then
                points[#points + 1] = { tonumber(x), tonumber(y) }
            end
        end
    end
    return points
end

-- Emit a path through waypoints as a chain of smooth curves. At each interior
-- point the tangent is the direction of the chord spanning its neighbours, so
-- the pathway flows through the detour rather than turning a corner -- which is
-- how Odum draws them, and what keeps a routed pathway from looking mechanical.
local function angle_between(x1, y1, x2, y2)
    return math.deg(math.atan(y2 - y1, x2 - x1))
end

-- The departure and arrival angle of every segment.
--
-- At an interior waypoint the tangent is the direction of the chord spanning
-- its neighbours, which is what makes the pathway flow through a detour rather
-- than turn a corner at it -- and it is the same direction on both sides, so
-- the curve is continuous in tangent (C1) at every waypoint, not merely
-- connected. TikZ states an arrival as the direction the curve comes *from*,
-- which is the departure reversed; the two expressions below are that one
-- statement written from each end.
local function path_tangents(pts, out_first, in_last)
    local angles = {}
    for i = 1, #pts - 1 do
        local ax, ay = pts[i][1], pts[i][2]
        local bx, by = pts[i + 1][1], pts[i + 1][2]
        local out_a
        if i == 1 then
            out_a = out_first or angle_between(ax, ay, bx, by)
        else
            out_a = angle_between(pts[i - 1][1], pts[i - 1][2], bx, by)
        end
        local in_a
        if i + 1 == #pts then
            in_a = in_last or angle_between(bx, by, ax, ay)
        else
            in_a = angle_between(pts[i + 2][1], pts[i + 2][2], ax, ay)
        end
        angles[i] = { out_a, in_a }
    end
    return angles
end

-- Does the curve through these points clear every obstacle? The polyline the
-- router returns is clear by construction; the curve drawn through it cuts the
-- corners, and that is what the reader sees.
function energese.curve_is_clear(pts, boxes, pad, out_first, in_last)
    local angles = path_tangents(pts, out_first, in_last)
    for i = 1, #pts - 1 do
        local samples = cubic_samples(pts[i][1], pts[i][2],
            pts[i + 1][1], pts[i + 1][2], angles[i][1], angles[i][2], 16)
        if not path_is_clear(samples, boxes, pad) then return false end
    end
    return true
end

function energese.smooth_path(pts, label_code, out_first, in_last)
    local angles = path_tangents(pts, out_first, in_last)
    local parts = {}
    for i = 1, #pts - 1 do
        -- The label rides the first segment; `midway' on a multi-segment path
        -- would otherwise attach to the last one.
        local node = (i == 1) and label_code or ""
        parts[#parts + 1] = string.format("to [out=%.1f, in=%.1f] %s (%.4f, %.4f)",
            angles[i][1], angles[i][2], node, pts[i + 1][1], pts[i + 1][2])
    end
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Edge labels
--
-- A flow's quantity is part of the diagram's content, and a quantity written
-- across a symbol or over another pathway is unreadable -- worse than
-- unreadable when it lands between two pathways and the reader has to guess
-- which one it belongs to.
--
-- The label is placed by choosing among the positions Ti*k*Z can express for
-- a node on a path: a fraction along it, above or below, at one of a few
-- distances clear of it. Each candidate is scored against the symbols, the
-- pathways -- sampled as the curves they will actually be drawn as, not as
-- straight chords -- and the labels already placed, and the best is taken.
-- Labels are placed in the order the model declares its edges, each one an
-- obstacle for the next.
--
-- Why an enumeration and not the annealing the graph-drawing literature
-- reaches for: goldens are only meaningful if rendering is reproducible
-- (AGENTS.md section 3), and a randomised search would have to carry a seed
-- and still give a different answer whenever anything upstream of it changed.
-- The candidate set here is also not a discretisation of a continuous problem
-- -- it *is* the set of placements Ti*k*Z can express relative to a path, and
-- a position it cannot express would have to be given absolutely, which stops
-- the label travelling with the pathway when the layout moves.
--
-- The geometry is approximate in the same way the obstacle extents are: Lua
-- places the label against the pathway between two node *boundaries*, while
-- TeX draws it against the pathway between two ports. The two agree to within
-- the accuracy of the extent estimate.
-- ---------------------------------------------------------------------------

-- A pathway's label is set in the package's label font, like every other
-- label the package places. It used to inherit the surrounding document's,
-- which put a diagram's quantities in the body text's serif beside its
-- symbols' sans -- and, worse for the placement below, made the size of a
-- label something Lua could not estimate, since it depended on a document it
-- cannot see.
local LABEL_DEFAULT = "midway, above, inner sep=2pt, font=\\energeselabelfont"

-- Fractions along the first segment, which is the one a label rides. Ordered
-- by preference: a label that has no reason to move stays at the midpoint.
local LABEL_POS = { 0.5, 0.35, 0.65, 0.22, 0.78 }
-- Distances clear of the pathway, in diagram units. The last two are wide
-- enough to escape a corridor between two symbols, which is where the short
-- ones all collide with something and the label has nowhere to go.
local LABEL_LIFT = { 0.05, 0.25, 0.45, 0.7, 1.0 }

-- Where on a symbol a pathway starts, in units of the symbol's own half-width
-- and half-height. Which side matters: money leaves a producer on its left and
-- loops back, so an approximation that assumed every pathway leaves towards
-- the far end put the money legs' labels on the wrong side of the symbol
-- entirely -- and a label placed against a pathway that is not where it was
-- thought to be lands on whatever is.
--
-- Generic, where the anchors themselves are per-shape: this is an estimate in
-- the same family as the extents, and wrong by less than the symbol it sits on.
local ANCHOR_SIDE = {
    energy_in   = { -1,  0   }, energy_out   = {  1,  0   },
    money_in    = {  1,  0.5 }, money_out    = { -1,  0.5 },
    feedback_in = {  0,  1   }, feedback_out = {  0,  1   },
    heat_sink   = {  0, -1   }, north        = {  0,  1   },
    south       = {  0, -1   }, east         = {  1,  0   },
    west        = { -1,  0   }, center       = {  0,  0   },
}

-- Where the pathway leaves a symbol: the anchor's side of its box, or, for an
-- anchor with no entry above, the point at which the straight line to the
-- other end leaves it.
local function boundary_point(box, x, y, tx, ty, anchor)
    if not box then return x, y end
    local side = ANCHOR_SIDE[anchor]
    if side then
        return x + side[1] * box.hw, y + side[2] * box.hh
    end
    local dx, dy = tx - x, ty - y
    local t = 1.0
    if math.abs(dx) > 1e-9 then t = math.min(t, math.abs(box.hw / dx)) end
    if math.abs(dy) > 1e-9 then t = math.min(t, math.abs(box.hh / dy)) end
    return x + dx * t, y + dy * t
end

-- The curve a pathway will be drawn as, sampled. Mirrors what the renderer
-- emits: a chain of smooth segments through the waypoints, or a single bend
-- when there are none.
local function pathway_samples(ax, ay, bx, by, waypoints, options)
    if #waypoints > 0 then
        local pts = { { ax, ay } }
        for _, w in ipairs(waypoints) do pts[#pts + 1] = w end
        pts[#pts + 1] = { bx, by }
        local angles = path_tangents(pts)
        local out = {}
        for i = 1, #pts - 1 do
            for _, p in ipairs(cubic_samples(pts[i][1], pts[i][2], pts[i + 1][1],
                    pts[i + 1][2], angles[i][1], angles[i][2], 12)) do
                out[#out + 1] = p
            end
        end
        return out, pts
    end
    local alpha = tonumber(options:match("bend%s+left%s*=%s*(%-?[%d.]+)"))
    if not alpha then
        local right = tonumber(options:match("bend%s+right%s*=%s*(%-?[%d.]+)"))
        alpha = right and -right or 6      -- the default gentle bend
    end
    return bezier_samples(ax, ay, bx, by, alpha, 24), { { ax, ay }, { bx, by } }
end

-- The point a fraction of the way along the first drawn segment, which is
-- where `pos=` puts a label.
local function point_at(samples, segments, fraction)
    local first = #samples
    if segments and #segments > 2 then
        first = math.floor(#samples / (#segments - 1))
    end
    local i = math.max(1, math.min(first, math.floor(fraction * first + 0.5)))
    return samples[i][1], samples[i][2]
end

function energese.place_edge_labels(edges, geom, boxes, x_coords, y_coords,
                                    windows, bundle, node_map)
    local box_of = {}
    for _, box in ipairs(boxes) do box_of[box.id] = box end

    -- Every pathway, as the short segments its curve will be drawn as. A label
    -- is scored against all of them, its own included: a quantity sitting on
    -- the pathway it belongs to is as unreadable as one sitting on any other.
    -- The system window counts as something to keep off. It is a line the
    -- reader follows, and a quantity written across it is as hard to read as
    -- one written across a pathway.
    local segments, curves = {}, {}
    for _, win in ipairs(windows or {}) do
        segments[#segments + 1] = { win.x_min, win.y_min, win.x_max, win.y_min }
        segments[#segments + 1] = { win.x_max, win.y_min, win.x_max, win.y_max }
        segments[#segments + 1] = { win.x_max, win.y_max, win.x_min, win.y_max }
        segments[#segments + 1] = { win.x_min, win.y_max, win.x_min, win.y_min }
    end

    -- And so do the dissipation pathways, which are not in `edges`: they are
    -- the package's own, and a label written across one is no more readable
    -- for that.
    if bundle then
        for _, path in ipairs(bundle.paths) do
            local angles = path_tangents(path.pts, -90, 90)
            for k = 1, #path.pts - 1 do
                local samples = cubic_samples(path.pts[k][1], path.pts[k][2],
                    path.pts[k + 1][1], path.pts[k + 1][2],
                    angles[k][1], angles[k][2], 10)
                for j = 1, #samples - 1 do
                    segments[#segments + 1] = { samples[j][1], samples[j][2],
                                                samples[j + 1][1], samples[j + 1][2] }
                end
            end
        end
        segments[#segments + 1] = { bundle.ground_x, bundle.collect_y,
                                    bundle.ground_x, bundle.ground_y }
    end
    for i, edge in ipairs(edges) do
        local x1, y1 = x_coords[edge.from], y_coords[edge.from]
        local x2, y2 = x_coords[edge.to], y_coords[edge.to]
        if x1 and x2 then
            local from_anchor, to_anchor = energese.edge_anchors(edge, node_map)
            local ax, ay = boundary_point(box_of[edge.from], x1, y1, x2, y2, from_anchor)
            local bx, by = boundary_point(box_of[edge.to], x2, y2, x1, y1, to_anchor)
            local samples, pts = pathway_samples(ax, ay, bx, by,
                geom[i].waypoints, geom[i].options)
            curves[i] = { samples = samples, points = pts }
            for k = 1, #samples - 1 do
                segments[#segments + 1] = { samples[k][1], samples[k][2],
                                            samples[k + 1][1], samples[k + 1][2] }
            end
        end
    end

    local placed, out = {}, {}
    for i, edge in ipairs(edges) do
        -- An author who has written label_options has placed the label.
        if not edge.label or edge.label_options then
            out[i] = edge.label_options or LABEL_DEFAULT
        elseif not curves[i] then
            out[i] = LABEL_DEFAULT
        else
            -- Scored a little larger than estimated. The estimate is good to
            -- a few percent, and a placement that clears an obstacle by less
            -- than that is not clear at all -- the search will happily take a
            -- position whose whole margin is estimation error.
            local hw = math.max(label_half_width(edge.label), 0.08) * 1.15 + 0.06
            local hh = 0.5 * LABEL_HEIGHT + 0.04
            local best, best_score
            for pi, pos in ipairs(LABEL_POS) do
                for _, side in ipairs({ "above", "below" }) do
                    for li, lift in ipairs(LABEL_LIFT) do
                        local px, py = point_at(curves[i].samples, curves[i].points, pos)
                        local cy = py + ((side == "above") and (lift + hh) or -(lift + hh))
                        -- No symbol is exempt. A node's own label may
                        -- overlap the node it belongs to -- it is anchored to
                        -- it -- but a flow's quantity written across either of
                        -- the symbols it runs between is just as lost as one
                        -- written across a third.
                        local score = energese.label_conflicts(px, cy, hw, hh,
                            nil, boxes, segments)
                        -- Two labels on top of each other are worse than
                        -- either on a pathway, and as bad as one on a symbol.
                        for _, other in ipairs(placed) do
                            if math.abs(other.x - px) < other.hw + hw
                               and math.abs(other.y - cy) < other.hh + hh then
                                score = score + 10
                            end
                        end
                        -- Among placements that read equally well, the one
                        -- nearest the default: midway, above, close in. A
                        -- label that moves without cause is a label the reader
                        -- has to hunt for.
                        score = score * 100 + (pi - 1) * 3 + (li - 1) * 2
                                + ((side == "above") and 0 or 1)
                        if not best_score or score < best_score then
                            best_score = score
                            best = { pos = pos, side = side, lift = lift,
                                     x = px, y = cy, hw = hw, hh = hh }
                        end
                    end
                end
            end
            placed[#placed + 1] = best
            out[i] = string.format(
                "pos=%.2f, %s=%.2fcm, inner sep=2pt, font=\\energeselabelfont",
                best.pos, best.side, best.lift)
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Ports
--
-- Where a pathway meets a symbol. The anchor names the *kind* of flow and so
-- the direction it belongs in -- energy in on the left, out on the right,
-- money through the upper half, dissipation below -- and the port allocator in
-- energese.sty turns that direction into one of the symbol's actual ports.
-- ---------------------------------------------------------------------------

-- The anchors an edge asks for at each end, before any port is allocated. The
-- model has the last word: `from_anchor`/`to_anchor` on the edge override.
function energese.edge_anchors(edge, node_map)
    local from_node = node_map[edge.from]
    local to_node = node_map[edge.to]

    local from_anchor = "energy_out"
    local to_anchor = "energy_in"

    if from_node and (from_node.type == "text" or from_node.type == "box") then
        from_anchor = "center"
    end
    if to_node and (to_node.type == "text" or to_node.type == "box") then
        to_anchor = "center"
    elseif to_node and to_node.type == "ground" then
        to_anchor = "north"
    end

    if edge.type == "money_feedback" then
        from_anchor = "money_out"
        to_anchor = "money_in"
    elseif edge.type == "information" then
        to_anchor = "north"
    end

    if edge.from_anchor then from_anchor = edge.from_anchor end
    if edge.to_anchor then to_anchor = edge.to_anchor end
    return from_anchor, to_anchor
end

-- Every port a diagram's pathways will ask for, in the order they should be
-- granted.
--
-- Ports are claimed one at a time and the first claim on a contested port
-- wins, so the order decides the picture, and two things have to come out of
-- it.
--
-- It must not depend on the order the model lists its edges in. Granting ports
-- as each pathway is drawn made two identical models render differently for
-- having declared their parts in a different sequence -- which is what
-- `make parity` caught between the JSON and TeX front ends, where the same
-- diagram lists its exchanges in a different order and the expansion appends
-- their pathways accordingly.
--
-- And a fan of pathways must not cross itself on the way out of the symbol.
-- The pathways contending for one anchor are therefore served from the middle
-- of the fan outwards: the one running closest to the fan's own mean direction
-- takes the anchor's port, and the rest step away from it on the side they
-- lean towards, so the order they attach in around the outline is the order
-- they leave in. Serving them by bearing instead put the third pathway of a
-- three-way fan on the far side of the anchor from the two it belonged with,
-- and its line crossed both of them.
--
-- The mean is circular -- summed as unit vectors -- because a fan straddling
-- due east has bearings near both 0 and 360, and an arithmetic mean of those
-- points due west.
function energese.port_requests(edges, node_map, x_coords, y_coords)
    local groups, order = {}, {}
    for i, edge in ipairs(edges) do
        local from_anchor, to_anchor = energese.edge_anchors(edge, node_map)
        for _, req in ipairs({
            { node = edge.from, anchor = from_anchor, other = edge.to,   key = "e" .. i .. "f" },
            { node = edge.to,   anchor = to_anchor,   other = edge.from, key = "e" .. i .. "t" },
        }) do
            local dx = (x_coords[req.other] or 0) - (x_coords[req.node] or 0)
            local dy = (y_coords[req.other] or 0) - (y_coords[req.node] or 0)
            req.bearing = math.deg(math.atan(dy, dx))
            req.seq = i
            -- One group per contested anchor: only pathways asking for the
            -- same anchor of the same symbol are competing for a port.
            local group = req.node .. "\0" .. req.anchor
            if not groups[group] then
                groups[group] = {}
                order[#order + 1] = group
            end
            local g = groups[group]
            g[#g + 1] = req
        end
    end

    table.sort(order)
    local requests = {}
    for _, group in ipairs(order) do
        local g = groups[group]
        local sx, sy = 0, 0
        for _, req in ipairs(g) do
            sx = sx + math.cos(math.rad(req.bearing))
            sy = sy + math.sin(math.rad(req.bearing))
        end
        -- Two pathways leaving in exactly opposite directions cancel; the mean
        -- is then meaningless and the tie-breaks below decide.
        local mean = math.deg(math.atan(sy, sx))
        for _, req in ipairs(g) do
            req.spread = math.abs((req.bearing - mean + 180) % 360 - 180)
        end
        table.sort(g, function(a, b)
            if math.abs(a.spread - b.spread) > 1e-9 then return a.spread < b.spread end
            if a.other ~= b.other then return a.other < b.other end
            return a.seq < b.seq
        end)
        for _, req in ipairs(g) do requests[#requests + 1] = req end
    end
    return requests
end

function energese.render(data, options)
    -- A GSSK model is normalised into an energese one first, so that both
    -- front ends and every check below see one shape of model. A native model
    -- passes through untouched.
    energese.normalise(data)

    local ok, err = energese.validate_schema(data)
    if not ok then
        report_error("Validation error: " .. err)
    end

    -- Expand before anything looks at the edges, so the synthesised legs are
    -- checked, routed and drawn exactly like declared ones.
    energese.expand_exchanges(data)

    local findings = energese.check_energetics(data)
    if #findings > 0 then
        local strict = data.metadata and data.metadata.strict
        for _, finding in ipairs(findings) do
            if strict then
                report_error("Energetic check: " .. finding)
            elseif luatexbase and luatexbase.module_warning then
                luatexbase.module_warning("energese", finding)
            else
                io.stderr:write("[energese] " .. finding .. "\n")
            end
        end
    end

    local col_spacing = (data.metadata and data.metadata.column_spacing) or 3.0
    local row_spacing = (data.metadata and data.metadata.row_spacing) or 1.5

    -- Modifiers that belong against a component rather than in a column of
    -- their own. Settled before the columns, because the columns are built
    -- from what is left.
    local attached = energese.attach_modifiers(data.nodes, data.edges, col_spacing)

    local tr_map = energese.calculate_transformity_columns(data.nodes, attached)
    local x_coords = energese.calculate_x_coordinates(data.nodes, tr_map, col_spacing)
    local y_coords = energese.calculate_vertical_positions(data.nodes, data.edges,
        tr_map, row_spacing, attached)
    energese.place_attached(attached, x_coords, y_coords)

    local node_map = {}
    for _, node in ipairs(data.nodes) do
        node_map[node.id] = node
    end

    tex.print("\\begin{tikzpicture}[" .. options .. "]")

    -- Nodes are created once, with their real labels, because a symbol sizes
    -- itself to its label: a placeholder node carrying an empty label would be
    -- smaller than the one finally drawn, and every edge would then aim at the
    -- wrong anchor. The pathways are drawn after them, and on the same layer:
    -- an arrowhead has to land on top of the symbol's outline to read as
    -- arriving at it, and the symbols are filled, so a pathway drawn earlier
    -- would be painted over.
    local label_mode = (data.metadata and data.metadata.label_mode) or "long"

    -- Symbols alone, and straight approximations of the pathways: enough to
    -- judge which side of a symbol has room for a displaced label.
    local base_boxes = energese.obstacles(data.nodes, x_coords, y_coords, nil)
    local segments = {}
    for _, edge in ipairs(data.edges) do
        if x_coords[edge.from] and x_coords[edge.to] then
            segments[#segments + 1] = {
                x_coords[edge.from], y_coords[edge.from],
                x_coords[edge.to], y_coords[edge.to],
            }
        end
    end

    local placement = {}
    for _, node in ipairs(data.nodes) do
        local inside, outside, where = energese.resolve_label(node, label_mode)
        if outside and not node.label_position then
            -- No explicit instruction, so put it wherever it is least crossed.
            local own
            for _, box in ipairs(base_boxes) do
                if box.id == node.id then own = box end
            end
            local hw = math.max(label_half_width(outside), 0.1)
            local below = energese.label_conflicts(own.x, own.y - own.hh - LABEL_HEIGHT,
                hw, LABEL_HEIGHT, node.id, base_boxes, segments)
            local above = energese.label_conflicts(own.x, own.y + own.hh + LABEL_HEIGHT,
                hw, LABEL_HEIGHT, node.id, base_boxes, segments)
            where = (above < below) and "above" or "below"
        end
        placement[node.id] = { inside = inside, outside = outside, where = where }
    end

    for _, node in ipairs(data.nodes) do
        -- An exchange marker is emitted with its pathway, not placed on its own.
        if not (node.seller and node.buyer) then
            local magnitude = node.magnitude or 1.0
            local lopts = node.label_options or ""
            -- `energese magnitude` scales the symbol; TikZ's `scale` would
            -- scale the label with it, so two symbols of different magnitude
            -- carrying the same words came out in different type sizes.
            local style = string.format("energese %s, energese magnitude=%f",
                node.type, magnitude)
            tex.print(string.format("\\node[%s] (%s) at (%f, %f) %s {%s};",
                style, node.id, x_coords[node.id], y_coords[node.id],
                lopts ~= "" and "[" .. lopts .. "]" or "", placement[node.id].inside))
        end
    end

    -- Labels too large for their symbol sit outside it, anchored to the
    -- symbol so they travel with it.
    for _, node in ipairs(data.nodes) do
        local place = placement[node.id]
        -- Markers are not emitted as nodes, so nothing can be anchored to them.
        if place.outside and not (node.seller and node.buyer) then
            tex.print(string.format(
                "\\node[energese text, %s=2pt of %s] {%s};",
                place.where, node.id, place.outside))
        end
    end

    -- Obstacles every pathway must keep clear of.
    local boxes = energese.obstacles(data.nodes, x_coords, y_coords, placement)

    -- Which components dissipate. Settled early: the window below has to leave
    -- room under them for the funnel, and their ports must be reserved before
    -- any pathway is allocated one -- dissipation must have the port under the
    -- symbol, because Odum draws used energy leaving downwards and the drop
    -- that follows is measured from the symbol's underside.
    local sinks = {}
    if not data.metadata or data.metadata.show_heat_sink ~= false then
        for _, node in ipairs(data.nodes) do
            -- An exchange marker annotates a coupling; it transforms nothing
            -- and so dissipates nothing, even though its glyph is a shape that
            -- otherwise would.
            if energese.HAS_HEAT_SINK[node.type]
                and not (node.seller and node.buyer) then
                sinks[#sinks + 1] = node.id
            end
        end
    end

    -- The system window: the optional frame declaring what the model treats as
    -- inside the system. Settled here rather than where it is drawn, because
    -- the pathway labels below have to keep off it.
    local windows, window_min_y = {}, nil
    if data.metadata and data.metadata.system_boundary then
        local boundaries = data.metadata.system_boundary
        if boundaries == true then
            -- Auto-fit: a fixed margin outside the extents of what the model
            -- puts inside the system. `boxes` already carries every symbol's
            -- estimated size and its displaced label.
            local margin = (data.metadata.boundary_margin
                            or energese.BOUNDARY_MARGIN * energese.UNIT_CM)
            -- Room for the funnel: the drop out of the symbols, a lane for
            -- each tributary, and the turn at the bottom.
            local floor = 0
            if #sinks > 0 then
                floor = (0.45 + (#sinks + 1) * 0.18) * row_spacing
            end
            local fitted = energese.system_bounds(data.nodes, boxes, margin, floor)
            boundaries = fitted and { fitted } or {}
        elseif not boundaries[1] then
            boundaries = { boundaries }
        end
        for _, sb in ipairs(boundaries) do
            windows[#windows + 1] = sb
            if not window_min_y or sb.y_min < window_min_y then
                window_min_y = sb.y_min
            end
        end
    end

    -- Ports. Every pathway from here on claims one, and a claimed port is
    -- closed to the next pathway (see energese.sty). Claims run per diagram,
    -- so a document holding several must start each one clean.
    tex.print("\\energeseresetports")

    for _, id in ipairs(sinks) do
        -- Reserved against the symbol itself: there is no other end to lean
        -- towards, and the port wanted is the one the anchor names.
        tex.print(string.format(
            "\\energeseport{%s}{heat_sink}{%s}\\energesekeepport{heat@%s}", id, id, id))
    end

    -- Then every pathway's ports, granted in geometric order and stashed under
    -- the edge's key. Claiming them all here rather than as each pathway is
    -- drawn is what keeps the result independent of the order the model lists
    -- its edges in.
    for _, req in ipairs(energese.port_requests(data.edges, node_map,
                                                x_coords, y_coords)) do
        tex.print(string.format(
            "\\energeseport{%s}{%s}{%s}\\energesekeepport{%s}",
            req.node, req.anchor, req.other, req.key))
    end

    -- Pathway geometry, settled for every edge before any is drawn. The
    -- labels are placed against it below, and a label can only be kept clear
    -- of the pathways if the pathways are all known first.
    local geom = {}
    for edge_index, edge in ipairs(data.edges) do
        local from, to = edge.from, edge.to
        local options = edge.options or ""
        -- Money feedback runs back against the energy flow and by convention
        -- arcs over the top. `out`/`in` do that whichever way the edge points,
        -- where a `bend` would dive under the diagram on right-to-left edges.
        -- Only supply it when the edge has not routed itself: two routings
        -- fight each other and the arc balloons into a circle.
        local ROUTE = "out=90, in=90, looseness=1.2"
        if edge.type == "money_feedback" and not options:match("bend")
            and not options:match("out%s*=") and not options:match("in%s*=") then
            options = options ~= "" and (options .. ", " .. ROUTE) or ROUTE
        end

        -- Route around any symbol that is not this edge's own endpoint. A
        -- pathway crossing a symbol reads as flow into it, so it has to go
        -- around; an edge that routes itself is left alone.
        local waypoints = {}
        if edge.waypoints then
            -- Model-supplied geometry wins: reproduce what was drawn.
            waypoints = energese.parse_waypoints(edge.waypoints)
        elseif options:match("bend") and x_coords[from] and x_coords[to] then
            -- Author-bent: keep the direction of curvature, open the angle
            -- until it clears, and only route automatically if none does.
            local others = {}
            for _, box in ipairs(boxes) do
                if box.id ~= from and box.id ~= to then others[#others + 1] = box end
            end
            local cleared = energese.clear_bend(options, x_coords[from], y_coords[from],
                x_coords[to], y_coords[to], others, 0.05)
            if cleared then
                options = cleared
            else
                waypoints = energese.route(x_coords[from], y_coords[from],
                                           x_coords[to], y_coords[to], others, 0.05)
                options = ""
            end
        elseif options == "" and x_coords[from] and x_coords[to] then
            local others = {}
            for _, box in ipairs(boxes) do
                if box.id ~= from and box.id ~= to then others[#others + 1] = box end
            end
            waypoints = energese.route(x_coords[from], y_coords[from],
                                       x_coords[to], y_coords[to], others, 0.05)
        end

        geom[edge_index] = { options = options, waypoints = waypoints }
    end

    -- The dissipation bundle, computed. Every dissipating component runs a
    -- pathway down to a single ground symbol, which sits OUTSIDE any system
    -- window: used energy leaves the system, so its terminator cannot be drawn
    -- inside the frame. Which components these are was settled before the
    -- pathways, so that their ports could be reserved; the geometry is settled
    -- here, before the labels, so that a quantity is not written across a
    -- dissipation pathway the placement could not see.
    local bundle = nil
    if #sinks > 0 then
        local min_y, min_x, max_x = 1e9, 1e9, -1e9
        for id, x in pairs(x_coords) do
            local y = y_coords[id]
            if y < min_y then min_y = y end
            if x > max_x then max_x = x end
            if x < min_x then min_x = x end
        end

        local base_y = min_y
        if window_min_y and window_min_y < base_y then base_y = window_min_y end
        -- Generous clearance. With the ground close under the nodes, a
        -- pathway leaving downwards and arriving downwards has to double
        -- back, and the curve visibly kinks; giving it room to fall makes
        -- the convergence smooth.
        local ground_y = (data.metadata and data.metadata.heat_sink_y)
                         or (base_y - 2.0 * row_spacing)
        -- A ground inside the window would be wrong whatever the model
        -- asked for, so clamp rather than honour it.
        if window_min_y and ground_y > window_min_y - 0.3 then
            ground_y = window_min_y - row_spacing
        end
        local ground_x = (data.metadata and data.metadata.ground_x)
                         or (min_x + max_x) / 2

        -- The pathways leave each component downwards and converge on the
        -- ground, rather than meeting a horizontal floor line: Odum draws
        -- dissipation as flow to a single sink, not to a surface.
        -- Where a system window exists the pathways converge *inside* it,
        -- and a single line crosses the frame to reach the ground outside.
        -- Letting each pathway cross separately makes the boundary look
        -- shredded, and misstates the accounting: what leaves the system is
        -- one aggregate flow of used energy, not several.
        local collect_y = ground_y
        if window_min_y then
            collect_y = window_min_y + 0.45 * row_spacing
            if collect_y <= ground_y then collect_y = ground_y end
        end

        -- Drop straight out of the symbol before curving in, so the
        -- pathway leaves vertically as Odum draws it and the bend happens
        -- in open space rather than against the symbol's edge.
        local drop = 0.45 * row_spacing
        local lane_of = energese.dissipation_lanes(sinks, x_coords, ground_x)
        local lane_gap = 0.18 * row_spacing
        bundle = { ground_x = ground_x, ground_y = ground_y,
                   collect_y = collect_y, paths = {} }
        for _, id in ipairs(sinks) do
            -- Dissipation must clear the other symbols too: a heat pathway
            -- crossing a component reads as flow into that component.
            -- Measure the drop from the symbol's underside, not its
            -- centre: a drop shorter than the symbol's half-height would
            -- run back up inside the glyph, and the pathway would appear
            -- to start somewhere other than its connection port.
            local hh = 0.3
            for _, box in ipairs(boxes) do
                if box.id == id then hh = box.hh end
            end
            -- The lane is how far this tributary drops before it turns in,
            -- not a point it turns at. Expressing it as a waypoint put a
            -- corner in the middle of the pathway, and the tangent at an
            -- interior waypoint is the chord spanning its neighbours -- which
            -- at a near-right-angle turn points back the way the pathway came,
            -- and bulged the curve out sideways before it could turn. One
            -- segment from a lane-dependent depth straight to the junction
            -- keeps the nesting and keeps the curve.
            local sx = x_coords[id]
            local sy = y_coords[id] - hh - drop
                       - (lane_of[id] - 1) * lane_gap
            -- Never below the junction: a tributary that dropped past it would
            -- have to come back up.
            if sy < collect_y + lane_gap then sy = collect_y + lane_gap end
            local others = {}
            for _, box in ipairs(boxes) do
                if box.id ~= id then others[#others + 1] = box end
            end

            local pts = { { sx, sy } }
            for _, w in ipairs(energese.route(sx, sy, ground_x, collect_y,
                                              others, 0.05)) do
                pts[#pts + 1] = w
            end
            pts[#pts + 1] = { ground_x, collect_y }
            bundle.paths[#bundle.paths + 1] = { id = id, pts = pts }
        end
    end

    local label_opts = energese.place_edge_labels(data.edges, geom, boxes,
                                                  x_coords, y_coords, windows,
                                                  bundle, node_map)

    for edge_index, edge in ipairs(data.edges) do
        local from = edge.from
        local to = edge.to
        local etype = edge.type
        local options = geom[edge_index].options
        local waypoints = geom[edge_index].waypoints

        -- Only override the shared pathway width when the model asks: `volume`
        -- is for showing relative flow, not for routine styling.
        local style = "energese " .. etype
        if edge.volume then
            style = string.format("%s, line width=%fpt", style, edge.volume)
        end

        -- An exchange marker rides the pathway rather than terminating it:
        -- placed at the midpoint, rotated to the flow, and unfilled so the
        -- pathway runs visibly through it.
        local marker_code = ""
        if edge.marker then
            marker_code = string.format(
                "node[energese %s, energese magnitude=%f, pos=0.5, sloped, "
                .. "fill=none, inner sep=0pt] {}",
                edge.marker, edge.marker_magnitude or 1.0)
        end

        local label_code = marker_code
        if edge.label then
            label_code = string.format("%s node[%s] {%s}",
                marker_code, label_opts[edge_index], edge.label)
        end

        -- The ports this pathway was granted above. Each end holds one, so a
        -- second pathway wanting the same place got the next port along
        -- rather than being drawn on top of this one.
        tex.print(string.format(
            "\\energeserecallport{e%df}\\let\\energesefromport\\energeseportname"
            .. "\\energeserecallport{e%dt}\\let\\energesetoport\\energeseportname",
            edge_index, edge_index))

        if #waypoints > 0 then
            local pts = { { x_coords[from], y_coords[from] } }
            for _, w in ipairs(waypoints) do pts[#pts + 1] = w end
            pts[#pts + 1] = { x_coords[to], y_coords[to] }
            tex.print(string.format("\\draw[%s] (\\energesefromport) %s;",
                style,
                energese.smooth_path(pts, label_code):gsub(
                    "%(%-?[%d.]+, %-?[%d.]+%)$", "(\\energesetoport)")))
        else
            -- A dead straight pathway reads as mechanical next to Odum's
            -- drawn curves, so an unrouted edge gets a slight bend.
            local shape = options
            if shape == "" then shape = "bend left=6" end
            tex.print(string.format(
                "\\draw[%s] (\\energesefromport) to [%s] %s (\\energesetoport);",
                style, shape, label_code))
        end
    end

    -- The system window, drawn. It was computed before the pathways -- a label
    -- has to know where the frame is to keep off it -- but it is drawn here,
    -- before the heat sinks, so the dissipation pathways cross it as they do
    -- in Odum's originals.
    for _, sb in ipairs(windows) do
        local style = sb.style or "thick"
        tex.print(string.format("\\draw[%s] (%f, %f) rectangle (%f, %f);",
            style, sb.x_min, sb.y_min, sb.x_max, sb.y_max))
        if sb.label then
            tex.print(string.format("\\node[anchor=north west, font=\\sffamily] at (%f, %f) {%s};",
                sb.x_min, sb.y_max, sb.label))
        end
    end

    -- The dissipation bundle, drawn.
    if bundle then
        for _, path in ipairs(bundle.paths) do
            tex.print(string.format(
                "\\energeserecallport{heat@%s}"
                .. "\\draw[energese heat] (\\energeseportname) -- (%.4f, %.4f) %s;",
                path.id, path.pts[1][1], path.pts[1][2],
                energese.smooth_path(path.pts, "", -90)))
        end

        -- One line from the collection point out through the frame, and
        -- the single arrowhead for the whole dissipation bundle.
        tex.print(string.format(
            "\\draw[energese heat, ->] (%f, %f) -- (%f, %f);",
            bundle.ground_x, bundle.collect_y, bundle.ground_x, bundle.ground_y - 0.28))
        tex.print(string.format("\\node[energese ground] at (%f, %f) {};",
            bundle.ground_x, bundle.ground_y - 0.30))

        local hs_label = data.metadata and data.metadata.heat_sink_label
        if hs_label then
            tex.print(string.format(
                "\\node[anchor=west, font=\\sffamily] at (%f, %f) {%s};",
                bundle.ground_x + 0.30, bundle.ground_y - 0.42, hs_label))
        end
    end

    tex.print("\\end{tikzpicture}")
end

-- ---------------------------------------------------------------------------
-- TeX-native front end
--
-- `\esnode` / `\esflow` / `\esmeta` build exactly the same model table that
-- `parse_json` produces, so both authoring paths share one layout engine and
-- one renderer. Values arrive already \detokenize'd, as a pgfkeys-style
-- `key=value` list.
-- ---------------------------------------------------------------------------

-- Keys whose values are numeric. Everything else stays a string, so a label of
-- "6000" is still typeset as text rather than reformatted as a Lua number.
local NUMERIC_KEYS = {
    Tr = true, x = true, y = true, magnitude = true, volume = true,
    column_spacing = true, row_spacing = true, heat_sink_y = true,
    ground_x = true, y_gravity = true,
    x_min = true, x_max = true, y_min = true, y_max = true,
    boundary_margin = true, parent_dx = true, parent_dy = true,
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split on commas that sit at brace depth zero, so `label_options={a, b}`
-- survives as one item.
local function split_top_level(s)
    local items, depth, buf = {}, 0, {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "{" then
            depth = depth + 1
            buf[#buf + 1] = c
        elseif c == "}" then
            depth = depth - 1
            buf[#buf + 1] = c
        elseif c == "," and depth == 0 then
            items[#items + 1] = table.concat(buf)
            buf = {}
        else
            buf[#buf + 1] = c
        end
    end
    items[#items + 1] = table.concat(buf)
    return items
end

-- Strip one pair of braces, but only when they wrap the whole value.
-- "{a}{b}" keeps its braces; "{a, b}" loses them.
local function strip_braces(s)
    if s:sub(1, 1) ~= "{" or s:sub(-1) ~= "}" then return s end
    local depth = 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 and i < #s then return s end
        end
    end
    return s:sub(2, -2)
end

function energese.parse_options(str)
    local opts = {}
    if not str or trim(str) == "" then return opts end
    for _, item in ipairs(split_top_level(str)) do
        item = trim(item)
        if item ~= "" then
            local key, value = item:match("^([%a_][%w_]*)%s*=%s*(.*)$")
            if key then
                value = strip_braces(trim(value))
                if value == "true" then
                    value = true
                elseif value == "false" then
                    value = false
                elseif NUMERIC_KEYS[key] then
                    value = tonumber(value) or value
                end
                opts[key] = value
            else
                -- A bare key is a flag: `system_boundary` means `= true`.
                opts[strip_braces(item)] = true
            end
        end
    end
    return opts
end

local function require_diagram(macro)
    if not energese.current then
        report_error(macro .. " used outside an energese environment")
    end
    return energese.current
end

function energese.tex_begin()
    energese.current = { metadata = {}, nodes = {}, edges = {} }
end

function energese.tex_meta(optstr)
    local model = require_diagram("\\esmeta")
    for key, value in pairs(energese.parse_options(optstr)) do
        model.metadata[key] = value
    end
end

function energese.tex_boundary(optstr)
    local model = require_diagram("\\esboundary")
    local boundary = energese.parse_options(optstr)
    local existing = model.metadata.system_boundary
    if type(existing) == "table" then
        if existing[1] then
            existing[#existing + 1] = boundary
        else
            model.metadata.system_boundary = { existing, boundary }
        end
    else
        model.metadata.system_boundary = { boundary }
    end
end

function energese.tex_node(id, ntype, optstr)
    local model = require_diagram("\\esnode")
    local node = energese.parse_options(optstr)
    node.id = trim(id)
    node.type = trim(ntype)
    -- The TeX front end treats an omitted label as an empty one; requiring
    -- `label={}` on every unlabelled node would be noise.
    if node.label == nil then node.label = "" end
    model.nodes[#model.nodes + 1] = node
end

function energese.tex_edge(from, to, etype, optstr)
    local model = require_diagram("\\esflow")
    local edge = energese.parse_options(optstr)
    edge.from = trim(from)
    edge.to = trim(to)
    etype = trim(etype)
    edge.type = etype ~= "" and etype or "energy"
    model.edges[#model.edges + 1] = edge
end

function energese.tex_end(tikz_options)
    local model = require_diagram("\\end{energese}")
    energese.current = nil
    energese.render(model, tikz_options or "")
end

return energese
