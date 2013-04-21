require 'em-xmpp/namespaces'

module EM::Xmpp
  module Component
    def stream_start(node)
      send_raw("<handshake>#{Digest::SHA1.hexdigest(node['id']+@pass)}</handshake>")
    end

    private
    def open_xml_stream_tag
      "<stream:stream
  to='#{@jid}'
  xmlns='#{Namespaces::Component}:accept'
  xmlns:stream='#{Namespaces::Stream}'
>"
    end
  end
end