#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'open-uri'
require 'nokogiri'

def notify_slack(username, text, image)
  config = eval(File.read('config.rb'))
  pl = {
    :channel  => config[:channel],
    :username => username,
    :text     => text,
    :icon_url => image
  }.to_json
  cmd = "curl -X POST --data-urlencode 'payload=#{pl}' #{config[:webhook_url]}"
  system(cmd)
end

# scrape the page
date = Date.today.strftime("%Y%m%d")
url = "http://www.espnfc.us/barclays-premier-league/23/scores?date=#{date}"
doc = Nokogiri::HTML(open(url))

# check for today's file and creat if not there
FileUtils.mkdir('scores') unless Dir.exists?('scores')
unless File.exists?("scores/#{date}.rb")
  File.open("scores/#{date}.rb", 'w+') do |f|
    f.write({}.to_s)
  end
end

# set our ref and the css for finding scores
score_ref = eval(File.read("scores/#{date}.rb"))
scores = doc.css('#score-leagues .scorebox-container .score-content')

# create references if they don't exist
scores.each do |score|
  if score_ref[score.css('.team-name').first.text.strip].nil?
    score_ref[score.css('.team-name').first.text.strip] = {
      :name => score.css('.team-name').first.text.strip,
      :image => score.css('.team-name img').first.attribute('src').value
        .split('&').first,
      :score => score.css('.team-score').first.text.strip.to_i
    }
  end
  if score_ref[score.css('.team-name').last.text.strip].nil?
    score_ref[score.css('.team-name').last.text.strip] = {
      :name => score.css('.team-name').last.text.strip,
      :image => score.css('.team-name img').last.attribute('src').value
        .split('&').first,
      :score => score.css('.team-score').last.text.strip.to_i
    }
  end
end

# comparison loop
scores.each do |score|
  home = score_ref[score.css('.team-name').first.text.strip]
  away = score_ref[score.css('.team-name').last.text.strip]
  if home[:score] != score.css('.team-score')[0].text.strip.to_i
    title = "#{home[:name]} Goal!"
    txt   = "#{away[:name]}: *#{away[:score]}* // "
    txt  += "#{home[:name]}: *#{score.css('.team-score')[0].text.strip.to_i}*"
    notify_slack(title, txt, home[:image])
    score_ref[home[:name]][:score] = score.css('.team-score')[0].text.strip.to_i
  end
  if away[:score] != score.css('.team-score')[1].text.strip.to_i
    title = "#{away[:name]} Goal!"
    txt   = "#{away[:name]}: *#{score.css('.team-score')[1].text.strip.to_i}*"
    txt  += " // #{home[:name]}: *#{home[:score]}*"
    notify_slack(title, txt, away[:image])
    score_ref[away[:name]][:score] = score.css('.team-score')[1].text.strip.to_i
  end
end

# save new score ref
File.open("scores/#{date}.rb", 'w+') { |f| f.write(score_ref.to_s) }
