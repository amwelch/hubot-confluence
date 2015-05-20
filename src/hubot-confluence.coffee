nconf = require("nconf")
btoa = require("btoa")

triggers = require './data/triggers.json'

cwd = process.cwd()
DEFAULTS_FILE = "#{__dirname}/data/defaults.json"

nconf.argv()
    .env()
    .file('defaults', DEFAULTS_FILE)

sanity_check_args = (msg) ->
  required_args = [
    "HUBOT_CONFLUENCE_USER"
    "HUBOT_CONFLUENCE_PASSWORD"
    "HUBOT_CONFLUENCE_HOST"
    "HUBOT_CONFLUENCE_PORT"
    "HUBOT_CONFLUENCE_SEARCH_SPACE"
  ]

  for arg in required_args
    if !nconf.get(arg)
      buf = "#hubot-confluence is not properly configured. #{arg} is not set."
      msg.send buf
      return false

  return true

search = (msg, query, text) ->

  query = clean_search(query)

  num_results = nconf.get("HUBOT_CONFLUENCE_NUM_RESULTS") or 1
  timeout = nconf.get("HUBOT_CONFLUENCE_TIMEOUT") or 2000
  space = nconf.get("HUBOT_CONFLUENCE_SEARCH_SPACE")
  if text
    text_search = "text~\"#{query}\""
  else
    text_search = "title~\"#{query}\""

  query_str = "type=page and space in(#{space}) and #{text_search}"
  query_str =  encodeURIComponent query_str
  suffix = "/content/search?cql=#{query_str}"
  url = make_url(suffix, true)
  headers = make_headers()

  msg.http(url, {timeout: timeout}).headers(headers).get() (e, res, body) ->
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

clean_search = (query) ->
  query = query.replace('?', '')

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
    if !sanity_check_args(msg)
      return
    search(msg, msg.match[1], false)

  robot.hear /confluence help/i, (msg) ->
    help(msg)

  robot.hear /confluence show triggers/i, (msg) ->
    msg.send triggers.join('\n')

  for trigger in triggers
    regex = new RegExp trigger, 'i'
    robot.hear regex, (msg) ->
      if !sanity_check_args(msg)
        return
      search(msg, msg.match[1], false)
