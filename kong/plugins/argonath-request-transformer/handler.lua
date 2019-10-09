local access = require "kong.plugins.argonath-request-transformer.access"


local ArgonathRequestTransformerHandler = {
  VERSION  = "0.1.0",
  PRIORITY = 801,
}


function ArgonathRequestTransformerHandler:access(conf)
  access.execute(conf)
end


return ArgonathRequestTransformerHandler
