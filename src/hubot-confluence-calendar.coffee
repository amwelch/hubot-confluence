# Description:
#   A slack integration for posting confluence calendar events autonmatically to a channel.
#
# Dependencies:
#   cron, moment-timezone, underscore, nconf, btoa, hubot-conversation, datejs
#
# Configuration:
#   Set how many minutes before an event to post in slack (default set to 15)
#
# Commands:
#   add calendar [calendar name] - Add a confluence calendar to your channel
#   show calendars - Lists all confluence calendars for your channel
#   remove calendar [calendar name] - Remove a confluence calendar from your channel
#
# Author:
#   danbeggan

_ = require("underscore")
nconf = require("nconf")
btoa = require("btoa")
moment = require('moment-timezone')
Conversation = require('hubot-conversation')
cronJob = require('cron').CronJob
lt = require('long-timeout')
require('datejs')

#Configuration
#Set how many minutes before an event to post in slack
reminderMinutesBefore = "15"

#setup nconf
nconf.argv()
    .env()

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
  onRestart(robot)

  switchBoard = new Conversation(robot)

  robot.respond /add calendar (.*)/i, (res) ->
    if sanity_check_args(res) is false
      return
    channelToPost = res.message.room

    #Use hubot-conversation to have a Conversation with the user
    dialog = switchBoard.startDialog(res)
    calendarName = res.match[1]

    #check if name already exhists for a calendar in the room
    calendarsForRoom = getCalendarsForRoom(robot, res.message.room)
    calsWithSameName = _.where calendarsForRoom, name: calendarName
    if calsWithSameName.length isnt 0
      res.reply("Calendar already exhists with the name \'#{calendarName}\' in this channel, please try again with a different name")
      return

    res.reply('Please follow these steps to get the calendar\n  - Click the related actions on the calendar you wish to use\n  - Choose subscribe and copy the url to the .ics file confluence gives you')
    dialog.addChoice /\s(.*.ics)/i, (res2) ->
      calendarUrl = res2.match[1]
      res2.reply('What timezone are you in? Example respone: America/Los_Angeles, Europe/London')
      dialog.addChoice /\s(\w+\/\w+)/i, (res3) ->
        timezone = res3.match[1]

        #check if timezone is valid
        validZone = moment.tz.zone(timezone)
        if validZone is null
          res3.reply('The timezone entered is invalid or in incorrect format, see http://momentjs.com/timezone/ for a map of valid timezones, timezone must be in format Region/City')
          return

        res3.reply('All day events for calendars are posted once a day unless re-added\n What time in 24hr (hh:mm) format would you like daily updates to be posted? Example resonse: 9:30, 22:00')
        dialog.addChoice /\s([01]?[0-9]|2[0-3]):([0-5][0-9])/i, (res4) ->
          hours = res4.match[1]
          minutes = res4.match[2]
          saveCalendar(robot, calendarName, channelToPost, calendarUrl, timezone, hours, minutes)
          res4.reply("New calendar: #{calendarName} added to #{res4.message.room}")

  robot.respond /show calendars/i, (res) ->
    if sanity_check_args(res) is false
      return
    calendarsForRoom = getCalendarsForRoom(robot, res.message.room)
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
        title: "All Day Events Check Time:"
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

  robot.respond /remove calendar (.*)/i, (res) ->
    if sanity_check_args(res) is false
      return
    deleteCalendar(robot, res, res.match[1])

getCalendars = (robot) ->
  robot.brain.get('calendars') or []

getCalendarsForRoom = (robot, room) ->
  _.where getCalendars(robot), room: room

getCronDayJobs = (robot) ->
  robot.brain.get('cronDayCalendars') or []

getCronTimedJobs = (robot) ->
  robot.brain.get('cronTimedCalendars') or []

getCronRecurringJobs = (robot) ->
  robot.brain.get('cronRecurringCalendars') or []

