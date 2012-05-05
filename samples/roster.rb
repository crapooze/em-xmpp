

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
  def ask_roster
    send_stanza(iq_stanza do |x|
      x.query('xmlns' => Roster)
    end) do |ctx|
      p ctx.items
      ctx
    end
  end

  def ready
    puts "***** #{@jid} ready for #{self}"
    on_exception(:anything) do |ctx|
      raise ctx['error']
    end

    ask_roster
  end
end

EM.run do
  EM::Xmpp::Connection.start(jid, pass, MyClient)
end
