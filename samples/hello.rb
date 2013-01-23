$LOAD_PATH.unshift './lib'
require 'em-xmpp'
require 'em-xmpp/helpers'

if ARGV.empty?
  puts "usage: #{__FILE__} <jid> [<pass>] [certificates-dir]"
  exit 0 
end

jid     = ARGV.first
pass    = ARGV[1]
certdir = ARGV[2] 

module RosterClient
  attr_reader :roster

  include EM::Xmpp::Helpers
  def ready
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
      puts msg.body
      hello = msg.reply do |rep|
        rep.body "hello world"
      end
      send_stanza  hello

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
  conn = EM::Xmpp::Connection.start(jid, pass, RosterClient, cfg) 
end
