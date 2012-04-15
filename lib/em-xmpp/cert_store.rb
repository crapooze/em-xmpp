=begin
The code from this file was copied from Blather:


Copyright (c) 2011 Jeff Smick
 
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:
 
The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.    
=end

module EM::Xmpp
  # An X509 certificate store that validates certificate trust chains.
  # This uses the #{cert_directory}/*.crt files as the list of trusted root
  # CA certificates.
  class CertStore
    @@certs = nil
    @cert_directory = nil

    def initialize(cert_directory)
      @cert_directory = cert_directory
      @store = OpenSSL::X509::Store.new
      certs.each {|c| @store.add_cert(c) }
    end

    # Return true if the certificate is signed by a CA certificate in the
    # store. If the certificate can be trusted, it's added to the store so
    # it can be used to trust other certs.
    def trusted?(pem)
      if cert = OpenSSL::X509::Certificate.new(pem) rescue nil
        @store.verify(cert).tap do |trusted|
          @store.add_cert(cert) if trusted rescue nil
        end
      end
    end

    # Return true if the domain name matches one of the names in the
    # certificate. In other words, is the certificate provided to us really
    # for the domain to which we think we're connected?
    def domain?(pem, domain)
      if cert = OpenSSL::X509::Certificate.new(pem) rescue nil
        OpenSSL::SSL.verify_certificate_identity(cert, domain) rescue false
      end
    end

    # Return the trusted root CA certificates installed in the @cert_directory. These
    # certificates are used to start the trust chain needed to validate certs
    # we receive from clients and servers.
    def certs
      unless @@certs
        pattern = /-{5}BEGIN CERTIFICATE-{5}\n.*?-{5}END CERTIFICATE-{5}\n/m
        dir = @cert_directory
        certs = Dir[File.join(dir, '*.crt')].map {|f| File.read(f) }
        certs = certs.map {|c| c.scan(pattern) }.flatten
        certs.map! {|c| OpenSSL::X509::Certificate.new(c) }
        @@certs = certs.reject {|c| c.not_after < Time.now }
      end
      @@certs
    end
  end
end
