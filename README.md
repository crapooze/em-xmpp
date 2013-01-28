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

XMPP is a stateful asynchronous protocol. Hence, to operate an XMPP client, you
must be able to receive and send XMPP messages (called stanzas) as well as
maintain some sort of states at the same time. For this reason, EventMachine is
a good fit to write and XMPP-client in. EM::Xmpp implements a middleware to
write XMPP clients on top of EventMachine for the asyncrhonous network, and
uses Ruby fibers to encapsulate states. Most of the code could easily be
extracted to work with other backends than EventMachine (e.g., TCPSocket) but
it would be harder to remove Fibers.

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

Summarizing, when your connection receives a stanza, the stanza is encapsulated
in a context object and matched against context handlers. Default handlers
exist for the three main stanza types (presence, iq, and message). For example:

    on_presence do |ctx|
      some_operation1
      ctx.env['foo'] = 'bar' #passes the 'bar' to the next stanza matcher
      ctx #unmodified context
    end

    on_presence do |ctx|
      some_operation2
      ctx.env['foo'] #=> 'bar' 
      ctx.done! #next stanza matchers will not receive the context
    end

    on_presence do |ctx|
      this_code_is_never_called
      ctx
    end


You can use on(*xpath_args) to build a matcher for any XPath in the stanza.
The arguments are passed verbatim to Nokogiri. A special argument is
on(:anything) that will match any stanza (e.g., for logging).  This is useful
to build new decorators for handling a specific XEP (if you do so, please share
with a pull-request).

When an exception occurs in a stanza handler, the stack rescues the error and
runs the Context through a set of exception handlers. To handle exception you
can use the on_exception(:anything) method.

See the ./samples directory for basic examples.

### Interpreting incoming stanzas

Now that you know how to receive contexts, you also want to read content inside
the stanza. Contexts have a stanza method to get the Nokogiri representation of
the stanza XML node (remember that stanzas are XML nodes of an XML stream).
Therefore, you can read any node/attribute in any XML namespace of the original
XML node. This way, you have a large control on what to read and you can
implement XEPs not covered in this piece of code (please share your code).

EM::Xmpp provides some level of abstraction to handle incoming stanzas that can
support multiple XEPs. Since a single stanza can carry lots of different XEPs,
single inheritence is not a beautiful option. There are two solutions with a
slightly different cost-model (expressive+slow and slightly-verbose+fast).

A first solution is to extend each context with methods (one Ruby module per
XEP).  Unfortunately, extending Ruby objects is expensive in terms of method
cache.  Extend lets you write code that clearly expresses your intention at the
expense of some slowness.

    on_message do |ctx|
      ctx.with(:message) # extends with EM::Xmpp::Context::Contexts::Message
      ctx.with(:mood)    #                                           Mood
      #then lets you write:
      puts ctx.from
      puts ctx.body
      puts ctx.mood
      ctx 
    end
This is the "Contexts" method.

A less expensive technique is to create, on demand, some delegators objects for
every XEPs. Therefore you must always prepend a method call to name the XEP you
use. We call this method the "Bits" method. Because we support XEPs by bits.

    on_message do |ctx|
      message = ctx.bit!(:message) # delegate to a EM::Xmpp::Context::Bits::Mood
      mood    = ctx.bit!(:mood)    #                                        Mood 
      #then lets you write:
      puts message.from
      puts message.body
      puts mood.mood
      ctx 
    end

My preference now goes for the Bits method. Hence, ctx.with will also generate
and cache a Bits object.  The reasons why I keep both APIs are (a) backward
compatibility (b) forces implementers of XEPs to write the methods for
Context::Bits in clean modules.  In the future, we might implement ctx.with
with Ruby refinements.


### Sending stanzas

It is good to receive stanza and interpret them, but sometimes you also want to
send data. EM::XMPP for now builds stanzas with Nokogiri::XML::Builder in the
form with an explicit block argument.  Then you send raw_strings with
Connection#send_raw or pre-built stanzas with Connection#send_stanza.  Note
that if you send malformed XML, your server will disconnect you. Hence, take
care when writing XML without and XML builder.

Contexts for message/iq/presence provide a "reply" method that will pre-fill
some fields for you. Otherwise, you can use 

    data = message_stanza('to' => 'someone@somehost') do |xml| 
             xml.body('hello world')
           end
    send_stanza data

to send a stanza to someone. Note that since EM:Xmpp sets jabber:client as
default namespace of the XML stream, you must not set the XML namespace for
body/iq/presence and all the things that sit in jabber:client namespace. For
other XEPs, do not forget to set your namespaces.

The XML::Builder uses method_missing and hence this building scheme may be slow
if you need a large throughput of outgoing stanzas.

Sometimes, you expect an answer when sending a stanza. For example, an IQ
result will come back with the same "id" attribute than the IQ query triggering
the result. For this specific use case, send_stanza can take a callback as
block parameter. 
The syntax becomes:

    one_time_handler = send_stanza data do |response_ctx|
	...
    end

Using this syntax will install a one-time handler in the connection handler.
Currently, there is no timeout on this timer. Therfore, you should get the
value of the one-time handler and you should remove it yourself if the handler
never matches any stanza fires.

See the ./samples directory for basic examples.

## Features

### Entities
XMPP defines entities as something with a JID and with which you can interact with.
In EM::Xmpp, each "from" or "to" field encapsulates the JID into an entity object.
This lets you write something such as:

    on_presence do |ctx|
      pre = ctx.bit!(:presence)
      entity = pre.from #here is your entity object
      if pre.subscription_request?
         send_stanza pre.reply('type' => 'subscribed')
         #here are the nice helper methods
         entity.subscribe                    	
         entity.say "hello my new friend"
         entity.add_to_roster
      end
      ctx
    end

### Stateful Conversations 
XMPP is inherently asynchronous. Hence, handling
stateful actions (for example, some XEPs have long request/response flow
charts) can become tricky. Fortunately, EM::Xmpp proposes an abstraction called
Conversation to manage. Under the hood, a Conversation is not much more than a
Fiber plus some wiring.  So far, EM::Xmpp does not route stanza to the
conversations automagically. You must do this by hand.

For short-lived conversations, when you know that an entity should answer to
your stanza with a reply stanza (and with same "id" attribute), use the block
argument of send_stanza.

### Roster management 
This library provides helpers to add/remove entities from your roster as well
as helpers to get the roster as a list of contacts.

## Missing

* anonymous login
* login as XMPP component
* obnoxious SASL schemes such as X-GOOGLE-TOKEN (should patch ruby-sasl gem)

## FAQ

Ask your questions via GitHub "issues".

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
