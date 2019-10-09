local pl_template = require "pl.template"
local tx = require "pl.tablex"
local typedefs = require "kong.db.schema.typedefs"
local validate_header_name = require("kong.tools.utils").validate_header_name
local ngx_log = ngx.log
local DEBUG = ngx.DEBUG

-- TODO 
function serialize(o)
  if type(o) == 'table' then
     local s = '{ '
     for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. serialize(v) .. ','
     end
     return s .. '} '
  else
     return tostring(o)
  end
end

-- TODO NPE safe logger
local function log(char, v)
  if (v) then
    ngx_log(DEBUG, char..serialize(v))
  else
    ngx_log(DEBUG, char.." ended up null...")
  end
end

-- entries must have colons to set the key and value apart
local function check_for_value(entry)
  local name, value = entry:match("^([^:]+):*(.-)$")
  if not name or not value or value == "" then
    return false, "key '" ..name.. "' has no value"
  end

  local status, res, err = pcall(pl_template.compile, value)
  if not status or err then
    return false, "value '" .. value ..
            "' is not in supported format, error:" ..
            (status and res or err)
  end
  return true
end

-- Check existance via plaintext
-- 
-- Arguments:
--  @stringValue: String value to check
--  @subString: Sub-string to check existance of
-- Returns
--  Boolean
local function stringContains(stringValue, subString)
  if (stringValue and subString) then
    return string.find(stringValue, subString, 1, true) ~= nil
  end

  return false
end

local function validate_headers(pair, validate_value)
  local name, value = pair:match("^([^:]+):*(.-)$")
  if validate_header_name(name) == nil then
    return false, string.format("'%s' is not a valid header", tostring(name))
  end

  if validate_value then
    if validate_header_name(value) == nil then
      return nil, string.format("'%s' is not a valid header", tostring(value))
    end
  end
  return true
end


local function validate_colon_headers(pair)
  return validate_headers(pair, true)
end

local function validate_name(name, direction)
  if (name == "query") then
    return true
  elseif (name == "header") then
    return true
  elseif (name == "body") then
    return nil, "body is not supported"
  elseif (name == "jwt") then
    if (direction == "from") then
      return true
    else 
      return nil, string.format("jwt is not a permissable '%s' value", tostring(direction))
    end
  elseif (name == "url") then
    return nil, string.format("url is not a permissable '%s' value", tostring(direction))
  end
  else
    return nil, string.format("%s is not supported", tostring(name))
  end
end

local function validate_value(entry, direction)
  if (stringContains(entry, "[*]")) then
    return nil, "[*] is not a permissable value. This module does not handle arrays"
  end

  local top, rest = entry:match("^([^.]+)%.*(.-)$")
  local isValid, err
  
  if top then
    isValid, err = validate_name(top, direction)
  else 
    isValid, err = nil, string.format("Could not parse %s entry, did you miss a . ?", tostring(direction))
  end

  if rest then
    -- TODO, should validate?
  else
    isValid, err = nil, string.format("Could not parse %s entry, did you miss a . ?", tostring(direction))
  end
  
  return isValid, err
end

local function validate_from_value(entry)
  local isValid, err = validate_value(entry, "from")
  log("isValid from: ", isValid)
  log("err from: ", err)
  return isValid, err
end

local function validate_to_value(entry)
  local isValid, err = validate_value(entry, "to")
  log("isValid to: ", isValid)
  log("err to: ", err)
  return isValid, err
end

local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_headers },
}


local strings_array_record = {
  type = "record",
  fields = {
    { body = strings_array },
    { headers = headers_array },
    { querystring = strings_array },
  },
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = check_for_value }
}


local colon_header_value_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_headers },
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_header_value_array },
    { querystring = colon_strings_array },
  },
}

-- TODO TRT, IDK what's going on here, but these validators are failing like hot cakes
local transform_record = {
  type = "record",
  fields = {
    { from = { type = "string", custom_validator = validate_from_value }}, -- match = "^([^.]+)%.*(.-)$", custom_validator = validate_from_value }},
    { to = { type = "string", custom_validator = validate_to_value }}, -- match = "^([^.]+)%.*(.-)$",custom_validator = validate_to_value }},
  },
}

local transform_array = {
  type = "array",
  default = {},
  elements = transform_record,
}


local colon_headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local colon_rename_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_headers_array },
    { querystring = colon_strings_array },
  },
}


local colon_strings_array_record_plus_uri = tx.deepcopy(colon_strings_array_record)
local uri = { uri = { type = "string" } }
table.insert(colon_strings_array_record_plus_uri.fields, uri)


return {
  name = "argonath-request-transformer",
  fields = {
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { http_method = typedefs.http_method },
          { remove  = strings_array_record },
          { rename  = colon_rename_strings_array_record },
          { replace = colon_strings_array_record_plus_uri },
          { add     = colon_strings_array_record },
          { append  = colon_strings_array_record },
          { transform = transform_array }
        }
      },
    },
  }
}
