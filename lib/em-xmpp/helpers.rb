
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

    def build_submit_form(xml,form)
      xml.x(:xmlns => DataForms, :type => 'submit') do |x|
        form.fields.each do |field|
          args = {'var' => field.var}
          args = args.merge('type' => field.type) unless field.type.nil? or field.type.empty?
          x.field(args) do |f|
            field.values.each do |value|
              f.value value
            end
          end
        end
      end
    end

  end
end
