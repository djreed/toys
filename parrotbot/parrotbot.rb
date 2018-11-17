require 'slack-ruby-client'
require 'digest'

BOT_TOKEN = ENV["PARROTBOT_TOKEN"]
INIT_BAL = 40
ADMIN_ID = 'U5G7Z8NM9'

Slack.configure do |config|
  config.token = BOT_TOKEN
end

$cl = Slack::RealTime::Client.new

def one_time_setup
  $test_mode = false
  $challenge = nil
  $testbank = Bank.new('testbank.txt')
  $prodbank = Bank.new('prodbank.txt')
  $legacybank = Bank.new('legacybank.txt')
end

def start_with_retry!
  loop do
    begin
      $cl.start!
      break
    rescue StandardError
      sleep 15
      puts "Retrying at #{Time.now}"
    end
  end
end

class Bank
  def initialize(file)
    @file = file
    @bank = {}

    File.open(@file, 'r') do |f|
      f.each do |line|
        name, balance = line.split
        @bank[name] = balance.to_i
      end
    end
  end

  def getbal(userid)
    initbal(userid)
    @bank[userid]
  end

  def changebal(userid, change)
    initbal(userid)
    @bank[userid] += change
    save
  end

  def leaderboard
    # break ties randomly
    @bank.sort_by { |_name, balance| [-balance, rand] }
  end

  def clear
    raise 'WTF' if !@file.include? 'test'
    @bank.clear
    save
  end

  # poop, refactor this
  def bank
    @bank
  end

  private

  def initbal(userid)
    if !@bank.key?(userid)
      @bank[userid] = INIT_BAL
      save
    end
  end

  def save
    File.open(@file, 'w') do |f|
      @bank.each do |name, balance|
        f.puts "#{name} #{balance}"
      end
    end
  end
end

$cl.on :hello do
  puts 'Running'
  $botid = $cl.self.id
  $botname = $cl.self.name
end

def bank
  ($test_mode ? $testbank : $prodbank)
end

def msg(channel, text)
  $cl.message channel: channel, text: text
end

def balstring(userid, show_sadparrot: false)
  amt = bank.getbal(userid)
  suffix = nil
  if (amt == 0) && show_sadparrot
    suffix = ":sadparrot:"
  else
    suffix = emoji_multiplier($test_mode ? ':oldtimeyparrot:' : ':parrot:', amt/10)
  end
  "#{$cl.users[userid].name}, you have #{n_parrot_points(amt)} #{suffix}"
end

def n_parrot_points(n)
  n_string = (n/10).to_s + ((n%10 == 0) ? '' : ".#{n%10}")
  "#{n_string} #{$test_mode ? 'test ' : ''}parrot point#{(n == 10) ? '' : 's'}™"
end

def emoji_multiplier(emoji, times)
  if times <= 20
    emoji*times
  else
    "#{emoji}×#{times}"
  end
end

def parse_decimal(input)
  matches = /^(\d+)?(?:\.(\d+))?$/.match(input)
  if matches.nil?
    raise "couldn't understand `#{input}` as a number"
  end
  if matches[2] && (matches[2].length > 1)
    raise "sorry, parrot points™ not subdividable past the 0.1 level"
  end

  matches[1].to_i*10 + matches[2].to_i
end

def amt_to_decimal(input)
  "#{input/10}" + ((input%10 == 0) ? '' : ".#{input%10}")
end

def really_is_bot(userid)
  $cl.users[userid].is_bot || userid == 'USLACKBOT'
end

def deductbal(userid, amt)
  if bank.getbal(userid) == 0
    raise "#{$cl.users[userid].name}, you don't have any parrot points™ :sadparrot:"
  elsif bank.getbal(userid) < amt
    raise "#{$cl.users[userid].name}, you only have #{n_parrot_points(bank.getbal(userid))}"
  end
  bank.changebal(userid, -amt)
end

def transferbal(receiverid, negsign, amt, senderid)
  raise "why? :kappa:" if amt == 0
  raise "nice try :kappa:" if !negsign.nil?
  raise "no :kappa:" if receiverid == senderid

  unless $test_mode
    if (really_is_bot(receiverid) && !really_is_bot(senderid))
      raise "in production mode, bots can only receive parrot points™ from other bots"
    elsif (really_is_bot(senderid) && !really_is_bot(receiverid))
      raise "in production mode, bots can only give parrot points™ to other bots"
    end
  end

  # TODO this setup looks ugly
  deductbal(senderid, amt)
  bank.changebal(receiverid, amt)
