
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

    DataFormState = Struct.new(:form, :answers, :current_idx, :user_input) do
      def current_field
        form.fields[current_idx]
      end

      def current_values
        current_field.values
      end

      def current_answer
        answers.fields[current_idx]
      end

      def current_response_values
        if current_answer
          current_answer.values 
        else
          current_values
        end
      end
    end

    def dataform_conversation(initial_ctx,&blk)
      form = initial_ctx.env['dataform']
      answers = EM::Xmpp::Context::Contexts::Dataforms::Form.new('submit',[],nil,nil)
      state = DataFormState.new(form, answers, 0, nil)

      start_conversation(initial_ctx,:dataform,state) do |conv|
        conv.prepare_callbacks(:start, :ask, :user_answer, :confirm, :submit, :cancel, &blk)
        finalize = :submit

        conv.callback(:start)

        catch :cancel do
          fields = state.form.fields.dup
          cnt = fields.size
          idx = 0
          until (idx + 1) > cnt
            state.current_idx = idx
            conv.callback(:ask)
            state.user_input = conv.delay.ctx
            cb_action = conv.callback(:user_answer)
            state.user_input = nil

            case cb_action 
            when :previous
              idx -= 1
              idx = [0,idx].max
            when :next, :modified
              idx += 1
            when :repeat
              #don't touch index
            when :cancel
              finalize = :cancel
              throw :cancel
            else
              raise RuntimeError, "no such data-form action: #{cb_action}"
            end
          end

          conv.callback(:confirm)
          state.user_input = conv.delay.ctx
        end
        conv.callback(finalize)
      end
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
