require 'mqtt'
require 'json'
require 'httparty'
require 'tempfile'
require "net/https"
require 'base64'

PUSHOVER_APP_TOKEN = ENV['PUSHOVER_APP_TOKEN']
PUSHOVER_USER_TOKEN = ENV['PUSHOVER_USER_TOKEN']

MQTT_HOST = ENV['MQTT_HOST']
MQTT_PORT = ENV['MQTT_PORT']
MQTT_USER = ENV['MQTT_USER']
MQTT_PASS = ENV['MQTT_PASS']

FRIGATE_URL = ENV['FRIGATE_URL']

camera_notify_cooldown_in_seconds = ENV['CAMERA_NOTIFY_COOLDOWN_IN_SECONDS'] ||= "360"

id_list = []
camera_cooldown = {}

def download_to_tmp(url)
  count = 0
  begin
    resp = HTTParty.get(url)
  rescue
    puts "Failed to download #{url}. Retrying..."
    sleep 1
    count = count + 1
    exit if count == 25
    retry
  end


  file = Tempfile.new
  file.binmode
  file.write(resp.body)
  file.rewind
  puts file.path
  puts file.size
  file
end

def to_pushover(message, file)
  url = URI.parse("https://api.pushover.net/1/messages.json")
  req = Net::HTTP::Post.new(url.path)
  encoded_string = Base64.encode64(File.open(file.path, "rb").read)
  req.set_form_data({
    :token => PUSHOVER_APP_TOKEN,
    :user => PUSHOVER_USER_TOKEN,
    :message => message,
    :attachment_base64 => encoded_string,
    :attachment_type => "image/jpeg",
    :html => 1
  })
  res = Net::HTTP.new(url.host, url.port)
  res.use_ssl = true
  res.verify_mode = OpenSSL::SSL::VERIFY_PEER
  res.start {|http| http.request(req) }

end




MQTT::Client.connect(host: MQTT_HOST, port: MQTT_PORT, username: MQTT_USER, password: MQTT_PASS) do |c|
  c.get('frigate/events') do |topic,message|
    a = JSON.parse message
    if a['before']['has_clip'] == true
      formatted_message = "#{a['before']['camera'].capitalize} - #{a['before']['label'].capitalize} was detected."
      if !id_list.include?("#{a['before']['id']}_snap")
        id_list << "#{a['before']['id']}_snap"
        #snap_fork = fork do
          snapshot = "#{FRIGATE_URL}/api/events/#{a['before']['id']}/thumbnail.jpg"
          clip = "#{FRIGATE_URL}/api/events/#{a['before']['id']}/clip.mp4"
          #bot.api.send_message(chat_id: chat_id, text: formatted_message)
          file = download_to_tmp(snapshot)
          if file.size > 100 && file.size < 10000000
            #bot.api.send_photo(chat_id: chat_id, photo: Faraday::UploadIO.new(file.path, 'image/jpeg'), caption: formatted_message, show_caption_above_media: true, disable_notification: false)
            if camera_cooldown[a['before']['camera']].nil? or camera_cooldown[a['before']['camera']] < Time.now.to_i
              to_pushover("<b><u>#{formatted_message}</b></u> <a href='#{clip}'>Clip</a>", file)
              camera_cooldown[a['before']['camera']] = Time.now.to_i + camera_notify_cooldown_in_seconds.to_i
            end
          end
          file.close
          file.unlink    # deletes the temp file
          #exit
        #end #fork
        #Process.detach(snap_fork)
      end
    else
      puts "skipped message, not new"
    end
  end
end
