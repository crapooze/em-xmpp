
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
    DiscoverInfos = "http://jabber.org/protocol/disco#info"
    #Jabber Roster
    Roster = 'jabber:iq:roster'
    #XMPP commands
    Commands = "http://jabber.org/protocol/commands"
    #avatar
    AvatarData     = "urn:xmpp:avatar:data"
    AvatarMetaData = "urn:xmpp:avatar:metadata"
    #attention
    Attention = "urn:xmpp:attention:0"
    #entity nicknames
    Nick = "http://jabber.org/protocol/nick"
    #entity activity
    Activity = "http://jabber.org/protocol/activity"
    #entity mood
    Mood = "http://jabber.org/protocol/mood"
    #entity geoloc
    Geoloc = "http://jabber.org/protocol/geoloc"
    #entity's song
    Tune = "http://jabber.org/protocol/tune"
    #XMPP delayed delivery
    Delay = "urn:xmpp:delay"
    #Jabber Data forms
    DataForms  = 'jabber:x:data'
    #Pubsub
    PubSub = 'http://jabber.org/protocol/pubsub'
    #Pubsub#owner
    PubSubOwner = 'http://jabber.org/protocol/pubsub#owner'
    #Pubsub#subscribe-authorization
    PubSubSubscribeAuthorization = 'http://jabber.org/protocol/pubsub#subscribe_authorization'
    #Pubsub#get-pending
    PubSubGetPending = 'http://jabber.org/protocol/pubsub#get-pending'
    #Pubsub#event
    PubSubEvent = 'http://jabber.org/protocol/pubsub#event'
    #Multi user chat
    Muc     = 'http://jabber.org/protocol/muc'
    #Multi user chat - simple user
    MucUser = 'http://jabber.org/protocol/muc#user'
    #Multi user chat - admin
    MucAdmin = 'http://jabber.org/protocol/muc#admin'
    #Multi user chat - owner
    MucOwner = 'http://jabber.org/protocol/muc#owner'
    #Multi user chat - roomconfig
    MucRoomconfig = 'http://jabber.org/protocol/muc#roomconfig'
    #Stream initiation offer
    StreamInitiation = 'http://jabber.org/protocol/si'
    #Bits of Binary (bob)
    BoB = 'urn:xmpp:bob'
    #In-Band Bytestreams
    IBB = 'http://jabber.org/protocol/ibb'
    #FileTransfer
    FileTransfer = 'http://jabber.org/protocol/si/profile/file-transfer'
    #Feature Negotiation
    FeatureNeg = 'http://jabber.org/protocol/feature-neg'
    #ByteStreamTransfer
    ByteStreams = 'http://jabber.org/protocol/bytestreams'
    #Extension for Fast byte stream transfers
    FastByteStreams = 'http://affinix.com/jabber/stream'
    #xhtml-im
    XhtmlIM = 'http://jabber.org/protocol/xhtml-im'
  end
end
