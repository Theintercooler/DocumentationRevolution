# Document Revolution
Document Revolution is a documentation generator for the lua language.
In your code you may use comment tags like this:
```lua
--[[!
    This function does absolutely nothing.
    Some more description follows the title,
    And can span multiple lines.
    
    @method
    @param name number
    @todo It may could do something
]]

function Object:nothing(name)
    --....
end
```

Then you can generate the docs using the command: `luvit init.lua path/to/dir/or/file`
It will then automatically create an out directory for the markdown to be stored in.
You could also run the command like this: `luvit ../path/to/init.lua lib/` to choose where to create the out directory.
