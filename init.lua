local directory = process.argv[1]
local string = require "string"
local table = require "table"
local utils = require "utils"

local core = require('core')

if not directory then
	print("Usage: <command> <directory name>")
	return
end

directory = directory:gsub("/$", ""	)

local fs = require "fs"

function string.split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find (fpat, 1)
	
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t, cap)
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

function string.trim (s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end


local function mkdir(file)
	local dir = file:split("/")
	
	local path = ""
	for i, d in pairs(dir) do
		path = path .. d.."/"
		if not fs.existsSync(path) then
			fs.mkdirSync(path, "777")
		end
	end
end

local Block = core.Object:extend()

function Block:initialize(type)
	self._subBlocks = {}

	self.tags = {}
	self.codeLines = {""}

	self.type = type or ""	
	self.name = ""
	self.title = ""
	self.description = ""
	self.parent = ""
	self.file = ""
end

function Block:addSubBlock(block)
	table.insert(self._subBlocks, block)
end

function Block:getSubBlocks()
	return self._subBlocks
end

function Block:loopAll(cb, depth)
	depth = depth or 0
	
	for i, row in pairs(self._subBlocks) do
		cb(row, depth)
		row:loopAll(cb, depth + 1)
	end
end

local function runFile(file, callback)
	if file:match(".lua$") then
		local niceName = file:gsub(directory, "out")
		local fileName = file:gsub(directory, "")
		
		mkdir(niceName:gsub("(.*)/(.-)$", function(a) return a end))
				
		fs.readFile(file, function (err, data)
				if err then
					print (("Could not open file for reading comments: %s"):format(file))
					return
				end
				
				local function isComment(line)
					return string.find(line, "^[\t ]*%-%-%[%[%!")
				end
				
				local function isCommentEnd(line)
					return string.find(line, "^[\t ]*]]")
				end
				
				local lines = data:split("\n")

				--File block
				local block = Block:new("file")
				block.file = fileName
				local i = 1
				
				repeat
					local codeBlock = Block:new()
					codeBlock.file = fileName
					--Make sure we start on the first commented line
					while lines[i] and not isComment(lines[i]) do
						i = i + 1
					end
					
					local startI = i
					
					i = i + 1 -- skip --[[!
					
					while lines[i] and not isCommentEnd(lines[i]) do
						if codeBlock.comment then
							codeBlock.comment = codeBlock.comment .. "\n" .. lines[i]
						else
							codeBlock.comment = lines[i]
						end

						i = i + 1
					end
					
					if codeBlock.comment then
					
						--Parse comments
						local commentLines = string.split(codeBlock.comment, "\n")
						local haveTitle = false
						for i, commentRow in pairs(commentLines) do
							commentRow = commentRow:gsub("^[\t ]*", "")

							if commentRow:find("^@(.*)") then
								local tag, value, _
							
								if commentRow:find("^@(.-) (.*)") then
									_, _, tag, value = commentRow:find("^@(.-) (.*)")
								else
									_, _, tag = commentRow:find("^@(.*)")
								end
							
								if not value then
									value = ""
								end
							
								tag = tag:lower()
								value = value:trim()
							
								--Manual overrides	
								if tag == "name" then
									codeBlock.name = value
								elseif tag == "title" then
									codeBlock.title = value
								elseif tag == "descriptionclear" then
									codeBlock.description = ""
								elseif tag == "description" then
									codeBlock.description = codeBlock.description .. value
							
								--type tags (Auto resolve)
								elseif tag == "file" then
									--File type: a lua file without a module
									codeBlock.type = "file"
									if value ~= "" then
										codeBlock.name = value
										codeBlock.file = value
									else
										codeBlock.name = block.file
									end
								elseif tag == "module" then
									codeBlock.type = "module"
									if value ~= "" then
										codeBlock.module = value
										codeBlock.name = value
									end
								elseif tag == "class" then
									codeBlock.type = "class"
									if value ~= "" then
										codeBlock.module = value
										codeBlock.name = value
									end								
								elseif tag == "function" then
									codeBlock.type = "function"
									if value ~= "" then
										codeBlock.name = value
									end
								elseif tag == "method" then
									codeBlock.type = "method"
									if value ~= "" then
										codeBlock.name = value
									end
								else
									commentRow = nil --Remove line
									codeBlock.tags[tag] = value --Todo: check for multiple of the same type
								end
							elseif not haveTitle then
								haveTitle = true
								codeBlock.title = commentRow
							else
								codeBlock.description = codeBlock.description .. commentRow .."\n"
							end
						end
					
						--Skip ]]
						i = i + 1
					end
					
					while lines[i] and not isComment(lines[i]) do
						if codeBlock.code then
							codeBlock.code = codeBlock.code .. "\n" .. lines[i]
						else
							codeBlock.code = lines[i]
						end
						
						i = i + 1
					end
					
					if codeBlock.code then
						--Nothing to do
						if codeBlock.type == "file" then
							codeBlock.code = ""
						end
					
						if codeBlock.type == "" then
							print (("Warning: No type was given for comment block in %s:%i"):format(file, startI))
						end
					
						local codeLines = codeBlock.code:split("\n")
						codeBlock.codeLines = {}
					
						for i, row in pairs(codeLines) do
							row = row:trim()
						
							if row ~= "" then
								table.insert(codeBlock.codeLines, row)
								local doBreak = false
								if codeBlock.type == "class" then
									row:gsub("(.-) = (.*):extend()", function(name, parent)
										name = name:gsub("^local ", ""):gsub("^module%.", "")
									
										if codeBlock.name == "" then
											codeBlock.name = name
										end
									
										if codeBlock.parent == "" then
											codeBlock.parent = parent
										end
									
										doBreak = true
									end)
								elseif codeBlock.type == "method" then
									row:gsub("function (.-):(.-)%((.*)%)", function(class, name, args)

										if codeBlock.name == "" then
											codeBlock.name = name
										end

										if codeBlock.parent == "" then
											codeBlock.parent = class
										end
									
										codeBlock.args = args
										doBreak = true
									end)
								elseif i < 10 then
									p("CODE", codeBlock.type, codeBlock.title, row)
								end
							
								if doBreak then
									break
								end
							end
						end
					end
					
					--Set main block
					if codeBlock.type == "file" or codeBlock.type == "module" then
						block:loopAll(function(row)
							print(("WARNING: %s will be ignored, perhaps a late @module or @file declaration?"):format(row.name))
						end)
						
						block = codeBlock
					elseif codeBlock.parent and codeBlock.parent ~= "" then
						local found = false
						block:loopAll(function(row)
							if row.name == codeBlock.parent then
								row:addSubBlock(codeBlock)
								found = true
							end
						end)
						
						if not found then
							print (("Could not find parent: %s"):format(codeBlock.parent))
							block:addSubBlock(codeBlock)
						end
					elseif codeBlock.name ~= "" then
						block:addSubBlock(codeBlock)
					else
						print(("Warning: no code blocks detected in file: %s"):format(file))
					end
				until i >= #lines
				
				local title = "File "..block.file
				
				if block.type == "module" then
					title = "Module "..block.name
				end
				
				local str = "# "..title .. "\n"
				
				if block.title ~= "" then
					str = str .. "**" .. block.title .. "**\n"
					str = str .. block.description .. "\n"
				end

				--Parse blocks
				--TODO: recursion!
				block:loopAll(function(row, depth)
					str = str .. ("#"):rep(depth+2)..row.name .. "\n"
					
					if row.title ~= "" then
						str = str .. "**"..row.title.."**\n"
						str = str .. row.description .. "\n"
						str = str .. "```lua\n" .. row.codeLines[1] .. "\n```\n\n"
					end
				end)
				
				fs.writeFile(niceName, str, function(err)
					if err then
						print (("Could not write to file: %s (%s)"):format(niceName, err.message))
						return
					end
				end)
		end)	
		
	end
end

local function runDir(directory, cb)
	fs.readdir(directory, function (err, files)
		if err then
			--Try if it's a file
			runFile(directory)
			return
		end
		
		for i, dir in pairs(files) do
			runDir(directory.."/"..dir, function() end)
		end
		
		cb()
	end)
end

runDir(directory, function()

end)
