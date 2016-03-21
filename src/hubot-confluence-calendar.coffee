# Description:
#   A slack integration for posting confluence calendar events
#
# Dependencies:
#   cron, time, underscore, nconf, btoa
#
# Configuration:
#   None
#
# Commands:
#   None, uses cron to automaticaly posts updates if any
#
# Author:
#   danbeggan

_ = require("underscore")
nconf = require("nconf")
btoa = require("btoa")

cwd = process.cwd()
DEFAULTS_FILE = "#{__dirname}/data/defaults.json"

nconf.argv()
    .env()
    .file('defaults', DEFAULTS_FILE)

sanity_check_args = (res) ->
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
      res.reply buf
      return false
  return true

# Instructions:
# Fill in the required arguements
# To use multiple calendars copy the cronJobs and change the arguements to different calendars

module.exports = (robot) ->
  cronJob = require('cron').CronJob

  #required arguements
  timezone = 'Europe/Dublin'
  # To get the calendar url you wish to use this plugin for:
  #   - Click the related actions on the calendar you wish to use
  #   - Choose subscribe and copy the link to the .ics file confluence gives you to calendarUrl
  calendarUrl = ''
  calendarName = ''
  #should be a link to the confluence page of the calendar, users will linked to this in the slack channel
  calendarPage = ''
  channelToPost = '#general'
  timeToCheckForDailyUpdate = '10' #Value should be a 24 hour value e.g. 14 for 2pm, currently at 10am
  
  #when bot starts for first time will check for todays calendar events
  checkForDailyUpdates(robot, calendarUrl, calendarName, calendarPage, channelToPost)

  #schedules a cronJob to run every day at 10am
  #will send a notification to general channel with todays events
  new cronJob("00 00 #{timeToCheckForDailyUpdate} * * *", sendDailyNotification(robot, calendarUrl, calendarName, calendarPage, channelToPost), null, true, "#{timezone}")

  #schedules a cronJob to run every hour on the hour
  #will send a notification to general channel with the hours events
  new cronJob("00 00 * * * *", sendHourlyNotification(robot, calendarUrl, calendarName, calendarPage, channelToPost), null, true, "#{timezone}")

sendDailyNotification = (robot, calendarUrl, calendarName, calendarPage, channelToPost) ->
  -> checkForDailyUpdates(robot, calendarUrl, calendarName, calendarPage, channelToPost)

sendHourlyNotification = (robot, calendarUrl, calendarName, calendarPage, channelToPost) ->
  -> checkForHourlyUpdates(robot, calendarUrl, calendarName, calendarPage, channelToPost)

checkForDailyUpdates = (robot, calendarUrl, calendarName, calendarPage, channelToPost) ->
  timeout = nconf.get("HUBOT_CONFLUENCE_TIMEOUT") or 2000
  headers = make_headers()
  robot.http(calendarUrl)
    .headers(headers)
    .get() (error, response, body) ->
      if error
        console.log("Hubot-confluence-calendar revieved and error from #{calendarUrl} while trying to check for daily updates on #{calendarName}")
        console.log("Error: #{error}")
        return

      if response.statusCode isnt 200
        console.log("Hubot-confluence-calendar revieved a response code which wasn't 200 from #{calendarUrl} while trying to check for daily updates on #{calendarName}")
        console.log("Status Code: " + response.statusCode)
        console.log("Response body:")
        console.log(body)
        return

      d = new Date();
      datestring = "#{d.getFullYear()}[?:0]?#{d.getMonth()+1}[?:0]?#{d.getDate()}"

      fields =
        fields: []

      reg = new RegExp("DTSTART;VALUE=DATE:#{datestring}\\r\\n.*\\r\\nSUMMARY:([\\s\\S]*?)UID:","gi")

      match = reg.exec(body)
      fields.fields.push {
        title: "Event:"
        value: match[1]
        short: false
      }

      #Check if any events were found for today if not do nothing
      if fields.fields[0] is null or undefined
        return
      else
        attachment =
          fallback: "Calendar notification"
          title: "#{calendarName}: todays events"
          title_link: calendarPage
          color: "#e0e0e0"

        attachment = _.extend {}, attachment, fields

        robot.adapter.customMessage
          channel: channelToPost
          username: robot.name
          attachments: [attachment]

checkForHourlyUpdates = (robot, calendarUrl, calendarName, calendarPage, channelToPost) ->
  timeout = nconf.get("HUBOT_CONFLUENCE_TIMEOUT") or 2000
  headers = make_headers()
  robot.http(calendarUrl)
    .headers(headers)
    .get() (error, response, body) ->
      if error
        console.log("Hubot-confluence-calendar revieved and error from #{calendarUrl} while trying to check for hourly updates on #{calendarName}")
        console.log("Error: #{error}")
        return

      if response.statusCode isnt 200
        console.log("Hubot-confluence-calendar revieved a response code which wasn't 200 from #{calendarUrl} while trying to check for hourly updates on #{calendarName}")
        console.log("Status Code: " + response.statusCode)
        console.log("Response body:")
        console.log(body)
        return

      d = new Date();
      datetimestring = "#{d.getFullYear()}[?:0]?#{d.getMonth()+1}[?:0]?#{d.getDate()}T([?:0]?#{d.getHours}\\d+)Z"

      reg = new RegExp("DTSTART;VALUE=DATE:#{datetimestring}\\r\\n.*\\r\\nSUMMARY:([\\s\\S]*?)UID:","gi")

      while match = reg.exec(body)
        fields.fields.push {
          title: "Event:"
          value: match[2]
          short: true
        }
        fields.fields.push {
          title: "Time of event:"
          value: nicelyFormattedTime(match[1])
          short: true
        }

      #Check if any events were found for this hour if not do nothing
      if fields.fields[0] is null or undefined
        return
      else
        attachment =
          fallback: "Calendar notification"
          title: "#{calendarName}: Events in the next hour"
          title_link: calendarPage
          color: "#e0e0e0"

        attachment = _.extend {}, attachment, fields

        robot.adapter.customMessage
          channel: channelToPost
          username: robot.name
          attachments: [attachment]

nicelyFormattedTime = (timestring) ->
  hours = dateToFormat.substring(0,2)
  minutes = dateToFormat.substring(2,4)
  "#{hours}:#{minutes}"

make_headers = ->
  user = nconf.get("HUBOT_CONFLUENCE_USER")
  password = nconf.get("HUBOT_CONFLUENCE_PASSWORD")

  auth = btoa("#{user}:#{password}")

  ret =
    Authorization: "Basic #{auth}"
