nconf = require("nconf")
btoa = require("btoa")

triggers = require './data/triggers.json'

cwd = process.cwd()
DEFAULTS_FILE = "#{__dirname}/data/defaults.json"

nconf.argv()
    .env()
    .file('defaults', DEFAULTS_FILE)

search = (msg, query, text) ->


  num_results = nconf.get("HUBOT_CONFLUENCE_NUM_RESULTS") or 1
  space = nconf.get("HUBOT_CONFLUENCE_SEARCH_SPACE")
  if text
    text_search = "text~\"#{query}\""
  else
    text_search = "title~\"#{query}\""

  query_str = encodeURIComponent("type=page and space=#{space} and #{text_search}")
  suffix = "/content/search?cql=#{query_str}"
  url = make_url(suffix, true)
  headers = make_headers()

  msg.http(url).headers(headers).get() (e, res, body) -> 
    if e
      msg.send "Error: #{e}"
      return

    content = JSON.parse(body)
    
    if !content.results or content.results.length == 0
      #Fall back to text search
      if !text
        search(msg, query, true)
        return
      else
        msg.send "No results found"
        return

    count = 0
    for result in content.results
      count += 1
      if count > num_results
        break
      link = make_url(result._links.webui, false)
      msg.send "#{result.title} - #{link}"
    
make_headers = ->

  user = nconf.get("HUBOT_CONFLUENCE_USER")
  password = nconf.get("HUBOT_CONFLUENCE_PASSWORD")

  auth = btoa("#{user}:#{password}")

  ret = 
    Accept: "application/json"
    Authorization: "Basic #{auth}"


make_url = (suffix, api) -> 
    host = nconf.get("HUBOT_CONFLUENCE_HOST")  
    port = nconf.get("HUBOT_CONFLUENCE_PORT")  

    url = "https://#{host}:#{port}/wiki"
    if api
      url = "#{url}/rest/api#{suffix}"
    else
      url = "#{url}#{suffix}"
   
help = (msg) ->
  commands = [
    "confluence show triggers"
    "confluence help"
    "confluence search SEARCH PHRASE"
  ]
  buf = ""
  for command in commands
    buf += "#{command}\n"

  msg.send buf

module.exports = (robot) ->

  robot.hear /confluence search (.*)/i, (msg) ->
    search(msg, msg.match[1], false)

  robot.hear /confluence help/i, (msg) ->
    help(msg)

  robot.hear /confluence show triggers/i, (msg) ->
    msg.send triggers.join('\n')

  for trigger in triggers
    regex = new RegExp trigger, 'i'
    robot.hear regex, (msg) ->
      search(msg, msg.match[1], false)
