[![Build Status](https://travis-ci.org/amwelch-oss/hubot-confluence.svg?branch=master)](https://travis-ci.org/amwelch-oss/hubot-confluence) [![Coverage Status](https://coveralls.io/repos/amwelch-oss/hubot-confluence/badge.svg?branch=master)](https://coveralls.io/r/amwelch-oss/hubot-confluence?branch=master) [![npm version](https://badge.fury.io/js/hubot-confluence.svg)](http://badge.fury.io/js/hubot-confluence)

## hubot-confluence
Automatically respond to questions in chat with a relevant confluence article.

##Features

Searches confluence for pages matching search terms extracted via regex

##Extending

Regexs are in src/data/triggers.json.

The capture group is the search phrase used.

For example:

"how do I configure hubot"

Would search your organization's confluence for an article on configuring hubot

##Installation

npm install hubot-confluence --save

Then add hubot-confluence to your external-scripts.json

["hubot-confluence"]


##Configuration

hubot-confluence requires an atlassian account with read access to your organization's confluence

hubot-confluence supports the following environment variables for configuration.

_Required_:

	HUBOT_CONFLUENCE_USER			#Atlassian User
	HUBOT_CONFLUENCE_PASSWORD		#Atlassian Password
	HUBOT_CONFLUENCE_HOST
	HUBOT_CONFLUENCE_SEARCH_SPACE 	#Comma-separated list of Confluence Spaces to search, eg DEV,MARKETING,SALES

_Optional_:

	HUBOT_CONFLUENCE_PORT			#Defaults to 443
	HUBOT_CONFLUENCE_NUM_RESULTS  	#The number of results to return. Defaults to 1.
	HUBOT_CONFLUENCE_TIMEOUT  		#Timeout in ms for requests to confluence. Default is no timeout
	HUBOT_CONFLUENCE_PROTOCOL     #Configure the protocol to use to connect to confluence (default: https, common use cases: http, https)


##Commands


	confluence show triggers	#Show the current trigger regexs
    confluence help				#Show this text
    confluence search TEXT		#Run a text search against the phrase TEXT


##Author

Alexander Welch <amwelch3@gmail.com>

##License

MIT
