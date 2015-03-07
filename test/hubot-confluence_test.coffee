chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

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
      

describe 'test-require', ->
  it 'requries hubot-confluence', ->
    require('../src/hubot-confluence')

  it 'requries triggers', ->
    require('../src/data/triggers.json')
