nconf = require "nconf"
jasmine = require 'jasmine'
chai = require 'chai'
sinon = require 'sinon'
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
  beforeEach (done) ->
    #Set env variables
    test_user = "foo"
    test_pw   = "bar"
    test_host = "baz.com"
    test_port = 0

    robot = new Robot null, 'mock-adapter', false    

    chatuser = robot.brain.userForId '1', {
      name: 'test-user',
      room: '#test'
    }

    nconf.set("HUBOT_CONFLUENCE_USER", test_user)
    nconf.set("HUBOT_CONFLUENCE_PASSWORD", test_pw)
    nconf.set("HUBOT_CONFLUENCE_HOST", test_host)
    nconf.set("HUBOT_CONFLUENCE_PORT", test_port)
  
    robot.adapter.on 'connected', ->
      adapter = robot.adapter

    require('../src/hubot-confluence')(robot)

    sinon.spy robot, 'hear'
    sinon.spy robot, 'respond'
    robot.run()

    done()

  afterEach -> 
    robot.shutdown()

 
  it 'test help text', (done) ->
    adapter.receive(new TextMessage chatuser, "confluence help")
    expect(@msg.send).to.have.been.calledWith(sinon.match.string)

  it 'test triggers', (done) ->
    adapter.receive(new TextMessage chatuser, "confluence show triggers")
    expect(@msg.send).to.have.been.calledWith(sinon.match.string)

describe 'test-require', ->
  it 'requries hubot-confluence', ->
    require('../src/hubot-confluence')

  it 'requries triggers', ->
    require('../src/data/triggers.json')
