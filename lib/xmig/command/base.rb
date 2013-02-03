
module Xmig::Command::Base

  # control client
  class Set < Specification
  end
  class Quit < Specification
  end
  class Conversations < Specification
  end

  # discover world
  class DiscoInfos < Specification
  end
  class DiscoItems < Specification
  end

  # low-level messaging
  class Msg < Specification
  end
  class Iq < Specification
  end

  # control friends list
  class Subscribe < Specification
  end
  class Unsubscribe < Specification
  end
  class AcceptSubscription < Specification
  end
  class Roster < Specification
  end

end
