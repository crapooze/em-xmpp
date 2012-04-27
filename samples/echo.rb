
$LOAD_PATH.unshift './lib'
require 'em-xmpp'
require 'em-xmpp/namespaces'
require 'em-xmpp/nodes'

if ARGV.empty?
  puts "usage: #{__FILE__} <jid> [<pass>]"
  exit 0 
end

jid     = ARGV.first
pass    = ARGV[1]

include EM::Xmpp::Namespaces
include EM::Xmpp::Nodes

module MyClient
  def ready
    puts "***** #{@jid} ready for #{self}"

    on_presence do |s|
      p "*presence> #{s.from} #{s.show} (#{s.status})"
      send_raw(s.reply('type'=>'subscribed')) if s.subscription_request?
      s
    end

    on_message do |s|
      p "*message> #{s.from}\n#{s.body}\n"
      send_raw(s.reply do |x|
        x.body "you sent:#{s.body}"
      end)
      s
    end
  end
end

EM.run do
  EM::Xmpp::Connection.start(jid, pass, MyClient)
end
