
-------------------------------------------------------------------------------
-- Allows Squeezeplay players connected to MySqueezebox.com to play Polish
-- public radio streams
-------------------------------------------------------------------------------
-- Copyright 2012 Michal Malek <michalm@jabster.pl>
-------------------------------------------------------------------------------
-- This file is licensed under BSD. Please see the LICENSE file for details.
-------------------------------------------------------------------------------


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local Icon          = require("jive.ui.Icon")
local Surface       = require("jive.ui.Surface")
local math          = require("math")

local appletManager = appletManager
local jiveMain      = jiveMain

local jnt           = jnt

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end

function registerApplet(meta)
	jnt:subscribe(meta)

	local icon = Icon("icon")
	-- use the checkSkin function to load the icon image on first call
	local cs = icon.checkSkin
	icon.checkSkin = function(...)
		local prefSize = jiveMain:getSkinParam('THUMB_SIZE')
		local image = Surface:loadImage("applets/CeskyRozhlas/logo.png")
		local imageWidth,imageHeight = image:getSize()
		local shrinkFactor = math.max(imageWidth,imageHeight) / prefSize
		image = image:shrink(shrinkFactor, shrinkFactor)
		icon:setValue(image)
		cs(...)
		-- replace with original
		icon.checkSkin = cs
	end
	meta.menu = meta:menuItem('CeskyRozhlas', 'extras', 'Český rozhlas',
			function(applet, ...) applet:show(...) end, nil, { icon = icon } )
	jiveMain:addItem(meta.menu)
end
