require 'bundler/setup'
require 'discordrb'
require 'twitter'

class TweetExpander
  def initialize(token)
    @bot = Discordrb::Bot.new(token: token)
    @twitter = Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
      config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
      config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
      config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
    end

    @relations = Hash.new { |hash, key| hash[key] = [] }

    register_events
  end

  # BOT起動
  def run(async = false)
    @bot.run(async)
  end

  private

  # イベント登録
  def register_events
    @bot.ready { @bot.game = "Twitter" }

    # メッセージイベント
    @bot.message do |event|
      # コマンド解釈
      urls  = case event.content
              when %r{(\d+)!https?://twitter\.com/\w+/status/(\d+)}
                expand_thread($1.to_i, $2.to_i)
              when %r{!https?://twitter\.com/\w+/status/(\d+)}
                expand_quote($1)
              else
                []
              end

      # コンテンツの送信
      urls.each_slice(5) do |content|
        message = event.send_message(content.join("\n"))
        @relations[event.message.id] << message.id
      end

      nil
    end

    # メッセージ削除イベント
    @bot.message_delete do |event|
      next unless message_ids = @relations.delete(event.id)

      message_ids.each do |message_id|
        Discordrb::API::Channel.delete_message(@bot.token, event.channel.id, message_id)
      end
      nil
    end
  end

  # ツリーコンテンツ展開
  def expand_thread(first_id, last_id)
    return [] if first_id <= last_id

    next_id = first_id
    urls = []
    25.times do
      break if next_id <= last_id
      tweet = get_tweet(next_id)
      next_id = tweet.in_reply_to_status_id
      urls << tweet.url.to_s
    end

    return urls.reverse if next_id == last_id
    []
  end

  # 引用コンテンツ展開
  def expand_quote(tweet_id)
    tweet = get_tweet(tweet_id)

    # URLを展開
    if tweet.urls? && (tweet.attrs[:is_quote_status] || !tweet.media?)
      return [tweet.urls[-1].expanded_url]
    end

    # 画像コンテンツの展開
    media = tweet.media
    if media.any? && media[0].type == "photo"
      return media[1..-1].map(&:media_url_https)
    end

    []
  end

  # ツイートの取得
  def get_tweet(tweet_id)
    begin
      @twitter.status(tweet_id, { tweet_mode: "extended" })
    rescue
      nil
    end
  end
end
