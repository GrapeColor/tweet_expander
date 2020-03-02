require 'dotenv/load'
require './tweet_expander'

tweet_expander = TweetExpander.new(ENV['TWEET_EXPANDER_TOKEN'])
tweet_expander.run
