

module EM::Xmpp
  JID = Struct.new(:node, :domain, :resource) do
    def self.parse(str)
      s1,s2 = str.split('@',2)
      if s2.nil?
        s1,s3 = s1.split('/',2)
        self.new(nil, s1, s3)
      else
        s2,s3 = s2.split('/',2)
        self.new(s1,s2,s3)
      end
    end

    def bare
      if node
        [node,domain].map(&:to_s).join('@')
      else
        domain
      end
    end

    def full
      if resource
        [bare,resource].map(&:to_s).join('/')
      else
        bare
      end
    end

    def to_s
      full
    end
  end
end
