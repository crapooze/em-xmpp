
module EM::Xmpp
  # A handy module with the XMPP namespaces name.
  module Namespaces
    Client = 'jabber:client'
    #In-band registration
    Registration = 'http://jabber.org/features/iq-register'
    #XMPP stream-level stanza
    Stream  = 'http://etherx.jabber.org/streams'
    #TLS negotiation
    TLS = 'urn:ietf:params:xml:ns:xmpp-tls'
    #SASL authentication
    SASL = 'urn:ietf:params:xml:ns:xmpp-sasl'
    #XMPP resource binding
    Bind = 'urn:ietf:params:xml:ns:xmpp-bind'
    #XMPP session creation
    Session = 'urn:ietf:params:xml:ns:xmpp-session'
    #XMPP capabilities discovery
    Capabilities = "http://jabber.org/protocol/caps"
    #XMPP item discovery
    DiscoverItems = "http://jabber.org/protocol/disco#items"
    #XMPP info discovery
    DiscoverInfos = "http://jabber.org/protocol/disco#infos"
    #XMPP commands
    Commands = "http://jabber.org/protocol/commands"
    #XMPP delayed delivery
    Delay = "urn:xmpp:delay"
    #Jabber Data forms
    DataForms  = 'jabber:x:data'
  end
end
