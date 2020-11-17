require "net/http"
require "uri"
require "rss"
require "time"

ITEM_LIMIT = 6

uri = URI.parse("https://www.youtube.com/feeds/videos.xml?user=ProvinceofBC")
response = Net::HTTP.get_response(uri)

unless response.code == "200"
  raise "invalid response: #{response.code} - #{response.body}"
end

input = RSS::Parser.parse(response.body, validate: false)

input_items = input.items.select do |input_item|
    title = input_item.title.content
    title =~ /COVID-19 BC Update|Premier Horgan Update/
end.first(ITEM_LIMIT)

input_items.each do |input_item|
  video_id = input_item.id.content[/\Ayt:video:(.*)\z/, 1]
  src = "https://www.youtube.com/watch?v=#{video_id}"
  dest = "data/#{video_id}.mp3"

  next if File.exist?(dest)

  tmp = "tmp/#{video_id}.m4a"
  system(*%W[youtube-dl --ignore-config -f bestaudio[ext=m4a] -o #{tmp} #{src}]) || exit($?.to_i)
  system(*%W[ffmpeg -i #{tmp} -codec:a libmp3lame -b:a 128k #{dest}]) || exit($?.to_i)
end

output = RSS::Maker.make("2.0") do |output|
  output.encoding = 'utf-8'

  output.channel.title = "COVID-19 BC Updates"
  output.channel.link = "https://github.com/jhawthorn/bccovidpod"
  output.channel.description = "Province of BC COVID-19 updates, pulled from youtube into a podcast for easy listening. UNOFFICIAL, check https://www.youtube.com/user/ProvinceofBC for updates and http://covid-19.bccdc.ca/ for info. Be kind, be safe, and be calm."
  output.channel.language = "en"

  output.channel.new_itunes_category "Government"
  output.channel.new_itunes_category "News"
  output.channel.new_itunes_category "Health & Fitness"
  output.channel.itunes_explicit = false
  output.channel.itunes_image = "https://raw.githubusercontent.com/jhawthorn/bccovidpod/main/icon.jpg"
  output.channel.itunes_owner.itunes_name = "John Hawthorn"
  output.channel.itunes_owner.itunes_email = "john@hawthorn.email"

  input_items.each do |input_item|
    output.items.new_item do |item|
      video_id = input_item.id.content[/\Ayt:video:(.*)\z/, 1]
      id = "jhawthorn/bccovidpod/#{video_id}"

      item.guid.content = id
      item.guid.isPermaLink = false

      item.title   = input_item.title.content
      item.link    = input_item.link.href
      #item.updated = input_item.updated.content
      item.pubDate = input_item.published.content

      item.itunes_explicit = false

      base_url = "https://github.com/jhawthorn/bccovidpod/raw/main" # FIXME
      item.enclosure.url = "#{base_url}/data/#{video_id}.mp3"
      item.enclosure.length = File.size("data/#{video_id}.mp3")
      item.enclosure.type = "audio/mpeg"

      # item.itunes_duration = # FIXME
    end
  end
end

File.write("feed.xml", output.to_s)
puts output


