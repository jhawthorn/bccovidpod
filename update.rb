require "net/http"
require "uri"
require "rss"
require "time"
require "fileutils"

ITEM_LIMIT = ENV.fetch("ITEM_LIMIT", 1).to_i

uri = URI.parse("https://www.youtube.com/feeds/videos.xml?user=ProvinceofBC")
response = Net::HTTP.get_response(uri)

unless response.code == "200"
  raise "invalid response: #{response.code} - #{response.body}"
end

input = RSS::Parser.parse(response.body, validate: false)

input_items = input.items.select do |input_item|
    title = input_item.title.content
    title =~ /COVID-19 (Vaccine |BC |Immunization Plan |vaccinations in BC )?Update|Immunization Plan|Surgical Renewal Strategy Update|Premier Horgan Update|Media Availability|plan to safely restart the province|AstraZeneca|plan to safely restart/i
end.first(ITEM_LIMIT)

# for testing
class FileStorage
  def exists?(file)
    File.exist?("data/#{file}")
  end

  def size_of(file)
    File.size("data/#{file}")
  end

  def store(dest, src, **options)
    FileUtils.mkdir_p("data")
    FileUtils.cp(src, "data/#{dest}")
  end

  def base_url
    "./data"
  end
end

# for realsies
class S3Storage
  def initialize(bucket_name)
    @bucket_name = bucket_name

    require "aws-sdk-s3"
    @client = Aws::S3::Client.new(region: "us-east-1")
    @resource = Aws::S3::Resource.new(client: @client)
    @bucket = @resource.bucket(@bucket_name)
  end

  def exists?(file)
    @bucket.object(file).exists?
  end

  def size_of(file)
    @bucket.object(file).size
  end

  def store(dest, src, content_type: "audio/mpeg")
    options = {
      acl: "public-read",
      content_type: content_type,
      content_disposition: "inline"
    }
    @bucket.object(dest).upload_file(src, options)
  end

  def base_url
    "https://#{@bucket_name}.s3.us-east-1.amazonaws.com"
  end
end

if s3_bucket = ENV["S3_BUCKET"]
  storage = S3Storage.new(s3_bucket)
else
  storage = FileStorage.new
end

input_items.each do |input_item|
  video_id = input_item.id.content[/\Ayt:video:(.*)\z/, 1]
  src_url = "https://www.youtube.com/watch?v=#{video_id}"
  original = "tmp/#{video_id}_original.m4a"
  converted = "tmp/#{video_id}_converted.mp3"
  dest = "#{video_id}.mp3"

  next if storage.exists?(dest)

  system(*%W[youtube-dl --ignore-config -f bestaudio[ext=m4a] -o #{original} #{src_url}])
  unless $?.success?
    warn "download with exit code #{$?.to_i}"
    next
  end

  system(*%W[ffmpeg -y -i #{original} -codec:a libmp3lame -b:a 128k -af silenceremove=1:0.01:-20dB #{converted}])
  unless $?.success?
    warn "conversion failed with exit code #{$?.to_i}"
    next
  end

  storage.store(dest, converted)
end

output = RSS::Maker.make("2.0") do |output|
  output.encoding = 'utf-8'

  output.channel.title = "COVID-19 BC Updates"
  output.channel.author = "John Hawthorn"
  output.channel.link = "https://covid.hawth.ca/"
  output.channel.description = "Province of BC COVID-19 updates, pulled from youtube into a podcast for easy listening. UNOFFICIAL, check https://www.youtube.com/user/ProvinceofBC for updates and http://covid-19.bccdc.ca/ for info. Be Calm, Be Kind, Be Safe."
  output.channel.language = "en"

  output.channel.new_itunes_category "Government"
  output.channel.new_itunes_category "News"
  output.channel.new_itunes_category "Health & Fitness"
  output.channel.itunes_explicit = false
  output.channel.itunes_image = "https://covid.hawth.ca/icon.jpg"
  output.channel.itunes_owner.itunes_name = "John Hawthorn"
  output.channel.itunes_owner.itunes_email = "john@hawthorn.email"

  input_items.each do |input_item|
    video_id = input_item.id.content[/\Ayt:video:(.*)\z/, 1]
    next unless storage.exists?("#{video_id}.mp3")

    output.items.new_item do |item|
      id = "jhawthorn/bccovidpod/#{video_id}"

      item.guid.content = id
      item.guid.isPermaLink = false

      item.title   = input_item.title.content
      item.link    = input_item.link.href
      #item.updated = input_item.updated.content
      item.pubDate = input_item.published.content

      item.itunes_explicit = false

      base_url = storage.base_url
      item.enclosure.url = "#{base_url}/#{video_id}.mp3"
      item.enclosure.length = storage.size_of("#{video_id}.mp3")
      item.enclosure.type = "audio/mpeg"

      # item.itunes_duration = # FIXME
    end
  end
end

puts output

tmp = "tmp/feed.xml"
File.write(tmp, output.to_s)
storage.store("feed.xml", tmp, content_type: "application/rss+xml")
