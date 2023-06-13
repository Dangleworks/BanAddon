-- Here be the few config options, make sure they line up with your BanDB config.json
port = 9007
server_name = "Server"
password = "ChangeMeFuckBoi"
steam_ids = {}
peer_ids = {}
tick = 0
debug = false
in_jail = {} -- List of peer_ids to be teleported every tick to the jail

function onCreate(is_world_create)
	server.command("ident")
	for _, player in pairs(server.getPlayers()) do
		if player.id == 0 then return end
		steam_ids[player.id] = tostring(player.steam_id)
		peer_ids[tostring(player.steam_id)] = player.id
	end
end

function onPlayerJoin(steam_id, name, peer_id, admin, auth)
	if peer_id == 0 then return end
	steam_ids[peer_id] = tostring(steam_id)
	peer_ids[tostring(steam_id)] = peer_id
	server.httpGet(port, "/check?steam_id=" .. steam_id .. "&p=" .. password)
end

function onPlayerLeave(steam_id, name, peer_id, is_admin, is_auth)
	if peer_id == 0 then return end
	steam_ids[peer_id] = nil
	peer_ids[tostring(steam_id)] = nil
end

function onTick()
	tick = tick + 1
	if tick % 60 == 0 then
		tick = 0
		local players = ""
		for _, player in pairs(server.getPlayers()) do
			if player.id == 0 then return end
			players = players .. player.steam_id .. ","
		end
		players = string.sub(players, 1, (#players - 1))
		server.httpGet(port, "/checkall?ids=" .. players .. "&p=" .. password)
	end

	for i,e in pairs(in_jail) do
		if not e.perm_removed then
			server.removeAuth(i)
			server.removeAdmin(i)
			e.perm_removed = true
		end
		server.setPlayerPos(i, matrix.translation(10000000 * (i + 1), 10, 10000000 * (i + 1)))
		server.setPopupScreen(i, e.ui_id, "Banned", true, "You have been banned: " .. e.reason, 0, 0)
		e.tick = e.tick + 1
		if debug then server.announce("test", e.tick) end
		if e.tick > 60*10 then
			if debug then server.announce("at this point we'd kick the player", "test") end
			server.kickPlayer(i)
			in_jail[i] = nil
		end
	end
end

function httpReply(rport, request, reply)
	if rport ~= port then return end
	if string.starts(request, "/ban") then
		local data = json.parse(reply)
	end
	if string.starts(request, "/check?") then
		local data = json.parse(reply)
		if data.status and not in_jail[peer_ids[tostring(data.steam_id)]] then
			mapid = server.getMapID()
			in_jail[peer_ids[tostring(data.steam_id)]] = { reason = data.reason, ui_id = mapid, tick = 0, perm_removed = false}
		end
	end
	if string.starts(request, "/checkall?") then
		if debug then server.announce("[Admin]", "Checking all players") end
		local data = json.parse(reply)
		if debug then server.announce("[Admin]", reply) end
		if data == nil then return end
		if data.status then
			for _, entry in pairs(data.bans) do
				if not in_jail[peer_ids[tostring(entry.steam_id)]] then
					mapid = server.getMapID()
					in_jail[peer_ids[tostring(entry.steam_id)]] = { reason = entry.reason, ui_id = mapid, tick = 0, perm_removed = false}
				end
			end
		end
	end
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, ...)
	local args = { ... }
	if command == "identresp" and user_peer_id == -1 then -- This is a response to the ident from and identity provider
		local ident = ""
		for i,v in ipairs(args) do
			ident = ident .. v .. " "
		end
		ident = string.sub(ident, 1, -2) -- remove the last space
		server_name = ident
	end
	if not is_admin then return end
	if command == "?b" then
		local _, exists = server.getPlayerName(tonumber(args[1]))
		if not exists then
			server.announce("[Admin]", "Player does not exist!", user_peer_id)
			return
		end
		server.httpGet(port, "/ban?steam_id=" .. tostring(steam_ids[tonumber(args[1])]) ..
			"&reason=" .. encode(slice(args, 2)) ..
			"&moderator=" .. encode(server.getPlayerName(user_peer_id)) ..
			"&banned_from=" .. encode(server_name) ..
			"&username=" .. encode(server.getPlayerName(tonumber(args[1]))) .. 
			"&p=" .. password)
		server.announce("[Admin]", "Trying to ban peer ID " .. args[1])
	end
end

-- Internal functions.

function encode(str)
	if str == nil then
		return ""
	end
	str = string.gsub(str, "([^%w _ %- . ~])", cth)
	str = str:gsub(" ", "%%20")
	return str
end

function cth(c)
	return string.format("%%%02X", string.byte(c))
end

function slice(T, start, stop)
	local result = ""
	if stop == nil then
		stop = #T
	end
	local i = start
	while i <= stop do
		result = result .. T[i] .. " "
		i = i + 1
	end
	return result
end

function string.starts(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end



json = {}

local function kind_of(obj)
	if type(obj) ~= 'table' then return type(obj) end
	local i = 1
	for _ in pairs(obj) do
		if obj[i] ~= nil then
			i = i + 1
		else
			return 'table'
		end
	end
	if i == 1 then
		return 'table'
	else
		return 'array'
	end
end

local function escape_str(s)
	local in_char = { '\\', '"', '/', '\b', '\f', '\n', '\r', '\t' }
	local out_char = { '\\', '"', '/', 'b', 'f', 'n', 'r', 't' }
	for i, c in ipairs(in_char) do s = s:gsub(c, '\\' .. out_char[i]) end
	return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;	 did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
	pos = pos + #str:match('^%s*', pos)
	if str:sub(pos, pos) ~= delim then
		if err_if_missing then return nil end
		return pos, false
	end
	return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
	val = val or ''
	local early_end_error = 'End of input found while parsing string.'
	if pos > #str then return nil end
	local c = str:sub(pos, pos)
	if c == '"' then return val, pos + 1 end
	if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
	-- We must have a \ character.
	local esc_map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
	local nextc = str:sub(pos + 1, pos + 1)
	if not nextc then return nil end
	return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
	local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
	local val = tonumber(num_str)
	if not val then return nil end
	return val, pos + #num_str
end

-- Public values and functions.

function json.stringify(obj, as_key)
	local s = {}           -- We'll build the string as an array of strings to be concatenated.
	local kind = kind_of(obj) -- This is 'array' if it's an array or type(obj) otherwise.
	if kind == "array" then
		if as_key then return nil end
		s[#s + 1] = "["
		for i, val in ipairs(obj) do
			if i > 1 then s[#s + 1] = ", " end
			s[#s + 1] = json.stringify(val)
		end
		s[#s + 1] = "]"
	elseif kind == "table" then
		if as_key then return nil end
		s[#s + 1] = "{"
		for k, v in pairs(obj) do
			if #s > 1 then s[#s + 1] = ", " end
			s[#s + 1] = json.stringify(k, true)
			s[#s + 1] = ":"
			s[#s + 1] = json.stringify(v)
		end
		s[#s + 1] = "}"
	elseif kind == "string" then
		return '"' .. escape_str(obj) .. '"'
	elseif kind == "number" then
		if as_key then return '"' .. tostring(obj) .. '"' end
		return tostring(obj)
	elseif kind == "boolean" then
		return tostring(obj)
	elseif kind == "nil" then
		return "null"
	else
		return nil
	end
	return table.concat(s)
end

json.null = {} -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
	pos = pos or 1
	if pos > #str then return nil end
	local pos = pos + #str:match("^%s*", pos) -- Skip whitespace.
	local first = str:sub(pos, pos)
	if first == "{" then                   -- Parse an object.
		local obj, key, delim_found = {}, true, true
		pos = pos + 1
		while true do
			key, pos = json.parse(str, pos, "}")
			if key == nil then return obj, pos end
			if not delim_found then return nil end
			pos = skip_delim(str, pos, ":", true) -- true -> error if missing.
			obj[key], pos = json.parse(str, pos)
			pos, delim_found = skip_delim(str, pos, ",")
		end
	elseif first == "[" then -- Parse an array.
		local arr, val, delim_found = {}, true, true
		pos = pos + 1
		while true do
			val, pos = json.parse(str, pos, "]")
			if val == nil then return arr, pos end
			if not delim_found then return nil end
			arr[#arr + 1] = val
			pos, delim_found = skip_delim(str, pos, ",")
		end
	elseif first == '"' then                   -- Parse a string.
		return parse_str_val(str, pos + 1)
	elseif first == "-" or first:match("%d") then -- Parse a number.
		return parse_num_val(str, pos)
	elseif first == end_delim then             -- End of an object or array.
		return nil, pos + 1
	else                                       -- Parse true, false, or null.
		local literals = {
			["true"] = true,
			["false"] = false,
			["null"] = json.null
		}
		for lit_str, lit_val in pairs(literals) do
			local lit_end = pos + #lit_str - 1
			if str:sub(pos, lit_end) == lit_str then
				return lit_val, lit_end + 1
			end
		end
		local pos_info_str = "position " .. pos .. ": " .. str:sub(pos, pos + 10)
		return nil
	end
end
