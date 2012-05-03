require "fiber"

require "vcap/stager/client/em_aware"

module VCAP
  module Stager
    module Client
    end
  end
end

class VCAP::Stager::Client::FiberAware < VCAP::Stager::Client::EmAware
  # Requests that an application be staged. Blocks the current fiber until
  # the request completes.
  #
  # @see VCAP::Stager::Client::EmAware#stage for a description of the arguments
  #
  # @return [Hash]
  def stage(*args, &blk)
    deferrable = super

    f = Fiber.current

    deferrable.callback { |response| f.resume({ :response => response }) }

    deferrable.errback { |e| f.resume({ :error => e }) }

    result = Fiber.yield

    if result[:error]
      raise result[:error]
    else
      result[:response]
    end
  end
end
