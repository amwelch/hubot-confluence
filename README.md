[![Build Status](https://travis-ci.org/amwelch-oss/hubot-influxdb-alerts.svg?branch=master)](https://travis-ci.org/amwelch-oss/hubot-influxdb-alerts) [![Coverage Status](https://coveralls.io/repos/amwelch-oss/hubot-confluence/badge.svg?branch=master)](https://coveralls.io/r/amwelch-oss/hubot-confluence?branch=master) [![npm version](https://badge.fury.io/js/hubot-confluence.svg)](http://badge.fury.io/js/hubot-confluence)

## hubot-confluence
Access your organization's confluence from hubot

#Features

#Installation

npm install hubot-confluence --save

Then add hubot-confluence to your external-scripts.json

["hubot-confluence"]


#Configuration

hubot-confluence will require read access to your organization's confluence

Required:
HUBOT_CONFLUENCE_USER
HUBOT_CONFLUENCE_PASSWORD
HUBOT_CONFLUENCE_HOST
HUBOT_CONFLUENCE_PORT
HUBOT_CONFLUENCE_SEARCH_SPACE = The space in confluence to search

HUBOT_CONFLUENCE_NUM_RESULTS = The number of results to return. Defaults to 1.
HUBOT_CONFLUENCE_TIMEOUT = Timeout in ms for requests to confluence.

#Commands

#Author

Alexander Welch <amwelch3@gmail.com>

#License

MIT
