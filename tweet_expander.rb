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

    # メンションイベント
    @bot.mention do |event|
      event.send_embed do |embed|
        embed.color = 0x1da1f2
        embed.title = "Tweet Expander の使い方"
        embed.description = <<DESC
**●ツイートの引用ツイート・コンテンツを表示**
```!https://twitter.com/～```ツイートのURLの直前に「!」を付ける

**●ツイートのスレッドを表示**
```ツイートID!https://twitter.com/～```ツイートのURLの直前に、表示したいスレッドの最後のツイートのID(数字)と「!」を付ける

**●展開されたコンテンツの削除**
コマンドを実行した元のメッセージを削除する

**[このBOTをサーバーに導入](https://discordapp.com/api/oauth2/authorize?client_id=629507137995014164&permissions=19456&scope=bot)**
**[その他の詳しい説明](https://github.com/GrapeColor/tweet_expander/blob/master/README.md)**
DESC
      end
    end
  end

  # ツリーコンテンツ展開
  def expand_thread(first_id, last_id)
    return [] if first_id <= last_id

    urls = []
    next_id = first_id
    25.times do
      break if next_id <= last_id
      break unless tweet = get_tweet(next_id)
      next_id = tweet.in_reply_to_status_id
      urls << tweet.url.to_s
    end

    return urls.reverse if next_id == last_id
    []
  end

  # 引用コンテンツ展開
  def expand_quote(tweet_id)
    return [] unless tweet = get_tweet(tweet_id)

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