deleteCalendar = (robot, res, name) ->
  calendars = getCalendarsForRoom(robot, res.message.room)
  cal = _.where calendars, name: name

  if cal.length is 0
    res.reply("Calendar does not exhist or name is incorrect(case sensitive), use \'@robot show calendars\' to list all calendars for this channel")
    return
  calendarID = cal[0].id

  #Stop and remove the cronJobs associated with the calendar
  (_.where getCronDayJobs(robot), id: calendarID)[0].job.stop()
  (_.where getCronTimedJobs(robot), id: calendarID)[0].job.stop()
  (_.where getCronRecurringJobs(robot), id: calendarID)[0].job.stop()

  calendars = _.reject getCalendars(robot), id: calendarID
  cronDayCalendars = _.reject getCronDayJobs(robot), id: calendarID
  cronTimedCalendars = _.reject getCronTimedJobs(robot), id: calendarID
  cronRecurringCalendars = _.reject getCronRecurringJobs(robot), id: calendarID

  robot.brain.set 'calendars', calendars
  robot.brain.set 'cronDayCalendars', cronDayCalendars
  robot.brain.set 'cronTimedCalendars', cronTimedCalendars
  robot.brain.set 'cronRecurringCalendars', cronRecurringCalendars
  res.reply("Calendar removed, use \'@robot show calendars\' to list all calendars for this channel")

saveCalendar = (robot, calendarName, channelToPost, calendarUrl, timezone, hours, minutes) ->
  calendars = getCalendars(robot)
  cronDayCalendars = getCronDayJobs(robot)
  cronTimedCalendars = getCronTimedJobs(robot)
  cronRecurringCalendars = getCronRecurringJobs(robot)
  calendarID = robot.brain.get('nextCalendarID') or 0

  newCalendar =
    room: channelToPost
    name: calendarName
    time: "#{hours}:#{minutes}"
    offset: parseInt(hours)*3600000+parseInt(minutes)*60000
    zone: timezone
    url: calendarUrl
    id: calendarID
    recurringEvents: []

  newCronDayEvent =
    id: calendarID
    job: new cronJob("00 #{minutes} #{hours} * * *", checkEvents(robot, calendarUrl, calendarName, channelToPost, timezone, "day"), null, true, timezone)

  newCronTimedEvent =
    id: calendarID
    job: new cronJob("00 #{Math.floor(Math.random() * 59)} 00 * * *", checkEvents(robot, calendarUrl, calendarName, channelToPost, timezone, "timed"), null, true, timezone)

  newCronRecurringEvent =
    id: calendarID
    job: new cronJob("00 #{Math.floor(Math.random() * 59)} 00 * * *", checkEvents(robot, calendarUrl, calendarName, channelToPost, timezone, "recurring"), null, true, timezone)

  calendars.push newCalendar
  cronDayCalendars.push newCronDayEvent
  cronTimedCalendars.push newCronTimedEvent
  cronRecurringCalendars.push newCronRecurringEvent

  robot.brain.set 'calendars', calendars
  robot.brain.set 'cronDayCalendars', cronDayCalendars
  robot.brain.set 'cronTimedCalendars', cronTimedCalendars
  robot.brain.set 'cronRecurringCalendars', cronRecurringCalendars
  robot.brain.set 'nextCalendarID', calendarID+1
  return

checkEvents = (robot, calendarUrl, calendarName, channelToPost, timezone, type) ->
  -> checkForEvents(robot, calendarUrl, calendarName, channelToPost, timezone, type)

