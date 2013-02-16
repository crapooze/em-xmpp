
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

    CommandFlash = Struct.new(:level, :msg)
    CommandState = Struct.new(:command, :status, :current_idx, :flash, :last_answer) do
      def current_step
        command.steps[current_idx]
      end
      def form
        current_step.form
      end
      def can_complete?
        current_step == command.steps.last
      end
      def can_prev?
        current_idx > 0
      end
      def can_next?
        current_idx + 1 < command.steps.size
      end
    end
    CommandSpec  = Struct.new(:steps)
    CommandStep  = Struct.new(:form) do
      def verify
        true
      end
      def execute
      end
    end

    def start_command_conversation(ctx,spec,&blk)
      query   = ctx.bit(:command)
      sess_id = "cmd:#{ctx.object_id}"
      key     = "command:#{query.from}:#{query.node}:#{sess_id}"

      state = CommandState.new(spec, :completed, 0, nil, nil)

      start_conversation(ctx,key,state) do |conv|
        conv.prepare_callbacks(:start, :answer, :cancel, &blk)

        cnt = state.command.steps.count
        idx = 0

        conv.callback(:start)

        catch :cancel do
          until (idx + 1) > cnt #XXX we may not want a linear questionning
            state.status = 'executing'
            state.current_idx = idx

            reply = query.reply do |iq|
              iq.command(:xmlns => EM::Xmpp::Namespaces::Commands, :sessionid => sess_id, :node => query.node, :status => state.status) do |cmd|
                cmd.actions do |n|
                  n.complete if state.can_complete?
                  n.prev     if state.can_prev?
                  n.next     if state.can_next?
                end
                build_form(cmd,state.form,'form')
                cmd.note({:type => state.flash.level}, state.flash.msg) if state.flash
              end
            end

            user_answer       = conv.send_stanza reply
            state.last_answer = user_answer
            action            = user_answer.ctx.bit(:command).action

            case action
            when 'cancel'
              conv.callback(:cancel)
              state.status = 'cancel'
              throw :cancel
            else
              conv.callback(:answer)
              idx += 1
            end
          end #end of until

          state.status = 'completed'
        end

        finalizer = state.last_answer.ctx.bit(:command).reply do |iq|
          iq.command(:xmlns => EM::Xmpp::Namespaces::Commands, :sessionid => sess_id, :node => query.node, :status => state.status) do |cmd|
            cmd.note({:type => state.flash.level}, state.flash.msg) if state.flash
          end
        end
        send_stanza finalizer
      end
    end

    def build_form(xml,form,type='submit')
      xml.x(:xmlns => DataForms, :type => type) do |x|
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

    def build_submit_form(xml,form)
      build_form(xml,form,'submit')
    end

  end
end
