$LOAD_PATH.unshift './lib'
require 'em-xmpp'
require 'em-xmpp/helpers'

if ARGV.empty?
  puts "usage: #{__FILE__} <jid> [<pass>] [certificates-dir]"
  exit 0 
end

jid     = ARGV.first
pass    = ARGV[1]
server = ARGV[2] 
port = ARGV[3] 
certdir = ARGV[4] 

module RosterClient
  attr_reader :roster

  include EM::Xmpp::Helpers

  def ready
    super #setup helpers
    puts "***** #{@jid} ready"

    on_presence do |ctx|
      presence = ctx.bit(:presence)

      if presence.subscription_request?
        puts "**** accepting subscription from #{presence.from}"
        send_stanza presence.reply('type'=>'subscribed')
        presence.from.subscribe
        presence.from.add_to_roster
      else
        puts "**** #{presence.from} is present"
      end

      ctx #returns a ctx for subsequent handlers if any
    end

    on_message do |ctx|
      msg = ctx.bit :message

      puts "**** message from #{msg.from}"

      key = msg.from.to_s

      conv = conversation(key)

      if conv 
        conv.resume ctx
      else
        x = rand(300)
        y = rand(300)
        start_conversation(ctx, key) do |c|
          rep = c.send_stanza(msg.reply{|xml| xml.body("how much is #{x} - #{y} ?")}, 5)
          greeting = if rep.interrupted?
                       if rep.ctx.bit(:message).body == (x - y).to_s
                         "great!"
                       else
                         "wrong: #{x - y}"
                       end
                     else
                       "too slow, laggard"
                     end
          self.send_stanza(msg.reply{|xml| xml.body(greeting)})
        end
      end

      ctx #returns a ctx for subsequent handlers if any
    end

    on_exception(:anything) do |ctx|
      p "rescued error"
      raise ctx.env['error']
      ctx
    end

    puts "***** friends list"
    subscriptions = get_roster
    subscriptions.each do |sub|
      p sub.to_a
    end
  end
end

cfg = {:certificates => certdir} 

EM.run do
  conn = EM::Xmpp::Connection.start(jid, pass, RosterClient, cfg, server, port) 
end
