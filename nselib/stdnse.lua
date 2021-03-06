local _G = require "_G"

local table = require "table"

local setmetatable = setmetatable

local getmetatable = getmetatable

local pack = table.pack

local io = require "io"


_ENV = require "strict" {};


function module(name, ...)
	local env = {};
	env._NAME = name;
	env._PACKAGE = name:match("(.+)%.[^.]+$");
	env.M = env;
	local mods = pack(...);
	for i=1, mods.n do
		mods[i](env)
	end
	return env;
end


function seeall(env)
	local m = getmetatable(env) or {};
	m.__index = _G;
	setmetatable(env, m)
end

function serialize(obj)
	local lua = ""
	local t = io.type(obj)

	if t == "number" then
		lua = lua .. obj
		
	elseif t == "boolean" then
		lua = lua .. tostring(obj)
	
	elseif t == "string" then
		lua = lua .. string.format("%q", obj)

	elseif t == "table" then
		lua = lua .. "{\n"
		for k,v in pairs(obj) do
			lua = lua .. " [" .. serialize(k) .. "]=" .. serialize(v) .. ",\n"
		end

		local metatable = getmetatable(obj)
			if metatable ~= nil and type(metatable.__index) == "table" then
				for k,v in pairs(metatable.__index) do
					lua = lua .. " [" .. serialize(k) .. "]" .. serialize(v) .. ",\n"
				end
			end

		lua = lua .. "}"	
	
	elseif t == "nil" then
		return nil
	else
		--io.print("can not serialize")
	end
	
	return lua
end	


return _ENV
