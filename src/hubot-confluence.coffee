# Description:
#   Automatically respond to questions in chat with a relevant confluence article.
#
# Configuration:
#  HUBOT_CONFLUENCE_USER           Required Atlassian User
#  HUBOT_CONFLUENCE_PASSWORD       Required Atlassian Password
#  HUBOT_CONFLUENCE_HOST           Required
#  HUBOT_CONFLUENCE_SEARCH_SPACE   Required Comma-separated list of Confluence Spaces to search, eg DEV,MARKETING,SALES
#  HUBOT_CONFLUENCE_PORT           Optional Defaults to 443
#  HUBOT_CONFLUENCE_NUM_RESULTS    Optional The number of results to return. Defaults to 1.
#  HUBOT_CONFLUENCE_TIMEOUT        Optional Timeout in ms for requests to confluence. Default is no timeout
#  HUBOT_CONFLUENCE_PROTOCOL       Optional Configure the protocol to use to connect to confluence (default: https, common use cases: http, https)
#  HUBOT_CONFLUENCE_NO_CONTEXT_ROOT Optional If the deployment is to wiki.example.com instead of example.com/wiki set this to 'true'
#  HUBOT_CONFLUENCE_REST_PROTOTYPE  Optional If connecting to a pre-5.5 deployment of confluence
#
# Commands:
#   confluence show triggers - Show the current trigger regexs
#   confluence search <text> - Run a text search against the phrase 'text'
#
# Authors:
#   amwelch
#   chrisatomix
#

nconf = require("nconf")
btoa = require("btoa")

triggers = require './data/triggers.json'

cwd = process.cwd()
DEFAULTS_FILE = "#{__dirname}/data/defaults.json"

nconf.argv()
    .env()
    .file('defaults', DEFAULTS_FILE)

noResultsFound = [
  'I have no idea'
]

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
      msg.reply buf
      return false

  return true

search = (msg, query, text) ->
  rest_prototype = nconf.get("HUBOT_CONFLUENCE_REST_PROTOTYPE")
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
  suffix = "/content/search?os_authType=basic&cql=#{query_str}"
  if rest_prototype
    suffix = "/search/site?type=page&query=#{query}"
  url = make_url(suffix, true)
  headers = make_headers()
  msg.http(url, {timeout: timeout}).headers(headers).get() (e, res, body) ->
    if e
      msg.reply "Error: #{e}"
      return
   
    if res.statusCode isnt 200
      msg.send "Error processing your request"
      msg.send "Check hubot logs for more information"
      console.log("Status Code: " + res.statusCode)
      console.log("Response body:")
      console.log(body)
      return

    content = JSON.parse(body)
    results = content.results
    if rest_prototype
      results = content.result
    if !results or results.length == 0
      #Fall back to text search
      if !text
        search(msg, query, true)
        return
      else
        msg.reply msg.random noResultsFound
        return

    count = 0
    for result in results
      count += 1
      if count > num_results
        break
      link = ""
      if rest_prototype
        link = make_url(result.wikiLink, false)
      else
        link = make_url(result._links.webui, false)
      msg.reply "#{result.title} - #{link}"

make_headers = ->

  user = nconf.get("HUBOT_CONFLUENCE_USER")
  password = nconf.get("HUBOT_CONFLUENCE_PASSWORD")

  auth = btoa("#{user}:#{password}")

  ret =
    Accept: "application/json"
    Authorization: "Basic #{auth}"

clean_search = (query) ->
  query = query.replace(/[!?,.]/g, ' ')

make_url = (suffix, api) ->
  host = nconf.get("HUBOT_CONFLUENCE_HOST")
  port = nconf.get("HUBOT_CONFLUENCE_PORT")
  protocol = nconf.get("HUBOT_CONFLUENCE_PROTOCOL")
  no_context = nconf.get("HUBOT_CONFLUENCE_NO_CONTEXT_ROOT")
  rest_prototype = nconf.get("HUBOT_CONFLUENCE_REST_PROTOTYPE")

  url = "#{protocol}://#{host}:#{port}/wiki"
  if no_context
    url = "#{protocol}://#{host}:#{port}"
  if api
    if rest_prototype
      url = "#{url}/rest/prototype/latest#{suffix}"
    else
      url = "#{url}/rest/api#{suffix}"
  else
    if rest_prototype
      debugger
      suffix = suffix.replace /\[/, ""
      suffix = suffix.replace /\]/, ""
      suffix = suffix.replace /:/, "/"
      suffix = suffix.replace /\s/g, "%20"
      url = "#{url}/display/#{suffix}"
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

  msg.reply buf

module.exports = (robot) ->

  robot.hear /confluence search (.*)/i, (msg) ->
    if !sanity_check_args(msg)
      return
    search(msg, msg.match[1], false)

  robot.hear /confluence help/i, (msg) ->
    help(msg)

  robot.hear /confluence show triggers/i, (msg) ->
    msg.reply triggers.join('\n')

  for trigger in triggers
    regex = new RegExp trigger, 'i'
    robot.hear regex, (msg) ->
      if !sanity_check_args(msg)
        return
      search(msg, msg.match[1], false)
