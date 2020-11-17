require "net/http"
require "uri"
require "rss"
require "time"

ITEM_LIMIT = 2

uri = URI.parse("https://www.youtube.com/feeds/videos.xml?user=ProvinceofBC")
response = Net::HTTP.get_response(uri)

unless response.code == "200"
  raise "invalid response: #{response.code} - #{response.body}"
end

input = RSS::Parser.parse(response.body, validate: false)
input_items = input.items.first(ITEM_LIMIT)

base_url = "https://jhawthorn.github.io/bccovidpod/"

input_items.each do |input_item|
  video_id = input_item.id.content[/\Ayt:video:(.*)\z/, 1]
  src = "https://www.youtube.com/watch?v=#{video_id}"
  dest = "data/#{video_id}.mp3"

  next if File.exist?(dest)

  system(*%W[youtube-dl -f bestaudio[ext=m4a] -x --audio-format mp3 -o #{dest} #{src}])
end

output = RSS::Maker.make("2.0") do |output|
  output.encoding = 'utf-8'

  output.channel.author = "Province of BC, podcastified by jhawthorn"
  output.channel.title = "COVID-19 BC Updates"
  output.channel.link = "#{base_url}"
  output.channel.description = "Province of BC Covid-19 updates, pulled from youtube into a podcast for easy listening. Be kind, be safe, and be calm."

  output.channel.new_itunes_category "Government"
  output.channel.new_itunes_category "News"
  output.channel.new_itunes_category "Health & Fitness"
  output.channel.itunes_explicit = false

  input.items.first(ITEM_LIMIT).each do |input_item|
    title = input_item.title.content

    next unless title =~ /COVID-19 BC Update|Premier Horgan Update/

    output.items.new_item do |item|
      item.title   = input_item.title.content
      item.link    = input_item.link.href
      item.updated = input_item.updated.content
      item.pubDate = input_item.published.content

      item.itunes_explicit = false

      # item.itunes_duration = # FIXME
    end
  end
end

puts output


