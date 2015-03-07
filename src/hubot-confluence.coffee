nconf = require("nconf")
cwd = process.cwd()
DEFAULTS_FILE = "#{__dirname}/data/defaults.json"

nconf.argv()
    .env()
    .file('defaults', DEFAULTS_FILE)

module.exports = (robot) ->

  robot.hear /hello world confluence!/i, (msg) ->
    msg.send "Hello, World!"

