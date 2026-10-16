-- busted loads one output handler. This one prints the usual terminal output
-- and writes JUnit to the file given with -Xoutput.
return function(options)
  require("busted.outputHandlers.junit")(options):subscribe(options)
  -- the terminal handler rejects the arguments of the JUnit handler
  local terminal_options = setmetatable({ arguments = {} }, { __index = options })
  return require("busted.outputHandlers.utfTerminal")(terminal_options)
end
