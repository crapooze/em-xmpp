
$LOAD_PATH.unshift './lib'
require 'em-xmpp'
require 'em-xmpp/namespaces'
require 'em-xmpp/nodes'

if ARGV.size < 3
  puts "usage: #{__FILE__} <jid> <pass> <muc> [<invitees>...]"
  exit 0 
end

jid     = ARGV.first
pass    = ARGV[1]
muc     = ARGV[2]
invitees = ARGV[3 .. -1]

include EM::Xmpp::Namespaces
include EM::Xmpp::Nodes

module MyClient
  def join_muc(muc, login='myclient')
    p "joining muc: #{muc}"
    muc = [muc, login].join('/')
    send_stanza presence_stanza('to'=> muc, 'id' => 'join.muc')
  end

  def leave_muc(muc, login='myclient')
    p "leaving muc: #{muc}"
    muc = [muc, login].join('/')
    send_stanza(presence_stanza('to'=> muc, 'id' => 'leave.muc', 'type' => 'unavailable')) do |ctx|
      p "left muc"
      ctx
    end
  end

  def invite_to_muc(invitee, muc, text)
    p "inviting #{invitee} to #{muc}"
    send_stanza(message_stanza('to' => muc, 'type' => 'normal') do |xml|
      xml.x(:xmlns => 'http://jabber.org/protocol/muc#user') do |x|
        x.invite(:to => invitee) do |invite|
          invite.reason do |reason|
            reason.text text
          end
        end
      end
    end)
  end

  attr_accessor :muc
  attr_accessor :invitees

  def ready
    puts "***** #{@jid} ready for #{self}"

    join_muc(muc)

    on('//xmlns:x', 'xmlns' => EM::Xmpp::Namespaces::MucUser) do |ctx|
      muc = ctx.jid.bare if ctx.jid
      p ctx.jid
      p ctx.affiliation
      p ctx.role
      if ctx.status
        invitees.each do |invitee|
          p invitee
          invite_to_muc muc, invitee, "hello, join my MUC" 
        end
      end
      ctx
    end

    on_message do |ctx|
      p "message"
      p ctx.nickname if ctx.respond_to?(:nickname)
      leave_muc(muc) if ctx.body =~ /leave/ and not ctx.delay?
      ctx
    end

    on_exception(:anything) do |ctx|
      raise ctx['error']
    end

    on_presence do |s|
      p "*presence> #{s.from} #{s.show} (#{s.status})"
      p "  has left" if s.entity_left?
      s
    end

  end
end

EM.run do
  conn = EM::Xmpp::Connection.start(jid, pass, MyClient)
  conn.muc = muc
  conn.invitees = invitees
end
