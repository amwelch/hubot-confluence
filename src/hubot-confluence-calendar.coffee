# Description:
#   A slack integration for posting confluence calendar events to a channel.
#   Currently only supports all day non recurring events.
#
# Dependencies:
#   cron, moment-timezone, underscore, nconf, btoa, hubot-conversation
#
# Configuration:
#   None
#
# Commands:
#   add calendar [calendar name] - Add a confluence calendar to your channel
#   show calendars - Lists all confluence calendars for your channel
#   delete calendar [calendar name] - Remove a confluence calendar from your channel
#
# Author:
#   danbeggan

_ = require("underscore")
nconf = require("nconf")
btoa = require("btoa")
moment = require('moment-timezone')
Conversation = require("hubot-conversation")

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
      buf = "#Hubot-confluence-calendar is not properly configured. #{arg} is not set."
      res.reply buf
      return false
  return true

module.exports = (robot) ->
  cronJob = require('cron').CronJob
  onRestart(robot)

  switchBoard = new Conversation(robot)

  robot.respond /add calendar (.*)/i, (res) ->
    if sanity_check_args(res) is false
      return
    channelToPost = res.message.room
    dialog = switchBoard.startDialog(res)
    calendarName = res.match[1]

    #check if name already exhists for a calendar in the room
    calendarsForRoom = getCalendarsForRoom(res.message.room)
    calsWithSameName = _.where calendarsForRoom, name: calendarName
    if calsWithSameName.length isnt 0
      res.reply("Calendar already exhists with the name \'#{calendarName}\', please try again with a different name")
      return

    res.reply('Please follow these steps to get the calendar\n  - Click the related actions on the calendar you wish to use\n   - Choose subscribe and copy the url to the .ics file confluence gives you')
    dialog.addChoice /\s(.*.ics)/i, (res2) ->
      calendarUrl = res2.match[1]
      res2.reply('What timezone are you in? Example respone: America/Los_Angeles, Europe/London')
      dialog.addChoice /\s(\w+\/\w+)/i, (res3) ->
        timezone = res3.match[1]

        #check if timezone is valid
        validZone = moment.tz.zone(timezone)
        if validZone is null
          res3.reply('The timezone entered is invalid or in incorrect format, see http://momentjs.com/timezone/ for a map of valid timezones, not it must be in format Region/City')
          return

        res3.reply('Events for calendars are posted once a day unless re-added\n What time in 24hr (hh:mm) format would you like daily updates to be posted? Example resonse: 9:30, 22:00')
        dialog.addChoice /\s([01]?[0-9]|2[0-3]):([0-5][0-9])/i, (res4) ->
          hours = res4.match[1]
          minutes = res4.match[2]
          saveDailyCalendar(robot, calendarName, channelToPost, calendarUrl, timezone, hours, minutes)
          res4.reply("New calendar: #{calendarName} added to #{res4.message.room}")

  robot.respond /show calendars/i, (res) ->
    if sanity_check_args(res) is false
      return
    calendarsForRoom = getCalendarsForRoom(res.message.room)
    if calendarsForRoom.length is 0
      res.reply("Currently no confluence calendars setup in this room")
      return

    fields =
      fields: []

    for c in calendarsForRoom
      timeString = "#{c.time} [#{c.zone}]"
      fields.fields.push {
        title: "Calendar Name:"
        value: c.name
        short: true
      }
      fields.fields.push {
        title: "Daily Check Time:"
        value: timeString
        short: true
      }

    attachment =
      fallback: "Calendars currently in #{res.message.room}"
      title: "List of calendars in #{res.message.room}"
      color: "#e0e0e0"

    attachment = _.extend {}, attachment, fields

    robot.adapter.customMessage
      channel: res.message.room
      username: robot.name
      attachments: [attachment]

  robot.respond /delete calendar (.*)/i, (res) ->
    if sanity_check_args(res) is false
      return
    deleteCalendar(res, res.match[1])

  getCalendarsForRoom = (room) ->
    _.where getCalendars(robot), room: room

  deleteCalendar = (res, name) ->
    calendars = getCalendarsForRoom(res.message.room)
    cal = _.where calendars, name: name

    if cal.length is 0
      res.reply("Calendar does not exhist or name is incorrect, use \'@robot show calendars\' to list all calendars for this channel")
      return
    calendarID = cal[0].id
    cronCalendars = getCronJobs(robot)
    cronCalendars[calendarID].stop()
    calendars = _.reject getCalendars(robot), id: calendarID
    robot.brain.set 'calendars', calendars
    robot.brain.set 'cronCalendars', cronCalendars
    res.reply("Calendar removed, use \'@robot show calendars\' to list all calendars for this channel")

  saveDailyCalendar = (robot, calendarName, channelToPost, calendarUrl, timezone, hours, minutes) ->
    calendars = getCalendars(robot)
    cronCalendars = getCronJobs(robot)
    calendarID = robot.brain.get('nextCalendarID') or 0

    newCalendar =
      room: channelToPost
      name: calendarName
      time: "#{hours}:#{minutes}"
      zone: timezone
      url: calendarUrl
      id: calendarID
      type: 'daily'

    cronCalendars[calendarID] = new cronJob("00 #{minutes} #{hours} * * *", sendDailyNotification(robot, calendarUrl, calendarName, channelToPost), null, true, timezone)

    calendars.push newCalendar
    robot.brain.set 'calendars', calendars
    robot.brain.set 'cronCalendars', cronCalendars
    robot.brain.set 'nextCalendarID', calendarID+1
    return

  sendDailyNotification = (robot, calendarUrl, calendarName, channelToPost) ->
    -> checkForDailyUpdates(robot, calendarUrl, calendarName, channelToPost)

  checkForDailyUpdates = (robot, calendarUrl, calendarName, channelToPost) ->
    timeout = nconf.get("HUBOT_CONFLUENCE_TIMEOUT") or 2000
    headers = make_headers()
    robot.http(calendarUrl)
      .headers(headers)
      .get() (error, response, body) ->
        if error
          console.log("Hubot-confluence-calendar revieved and error from #{calendarUrl} while trying to check for daily updates on #{calendarName}")
          console.log(error)
          return

        if response.statusCode isnt 200
          console.log("Hubot-confluence-calendar revieved a response code which wasn't 200 from #{calendarUrl} while trying to check for daily updates on #{calendarName}")
          console.log("Status Code: " + response.statusCode)
          console.log("Response body:")
          console.log(body)
          return

        #Todays date in ical format
        d = new Date();
        datestring = "#{d.getFullYear()}[?:0]?#{d.getMonth()+1}[?:0]?#{d.getDate()}"

        #Match full VEVENT today
        reg = new RegExp("(DTSTART;VALUE=DATE:#{datestring}[\\s\\S]*?END:VEVENT)","g")
        while(full = reg.exec(body))
          fullEvent = full[1]

          #Match start date & end date
          reg1 = new RegExp("DTSTART;VALUE=DATE:(.*)\\r\\nDTEND;VALUE=DATE:(.*)")
          dates = reg1.exec(fullEvent)
          startdate = dates[1]
          enddate = dates[2]

          #Match summary & description
          #reg21 = new RegExp("SUMMARY:(.*)\\r\\nUID:.*\\r\\nDESCRIPTION:(.*)")
          reg21 = new RegExp("SUMMARY:([\\s\\S]*?)\\r\\n\\w+[:|;]")
          reg22 = new RegExp("DESCRIPTION:([\\s\\S]*?)\\r\\n\\w+[:|;]")

          summ = reg21.exec(fullEvent)
          desc = reg22.exec(fullEvent)
          summary = summ[1].replace(/\r|\n |\\n|\\r/g, "")
          description = desc[1].replace(/\r|\n |\\n|\\r/g, "")

          if summary.length is 0 and description.length is 0
            description = "No description for event"
          else if  summary.length is 0 or description.length is 0
            description = summary + description
          else
            description = summary + "\n" + description

          organiser = ""
          #Organiser & if attendee
          reg3 = new RegExp("ORGANIZER;.*CN=([\\s\\S]*?);CUTYPE")
          if reg3.test(fullEvent)
            org = reg3.exec(fullEvent)
            organiser = org[1].replace(/\r|\n |\\n|\\r/g, "")

          reg4 = new RegExp("ATTENDEE;.*CN=([\\s\\S]*?);CUTYPE")
          attendee = organiser
          if reg4.test(fullEvent)
            att = reg4.exec(fullEvent)
            attendee = att[1].replace(/\r|\n |\\n|\\r/g, "")

          #calendar type
          reg5 = new RegExp("X-CONFLUENCE-SUBCALENDAR-TYPE:(.*)")
          caltype = reg5.exec(fullEvent)
          type = caltype[1]
          if type is "other"
            type = "event"

          #Check for location
          reg6 = new RegExp("LOCATION:(.*)")
          if reg6.test(fullEvent)
            loc = reg6.exec(fullEvent)
            description += "\n" + loc[1]

          #Check for url
          reg7 = new RegExp("URL:([\\s\\S]*?)\\r\\n\\w+[;|:]")
          if reg7.test(fullEvent)
            url = reg7.exec(fullEvent)
            description += "\n" + url[1].replace(/\r|\n |\\n|\\r/g, "")

          attachment =
            fallback: "Calendar notification"
            title: "#{calendarName} [#{type}]"
            text: description
            fields: [
              {
                title: "Start Date:"
                value: nicelyFormattedDate(startdate)
                short: true
              }
              {
                title: "End Date:"
                value: nicelyFormattedDate(enddate)
                short: true
              }
              {
                title: "Confluence user:"
                value: attendee
                short: true
              }
            ]
            color: "#e0e0e0"
            thumb_url: "http://marketplace.servicerocket.com/static/products/atlassian/logoTeamCalendarsPNG.png"

          robot.adapter.customMessage
            channel: channelToPost
            username: robot.name
            attachments: [attachment]

nicelyFormattedTime = (timestring) ->
  hours = dateToFormat.substring(0,2)
  minutes = dateToFormat.substring(2,4)
  "#{hours}:#{minutes}"

nicelyFormattedDate = (dateToFormat) ->
  year = dateToFormat.substring(0,4)
  day = dateToFormat.substring(6,8)
  month = dateToFormat.substring(4,6)
  "#{day}/#{month}/#{year}"

make_headers = ->
  user = nconf.get("HUBOT_CONFLUENCE_USER")
  password = nconf.get("HUBOT_CONFLUENCE_PASSWORD")
  auth = btoa("#{user}:#{password}")
  ret =
    Authorization: "Basic #{auth}"

#restarts cronJobs if robot is turned off
onRestart = (robot) ->
  calendars = getCalendars(robot)
  if calendars.length is 0
    return
  jobs = getCronJobs(robot)
  for c in calendars
    jobs[c.id].start()
  return

getCalendars = (robot) ->
  robot.brain.get('calendars') or []

getCronJobs = (robot) ->
  robot.brain.get('cronCalendars') or []