checkForEvents = (robot, calendarUrl, calendarName, channelToPost, timezone, type) ->
  timeout = nconf.get("HUBOT_CONFLUENCE_TIMEOUT") or 2000
  headers = make_headers()
  robot.http(calendarUrl)
    .headers(headers)
    .get() (error, response, body) ->
      if error
        console.log("Hubot-confluence-calendar revieved and error from #{calendarUrl} while trying to check for updates on #{calendarName}")
        console.log(error)
        return

      if response.statusCode isnt 200
        console.log("Hubot-confluence-calendar revieved a response code which wasn't 200 from #{calendarUrl} while trying to check for updates on #{calendarName}")
        console.log("Status Code: " + response.statusCode)
        console.log("Response body:")
        console.log(body)
        attachment =
          fallback: "Calendar notification"
          title: "Error while check for updates on #{calendarName}"
          text: "Hubot recieved an invalid response while checking for updates. Try removing the calendar from channel using \'@robot remove calendar [calendar name]\' and re-adding it."
          color: "#dd0000"
        robot.adapter.customMessage
          channel: channelToPost
          username: robot.name
          attachments: [attachment]
        return

      #Check for all day events
      if type is "day"
        datestring = Date.today().setTimeToNow().addMinutes(-moment.tz.zone(timezone).offset(moment.utc())).toString('yyyyMMdd')
        reg = new RegExp("BEGIN:VEVENT((?:(?!\\b(?:END|BEGIN):VEVENT\\b)[\\s\\S])*DTSTART;VALUE=DATE:#{datestring}[\\s\\S]*?)END:VEVENT","g")
        while(full = reg.exec(body))
          fullEvent = full[1]
          attachment = extractEvent(fullEvent, calendarUrl, calendarName, channelToPost, timezone, "day")

          robot.adapter.customMessage
            channel: channelToPost
            username: robot.name
            attachments: [attachment]
      #Check for events with a time set
      else if type is "timed"
        timezoneUTCdiff = moment.tz.zone(timezone).offset(moment.utc())
        datetimestring = "#{Date.today().setTimeToNow().addMinutes(-moment.tz.zone(timezone).offset(moment.utc())).toString('yyyyMMdd')}T\\d+Z"
        reg = new RegExp("BEGIN:VEVENT((?:(?!\\b(?:END|BEGIN):VEVENT\\b)[\\s\\S])*DTSTART:#{datetimestring}[\\s\\S]*?)END:VEVENT","g")
        while(full = reg.exec(body))
          fullEvent = full[1]

          attachment = extractEvent(fullEvent, calendarUrl, calendarName, channelToPost, timezone, "timed")

          reg1 = new RegExp("DTSTART:(\\d+)T(\\d+)Z")
          datetimes = reg1.exec(fullEvent)
          startdate = datetimes[1]
          starttime = datetimes[2]

          time = {hour:parseInt(starttime.substring(0,2)), minute:parseInt(starttime.substring(2,4))}
          timeout = new Date(Date.today().set(time).addMinutes(-reminderMinutesBefore)).getTime()-Date.now()

          delay fireTimedEvent, timeout, robot, channelToPost, attachment, calendarName
      #check for recurring events
      else if type is "recurring"
        reg = new RegExp("BEGIN:VEVENT((?:(?!\\b(?:END|BEGIN):VEVENT\\b)[\\s\\S])*RRULE:(.*)[\\s\\S]*?)END:VEVENT","g")
        while(full = reg.exec(body))
          fullEvent = full[1]
          keepcheck = true

          reg0 = new RegExp("UID:(.*)@")
          uid = reg0.exec(fullEvent)[1]

          #If a recurring event is found check if it has an end date
          reg1 = new RegExp("RRULE:.*UNTIL=(\\d+)")
          if reg1.test(fullEvent)
            endrecurrance = reg1.exec(fullEvent)
            enddate = endrecurrance[1]
            timeset = {day:parseInt(enddate.substring(6,8)), month:parseInt(enddate.substring(4,6)), year:parseInt(enddate.substring(0,4))}
            #Check if the end date is in the past or not today
            if (Date.today().getTime() - Date.today().set(timeset).getTime()) > 0
              keepcheck = false

          if keepcheck is true
            calendar = _.where getCalendarsForRoom(robot, channelToPost), name: calendarName
            for event in calendar[0].recurringEvents
              #Check if the event is already set to fire in the future
              if event.uid is uid
                keepcheck = false
                break

            reg0 = new RegExp("DTSTART;VALUE=DATE")
            if keepcheck is true
              if reg0.test(fullEvent)
                type = "day"
              else
                type = "timed"

              #Find the interval and frequency to post the event
              reg0 = new RegExp("RRULE:FREQ=(\\w+).*INTERVAL=(\\d+)")
              intfreq = reg0.exec(fullEvent)
              frequency = intfreq[1]
              interval = parseInt(intfreq[2])

              #iCal doesnt specify frequency=weekday but has BYDAY rule
              reg1 = new RegExp("RRULE:.*BYDAY=")
              if reg1.test(fullEvent)
                frequency = "WEEKDAY"

              if type is "day"
                reg1 = new RegExp("DTSTART;VALUE=DATE:(.*)\\r\\nDTEND;VALUE=DATE:(.*)")
                dates = reg1.exec(fullEvent)
                startdate = dates[1]
                enddate = dates[2]
                startdate = new Date(startdate.substring(0,4), parseInt(startdate.substring(4,6))-1, startdate.substring(6,8))
                enddate = new Date(enddate.substring(0,4), parseInt(enddate.substring(4,6))-1, enddate.substring(6,8))
              else if type is "timed"
                reg1 = new RegExp("DTSTART:(\\d+)T(\\d+)Z\\r\\nDTEND:(\\d+)T(\\d+)Z")
                datetimes = reg1.exec(fullEvent)
                startdate = datetimes[1]+datetimes[2]
                enddate = datetimes[3]+datetimes[4]
                startdate = new Date(startdate.substring(0,4), parseInt(startdate.substring(4,6))-1, startdate.substring(6,8), startdate.substring(8,10), startdate.substring(10,12)).addMinutes(-15)
                enddate = new Date(enddate.substring(0,4), parseInt(enddate.substring(4,6))-1, enddate.substring(6,8), enddate.substring(8,10), enddate.substring(10,12))

              [timeout, nextstartdate, nextenddate] = getNextRecurring(frequency, interval, startdate, enddate)
              attachment = extractEvent(fullEvent, calendarUrl, calendarName, channelToPost, timezone, type)

              if type is "timed"
                #if timed event is less than the time left in the day calculate it for tomorrow
                if nextstartdate.getTime() - Date.today().addHours(24) < 0
                  [timeout, nextstartdate, nextenddate] = getNextRecurring(frequency, interval, startdate.addHours(24), enddate.addHours(24))
                nextstartdate = nextstartdate.addMinutes(15)

              attachment.fields.forEach (field) ->
                if field.title is "Starts:"
                  if type is "timed"
                    field.value = nicelyFormattedTime(nextstartdate.toString('yyyyMMdd'), nextstartdate.toString('HHmm'), timezone)
                  else
                    field.value = nicelyFormattedDate(nextstartdate.toString('yyyyMMdd'))
                else if field.title is "Ends:"
                  if type is "timed"
                    field.value = nicelyFormattedTime(nextenddate.toString('yyyyMMdd'), nextenddate.toString('HHmm'), timezone)
                  else
                    field.value = nicelyFormattedDate(nextenddate.toString('yyyyMMdd'))

              calendars = getCalendarsForRoom(robot, channelToPost)
              cal = _.where calendars, name: calendarName
              calendars = _.reject getCalendars(robot), id: cal[0].id
              newRecurringEvent =
                uid: uid
              cal[0].recurringEvents.push newRecurringEvent
              calendars.push cal[0]
              robot.brain.set 'calendars', calendars

              if type is "day"
                timeout+=cal[0].offset

              delay fireRecurringEvent, timeout, robot, channelToPost, calendarName, uid, attachment

