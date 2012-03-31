
-------------------------------------------------------------------------------
-- Allows Squeezeplay players connected to MySqueezebox.com to play Polish
-- public radio streams
-------------------------------------------------------------------------------
-- Copyright 2012 Michal Malek <michalm@jabster.pl>
-------------------------------------------------------------------------------
-- This file is licensed under BSD. Please see the LICENSE file for details.
-------------------------------------------------------------------------------

-- stuff we use
local assert, ipairs, pairs, string, table, type, io = assert, ipairs, pairs, string, table, type, io

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
local datetime               = require("jive.utils.datetime")
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
	
	self:showPodcastExport(menu, STATIONS_FILE)
	self:showPodcastExport(menu, TEMATA_FILE)
	
	window:addWidget(menu)
	self:tieAndShowWindow(window)
	return window
end

function showPodcastExport(self, menu, fileName)

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
end


function showPodcastExportContent(self, previousMenu, menuItem, url)

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local newMenuItem, callbacks, insideRevHistory
	local dateMenuItems = {}

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
					local b, e, day, month, year, hours, minutes = string.find( text, "(%d+)%.(%d+)%.(%d+) (%d+)%:(%d+)" )
					if day and month and year and hours and minutes then
						newMenuItem.date = { day = day, month = month, year = year }
						newMenuItem.formattedDate = datetime:getShortDateFormat()
						newMenuItem.formattedDate = string.gsub( newMenuItem.formattedDate, "%%d", day )
						newMenuItem.formattedDate = string.gsub( newMenuItem.formattedDate, "%%m", month )
						newMenuItem.formattedDate = string.gsub( newMenuItem.formattedDate, "%%Y", year )

						newMenuItem.time = string.format("%02d:%02d", hours, minutes)
					end
				end
			end
		end,
		EndElement = function (parser, name)
			callbacks.CharacterData = false
			if name == "audioobject" then
				if newMenuItem.time then
					if newMenuItem.text then
						newMenuItem.text = newMenuItem.time .. " " .. newMenuItem.text
					else
						newMenuItem.text = newMenuItem.time
					end
				end

				if newMenuItem.formattedDate then
					local items = dateMenuItems[newMenuItem.formattedDate]
					if items == nil then
						items = {}
					end
					items[#items + 1] = newMenuItem
					items.date = newMenuItem.date
					items.formattedDate = newMenuItem.formattedDate
					dateMenuItems[newMenuItem.formattedDate] = items
				end
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
				for key, item in pairs(dateMenuItems) do
					menu:addItem( {
						text = item.formattedDate,
						date = item.date,
						callback = function(event,menuItem) self:showPodcastItems(menuItem,item) end
					} )
				end
				menu:setComparator( function(a, b)
					return a.date.year > b.date.year or
						a.date.month > b.date.month or
						a.date.day > b.date.day
				end )
				self:tieAndShowWindow(window)
			end
			previousMenu:unlock()
		else
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

function showPodcastItems(self, menuItem, subItems)

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	menu:setComparator(menu.itemComparatorAlpha)
	menu:setItems(subItems)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end
