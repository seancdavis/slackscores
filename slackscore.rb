#!/Users/sean/.rbenv/shims/ruby

#!/home/deploy/.rbenv/shims/ruby

require 'json'
require 'fileutils'
require 'open-uri'
require 'nokogiri'


def notify_slack(username, text, image)
  config = eval(File.read(File.expand_path('../config.rb', __FILE__)))
  pl = {
    :channel  => config[:channel],
    :username => username,
    :text     => text,
    :icon_url => image
  }.to_json
  cmd = "curl -X POST --data-urlencode 'payload=#{pl}' #{config[:webhook_url]}"
  system(cmd)
end

def get_status(score)
  return :live unless score.css('.game-info span strong em')[0].nil?
  return :ft if score.css('.game-info .time')[0].text == 'FT'
  :not_started
end

# scrape the page
date = Date.today.strftime("%Y%m%d")

# live
# url = "http://www.espnfc.us/barclays-premier-league/23/scores?date=#{date}"
# doc = Nokogiri::HTML(open(url))

# test
doc = Nokogiri::HTML(File.read(File.expand_path('../test/epl.html', __FILE__)))

# check for today's file and creat if not there
scores_file = File.expand_path("../scores/#{date}.rb", __FILE__)
FileUtils.mkdir('scores') unless Dir.exists?('scores')
unless File.exists?(scores_file)
  File.open(scores_file, 'w+') do |f|
    f.write({}.to_s)
  end
end

# set our ref and the css for finding scores
score_ref = eval(File.read(scores_file))
scores = doc.css('#score-leagues .scorebox-container .score-content')

# create references if they don't exist
scores.each do |score|
  if score_ref[score.css('.team-name').first.text.strip].nil?
    score_ref[score.css('.team-name').first.text.strip] = {
      :name   => score.css('.team-name').first.text.strip,
      :image  => score.css('.team-name img').first.attribute('src').value
                    .split('&').first,
      :score  => score.css('.team-score').first.text.strip.to_i,
      :status => get_status(score)
    }
  end
  if score_ref[score.css('.team-name').last.text.strip].nil?
    score_ref[score.css('.team-name').last.text.strip] = {
      :name   => score.css('.team-name').last.text.strip,
      :image  => score.css('.team-name img').last.attribute('src').value
                    .split('&').first,
      :score  => score.css('.team-score').last.text.strip.to_i,
      :status => get_status(score)
    }
  end
end

# comparison loop
scores.each do |score|
  # retrieve the status
  status = get_status(score)
  # reference the stored team info
  home = score_ref[score.css('.team-name').first.text.strip]
  away = score_ref[score.css('.team-name').last.text.strip]
  # if home team scores
  if home[:score] != score.css('.team-score')[0].text.strip.to_i
    title = "#{home[:name]} Goal!"
    txt   = "#{away[:name]}: *#{away[:score]}* // "
    txt  += "#{home[:name]}: *#{score.css('.team-score')[0].text.strip.to_i}*"
    notify_slack(title, txt, home[:image])
    score_ref[home[:name]][:score] = score.css('.team-score')[0].text.strip.to_i
  end
  # if away team scored
  if away[:score] != score.css('.team-score')[1].text.strip.to_i
    title = "#{away[:name]} Goal!"
    txt   = "#{away[:name]}: *#{score.css('.team-score')[1].text.strip.to_i}*"
    txt  += " // #{home[:name]}: *#{home[:score]}*"
    notify_slack(title, txt, away[:image])
    score_ref[away[:name]][:score] = score.css('.team-score')[1].text.strip.to_i
  end
  # if the game has ended, but not been recorded
  if status == :ft && home[:status] != :ft
    # if we have a winner
    if home[:score] != away[:score]
      winner = (home[:score] > away[:score]) ? home : away
      loser = (home[:score] > away[:score]) ? away : home
      title = "#{winner[:name]} Wins!"
      txt   = "#{winner[:name]} defeated #{loser[:name]} "
      txt  += "#{score_ref[winner[:name]][:score]}-"
      txt  += "#{score_ref[loser[:name]][:score]}"
      img = winner[:image]
    # if the game ended in a tie
    else
      title = "#{home[:name]} / #{away[:name]} Has Ended"
      txt   = "#{home[:name]} and #{away[:name]} ended in a "
      txt  += "#{score_ref[home[:name]][:score]}-"
      txt  += "#{score_ref[away[:name]][:score]} draw."
      img = 'http://a.espncdn.com/combiner/i?img=/i/leaguelogos/soccer/500-dark/23.png'
    end
    notify_slack(title, txt, img)
    score_ref[home[:name]][:status] = status
    score_ref[away[:name]][:status] = status
  end
end

# save new score ref
File.open(scores_file, 'w+') { |f| f.write(score_ref.to_s) }
