
module Xmig::Command::PubSub

  # standard use
  class Subscribe < Specification
  end
  class Unsubscribe < Specification
  end
  class Items < Specification
  end
  class Publish < Specification
  end
  class Retract < Specification
  end
  class Purge < Specification
  end
  class Create < Specification
  end
  class Delete < Specification
  end

  # per node
  class NodeSubscriptions < Specification
  end
  class NodeAffiliations < Specification
  end
  class NodeOptions < Specification
  end
  class NodeDefaultOptions < Specification
  end
  class ConfigureNode < Specification
  end
  class ChangeAffiliation < Specification
  end
  class DeleteSubscription < Specification
  end
  class DeleteSubscription < Specification
  end

  # per subscription
  class SubscriptionOptions < Specification
  end
  class ConfigureSubscription < Specification
  end

  # per service
  class SubscriptionDefaultOptions < Specification
  end
  class ServiceSubscriptions < Specification
  end
  class ServiceAffiliations < Specification
  end

end
