
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

    # Sending a stanza and adding a temporary matcher to it.
    # Returns an handler object that is already ready to process further stanzas.
    # Note that so far there is no way to time-out such an handler automatically.
    handler = send_stanza(iq_stanza('to'=> 'dicioccio@mbpldc.local') do |x|
      x.body "this will trigger an XMPP error"
    end) do |ctx|
      if ctx.error?
        p ctx.error_code
        p ctx.error_type
        p ctx.error_condition
      end
      ctx
    end

    # Exception handling (i.e., when Ruby raises something)
    on_exception(:anything) do |ctx|
      raise ctx['error']
    end

    # Manually add a matcher + handler for it
    m = EM::Xmpp::StanzaMatcher.new do |ctx|
      p "proc-ing"
      true
    end
    h = EM::Xmpp::StanzaHandler.new(m) do |ctx|
      p "proc-ed"
      ctx
    end
    @handler.add_handler h

    # Presence handler
    on_presence do |s|
      p "*presence> #{s.from} #{s.show} (#{s.status})"
      send_stanza(s.reply('type'=>'subscribed')) if s.subscription_request?
      s
    end

    # Message handler
    on_message do |s|
      p "*message> #{s.from}\n#{s.body}\n"
      send_stanza(s.reply do |x|
        x.body "you sent:#{s.body}"
      end)
      s
    end
  end
end

EM.run do
  EM::Xmpp::Connection.start(jid, pass, MyClient)
end
