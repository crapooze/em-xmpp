
require 'em-xmpp/nodes'
module EM::Xmpp
  module Helpers
    include EM::Xmpp::Namespaces
    def get_roster
      f = Fiber.current

      roster = iq_stanza do |iq|
        iq.query(:xmlns => Roster)
      end

      send_stanza roster do |rsp|
        f.resume rsp.items
      end

      Fiber.yield
    end
  end
end