#Custom delay function - used to pass multiple arguments to timeout & keep them within scope
delay = (func, wait) ->
  argu = Array.prototype.slice.call(arguments, 2)
  lt.setTimeout (->
    func.apply null, argu
  ), wait

fireTimedEvent = (robot, channelToPost, attachment, calendarName) ->
  calendars = getCalendarsForRoom(robot, channelToPost)
  cal = _.where calendars, name: calendarName
  #Check the calendar hasnt been deleted
  if cal.length is 0
    return
  robot.adapter.customMessage
    channel: channelToPost
    username: robot.name
    attachments: [attachment]

fireRecurringEvent = (robot, channelToPost, calendarName, uid, attachment) ->
  calendars = getCalendarsForRoom(robot, channelToPost)
  cal = _.where calendars, name: calendarName
  #Check the calendar hasnt been deleted
  if cal.length is 0
    return
  event = _.where cal[0].recurringEvents, uid: uid
  calendars = _.reject getCalendars(robot), id: cal[0].id
  cal[0].recurringEvents = _.reject cal[0].recurringEvents, uid: uid
  calendars.push cal[0]
  robot.brain.set 'calendars', calendars

  checkForEvents(robot, cal[0].url, cal[0].name, cal[0].room, cal[0].zone, "recurring")

  robot.adapter.customMessage
    channel: channelToPost
    username: robot.name
    attachments: [attachment]

#Dates are in US format month/day/year
nicelyFormattedTime = (startdate, starttime, timezone) ->
  time = {year:parseInt(startdate.substring(0,4)) ,month:parseInt(startdate.substring(4,6)) ,day:parseInt(startdate.substring(6,8)) ,hour:parseInt(starttime.substring(0,2)), minute:parseInt(starttime.substring(2,4))}
  datetime = Date.today().set(time).addMinutes(-moment.tz.zone(timezone).offset(moment.utc())).toString('HH:mm - MM/dd/yyyy')

nicelyFormattedDate = (dateToFormat) ->
  year = dateToFormat.substring(0,4)
  day = dateToFormat.substring(6,8)
  month = dateToFormat.substring(4,6)
  "#{month}/#{day}/#{year}"

