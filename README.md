# Em::Xmpp

EM::Xmpp is an XMPP client library for EventMachine.
It uses Nokogiri as an XML parser and XML builder.

EM::Xmpp provides decorator-style modules in the mean of contexts
to easily match and reply to stanzas.

## Installation

### Standard

    gem install em-xmpp

### Bundler
Add this line to your application's Gemfile:

    gem 'em-xmpp'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install em-xmpp

## Usage

### Connecting to an XMPP server

Like many EventMachine libraries, you need to first create a module and pass it
to EM::Xmpp::Connection.start

When the connection is ready, EM::Xmpp will call :ready on your connection
object.  From that point, you can start handling stanzas.

### Receiving stanzas

You can setup handlers for message, presence, and iq with on_message,
on_presence, and on_iq methods.  All these methods take a callback block
argument. EM::Xmpp will be call-back the block with a Context object. This
context object helps you while reading the content of a stanza and replying to
it.

You may have multiple handlers per stanza type and the callback block argument
must return the same or another context that will be used for further matching.
This layering lets you write stack-like middlewares where every Context handler
adds some features/environment-variables to the Context.

You can call #done! on a Context to notify the stack that you are done with
this stanza. That is, you do not give a chance to subsequent handlers to match
on the stanza.

You can also call #delete_xpath_handler! on a context handler to remove it from
the stack for the next stanzas. This let you build temporary handlers quite
easily.

Any handler can also throw :halt to interrupt the layering and all the handler
removal operations. You should read the code to understand well what you skip
by doing so.

You can use on(*xpath_args) to build a matcher for any XPath in the stanza.
The arguments are passed verbatim to Nokogiri. A special argument is
on(:anything) that will match any stanza (e.g., for logging).  This is useful
to build new decorators for handling a specific XEP (if you do so, please share
with a pull-request).

When an exception occurs in a stanza handler, the stack rescues the error and
runs the Context through a set of exception handlers. To handle exception you
can use the on_exception(:anything) method.

See the ./samples directory for basic examples.

### Sending stanzas

EM::XMPP for now builds stanzas with Nokogiri::XML::Builder in the form with an
explicit block argument.
Then you send raw_strings with Connection#send_raw.
Note that if you send malformed XML, your server will disconnect you. Hence,
take care when writing XML without and XML builder.

Contexts for message/iq/presence provide a "reply" method that will pre-fill
some fields for you. Otherwise, you can use 

    data = message_stanza('to' => 'someone@somehost') do |xml| 
             xml.body('hello world')
           end
    send_raw data

to send a stanza to someone. Note that since EM:Xmpp sets jabber:client as
default namespace of the XML stream, you must not set the XML namespace for
body/iq/presence and all the things that sit in jabber:client namespace. For
other XEPs, do not forget to set your namespaces.

The XML::Builder uses method_missing and hence this building scheme may be slow
if you need a large throughput of outgoing stanzas.

See the ./samples directory for basic examples.

## Features and Missing

This library does not manage the roster for you. You will have to
do this by hand.

We do not support but plan to support anonymous login yet.

We do not support but may support component login in the future.

SASL authentication uses the ruby-sasl gem. It misses some types of
authentication (for example, X-GOOGLE-TOKEN). 

This library lets you manage the handling and matching of stanza quite close to
the wire. .


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
