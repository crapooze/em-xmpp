
require 'em-xmpp/nodes'
require 'em-xmpp/conversation'
module EM::Xmpp
  module Helpers
    include EM::Xmpp::Namespaces
    def get_roster
      f = Fiber.current

      roster = iq_stanza do |iq|
        iq.query(:xmlns => Roster)
      end

      send_stanza(roster) do |response|
        f.resume response.bit!(:roster).items
      end

      Fiber.yield
    end

    def start_conversation(ctx,&blk)
      EM::Xmpp::Conversation.start(ctx,&blk)
    end

  end
end
