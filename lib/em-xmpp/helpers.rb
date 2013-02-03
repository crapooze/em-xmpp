
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

    attr_reader :conversations

    def framework_ready(*args,&blk)
      @conversations = {}
    end

    def start_conversation(ctx,key,state=nil,&blk)
      EM::Xmpp::Conversation.start(ctx,state) do |conv|
        conversations[key] = conv
        blk.call conv
        conversations.delete key
      end
    end

    def conversation(key)
      @conversations[key]
    end
    
    def build_submit_form(xml,form)
      xml.x(:xmlns => DataForms, :type => 'submit') do |x|
        form.fields.each do |field|
          args = {'var' => field.var}
          args = args.merge('type' => field.type) unless field.type.nil? or field.type.empty?
          x.field(args) do |f|
            (field.options||[]).each do |opt_value|
              f.option do |o|
                o.value opt_value
              end
            end
            (field.values||[]).each do |value|
              f.value value
            end
          end
        end
      end
    end

  end
end
