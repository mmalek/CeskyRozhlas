
-------------------------------------------------------------------------------
-- Allows Squeezeplay players connected to MySqueezebox.com to play Polish
-- public radio streams
-------------------------------------------------------------------------------
-- Copyright 2012 Michal Malek <michalm@jabster.pl>
-------------------------------------------------------------------------------
-- This file is licensed under BSD. Please see the LICENSE file for details.
-------------------------------------------------------------------------------

-- stuff we use
local assert, ipairs, pairs, string, type, io = assert, ipairs, pairs, string, type, io

local oo                     = require("loop.simple")

local lxp                    = require("lxp")

local Applet                 = require("jive.Applet")
local SocketHttp             = require("jive.net.SocketHttp")
local RequestHttp            = require("jive.net.RequestHttp")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Window                 = require("jive.ui.Window")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Textarea               = require("jive.ui.Textarea")
local debug                  = require("jive.utils.debug")
local Player                 = require("jive.slim.Player")
local System                 = require("jive.System")

local appletManager          = appletManager
local jiveMain               = jiveMain
local jnt                    = jnt

local PODCAST_EXPORT_PREFIX="applets/CeskyRozhlas/"
local STATIONS_FILE = "stanice.xml" -- downloaded from "http://www.rozhlas.cz/podcast_export/stanice" and converted to UTF-8
local TEMATA_FILE = "temata.xml"    -- downloaded from "http://www.rozhlas.cz/podcast_export/temata" and converted to UTF-8

local PODCAST_HOST = "www2.rozhlas.cz"
local PODCAST_QUERY = "/podcast/podcast_porady.php?p_po="

local MEDIA_PREFIX = "http://media.rozhlas.cz/_audio"

local _streamCallback = function(event, menuItem)
	local player = Player:getLocalPlayer()
	local server = player:getSlimServer()
	server:userRequest(nil,	player:getId(), { "playlist", "play", menuItem.stream, menuItem.text })
	appletManager:callService('goNowPlaying', Window.transitionPushLeft, false)
end

local _streamContextMenuCallback = function(menuItem, applet)
	local player = Player:getLocalPlayer()
	local server = player:getSlimServer()
	server:userRequest(nil,	player:getId(), { "playlist", "add", menuItem.stream, menuItem.text })
end

module(..., Framework.constants)
oo.class(_M, Applet)

function show(self, menuItem)

	local player = Player:getLocalPlayer()
	self.server = player:getSlimServer()

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	
-- 	menu:setComparator(menu.itemComparatorAlpha)
	menu:addItem( {
		text = self:string('STATIONS'),
		callback = function(event,menuItem) self:showPodcastExport(menu, menuItem, STATIONS_FILE) end
	} )
	menu:addItem( {
		text = self:string('TOPICS'),
		callback = function(event,menuItem) self:showPodcastExport(menu, menuItem, TEMATA_FILE) end
	} )
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function showPodcastExport(self, previousMenu, menuItem, fileName)

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local newMenuItem, callbacks

	callbacks = {
		StartElement = function (parser, name, attr)
			if name == "item" then
				newMenuItem = { icon = Icon("icon") }
			elseif name == "title" then
				callbacks.CharacterData = function (parser, text)
					newMenuItem.text = text
				end
			elseif name == "export" then
				callbacks.CharacterData = function (parser, text)
					newMenuItem.callback = function(event,menuItem) self:showPodcastExportContent(menu, menuItem, text) end
				end
			elseif name == "img" then
				callbacks.CharacterData = function (parser, text)
					self.server:fetchArtwork( text, newMenuItem.icon, jiveMain:getSkinParam('THUMB_SIZE'), 'jpg' )
				end
			end
		end,
		EndElement = function (parser, name)
			callbacks.CharacterData = false
			if name == "item" then
				menu:addItem( newMenuItem )
			end
		end,
		CharacterData = false
	}

	local p = lxp.new(callbacks)

	local filePath = System:findFile( PODCAST_EXPORT_PREFIX .. fileName )
	local file, err = io.open( filePath )

	if file then

		for line in file:lines() do
			p:parse(line)
		end

	else
		log:warn( err )
		menu:setHeaderWidget( Textarea( "help_text", err ) )
	end

	self:tieAndShowWindow(window)
end


function showPodcastExportContent(self, previousMenu, menuItem, url)

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local newMenuItem, callbacks, insideRevHistory

	callbacks = {
		StartElement = function (parser, name, attr)
			if name == "audioobject" then
				newMenuItem = {
					callback = _streamCallback,
					cmCallback = function(event, menuItem) _streamContextMenuCallback(menuItem, self) end,
					style = 'item_choice'
				}
			elseif name == "audiodata" and attr.fileref then
				newMenuItem.stream = MEDIA_PREFIX .. '/' .. attr.fileref
			elseif name == "title" then
				callbacks.CharacterData = function (parser, text)
					if newMenuItem.text then
						newMenuItem.text = newMenuItem.text .. " " .. text
					else
						newMenuItem.text = text
					end
				end
			elseif name == "revhistory" then
				insideRevHistory = true
			elseif name == "date" and not insideRevHistory then
				callbacks.CharacterData = function (parser, text)
					if newMenuItem.text then
						newMenuItem.text = text .. " " .. newMenuItem.text
					else
						newMenuItem.text = text
					end
				end
			end
		end,
		EndElement = function (parser, name)
-- 			log:info( "endElement: " .. name )
			callbacks.CharacterData = false
			if name == "audioobject" then
				menu:addItem( newMenuItem )
			elseif name == "edition" then
				insideRevHistory = false
			end
		end,
		CharacterData = false
	}

	local p = lxp.new(callbacks)

	local canceled = false

	local function sink(chunk, err)
		if err then
			log:warn( err )
			menu:setHeaderWidget( Textarea( "help_text", self:string('HTTP_SINK_ERROR', url, err) ) )
			self:tieAndShowWindow(window)
			previousMenu:unlock()
		elseif chunk == nil then
			p:parse()
			p:close()
			if not canceled then
				self:tieAndShowWindow(window)
			end
			previousMenu:unlock()
		else
-- 			log:info("parsing chunk " .. chunk)
			p:parse(chunk)
		end
	end

	local req = RequestHttp(sink, 'GET', url )
	local http = SocketHttp(jnt, req:getURI().host, 80)

	-- lock the previous menu till we load the file
	previousMenu:lock( function()
		canceled = true
		http:close()
	end )

	-- go get it!
	http:fetch(req)

	return window
end