end

def leaderboard(for_bots:)
  order = bank.leaderboard.select { |name, _balance| $test_mode || (for_bots == really_is_bot(name)) }
  order.first(5)
end

def weighted_random_user(posterid)
  ordered_bank = bank.bank.to_a
  ordered_user_ids = ordered_bank.map(&:first)
  ordered_bals = ordered_bank.map(&:second)
  ordered_weights = ordered_bals.map { |b| ordered_bals.sum/(b+0.1) }

  cdf = (0...ordered_weights.length).map { |i| ordered_weights[0..i].sum }

  not_online_ids = []
  loop do
    winner_id = nil
    loop do
      random = rand*cdf.last
      winner_index = cdf.count { |n| n < random }
      winner_id = ordered_user_ids[winner_index]
      break if !(not_online_ids.include? winner_id)
    end

    online = $cl.web_client.users_getPresence(user: winner_id).presence == "active"
    if !online
      not_online_ids << winner_id
      next
    end

    bot_check_passes = $test_mode || (really_is_bot(winner_id) == really_is_bot(posterid))
    not_parrotbot = (winner_id != $botid)
    return $cl.users[winner_id] if bot_check_passes && not_parrotbot
  end
end

$cl.on :message do |data|
  text = data&.text
  posterid = data&.user
  channel = data&.channel
  next if (text.nil? || posterid.nil? || channel.nil?)
  postername = $cl.users[posterid].name

  if /(parrot|#{$botid})/i.match(text)
    puts "#{postername} #{text}"  # debug
  end

  parrotbot = /(?:#{$botname}|<@#{$botid}>)/i
  parrot_points = /(?:parrot ?points?™?|:parrot: ?(?:point)?s?™?)/i

  if /how many #{parrot_points}/i.match(text)
    msg(channel, balstring(posterid, show_sadparrot: true))
  end

  if ((matches = /(?:give|send) <@([0-9A-Z]+)> (-)?(\S+) #{parrot_points}/i.match(text)))
    text = "give #{matches[2]}#{matches[3]} parrot points™ to <@#{matches[1]}>"
    # intentional fall through to next if case
  end

  if ((matches = /(?:give|send) (-)?(\S+) #{parrot_points} to <@([0-9A-Z]+)>/i.match(text)))
    begin
      receiverid = matches[3]
      amt = parse_decimal(matches[2])
      transferbal(receiverid, matches[1], amt, posterid)

      msg(channel, "#{$cl.users[receiverid].name} #{emoji_multiplier(':reversecongaparrot:', [1, amt/10].max)} #{postername}")
      msg(channel, balstring(receiverid))
      msg(channel, balstring(posterid))
    rescue RuntimeError => e
      msg(channel, e.message)
    end
  end

  if /#{parrot_points} leaderboard/i.match(text)
    board = leaderboard(for_bots: really_is_bot(posterid)).map do |userid, _balance| balstring(userid) end.join("\n")
    msg(channel, board)
  end

  if /#{parrotbot} help/i.match(text)
    output = []
    output << 'type "how many parrot points™ do I have" to check your balance'
    output << 'type "give <number> parrot points™ to @<user>" to give parrot points™'
    output << 'type "parrot point™ leaderboard" to check the leaderboard'
    output << 'type "gamble <number> parrot points™" to use the slot machine'
    output << 'type "parrotbot, I\'m feeling lucky" if you\'re feeling lucky (alias for "gamble 1 parrot point™")'
    output << 'type "is parrotbot down" to check status'
    output << 'type "parrotbot help" to print this'

    msg(channel, output.join("\n"))
  end

  if /#{parrotbot} status/i.match(text)
    msg(channel, "Parrotbot is in *#{$test_mode ? "test mode" : "prod mode"}* right now")
  end

  im_feeling_lucky = /(?:I’?m|I'?m) ([a-z]+ )?feeling (?:[a-z]+ )?(un)?lucky/i
  if (((matches = /#{parrotbot},? #{im_feeling_lucky}/i.match(text))) || ((matches = /#{im_feeling_lucky},? #{parrotbot}/i.match(text))))
    if (matches[1] == "not ") ^ (!matches[2].nil?)
      msg(channel, "Don't put any parrot points™ into the slot machine then :kappa:")
    else
      text = "gamble 1 parrot point"
    end
  end

  if ((matches = /(gamble|!jeopardize) (-)?(\S+) #{parrot_points}/i.match(text)))
    risk = matches[1] == "!jeopardize"

    amt = nil
    begin
      amt = parse_decimal(matches[3])
    rescue RuntimeError => e
      msg(channel, e.message)
      next
    end

    if amt == 0
      msg(channel, "not feeling lucky? :kappa:")
      next
    end

    if !matches[2].nil?
      msg(channel, "nice try :kappa:")
      #msg(channel, "you probably don't want to receive negative parrot points™ if you hit the jackpot :kappa:")
      next
    end

    if bank.getbal(posterid) >= 1000000000000
      msg(channel, "no going over 100 billion parrot points™ :notlikethis:")
      next
    end

    if !risk
      potential_random_winner = weighted_random_user(posterid)
    end

    # TODO refactor the three rescues in this block together
    # TODO consider putting all bal methods inside Bank
    begin
      deductbal(posterid, amt)
    rescue RuntimeError => e
      msg(channel, e.message)
      #msg(channel, "You don't have enough parrot points™ to put in the slot machine :sadparrot:")
      next
    end

    output = []
    output << "Inserting #{n_parrot_points(amt)} into the #{risk ? "high-risk " : ""}slot machine..."
    output << "#{postername} #{emoji_multiplier(':congaparrot:', [1, amt/10].max)} #{risk ? ":fire:" : ""}:slot_machine:#{risk ? ":fire:" : ""}"
    output << "..."

    slotmachine = (1..100).to_a.sample

    if slotmachine <= 25 && !risk
      random_winner = potential_random_winner
      output << "The #{n_parrot_points(amt)} went to a random user!"
      output << "<@#{random_winner.id}> wins #{n_parrot_points(amt)}!"
      output << "#{risk ? ":fire:" : ""}:slot_machine:#{risk ? ":fire:" : ""} #{emoji_multiplier(':congaparrot:', [1, amt/10].max)} #{random_winner.name}"
      bank.changebal(random_winner.id, amt)
      output << balstring(random_winner.id) if random_winner.id != posterid
    else
      if risk
        batch_size = (amt**0.75).floor
      else
        batch_size = Math.sqrt(amt).floor
      end
      batches = [batch_size]*(amt/batch_size) + [amt - (amt/batch_size)*batch_size]

      win = 0
      batches.each do |n|
        low = risk ? 1 : 26
        slotmachine = (low..100).to_a.sample

        if risk
          case slotmachine
          when 1..76 then win += 0
          when 77..82 then win += n*3
          when 83..92 then win += n*4
          when 93..96 then win += n*6
          when 97..100 then win += n*12
          end
        else
          case slotmachine
          when 26..44 then win += 0
          when 45..72 then win += n
          when 73..90 then win += n*2
          when 91..97 then win += n*3
          when 98..99 then win += n*4
          when 100 then win += n*5
          end
        end
      end

      if win > 0
        output << "#{(win >= 10*amt) ? "*Jackpot!* " : ""}You win #{n_parrot_points(win)}!"
        output << "#{risk ? ":fire:" : ""}:slot_machine:#{risk ? ":fire:" : ""} #{emoji_multiplier(':congaparrot:', [1, win/10].max)} #{postername}"
      else
        output << 'Oh no! Nothing came out :sadparrot:'
      end

      bank.changebal(posterid, win)
    end

    output << balstring(posterid)

    msg(channel, output.join("\n\n"))
  end

  if /test #{parrot_points} faucet/i.match(text)
    if !$test_mode
      msg(channel, "test parrot point™ faucet only works in test mode")
    elsif really_is_bot(posterid)
      msg(channel, "bots can't use the test parrot point™ faucet")
    else
      msg(channel, ":congaparrot: #{postername}")
      bank.changebal(posterid, 1)
      msg(channel, balstring(posterid))
    end
  end

  if /is #{parrotbot} down/i.match(text)
    msg(channel, "No :kappa:")
  end

  matches = /mine (?:for )?(?:a )?#{parrot_points}(?: `?([A-Z0-9]{12,})\b)?/i.match(text)
  if matches
    unless $test_mode
      msg(channel, "mining not ready for prod mode yet")
      next
    end

    requirement = $test_mode ? "000000" : "00000000"

    if matches[1].nil?
      if $challenge.nil?
        $challenge = (0...11).map { "1234567890QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnm".chars.sample }.join
        prefix = "A new mining challenge has started!"
      else
        prefix = "A mining challenge is already underway!"
      end
      output = []
      output << "Mine a parrot point™ by being the first to type"
      output << ">mine for parrot points™ `#{$challenge}<suffix>`"
      output << "such that `SHA256(\"<your input>\")` starts with `#{requirement}`!"

      msg(channel, "#{prefix} #{output.join("\n")}")
    elsif $challenge.nil?
      msg(channel, 'no mining challenge is active; type "mine for parrot points™" to start one')
    elsif !matches[1].start_with?($challenge)
      msg(channel, "invalid solution; solution must start with `#{$challenge}`")
    else
      hash_string = Digest::SHA256.hexdigest(matches[1])
      if !hash_string.start_with?(requirement)
        msg(channel, "invalid solution; `SHA256(\"#{matches[1]}\")` starts with `#{hash_string[0...requirement.length]}` instead of `#{requirement}`")
      else
        output = []
        output << "Solution found! `SHA256(\"#{matches[1]}\")` = `#{hash_string[0...16]}...`"
        output << ":pick: :congaparrot: #{postername}"

        bank.changebal(posterid, 10)
        output << balstring(posterid)

        msg(channel, output.join("\n\n"))
        $challenge = nil
      end
    end
  end

  if posterid == ADMIN_ID
    if (text == "parrotbot !!test mode on")
      if $test_mode
        msg(channel, "test mode is already on")
      else
        $test_mode = true
        msg(channel, "test mode has been turned on")
      end
    elsif (text == "parrotbot !!prod mode on")
      if $test_mode
        $test_mode = false
        msg(channel, "*prod mode has been turned on*")
      else
        msg(channel, "*prod mode is already on*")
      end
    end

    if false && ((matches = /!distribute (\S+) #{parrot_points}/i.match(text)))
      amt = nil
      begin
        amt = parse_decimal(matches[1])
      rescue RuntimeError => e
        msg(channel, e.message)
        next
      end

      if amt == 0
        next
      end

      output = []
      output << "Distributing #{n_parrot_points(amt)} to a random user..."
      output << "..."

      random_winner = weighted_random_user(posterid)
      output << "<@#{random_winner.id}> gets #{n_parrot_points(amt)}!"
      output << ":sparkles: #{emoji_multiplier(':congaparrot:', [1, amt/10].max)} #{random_winner.name}"
      bank.changebal(random_winner.id, amt)
      output << balstring(random_winner.id)

      msg(channel, output.join("\n\n"))
    end
  end

  if /#{parrotbot} !!!destroy test bank/i.match(text)
    if $test_mode
      $testbank.clear
      msg(channel, "*test bank has been reset*")
    else
      msg(channel, "can only do that in test mode")
    end
  end

  if (matches = /disguise yourself as (\S+)bot :(\S+):/i.match(text))
    $cl.web_client.chat_postMessage channel: channel, text: "test", as_user: false, icon_emoji: ":#{matches[2]}:", username: "#{matches[1]}bot"
  end

  if /taking looker dev/i.match(text)
    $cl.web_client.chat_postMessage channel: channel, text: ":screamparrot: :coldsweatparrot:", as_user: false, icon_url: "https://emojipedia-us.s3.amazonaws.com/thumbs/120/apple/33/hot-pepper_1f336.png", username: "ryanbot"
  end

  if /done with looker dev/i.match(text)
    $cl.web_client.chat_postMessage channel: channel, text: ":relievedparrot:", as_user: false, icon_url: "https://emojipedia-us.s3.amazonaws.com/thumbs/120/apple/33/hot-pepper_1f336.png", username: "ryanbot"
  end
end

$cl.on :close do
  puts 'Closing'
end

$cl.on :closed do
  puts 'Closed'
  start_with_retry!
end

one_time_setup
start_with_retry!