#Method to find the next time a recurring event should fire
getNextRecurring = (frequency, interval, startdate, enddate) ->
  diff = enddate.getTime() - startdate.getTime()

  nextstartdate = startdate
  timeout = nextstartdate.getTime() - Date.now()
  while timeout < 0
    if frequency is "DAILY"
      nextstartdate = nextstartdate.addDays(interval)
      timeout = nextstartdate.getTime() - Date.now()
    else if frequency is "WEEKLY"
      nextstartdate = nextstartdate.addWeeks(interval)
      timeout = nextstartdate.getTime() - Date.now()
    else if frequency is "WEEKDAY"
      nextstartdate = nextstartdate.addDays(interval)
      while !(nextstartdate.is().weekday())
        nextstartdate = nextstartdate.addDays(interval)
      timeout = nextstartdate.getTime() - Date.now()
    else if frequency is "MONTHLY"
      nextstartdate = nextstartdate.addMonths(interval)
      timeout = nextstartdate.getTime() - Date.now()
    else if frequency is "YEARLY"
      nextstartdate = nextstartdate.addYears(interval)
      timeout = nextstartdate.getTime() - Date.now()

  nextenddate = new Date(nextstartdate.getTime() + diff)
  [timeout, nextstartdate, nextenddate]

#Takes a calendar event in ical format and converts it to an attachment to post to slack
extractEvent = (fullEvent, calendarUrl, calendarName, channelToPost, timezone, type) ->
  if type is "day"
    #Match start date & end date
    reg1 = new RegExp("DTSTART;VALUE=DATE:(.*)\\r\\nDTEND;VALUE=DATE:(.*)")
    dates = reg1.exec(fullEvent)
    start = nicelyFormattedDate(dates[1])
    end = nicelyFormattedDate(dates[2])
  else if type is "timed"
    #Match start date & time & end date & time
    reg1 = new RegExp("DTSTART:(\\d+)T(\\d+)Z\\r\\nDTEND:(\\d+)T(\\d+)Z")
    datetimes = reg1.exec(fullEvent)
    start = nicelyFormattedTime(datetimes[1], datetimes[2], timezone)
    end = nicelyFormattedTime(datetimes[3], datetimes[4], timezone)

  #event type
  reg5 = new RegExp("X-CONFLUENCE-SUBCALENDAR-TYPE:(.*)")
  caltype = reg5.exec(fullEvent)
  type = caltype[1]
  if type is "other" or "custom"
    type = "event"

  #Match summary & description
  reg21 = new RegExp("SUMMARY:([\\s\\S]*?)\\r\\n\\w+[:|;]")
  reg22 = new RegExp("DESCRIPTION:([\\s\\S]*?)\\r\\n\\w+[:|;]")

  summ = reg21.exec(fullEvent)
  desc = reg22.exec(fullEvent)
  summary = summ[1].replace(/\r\n /g, "")
  description = desc[1].replace(/\r\n /g, "")

  if summary.length is 0 and description.length is 0
    description = "No description for event"
  else if  summary.length is 0 or description.length is 0
    description = summary + description
  else if type is "travel"
    description = summary
  else
    description = summary + "\n" + description

  #Organiser & if attendee, attendee overwrites organiser
  reg3 = new RegExp("ORGANIZER;.*CN=([\\s\\S]*?);CUTYPE")
  if reg3.test(fullEvent)
    org = reg3.exec(fullEvent)
    organiser = org[1].replace(/\r|\n /g, "")

  reg4 = new RegExp("ATTENDEE;.*CN=([\\s\\S]*?);CUTYPE")
  attendee = organiser or ""
  if reg4.test(fullEvent)
    att = reg4.exec(fullEvent)
    attendee = att[1].replace(/\r|\n /g, "")

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
    title: "#{calendarName} - #{type}"
    text: description.replace(/\\n/g,'\n')
    fields: [
      {
        title: "Starts:"
        value: start
        short: true
      }
      {
        title: "Ends:"
        value: end
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

#Authentication headers for http request
make_headers = ->
  user = nconf.get("HUBOT_CONFLUENCE_USER")
  password = nconf.get("HUBOT_CONFLUENCE_PASSWORD")
  auth = btoa("#{user}:#{password}")
  ret =
    Authorization: "Basic #{auth}"

#Restarts cronJobs if robot is turned off
onRestart = (robot) ->
  calendars = getCalendars(robot)
  if calendars.length is 0
    return
  dayjobs = getCronDayJobs(robot)
  timedjobs = getCronTimedJobs(robot)
  recurringJobs = getCronRecurringJobs(robot)
  for c in calendars
    (_.where dayjobs, id: c.id)[0].job.start()
    (_.where timedjobs, id: c.id)[0].job.start()
    (_.where recurringJobs, id: c.id)[0].job.start()
  return
