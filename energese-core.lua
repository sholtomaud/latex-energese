local dkjson = require("dkjson")

local energese = {}

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

function energese.parse_json_file(filepath)
    local f = io.open(filepath, "r")
    if not f then
        report_error("File not found: " .. filepath)
    end
    local content = f:read("*all")
    f:close()
    return energese.parse_json(content)
end

function energese.validate_node(node)
    if not node.id then return false, "Node missing required field 'id'" end
    if not node.type then return false, "Node '" .. node.id .. "' missing required field 'type'" end

    if node.type ~= "text" and node.type ~= "box" and node.type ~= "ground" then
        if not node.Tr then return false, "Node '" .. node.id .. "' missing required field 'Tr' (Transformity)" end
        if not node.label then return false, "Node '" .. node.id .. "' missing required field 'label'" end
    end

    local valid_types = {
        source = true, producer = true, consumer = true,
        storage = true, interaction = true, transaction = true,
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

    return true
end

function energese.calculate_transformity_columns(nodes)
    local tr_values = {}
    for _, node in ipairs(nodes) do
        table.insert(tr_values, node.Tr)
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

function energese.build_directed_graph(nodes, edges)
    local adj = {}
    local node_map = {}
    for _, node in ipairs(nodes) do
        adj[node.id] = {}
        node_map[node.id] = node
    end
    for _, edge in ipairs(edges) do
        if edge.type == "energy" or edge.type == "material" then
            if adj[edge.from] then
                table.insert(adj[edge.from], edge.to)
            end
        end
    end
    return adj, node_map
end

function energese.find_longest_path(nodes, edges)
    local adj, node_map = energese.build_directed_graph(nodes, edges)

    local is_target = {}
    for _, edge in ipairs(edges) do
        if edge.type == "energy" or edge.type == "material" then
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

function energese.calculate_vertical_positions(nodes, edges, tr_map, row_spacing)
    local main_chain_list = energese.find_longest_path(nodes, edges)
    local main_chain = {}
    for _, id in ipairs(main_chain_list) do main_chain[id] = true end

    local y_coords = {}

    local cols = {}
    for _, node in ipairs(nodes) do
        local c = tr_map[node.Tr] or 0
        cols[c] = cols[c] or {}
        table.insert(cols[c], node)
    end

    for c, nodes_in_col in pairs(cols) do
        table.sort(nodes_in_col, function(a, b) return a.id < b.id end)

        local main_node = nil
        local others = {}
        for _, node in ipairs(nodes_in_col) do
            if main_chain[node.id] then
                if not main_node then
                    main_node = node
                else
                    table.insert(others, node)
                end
            else
                table.insert(others, node)
            end
        end

        if main_node then
            y_coords[main_node.id] = 0
        end

        for i, node in ipairs(others) do
            local offset = math.ceil(i / 2)
            local sign = (i % 2 == 1) and 1 or -1
            y_coords[node.id] = sign * offset * row_spacing
        end
    end

    for _, node in ipairs(nodes) do
        if node.y then
            y_coords[node.id] = node.y
        else
            if node.layer_hint == "control" then
                y_coords[node.id] = (y_coords[node.id] or 0) + row_spacing
            elseif node.layer_hint == "decomposition" then
                y_coords[node.id] = (y_coords[node.id] or 0) - row_spacing
            end

            if node.y_gravity then
                y_coords[node.id] = (y_coords[node.id] or 0) + node.y_gravity
            end
        end
    end

    return y_coords
end

function energese.render(data, options)
    local ok, err = energese.validate_schema(data)
    if not ok then
        report_error("Validation error: " .. err)
    end

    local tr_map = energese.calculate_transformity_columns(data.nodes)
    local col_spacing = (data.metadata and data.metadata.column_spacing) or 3.0
    local row_spacing = (data.metadata and data.metadata.row_spacing) or 1.5

    local x_coords = energese.calculate_x_coordinates(data.nodes, tr_map, col_spacing)
    local y_coords = energese.calculate_vertical_positions(data.nodes, data.edges, tr_map, row_spacing)

    local node_map = {}
    for _, node in ipairs(data.nodes) do
        node_map[node.id] = node
    end

    tex.print("\\begin{tikzpicture}[" .. options .. "]")

    -- 1. Create nodes first (invisible but defined for coordinates)
    for _, node in ipairs(data.nodes) do
        local x = x_coords[node.id]
        local y = y_coords[node.id]
        local magnitude = node.magnitude or 1.0
        local style = string.format("energese %s, scale=%f, draw=none, fill=none", node.type, magnitude)
        tex.print(string.format("\\node[%s] (%s) at (%f, %f) {};", style, node.id, x, y))
    end

    -- 2. Render edges
    for _, edge in ipairs(data.edges) do
        local from = edge.from
        local to = edge.to
        local etype = edge.type
        local volume = edge.volume or 1.0

        local from_node = node_map[from]
        local to_node = node_map[to]

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

        if etype == "money_feedback" then
            from_anchor = "money_out"
            to_anchor = "money_in"
        elseif etype == "information" then
            to_anchor = "north"
        end

        -- Handle anchors if explicitly provided in edge
        if edge.from_anchor then from_anchor = edge.from_anchor end
        if edge.to_anchor then to_anchor = edge.to_anchor end

        local style = string.format("energese %s, line width=%fpt", etype, volume)
        local options = edge.options or ""
        local label_code = ""
        if edge.label then
            local lopts = edge.label_options or "midway, sloped, above, inner sep=2pt"
            label_code = string.format("node[%s] {%s}", lopts, edge.label)
        end

        tex.print(string.format("\\draw[%s] (%s.%s) to [%s] %s (%s.%s);",
            style, from, from_anchor, options, label_code, to, to_anchor))
    end

    -- 3. Render nodes properly (on top of edges)
    for _, node in ipairs(data.nodes) do
        local x = x_coords[node.id]
        local y = y_coords[node.id]
        local magnitude = node.magnitude or 1.0
        local label = node.label or ""
        local lopts = node.label_options or ""
        local style = string.format("energese %s, scale=%f", node.type, magnitude)
        tex.print(string.format("\\node[%s] (%s) at (%f, %f) %s {%s};", style, node.id, x, y, lopts ~= "" and "["..lopts.."]" or "", label))
    end

    -- Heat sinks
    if not data.metadata or data.metadata.show_heat_sink ~= false then
        local min_y = 1000
        local max_x = -1000
        local min_x = 1000
        for id, x in pairs(x_coords) do
            local y = y_coords[id]
            if y < min_y then min_y = y end
            if x > max_x then max_x = x end
            if x < min_x then min_x = x end
        end
        local floor_y = (data.metadata and data.metadata.heat_sink_y) or (min_y - row_spacing)

        tex.print(string.format("\\draw[thick] (%f, %f) -- (%f, %f);",
            min_x - 1.0, floor_y, max_x + 1.0, floor_y))

        for _, node in ipairs(data.nodes) do
            if node.type ~= "interaction" and node.type ~= "source" and node.type ~= "text" then
                tex.print(string.format("\\draw[energese heat] (%s.heat_sink) -- (%s.heat_sink |- 0,%f);",
                    node.id, node.id, floor_y))
            end
        end

        -- Ground symbol and label
        local ground_x = (min_x + max_x) / 2
        if data.metadata and data.metadata.ground_x then ground_x = data.metadata.ground_x end

        tex.print(string.format("\\node[inner sep=0pt, minimum size=0pt] (ground_point) at (%f, %f) {};", ground_x, floor_y))
        tex.print(string.format("\\draw[thick] (ground_point.center) -- ++(0, -0.3);"))
        tex.print(string.format("\\draw[thick] ([xshift=-0.2cm, yshift=-0.3cm]ground_point.center) -- ++(0.4, 0);"))
        tex.print(string.format("\\draw[thick] ([xshift=-0.1cm, yshift=-0.4cm]ground_point.center) -- ++(0.2, 0);"))
        tex.print(string.format("\\draw[thick] ([xshift=-0.05cm, yshift=-0.5cm]ground_point.center) -- ++(0.1, 0);"))

        local hs_label = (data.metadata and data.metadata.heat_sink_label) or "Environmental Floor"
        tex.print(string.format("\\node[anchor=west] at ([xshift=0.3cm, yshift=-0.3cm]ground_point.center) {%s};", hs_label))
    end

    -- System Boundary
    if data.metadata and data.metadata.system_boundary then
        local boundaries = data.metadata.system_boundary
        if boundaries == true then
            -- Auto-calculate boundary
            local min_x, max_x, min_y, max_y = 1000, -1000, 1000, -1000
            for _, node in ipairs(data.nodes) do
                local x, y = x_coords[node.id], y_coords[node.id]
                if x < min_x then min_x = x end
                if x > max_x then max_x = x end
                if y < min_y then min_y = y end
                if y > max_y then max_y = y end
            end
            boundaries = {{
                x_min = min_x - col_spacing/2,
                x_max = max_x + col_spacing/2,
                y_min = min_y - row_spacing,
                y_max = max_y + row_spacing
            }}
        elseif not boundaries[1] then
            boundaries = {boundaries}
        end

        for _, sb in ipairs(boundaries) do
            local style = sb.style or "thick"
            tex.print(string.format("\\draw[%s] (%f, %f) rectangle (%f, %f);",
                style, sb.x_min, sb.y_min, sb.x_max, sb.y_max))
            if sb.label then
                tex.print(string.format("\\node[anchor=north west] at (%f, %f) {%s};",
                    sb.x_min, sb.y_max, sb.label))
            end
        end
    end

    tex.print("\\end{tikzpicture}")
end

return energese
