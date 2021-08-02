--[[
TXBattMan lua app for Jeti DS-12, DS/DC-16 II, DS/DC-24 transmitters

MIT License

Copyright (c) 2021 temorostyx

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

-- declarations
local appName, appVersion, appAuthor = "TXBattMan", "1.2", "Morote"
local voltage, capacity, capacity_relative, capacity_used, capacity_nominal, current, startup_counter = 0, 0, 0, 0, 9999, 0, 100
local runtime_remaining, runtime_remaining_h, runtime_remaining_min, runtime_remaining_min_string, runtime_remaining_string = 0, 0, 0, "", ""
local alarm_audio, alarm_vibrate, audio_switch, audio_switch_state, temp,data, alarm_state, alarm_threshold, value, componentIndex, config, file, json_table, json_text, locale, dic, font_size, pos_x, pos_y
local audio_triggered, settings_changed = false, false
local current_avg1, current_avg0, avg_n0, avg_n1 = 0, 0, 1, 1

-- read translations
local function get_translations()
	locale =  system.getLocale()
	dic = json.decode(io.readall("Apps/TXBattMan/locale.jsn"))
	if dic[locale] == nil then
		locale = "en"
		dic = json.decode(io.readall("Apps/TXBattMan/locale.jsn"))
	end
end

-- load global settings from config.jsn
local function load_config()
	file = io.readall("Apps/TXBattMan/config.jsn")	
	config = json.decode(file)
	capacity_nominal = config[1]["capacity_nominal"]
	alarm_threshold = config[2]["alarm_threshold"]
	alarm_audio = config[3]["alarm_audio"]
	alarm_vibrate = config[4]["alarm_vibrate"]
end

-- write global settings to config.jsn
local function write_config()
	if settings_changed == true then -- check if changes have been made to global settings
		json_table = {{capacity_nominal = capacity_nominal},
					{alarm_threshold = alarm_threshold},
					{alarm_audio = tostring(alarm_audio)},
	   			    {alarm_vibrate = alarm_vibrate}
				    }
		json_text = json.encode(json_table)
		file = io.open("Apps/TXBattMan/config.jsn", "w")
		io.write(file, json_text)
		io.close(file)
		settings_changed = false --changes have been applied, reset state flag
		load_config() -- refresh global settings
	end
end

-- returns current state of a switch
local function get_switch_state(value)
	value = system.getInputsVal(value)
	if (value) then return value end
end

-- save audio_switch to model configuration
local function audio_switch_changed(value)
    audio_switch = value
    system.pSave("audio_switch", value)
end

-- define functions of bottom line buttons
local function keyPressed(key)
	if key == KEY_1 then -- go to/refresh status page
		form.reinit(1)
	elseif (key == KEY_2 and formID ~= 2) then	-- go to settings page
		form.reinit(2)
	end
end

-- returns a number rounded to a defined amount of decimals
local function round(value, decimals)
	local mult = 10^(decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

-- print dialog box for "low TX battery" warning
local function print_alarm_dialogue()
	system.messageBox(dic[locale]["alarm_text"], 5)
end

-- activate vibration warning
local function vibrate()
	system.vibration(true, 3)
	system.vibration(not true, 3);
end

-- raise audio warning
local function play_alarm_audio(value)
	system.playFile(value, AUDIO_IMMEDIATE)
end

-- actualize capacity_nominal upon user input
local function actualize_capacity_nominal(value)
	settings_changed = true
	capacity_nominal = value
end
  
-- actualize alarm_threshold upon user input
local function actualize_alarm_threshold(value)
	settings_changed = true
	alarm_threshold = value
end

-- actualize alarm_audio upon user input
local function actualize_audio_file(value)
	settings_changed = true
	alarm_audio = value
end

-- actualize alarm_vibrate upon user input
local function actualize_alarm_vibrate(value)
	settings_changed = true
	alarm_vibrate = not value
	form.setValue(componentIndex, alarm_vibrate)
end

-- draw telemetry window
local function printWindow(width, height)
	if height == 30 then -- settings for position beneath battery symbol
		if string.sub(runtime_remaining_string, -1) == "-" then pos_x = 31
		elseif string.sub(runtime_remaining_string, -1) == "h" then
			if runtime_remaining_string:sub(4, 4) == ":" then pos_x = 15
			elseif runtime_remaining_string:sub(3, 3) == ":" then pos_x = 23
			else pos_x = 31
			end
		else pos_x = 5 end
		pos_y = 5
		font_size = FONT_BOLD
	elseif height == 24 then -- settings for small telemetry window
		pos_x = 7
		pos_y = 2
		font_size = FONT_NORMAL
	else -- settings for large telemetry window
		pos_x = 7
		pos_y = 12
		font_size = FONT_MAXI
	end
	lcd.drawText(pos_x, pos_y, runtime_remaining_string, font_size)
end

-- draw status page
local function draw_status_page()
	form.addLabel({label = dic[locale]["actual_values"], font = FONT_BOLD})
	form.addLabel({label = dic[locale]["capacity"] .. tostring((math.floor(capacity))) .. " mAh" .. " (" .. tostring(capacity_relative) .. " %)"})
	form.addLabel({label = tostring(voltage) .. " V @ " .. tostring(current) .. " mA"})
	if current_avg1 < 0 then form.addLabel({label = dic[locale]["charging"], font = FONT_BOLD})
	else form.addLabel({label = dic[locale]["estimated_remaining_runtime"] .. runtime_remaining_string, font = FONT_BOLD}) end
end

-- draw settings page
local function draw_settings_page()
	form.addLabel({label = dic[locale]["settings"], font = FONT_BOLD})
	form.addRow(2)
	form.addLabel({label = dic[locale]["capacity_in_mAh"]})
	form.addIntbox(capacity_nominal, 100, 9900, 6200, 0, 10, actualize_capacity_nominal)
	form.addLabel({label = dic[locale]["reference"], font = FONT_MINI})
	form.addRow(2)
	form.addLabel({label = dic[locale]["runtime_alarm"]})
	form.addIntbox(alarm_threshold, 0, 180, 60, 0, 1, actualize_alarm_threshold)
	form.addRow(2)
 	form.addLabel({label = dic[locale]["select_audio_file"]})
	form.addAudioFilebox(alarm_audio or "", actualize_audio_file)
	form.addRow(2)
	form.addLabel({label = dic[locale]["use_vibration"], width = 275})
	if (alarm_vibrate == true) then componentIndex = form.addCheckbox(true, actualize_alarm_vibrate)
	else componentIndex = form.addCheckbox(false, actualize_alarm_vibrate) end
	form.addRow(2)
	form.addLabel({label = dic[locale]["voice_output"]})
    form.addInputbox(audio_switch, false, audio_switch_changed)
end

local function initForm(subform)
	form.setButton(1 ,":refresh", ENABLED)
	form.setButton(2, ":tools", subform == 2 and HIGHLIGHTED or ENABLED)
	formID = subform
	if (subform == 1) then draw_status_page() -- call draw_status_page function
  	elseif (subform == 2) then draw_settings_page() end -- call draw_settings_page function
end

-- initialize app
local function init()
	get_translations() -- get system language
	load_config() -- load configuration from config.jsn (global)
	alarm_state = 0 -- reset alarm_state
	form.setValue(componentIndex, alarm_vibrate) -- set state (global)
	audio_switch = system.pLoad("audio_switch") -- set state (model specific)
	system.registerForm(1, MENU_APPS, appName, initForm, keyPressed, printForm) -- register form
	system.registerTelemetry(2, dic[locale]["remaining_TX_runtime"], 0, printWindow) -- register telemetry window
end

-- runtime functions
local function loop()
	write_config() -- actualize settings in config.jsn (if necessary)

	data = system.getTxTelemetry() -- get TX battery status
	voltage = data.txVoltage -- in V
	capacity_relative = data.txBattPercent -- in %
	capacity = capacity_nominal * (capacity_relative / 100) -- in mAh
	current = data.txCurrent -- in mA
	-- current = current - 500 -- for testing & debugging with the emulator [state "charging"]
	--current = current + 500 -- for testing & debugging with the emulator [state "draining battery"]
	current_avg1 = (current_avg0 * (avg_n0 / avg_n1)) + (current / avg_n1)
    avg_n0 = avg_n1
    avg_n1 = avg_n1 + 1
    current_avg0 = current_avg1

	if startup_counter > 0 then startup_counter = startup_counter - 1 end

	if current_avg1 == 0 then runtime_remaining_string = "--:--" -- no current
	
	elseif startup_counter > 0 then runtime_remaining_string = dic[locale]["starting"] -- swing-in phase
	
	elseif current_avg1 < 0 then runtime_remaining_string = dic[locale]["charge"] -- charging battery
		
	else -- draining battery
		runtime_remaining = capacity / current_avg1 -- in h
	  	runtime_remaining_h = math.floor(capacity / current_avg1) -- in h
	  	runtime_remaining_min = math.floor(((runtime_remaining - runtime_remaining_h) * 60) / 1) -- in min
  
		if runtime_remaining_min < 10 then runtime_remaining_min_string = "0" .. tostring(runtime_remaining_min)
		else runtime_remaining_min_string = tostring(runtime_remaining_min) end
  
		runtime_remaining_string = tostring(runtime_remaining_h) .. ":" .. runtime_remaining_min_string .. " h"

		if string.len(runtime_remaining_string) > 8 then runtime_remaining_string = dic[locale]["eternal"] end
	end

	if (alarm_threshold > 0 and alarm_state == 0 and current_avg1 > 0 and startup_counter <= 0) then -- check if preconditions met (alarm enabled and not yet triggered while TX draining battery)
			if runtime_remaining < (alarm_threshold / 60) then -- check if remaining runtime below threshold 
				alarm_state = 1
				print_alarm_dialogue()
				if alarm_vibrate == true then vibrate() end -- raise vibration if enabled
				if alarm_audio then play_alarm_audio(alarm_audio, AUDIO_QUEUE) end -- play audio file if assigned
			end
	end

	audio_switch_state = get_switch_state(audio_switch)
	
	if audio_switch_state == 1 then
		if (audio_triggered == false and current_avg1 > 0) then
			system.playNumber(runtime_remaining_h, 0, "h")
			system.playNumber(runtime_remaining_min, 0, "min")
			audio_triggered = true
		end
	else audio_triggered = false
	end

end

-- return
collectgarbage()
return {init = init, loop = loop, author = appAuthor, version = appVersion, name = appName}