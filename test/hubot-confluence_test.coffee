nconf = require "nconf"
jasmine = require 'jasmine'
chai = require 'chai'
sinon = require 'sinon'
nock = require 'nock'
chai.use require 'sinon-chai'

Robot = require 'hubot/src/robot'
TextMessage = require('hubot/src/message').TextMessage

expect = chai.expect

describe 'Basic listeners', ->
  beforeEach ->
    @robot =
      respond: sinon.spy()
      hear: sinon.spy()

    require('../src/hubot-confluence')(@robot)

  it 'confluence help', ->
    expect(@robot.hear).to.have.been.calledWith(/confluence help/i)

  it 'confluence show triggers', ->
    expect(@robot.hear).to.have.been.calledWith(/confluence show triggers/i)

  it 'confluence search', ->
    expect(@robot.hear).to.have.been.calledWith(/confluence search (.*)/i)

  it 'triggers', ->
    triggers = require('../src/data/triggers.json')
    for trigger in triggers
      rgx = new RegExp trigger, 'i'
      expect(@robot.hear).to.have.been.calledWith(rgx)

describe 'Unit Tests', ->
  robot =
    http: sinon.spy()

  chat_user = {}
  adapter = {}
  #Set env variables
  test_user = "foo"
  test_pw   = "bar"
  test_host = "baz.com"
  test_port = 0

  beforeEach (done) ->
    # Create new robot, without http, using mock adapter
    robot = new Robot null, "mock-adapter", false

    robot.adapter.on "connected", ->
    nconf.set("HUBOT_CONFLUENCE_USER", test_user)
    nconf.set("HUBOT_CONFLUENCE_PASSWORD", test_pw)
    nconf.set("HUBOT_CONFLUENCE_HOST", test_host)
    nconf.set("HUBOT_CONFLUENCE_PORT", test_port)
    nconf.set("HUBOT_CONFLUENCE_SEARCH_SPACE", "bar")

    # load the module under test and configure it for the
    # robot. This is in place of external-scripts
    require("../src/hubot-confluence")(robot)

    chat_user = robot.brain.userForId "1", {
      name: "foo-user"
      room: "#test"
    }

    adapter = robot.adapter

    do nock.disableNetConnect

    robot.run()
    done()

  afterEach ->
    robot.shutdown()

  it 'test help text', (done) ->

    adapter.on "send", (envelope, strings) ->
      expect(strings[0]).to.string "confluence help"
      done()

    adapter.receive(new TextMessage chat_user, "confluence help")

  it 'test triggers', (done) ->
    adapter.on "send", (envelope, strings) ->
      triggers = require("../src/data/triggers.json")
      for trigger in triggers
        expect(strings[0]).to.string trigger
      done()

    adapter.receive(new TextMessage chat_user, "confluence show triggers")

  filter = (path) ->
    '/'

#TODO: need to force an error in nock,
#  try https://github.com/pgte/nock/issues/164
#
#  it 'test search error', (done) ->
#
#    err = "test error"
#    base = "https://#{test_host}:#{test_port}"
#    path = "/wiki/rest/api/content/search"
#    params = "cql=type%3Dpage%20and%20space%3Dbar%20and%20title~%22foo%22"
#    path = "#{path}?#{params}"
#    nconf.set("HUBOT_CONFLUENCE_TIMEOUT", 200)
#    nock(base).get(path).delayConnection(1000).reply(200);
#    adapter.on "send", (envelope, strings) ->
#      expect(strings[0]).to.string "Error"
#      done()
#    adapter.receive(new TextMessage chat_user, "confluence search foo")

  it 'test basic search', (done) ->
    url = "/foo"
    title = "fake title"
    body =
      results: [
        title: title
        _links:
          webui: url
      ]
    base = "https://#{test_host}:#{test_port}"
    path = "/wiki/rest/api/content/search"
    params = "cql=type%3Dpage%20and%20space%3Dbar%20and%20title~%22foo%22"
    full = "#{path}?#{params}"
    nock(base).get(full).reply(200, JSON.stringify(body))
    adapter.on "send", (envelope, strings) ->
      expect_str = "#{title} - https://#{test_host}:#{test_port}/wiki#{url}"
      expect(strings[0]).to.string expect_str
      done()

    adapter.receive(new TextMessage chat_user, "confluence search foo")

  it 'test trigger search', (done) ->
    url = "/foo"
    title = "fake title"
    body =
      results: [
        title: title
        _links:
          webui: url
      ]
    base = "https://#{test_host}:#{test_port}"
    path = "/wiki/rest/api/content/search"
    params = "cql=type%3Dpage%20and%20space%3Dbar%20and%20title~%22foo%22"
    full = "#{path}?#{params}"
    nock(base).get(full).reply(200, JSON.stringify({}))
    path = "/wiki/rest/api/content/search"
    params = "cql=type%3Dpage%20and%20space%3Dbar%20and%20text~%22foo%22"
    full = "#{path}?#{params}"
    nock(base).get(full).reply(200, JSON.stringify(body))
    adapter.on "send", (envelope, strings) ->
      expect_str = "#{title} - https://#{test_host}:#{test_port}/wiki#{url}"
      expect(strings[0]).to.string expect_str
      done()

    adapter.receive(new TextMessage chat_user, "how do I foo")

describe 'test-require', ->
  it 'requries hubot-confluence', ->
    require('../src/hubot-confluence')

  it 'requries triggers', ->
    require('../src/data/triggers.json')
