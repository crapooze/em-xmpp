# -*- encoding: utf-8 -*-
require File.expand_path('../lib/em-xmpp/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["crapooze"]
  gem.email         = ["crapooze@gmail.com"]
  gem.description   = %q{XMPP client for event machine}
  gem.summary       = %q{Easy to write and to extend XMPP client}
  gem.homepage      = "https://github.com/crapooze/em-xmpp"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "em-xmpp"
  gem.require_paths = ["lib"]
  gem.version       = Em::Xmpp::VERSION
  gem.add_dependency "eventmachine"
  gem.add_dependency "nokogiri"
  gem.add_dependency "ox"
  gem.add_dependency "ruby-sasl"
end
