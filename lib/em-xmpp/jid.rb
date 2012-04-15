

module EM::Xmpp
  JID = Struct.new(:node, :domain, :resource) do
    def self.parse(str)
      s1,s2 = str.split('@',2)
      if s2.nil?
        self.new(nil, s1, nil)
      else
        s2,s3 = s2.split('/',2)
        self.new(s1,s2,s3)
      end
    end

    def bare
      [node,domain].map(&:to_s).join('@')
    end

    def full
      [bare,resource].map(&:to_s).join('/')
    end

    def to_s
      full
    end
  end
end
